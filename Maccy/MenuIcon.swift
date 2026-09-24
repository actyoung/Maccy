import AppKit
import Defaults

enum MenuIcon: String, CaseIterable, Identifiable, Defaults.Serializable {
  case maccy
  case clipboard
  case scissors
  case paperclip

  var id: Self { self }

  var image: NSImage {
    let symbolName: String
    switch self {
    case .maccy:
      symbolName = "doc.on.clipboard"
    case .clipboard:
      symbolName = "clipboard.fill"
    case .scissors:
      symbolName = "scissors"
    case .paperclip:
      symbolName = "paperclip"
    }

    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Maccy") ?? NSImage()
    image.isTemplate = true
    return image
  }
}
