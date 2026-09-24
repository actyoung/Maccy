@MainActor
class Storage {
  static let shared = Storage()

  private(set) var items: [HistoryItem] = []
  var size: String { "Memory only" }

  func insert(_ item: HistoryItem) {
    guard !items.contains(item) else { return }
    items.append(item)
  }

  func delete(_ item: HistoryItem) {
    items.removeAll { $0 == item }
  }

  func removeAll(where shouldRemove: (HistoryItem) -> Bool) {
    items.removeAll(where: shouldRemove)
  }

  func removeAll() {
    items.removeAll()
  }
}
