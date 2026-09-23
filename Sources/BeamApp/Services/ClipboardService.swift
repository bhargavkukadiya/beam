import AppKit

@MainActor
final class ClipboardService {
    static let shared = ClipboardService()

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
