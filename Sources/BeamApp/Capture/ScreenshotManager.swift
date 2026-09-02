import BeamCore
import Cocoa
@preconcurrency import ScreenCaptureKit
import Vision

@MainActor
final class ScreenshotManager {
    private var overlayWindows: [OverlayWindow] = []
    private let onResult: @MainActor (ScanResult) -> Void
    private var screenChangeTask: Task<Void, Never>?
    private var currentGeneration: UInt64 = 0
    private var currentTask: Task<Void, Never>?

    init(onResult: @escaping @MainActor (ScanResult) -> Void) {
        self.onResult = onResult

        self.screenChangeTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification
            ) {
                guard let self else { break }
                self.closeOverlays()
            }
        }
    }

    deinit {
        screenChangeTask?.cancel()
    }

    func startCapture() {
        // Increment generation and cancel any ongoing capture/scan work
        currentGeneration += 1
        currentTask?.cancel()
        currentTask = nil

        // Close any existing overlays
        closeOverlays()

        // Bring the app to the front so it can receive key events (like ESC) immediately
        NSApp.activate(ignoringOtherApps: true)

        // Create an overlay window on each screen
        for screen in NSScreen.screens {
            let window = OverlayWindow(
                screen: screen,
                onRegionSelected: { [weak self] rect, screenFrame in
                    self?.captureRegion(rect: rect, screenFrame: screenFrame)
                },
                onCancel: { [weak self] in
                    self?.closeOverlays()
                })
            overlayWindows.append(window)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func closeOverlays() {
        let windows = overlayWindows
        overlayWindows.removeAll()
        for window in windows {
            window.orderOut(nil)
        }
    }

    private func captureRegion(rect: CGRect, screenFrame: CGRect) {
        closeOverlays()

        currentGeneration += 1
        let generation = currentGeneration
        currentTask?.cancel()

        guard let mainScreen = NSScreen.screens.first else {
            onResult(.error("No screen found"))
            return
        }

        let mainHeight = mainScreen.frame.height

        // Convert from NS screen coords (bottom-left origin) to CG coords (top-left origin)
        let cgRect = CGRect(
            x: rect.origin.x,
            y: mainHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )

        currentTask = Task { [weak self] in
            // Allow window server 100ms to order out the overlay window before capturing
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled, let self = self, self.currentGeneration == generation else { return }

            // Use ScreenCaptureKit for reliable capture
            if #available(macOS 14.0, *) {
                do {
                    let image = try await self.captureWithSCK(rect: cgRect)
                    guard !Task.isCancelled, self.currentGeneration == generation else { return }
                    await self.scanQRCode(from: image, generation: generation)
                } catch {
                    guard !Task.isCancelled, self.currentGeneration == generation else { return }
                    self.onResult(
                        .error(
                            "Screen Capture failed: \(error.localizedDescription)\n\nIf you just granted permission, you may need to restart the app."
                        ))
                }
            } else {
                self.captureWithCGWindowList(rect: cgRect, generation: generation)
            }
        }
    }

    @available(macOS 14.0, *)
    private func captureWithSCK(rect: CGRect) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        let targetCenter = CGPoint(x: rect.midX, y: rect.midY)
        guard let display = content.displays.first(where: { $0.frame.contains(targetCenter) }) ?? content.displays.first
        else {
            throw NSError(
                domain: "Beam", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No display found for capture region"])
        }

        // Convert global CG rect to display-local coordinates
        let localRect = CGRect(
            x: rect.origin.x - display.frame.origin.x,
            y: rect.origin.y - display.frame.origin.y,
            width: rect.width,
            height: rect.height
        )

        // Clamp to display bounds to prevent SCStreamConfiguration out-of-bounds error
        let displayBounds = CGRect(origin: .zero, size: display.frame.size)
        let clampedRect = localRect.intersection(displayBounds)
        guard !clampedRect.isNull, clampedRect.width > 1, clampedRect.height > 1 else {
            throw NSError(
                domain: "Beam", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Selected region is outside display boundaries"])
        }

        // Exclude our own app windows by PID for reliability
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let appWindows = content.windows.filter { $0.owningApplication?.processID == currentPID }
        let filter = SCContentFilter(display: display, excludingWindows: appWindows)

        let scale = display.frame.width > 0 ? CGFloat(display.width) / display.frame.width : 2.0
        let config = SCStreamConfiguration()
        config.sourceRect = clampedRect
        config.width = max(1, Int(clampedRect.width * scale))
        config.height = max(1, Int(clampedRect.height * scale))
        config.showsCursor = false
        config.captureResolution = .best

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private func captureWithCGWindowList(rect: CGRect, generation: UInt64) {
        guard
            let cgImage = CGWindowListCreateImage(
                rect,
                .optionAll,
                kCGNullWindowID,
                [.bestResolution]
            )
        else {
            guard currentGeneration == generation else { return }
            onResult(
                .error(
                    "Failed to capture screen.\n\nGrant Screen Recording access in:\nSystem Settings → Privacy & Security → Screen Recording"
                ))
            return
        }

        guard cgImage.width > 1, cgImage.height > 1 else {
            guard currentGeneration == generation else { return }
            onResult(.error("Captured image is empty."))
            return
        }

        Task { [weak self] in
            await self?.scanQRCode(from: cgImage, generation: generation)
        }
    }

    // Non-isolated Vision processing worker boundary
    private nonisolated static func processVision(in image: CGImage) throws -> String? {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let results = request.results, let qrResult = results.first(where: { $0.symbology == .qr }) else {
            return nil
        }

        return qrResult.payloadStringValue
    }

    private func scanQRCode(from image: CGImage, generation: UInt64) async {
        do {
            let payload = try await Task.detached(priority: .userInitiated) {
                try Self.processVision(in: image)
            }.value

            guard !Task.isCancelled, self.currentGeneration == generation else { return }

            if let payload = payload {
                // Sensory feedback
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                if let sound = NSSound(named: "Glass") ?? NSSound(named: "Pop") {
                    sound.play()
                }

                let scanResult = ScanResult.success(payload)
                HistoryManager.shared.add(
                    title: scanResult.title,
                    summary: scanResult.summary,
                    rawPayload: payload,
                    iconName: scanResult.iconName
                )

                self.onResult(scanResult)
            } else {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                self.onResult(.noQRCodeFound)
            }
        } catch {
            guard !Task.isCancelled, self.currentGeneration == generation else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            self.onResult(.error("Failed to process image: \(error.localizedDescription)"))
        }
    }
}
