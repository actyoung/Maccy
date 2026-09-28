import CryptoKit
import Defaults
import Foundation
import Testing

@testable import Maccy

@Suite(.serialized)
struct EncryptedHistoryPersistenceTests {
  @Test
  func roundTripEncryptsEveryStoredFieldAndLocksDownPermissions() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let key = SymmetricKey(size: .bits256)
    let store = EncryptedHistoryFileStore(directoryURL: directory, key: key)
    let now = Date()
    let secret = "private clipboard value"
    let item = makeItem(text: secret, lastCopiedAt: now)
    item.application = "com.example.SecretApp"
    item.firstCopiedAt = now.addingTimeInterval(-120)
    item.numberOfCopies = 4
    item.pin = "p"
    item.title = "Private title"

    try store.save(item)

    let recordURL = try #require(recordURLs(in: directory).first)
    let ciphertext = try Data(contentsOf: recordURL)
    #expect(ciphertext.range(of: Data(secret.utf8)) == nil)
    #expect(ciphertext.range(of: Data(item.title.utf8)) == nil)

    let loaded = try #require(store.load(retentionDays: 30, now: now).first)
    #expect(loaded.id == item.id)
    #expect(loaded.application == item.application)
    let firstCopiedAtDifference = loaded.firstCopiedAt.timeIntervalSince1970 - item.firstCopiedAt.timeIntervalSince1970
    let lastCopiedAtDifference = loaded.lastCopiedAt.timeIntervalSince1970 - item.lastCopiedAt.timeIntervalSince1970
    #expect(abs(firstCopiedAtDifference) < 0.001)
    #expect(abs(lastCopiedAtDifference) < 0.001)
    #expect(loaded.numberOfCopies == item.numberOfCopies)
    #expect(loaded.pin == item.pin)
    #expect(loaded.title == item.title)
    #expect(loaded.contents.first?.type == "public.utf8-plain-text")
    #expect(loaded.contents.first?.value == Data(secret.utf8))

    let directoryMode = try posixPermissions(at: directory)
    let fileMode = try posixPermissions(at: recordURL)
    #expect(directoryMode & 0o777 == 0o700)
    #expect(fileMode & 0o777 == 0o600)
  }

  @Test
  func tamperedCiphertextAndWrongKeyAreRejectedWithoutDeletingCiphertext() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = EncryptedHistoryFileStore(
      directoryURL: directory,
      key: SymmetricKey(size: .bits256)
    )
    let item = makeItem(text: "authenticated content")
    try store.save(item)

    let recordURL = try #require(recordURLs(in: directory).first)
    var tampered = try Data(contentsOf: recordURL)
    tampered[tampered.startIndex] ^= 0xff
    try tampered.write(to: recordURL, options: .atomic)

    #expect(try store.load(retentionDays: 30).isEmpty)
    #expect(FileManager.default.fileExists(atPath: recordURL.path))

    try store.save(item)
    let wrongKeyStore = EncryptedHistoryFileStore(
      directoryURL: directory,
      key: SymmetricKey(size: .bits256)
    )
    #expect(try wrongKeyStore.load(retentionDays: 30).isEmpty)
    #expect(FileManager.default.fileExists(atPath: recordURL.path))
  }

  @Test
  func retentionDeletesOnlyExpiredCiphertext() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let now = Date()
    let store = EncryptedHistoryFileStore(
      directoryURL: directory,
      key: SymmetricKey(size: .bits256)
    )
    let recentDate = now.addingTimeInterval(-29 * 24 * 60 * 60)
    let expiredDate = now.addingTimeInterval(-31 * 24 * 60 * 60)
    let recent = makeItem(text: "recent", lastCopiedAt: recentDate)
    let expired = makeItem(text: "expired", lastCopiedAt: expiredDate)
    try store.save(recent)
    try store.save(expired)

    let loaded = try store.load(retentionDays: 30, now: now)
    #expect(loaded.map(\.id) == [recent.id])
    #expect(FileManager.default.fileExists(atPath: recordURL(for: recent.id, in: directory).path))
    #expect(!FileManager.default.fileExists(atPath: recordURL(for: expired.id, in: directory).path))
  }

  @Test @MainActor
  func disableReinstallAndReenableReuseTheExistingKeyAndCiphertext() throws {
    let oldEnabled = Defaults[.persistentHistoryEnabled]
    let oldRetention = Defaults[.historyRetentionDays]
    let directory = temporaryDirectory()
    defer {
      Defaults[.persistentHistoryEnabled] = oldEnabled
      Defaults[.historyRetentionDays] = oldRetention
      try? FileManager.default.removeItem(at: directory)
    }

    Defaults[.persistentHistoryEnabled] = false
    Defaults[.historyRetentionDays] = 30
    let keyStore = TestKeyStore()
    let storage = Storage(keyStore: keyStore, persistenceDirectoryURL: directory)
    try storage.setPersistenceEnabled(true)
    let item = makeItem(text: "survives replacement")
    storage.insert(item)

    let reinstalledStorage = Storage(keyStore: keyStore, persistenceDirectoryURL: directory)
    reinstalledStorage.prepareForLaunch()
    #expect(reinstalledStorage.items.map(\.id) == [item.id])
    #expect(keyStore.createCount == 1)

    try reinstalledStorage.setPersistenceEnabled(false)
    #expect(keyStore.key != nil)
    #expect(FileManager.default.fileExists(atPath: recordURL(for: item.id, in: directory).path))

    try reinstalledStorage.setPersistenceEnabled(true)
    #expect(keyStore.createCount == 1)
    #expect(reinstalledStorage.items.map(\.id) == [item.id])

    try reinstalledStorage.deletePersistentHistoryAndKey()
    #expect(keyStore.key == nil)
    #expect(keyStore.deleteCount == 1)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
    #expect(!Defaults[.persistentHistoryEnabled])
  }

  @Test @MainActor
  func missingKeyNeverOverwritesExistingCiphertext() throws {
    let oldEnabled = Defaults[.persistentHistoryEnabled]
    let directory = temporaryDirectory()
    let ciphertextURL = directory.appendingPathComponent("orphaned.maccy-history")
    defer {
      Defaults[.persistentHistoryEnabled] = oldEnabled
      try? FileManager.default.removeItem(at: directory)
    }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data([0x01, 0x02, 0x03]).write(to: ciphertextURL)
    Defaults[.persistentHistoryEnabled] = false
    let keyStore = TestKeyStore()
    let storage = Storage(keyStore: keyStore, persistenceDirectoryURL: directory)

    do {
      try storage.setPersistenceEnabled(true)
      Issue.record("Expected enabling persistence to fail when ciphertext has no key")
    } catch EncryptedHistoryPersistenceError.missingKeyForExistingHistory {
      // Expected: existing ciphertext must not be overwritten with a new key.
    } catch {
      Issue.record("Unexpected error: \(error)")
    }

    #expect(keyStore.createCount == 0)
    #expect(FileManager.default.fileExists(atPath: ciphertextURL.path))
    #expect(!Defaults[.persistentHistoryEnabled])
  }

  @Test @MainActor
  func pinSettingsUpdatesRewriteTheEncryptedRecord() throws {
    let oldEnabled = Defaults[.persistentHistoryEnabled]
    let directory = temporaryDirectory()
    defer {
      Defaults[.persistentHistoryEnabled] = oldEnabled
      try? FileManager.default.removeItem(at: directory)
    }

    Defaults[.persistentHistoryEnabled] = false
    let keyStore = TestKeyStore()
    let storage = Storage(keyStore: keyStore, persistenceDirectoryURL: directory)
    try storage.setPersistenceEnabled(true)

    let item = makeItem(text: "original")
    item.pin = "a"
    storage.insert(item)

    item.pin = "b"
    item.title = "Updated alias"
    item.contents = [
      HistoryItemContent(type: "public.utf8-plain-text", value: Data("updated content".utf8))
    ]
    storage.update(item)

    let key = try #require(keyStore.key)
    let fileStore = EncryptedHistoryFileStore(directoryURL: directory, key: key)
    let loaded = try #require(fileStore.load(retentionDays: 30).first)
    #expect(loaded.id == item.id)
    #expect(loaded.pin == "b")
    #expect(loaded.title == "Updated alias")
    #expect(loaded.contents.first?.value == Data("updated content".utf8))
  }

  private func makeItem(text: String, lastCopiedAt: Date = .now) -> HistoryItem {
    let item = HistoryItem(
      contents: [HistoryItemContent(type: "public.utf8-plain-text", value: Data(text.utf8))]
    )
    item.lastCopiedAt = lastCopiedAt
    item.title = text
    return item
  }

  private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("MaccyPersistenceTests")
      .appendingPathComponent(UUID().uuidString)
  }

  private func recordURLs(in directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "maccy-history" }
  }

  private func recordURL(for id: UUID, in directory: URL) -> URL {
    directory
      .appendingPathComponent(id.uuidString.lowercased())
      .appendingPathExtension("maccy-history")
  }

  private func posixPermissions(at url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require((attributes[.posixPermissions] as? NSNumber)?.intValue)
  }
}

private final class TestKeyStore: EncryptionKeyStoring {
  var createCount = 0
  var deleteCount = 0
  var key: SymmetricKey?

  func load() throws -> SymmetricKey? {
    key
  }

  func createRandomKey() throws -> SymmetricKey {
    createCount += 1
    let newKey = SymmetricKey(size: .bits256)
    key = newKey
    return newKey
  }

  func delete() throws {
    deleteCount += 1
    key = nil
  }
}
