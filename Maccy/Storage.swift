import CryptoKit
import Defaults
import Foundation
import Logging

@MainActor
final class Storage {
  static let shared = Storage()

  private let fileManager: FileManager
  private let keyStore: any EncryptionKeyStoring
  private let logger = Logger(label: "org.p0deje.Maccy.Storage")
  private let persistenceDirectoryURL: URL
  private var fileStore: EncryptedHistoryFileStore?
  private var prepared = false

  private(set) var items: [HistoryItem] = []
  var persistenceEnabled: Bool { Defaults[.persistentHistoryEnabled] }
  var size: String {
    return ByteCountFormatter.string(
      fromByteCount: persistentStorageBytes(),
      countStyle: .file
    )
  }

  init(
    fileManager: FileManager = .default,
    keyStore: any EncryptionKeyStoring = KeychainEncryptionKeyStore(),
    persistenceDirectoryURL: URL? = nil
  ) {
    self.fileManager = fileManager
    self.keyStore = keyStore
    self.persistenceDirectoryURL = persistenceDirectoryURL ??
      URL.applicationSupportDirectory.appending(path: "Maccy/EncryptedHistory", directoryHint: .isDirectory)
  }

  func prepareForLaunch() {
    guard !prepared else { return }
    prepared = true

    guard persistenceEnabled else { return }

    do {
      let store = try openOrCreateFileStore()
      items = try store.load(retentionDays: Defaults[.historyRetentionDays])
      fileStore = store
    } catch {
      logger.error("Unable to open encrypted history: \(error.localizedDescription)")
      Defaults[.persistentHistoryEnabled] = false
    }
  }

  func setPersistenceEnabled(_ enabled: Bool) throws {
    prepareForLaunch()
    guard enabled != persistenceEnabled || (enabled && fileStore == nil) else {
      return
    }

    if enabled {
      do {
        let store = try openOrCreateFileStore()
        let persistedItems = try store.load(retentionDays: Defaults[.historyRetentionDays])
        let sessionItems = items
        var mergedItems = persistedItems

        for sessionItem in sessionItems {
          if let sameItemIndex = mergedItems.firstIndex(where: { $0.id == sessionItem.id }) {
            mergedItems[sameItemIndex] = sessionItem
          } else {
            mergedItems.removeAll { persistedItem in
              persistedItem.supersedes(sessionItem) || sessionItem.supersedes(persistedItem)
            }
            mergedItems.append(sessionItem)
          }
        }

        items = mergedItems
        fileStore = store
        Defaults[.persistentHistoryEnabled] = true
        for item in mergedItems {
          try store.save(item)
        }
      } catch {
        fileStore = nil
        Defaults[.persistentHistoryEnabled] = false
        throw error
      }
    } else {
      fileStore = nil
      Defaults[.persistentHistoryEnabled] = false
    }
  }

  func deletePersistentHistoryAndKey() throws {
    try removePersistentArtifacts()
    fileStore = nil
    Defaults[.persistentHistoryEnabled] = false
  }

  func insert(_ item: HistoryItem) {
    guard !items.contains(item) else { return }
    items.append(item)
    persist(item)
  }

  func update(_ item: HistoryItem) {
    guard items.contains(item) else { return }
    persist(item)
  }

  func delete(_ item: HistoryItem) {
    items.removeAll { $0 == item }
    do {
      try fileStore?.delete(id: item.id)
    } catch {
      logger.error("Unable to delete an encrypted history item: \(error.localizedDescription)")
    }
  }

  func removeAll(where shouldRemove: (HistoryItem) -> Bool) {
    let removed = items.filter(shouldRemove)
    items.removeAll(where: shouldRemove)
    for item in removed {
      do {
        try fileStore?.delete(id: item.id)
      } catch {
        logger.error("Unable to delete an encrypted history item: \(error.localizedDescription)")
      }
    }
  }

  func removeAll() {
    items.removeAll()
    do {
      try fileStore?.deleteAll()
      try fileStore?.prepare()
    } catch {
      logger.error("Unable to clear encrypted history: \(error.localizedDescription)")
    }
  }

  @discardableResult
  func pruneExpired(now: Date = .now) -> Set<UUID> {
    guard persistenceEnabled else { return [] }

    let cutoff = now.addingTimeInterval(
      -TimeInterval(max(1, Defaults[.historyRetentionDays])) * 24 * 60 * 60
    )
    let expired = items.filter { $0.lastCopiedAt < cutoff }
    let ids = Set(expired.map(\.id))
    removeAll { ids.contains($0.id) }
    return ids
  }

  private func persist(_ item: HistoryItem) {
    guard persistenceEnabled, let fileStore else { return }
    do {
      try fileStore.save(item)
    } catch {
      logger.error("Unable to save encrypted history: \(error.localizedDescription)")
    }
  }

  private func removePersistentArtifacts() throws {
    if fileManager.fileExists(atPath: persistenceDirectoryURL.path) {
      try fileManager.removeItem(at: persistenceDirectoryURL)
    }
    try keyStore.delete()
  }

  private func openOrCreateFileStore() throws -> EncryptedHistoryFileStore {
    let key: SymmetricKey
    if let existingKey = try keyStore.load() {
      key = existingKey
    } else {
      if persistentArtifactsExist() {
        throw EncryptedHistoryPersistenceError.missingKeyForExistingHistory
      }
      key = try keyStore.createRandomKey()
    }

    let store = EncryptedHistoryFileStore(
      directoryURL: persistenceDirectoryURL,
      key: key,
      fileManager: fileManager
    )
    try store.prepare()
    return store
  }

  private func persistentArtifactsExist() -> Bool {
    guard fileManager.fileExists(atPath: persistenceDirectoryURL.path) else {
      return false
    }
    return ((try? fileManager.contentsOfDirectory(atPath: persistenceDirectoryURL.path)) ?? []).isEmpty == false
  }

  private func persistentStorageBytes() -> Int64 {
    guard let urls = try? fileManager.contentsOfDirectory(
      at: persistenceDirectoryURL,
      includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
      options: [.skipsHiddenFiles]
    ) else {
      return 0
    }

    return urls.reduce(into: 0) { total, url in
      let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
      total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }
  }
}
