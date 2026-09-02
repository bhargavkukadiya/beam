import BeamCore
import Cocoa
import SwiftUI

@MainActor
final class ResultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        self.close()
    }
}

@MainActor
final class ResultWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (@MainActor () -> Void)?

    convenience init(result: ScanResult, onClose: (@MainActor () -> Void)? = nil) {
        let contentView = ResultView(result: result)
        let hostingController = NSHostingController(rootView: contentView)

        let window = ResultPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 420, height: 300)

        window.title = result.title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.center()

        // Appear with smooth spring animation
        window.alphaValue = 0

        self.init(window: window)
        self.onClose = onClose
        window.delegate = self

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }

        // Bring app to front and activate window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
