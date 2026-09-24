import AppKit

class Notifier {
  static func notify(body _: String?, sound: NSSound?) {
    sound?.play()
  }
}
