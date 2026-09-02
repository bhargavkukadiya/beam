import BeamCore
import Cocoa
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var screenshotManager: ScreenshotManager!
    private var resultWindow: ResultWindowController?
    private var hotKeyErrorMessage: String?
    private var launchAtLoginErrorMessage: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "qrcode.viewfinder", accessibilityDescription: "Beam")
            button.image?.size = NSSize(width: 18, height: 18)
            button.action = #selector(statusBarButtonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        // Initialize screenshot manager
        screenshotManager = ScreenshotManager { [weak self] result in
            self?.showResult(result)
        }

        // Register global hotkey (⌘ + ⇧ + 2)
        let hotKeyResult = HotKeyManager.shared.register { [weak self] in
            self?.screenshotManager.startCapture()
        }
        if case .failure(let error) = hotKeyResult {
            NSLog("[Beam] HotKey registration failed: \(error.localizedDescription)")
            self.hotKeyErrorMessage = error.localizedDescription
        }
    }

    @objc func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        let isRightClick =
            event.type == .rightMouseUp || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))

        if isRightClick {
            showMenu()
        } else {
            // Start screenshot capture
            screenshotManager.startCapture()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let scanItem = NSMenuItem(title: "Scan QR Code", action: #selector(scanAction), keyEquivalent: "2")
        scanItem.keyEquivalentModifierMask = [.command, .shift]
        scanItem.target = self
        menu.addItem(scanItem)

        if let errorMsg = hotKeyErrorMessage {
            let errorItem = NSMenuItem(title: "⚠️ Hotkey unavailable: \(errorMsg)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        // Recent Scans Submenu
        let historyMenu = NSMenu()

        let saveHistoryItem = NSMenuItem(
            title: "Save Scan History", action: #selector(toggleSaveHistory), keyEquivalent: "")
        saveHistoryItem.target = self
        saveHistoryItem.state = HistoryManager.shared.isHistoryEnabled ? .on : .off
        historyMenu.addItem(saveHistoryItem)
        historyMenu.addItem(.separator())

        let historyItems = HistoryManager.shared.items

        if historyItems.isEmpty {
            let emptyItem = NSMenuItem(title: "No Recent Scans", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historyMenu.addItem(emptyItem)
        } else {
            for item in historyItems.prefix(8) {
                // Cap visible label length to prevent excessively wide menus
                let maxSummaryLength = 32
                let displaySummary =
                    item.summary.count > maxSummaryLength
                    ? String(item.summary.prefix(maxSummaryLength)) + "…"
                    : item.summary

                let menuItem = NSMenuItem(
                    title: "\(displaySummary) (\(item.timeAgoString))",
                    action: #selector(historyItemClicked(_:)),
                    keyEquivalent: ""
                )
                menuItem.toolTip = "\(item.title)\n\(item.summary)"
                menuItem.representedObject = item
                menuItem.target = self
                historyMenu.addItem(menuItem)
            }

            historyMenu.addItem(.separator())
            let clearItem = NSMenuItem(title: "Clear History", action: #selector(clearHistoryAction), keyEquivalent: "")
            clearItem.target = self
            historyMenu.addItem(clearItem)
        }

        let historyMenuItem = NSMenuItem(title: "Recent Scans", action: nil, keyEquivalent: "")
        historyMenuItem.submenu = historyMenu
        menu.addItem(historyMenuItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        if #available(macOS 13.0, *) {
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
        menu.addItem(loginItem)

        if let loginErr = launchAtLoginErrorMessage {
            let errItem = NSMenuItem(title: "⚠️ Login Item: \(loginErr)", action: nil, keyEquivalent: "")
            errItem.isEnabled = false
            menu.addItem(errItem)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Beam", action: #selector(quitAction), keyEquivalent: "q").target = self

        if let button = statusItem.button {
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
        }
    }

    @objc func historyItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ScanHistoryItem else { return }
        // Display result window directly without hijacking the user's pasteboard
        let scanResult = ScanResult.success(item.rawPayload)
        showResult(scanResult)
    }

    @objc func toggleSaveHistory() {
        let current = HistoryManager.shared.isHistoryEnabled
        HistoryManager.shared.setHistoryEnabled(!current)
    }

    @objc func clearHistoryAction() {
        HistoryManager.shared.purgePersistedHistory()
    }

    @objc func toggleLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
                launchAtLoginErrorMessage = nil
            } catch {
                launchAtLoginErrorMessage = error.localizedDescription
                let alert = NSAlert()
                alert.messageText = "Launch at Login Failed"
                alert.informativeText =
                    "Unable to update Login Items: \(error.localizedDescription)\n\nPlease check System Settings > General > Login Items."
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    @objc func scanAction() {
        statusItem.menu = nil
        screenshotManager.startCapture()
    }

    @objc func quitAction() {
        NSApp.terminate(nil)
    }

    func showResult(_ result: ScanResult) {
        // Close previous result window
        resultWindow?.close()

        let controller = ResultWindowController(result: result) { [weak self] in
            self?.resultWindow = nil
        }
        resultWindow = controller
        controller.showWindow(nil)
    }
}
