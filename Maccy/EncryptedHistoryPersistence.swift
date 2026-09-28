import CryptoKit
import Foundation
import Security

enum EncryptedHistoryPersistenceError: LocalizedError {
  case invalidKey
  case invalidRecord
  case keychain(OSStatus)
  case missingKeyForExistingHistory
  case missingCombinedData

  var errorDescription: String? {
    switch self {
    case .invalidKey:
      return "The encrypted history key is invalid."
    case .invalidRecord:
      return "An encrypted history record is invalid."
    case let .keychain(status):
      if let message = SecCopyErrorMessageString(status, nil) {
        return message as String
      }
      return "Keychain error: \(status)"
    case .missingKeyForExistingHistory:
      return "Encrypted history exists, but its key is missing. " +
        "Delete the encrypted history explicitly before creating a new key."
    case .missingCombinedData:
      return "CryptoKit could not encode the encrypted history record."
    }
  }
}

protocol EncryptionKeyStoring {
  func load() throws -> SymmetricKey?
  func createRandomKey() throws -> SymmetricKey
  func delete() throws
}

struct KeychainEncryptionKeyStore: EncryptionKeyStoring {
  private let account = "encrypted-history"
  private let service = "org.p0deje.Maccy.localprivacy.encrypted-history"

  func load() throws -> SymmetricKey? {
    var query = baseQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess else {
      throw EncryptedHistoryPersistenceError.keychain(status)
    }
    guard let data = result as? Data, data.count == 32 else {
      throw EncryptedHistoryPersistenceError.invalidKey
    }
    return SymmetricKey(data: data)
  }

  func createRandomKey() throws -> SymmetricKey {
    let key = SymmetricKey(size: .bits256)
    let data = key.withUnsafeBytes { Data($0) }
    var query = baseQuery
    query[kSecValueData as String] = data

    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw EncryptedHistoryPersistenceError.keychain(status)
    }
    return key
  }

  func delete() throws {
    let status = SecItemDelete(baseQuery as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw EncryptedHistoryPersistenceError.keychain(status)
    }
  }

  private var baseQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}

private struct PersistentHistoryContent: Codable {
  let type: String
  let value: Data?

  init(_ content: HistoryItemContent) {
    type = content.type
    value = content.value
  }
}

private struct PersistentHistoryRecord: Codable {
  static let currentVersion = 1

  let version: Int
  let id: UUID
  let application: String?
  let firstCopiedAt: Date
  let lastCopiedAt: Date
  let numberOfCopies: Int
  let pin: String?
  let title: String
  let contents: [PersistentHistoryContent]

  init(_ item: HistoryItem) {
    version = Self.currentVersion
    id = item.id
    application = item.application
    firstCopiedAt = item.firstCopiedAt
    lastCopiedAt = item.lastCopiedAt
    numberOfCopies = item.numberOfCopies
    pin = item.pin
    title = item.title
    contents = item.contents.map(PersistentHistoryContent.init)
  }

  func historyItem() throws -> HistoryItem {
    guard version == Self.currentVersion, numberOfCopies > 0 else {
      throw EncryptedHistoryPersistenceError.invalidRecord
    }

    let item = HistoryItem(
      id: id,
      contents: contents.map { HistoryItemContent(type: $0.type, value: $0.value) }
    )
    item.application = application
    item.firstCopiedAt = firstCopiedAt
    item.lastCopiedAt = lastCopiedAt
    item.numberOfCopies = numberOfCopies
    item.pin = pin
    item.title = title
    return item
  }
}

final class EncryptedHistoryFileStore {
  private static let fileExtension = "maccy-history"
  private static let authenticatedDataPrefix = "org.p0deje.Maccy.localprivacy.history.v1:"

  let directoryURL: URL

  private let decoder = JSONDecoder()
  private let encoder = JSONEncoder()
  private let fileManager: FileManager
  private let key: SymmetricKey

  init(directoryURL: URL, key: SymmetricKey, fileManager: FileManager = .default) {
    self.directoryURL = directoryURL
    self.key = key
    self.fileManager = fileManager
    encoder.outputFormatting = [.sortedKeys]
  }

  func prepare() throws {
    try fileManager.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
  }

  func load(retentionDays: Int, now: Date = .now) throws -> [HistoryItem] {
    try prepare()
    let cutoff = Self.cutoff(retentionDays: retentionDays, now: now)
    var items: [HistoryItem] = []

    for url in try recordURLs() {
      do {
        let record = try readRecord(at: url)
        if record.lastCopiedAt < cutoff {
          try fileManager.removeItem(at: url)
        } else {
          items.append(try record.historyItem())
        }
      } catch {
        continue
      }
    }
    return items
  }

  func save(_ item: HistoryItem) throws {
    try prepare()
    let plaintext = try encoder.encode(PersistentHistoryRecord(item))
    let sealedBox = try AES.GCM.seal(
      plaintext,
      using: key,
      authenticating: authenticatedData(for: item.id)
    )
    guard let combined = sealedBox.combined else {
      throw EncryptedHistoryPersistenceError.missingCombinedData
    }

    let url = recordURL(for: item.id)
    try combined.write(to: url, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  func delete(id: UUID) throws {
    let url = recordURL(for: id)
    if fileManager.fileExists(atPath: url.path) {
      try fileManager.removeItem(at: url)
    }
  }

  func deleteAll() throws {
    if fileManager.fileExists(atPath: directoryURL.path) {
      try fileManager.removeItem(at: directoryURL)
    }
  }

  func allocatedBytes() -> Int64 {
    guard let urls = try? recordURLs() else {
      return 0
    }

    return urls.reduce(into: 0) { total, url in
      let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
      total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }
  }

  private func readRecord(at url: URL) throws -> PersistentHistoryRecord {
    guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) else {
      throw EncryptedHistoryPersistenceError.invalidRecord
    }

    let encryptedData = try Data(contentsOf: url)
    let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
    let plaintext = try AES.GCM.open(
      sealedBox,
      using: key,
      authenticating: authenticatedData(for: id)
    )
    let record = try decoder.decode(PersistentHistoryRecord.self, from: plaintext)
    guard record.id == id else {
      throw EncryptedHistoryPersistenceError.invalidRecord
    }
    return record
  }

  private func authenticatedData(for id: UUID) -> Data {
    Data((Self.authenticatedDataPrefix + id.uuidString.lowercased()).utf8)
  }

  private func recordURL(for id: UUID) -> URL {
    directoryURL
      .appendingPathComponent(id.uuidString.lowercased())
      .appendingPathExtension(Self.fileExtension)
  }

  private func recordURLs() throws -> [URL] {
    guard fileManager.fileExists(atPath: directoryURL.path) else {
      return []
    }
    return try fileManager.contentsOfDirectory(
      at: directoryURL,
      includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
      options: [.skipsHiddenFiles]
    ).filter { $0.pathExtension == Self.fileExtension }
  }

  private static func cutoff(retentionDays: Int, now: Date) -> Date {
    now.addingTimeInterval(-TimeInterval(max(1, retentionDays)) * 24 * 60 * 60)
  }
}
