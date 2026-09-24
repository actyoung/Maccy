import Foundation

final class HistoryItemContent {
  var type: String = ""
  var value: Data?

  init(type: String, value: Data? = nil) {
    self.type = type
    self.value = value
  }
}
