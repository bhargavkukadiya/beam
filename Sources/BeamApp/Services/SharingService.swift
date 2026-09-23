import AppKit

@MainActor
final class SharingService {
    static let shared = SharingService()

    func present(items: [Any], from view: NSView) {
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
    }
}
