import Cocoa

@MainActor
final class OverlayWindow: NSWindow {
    private var onRegionSelected: ((CGRect, CGRect) -> Void)?
    private var onCancel: (() -> Void)?
    private var overlayContentView: OverlayContentView?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    convenience init(
        screen: NSScreen, onRegionSelected: @escaping (CGRect, CGRect) -> Void, onCancel: @escaping () -> Void
    ) {
        self.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.onRegionSelected = onRegionSelected
        self.onCancel = onCancel

        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.hasShadow = false
        self.isReleasedWhenClosed = false

        self.setFrame(screen.frame, display: true)

        let contentView = OverlayContentView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            onRegionSelected: { [weak self] rect in
                guard let self = self else { return }
                self.onRegionSelected?(rect, screen.frame)
            },
            onCancel: { [weak self] in
                self?.onCancel?()
            }
        )
        self.overlayContentView = contentView
        self.contentView = contentView
        self.makeFirstResponder(contentView)
        self.makeKey()
    }
}

// MARK: - Overlay Content View

@MainActor
final class OverlayContentView: NSView {
    private enum KeyCode {
        static let escape: UInt16 = 53
        static let space: UInt16 = 49
    }

    private static let dimTextAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    private static let instructionTextAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .medium),
        .foregroundColor: NSColor.white,
    ]

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var selectionRect: NSRect?
    private var isSpacePressed = false
    private let onRegionSelected: (CGRect) -> Void
    private let onCancel: () -> Void

    init(frame: NSRect, onRegionSelected: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onRegionSelected = onRegionSelected
        self.onCancel = onCancel

        super.init(frame: frame)

        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor

        // Track mouse for crosshair
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: isSpacePressed ? .openHand : .crosshair)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isSpacePressed, let start = startPoint, let current = currentPoint {
            let dx = point.x - current.x
            let dy = point.y - current.y
            startPoint = NSPoint(x: start.x + dx, y: start.y + dy)
            currentPoint = point
        } else {
            currentPoint = point
        }

        updateSelectionRect()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isSpacePressed = false
        guard let rect = selectionRect, rect.width > 10, rect.height > 10 else {
            // Too small, reset
            resetSelection()
            return
        }

        // Convert from view coordinates to screen coordinates
        let windowRect = convert(rect, to: nil)
        guard
            let screenRect = window?.convertToScreen(
                NSRect(
                    x: windowRect.origin.x,
                    y: windowRect.origin.y,
                    width: windowRect.width,
                    height: windowRect.height
                ))
        else { return }

        onRegionSelected(screenRect)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        currentPoint = point
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == KeyCode.escape {
            onCancel()
        } else if event.keyCode == KeyCode.space {
            if !isSpacePressed {
                isSpacePressed = true
                window?.invalidateCursorRects(for: self)
                needsDisplay = true
            }
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == KeyCode.space {
            isSpacePressed = false
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    // MARK: - Drawing

    private func updateSelectionRect() {
        guard let start = startPoint, let current = currentPoint else { return }
        selectionRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw dimming overlay
        NSColor.black.withAlphaComponent(0.35).setFill()

        if let rect = selectionRect, rect.width > 2, rect.height > 2 {
            // Draw dim everywhere except selection
            let path = NSBezierPath(rect: bounds)
            path.windingRule = .evenOdd
            path.appendRect(rect)
            path.fill()

            // Selection border - white dashed line
            NSColor.white.setStroke()
            let borderPath = NSBezierPath(rect: rect)
            borderPath.lineWidth = 2.0
            borderPath.setLineDash([6, 4], count: 2, phase: 0)
            borderPath.stroke()

            // Corner handles
            let handleSize: CGFloat = 8.0
            NSColor.white.setFill()
            let corners = [
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
                CGPoint(x: rect.maxX, y: rect.maxY),
            ]
            for corner in corners {
                let handleRect = NSRect(
                    x: corner.x - handleSize / 2,
                    y: corner.y - handleSize / 2,
                    width: handleSize,
                    height: handleSize
                )
                NSBezierPath(roundedRect: handleRect, xRadius: 2, yRadius: 2).fill()
            }

            // Dimensions label
            let dimText =
                isSpacePressed
                ? "⎵ Moving: \(Int(rect.width)) × \(Int(rect.height))" : "\(Int(rect.width)) × \(Int(rect.height))"
            let attrs = OverlayContentView.dimTextAttributes
            let textSize = (dimText as NSString).size(withAttributes: attrs)
            let labelPadding: CGFloat = 7
            let labelWidth = textSize.width + labelPadding * 2
            let labelHeight = textSize.height + labelPadding * 2
            var labelY = rect.minY - labelHeight - 8
            if labelY < 8 {
                labelY = rect.maxY + 8
            }
            let labelX = max(8, min(bounds.width - labelWidth - 8, rect.midX - labelWidth / 2))
            let labelRect = NSRect(
                x: labelX,
                y: labelY,
                width: labelWidth,
                height: labelHeight
            )

            // Label background
            NSColor.black.withAlphaComponent(0.75).setFill()
            NSBezierPath(roundedRect: labelRect, xRadius: 6, yRadius: 6).fill()

            // Label text
            let textRect = NSRect(
                x: labelRect.origin.x + labelPadding,
                y: labelRect.origin.y + labelPadding,
                width: textSize.width,
                height: textSize.height
            )
            (dimText as NSString).draw(in: textRect, withAttributes: attrs)
        } else {
            // No selection yet — dim everything
            bounds.fill()

            // Draw instruction text
            let instruction = "Drag to select area with QR code  •  Hold Space to move  •  ESC to cancel"
            let attrs = OverlayContentView.instructionTextAttributes
            let textSize = (instruction as NSString).size(withAttributes: attrs)
            let labelPadding: CGFloat = 14
            let labelWidth = textSize.width + labelPadding * 2
            let labelHeight = textSize.height + labelPadding * 2
            let labelX = max(14, min(bounds.width - labelWidth - 14, bounds.midX - labelWidth / 2))
            let labelY = max(24, min(bounds.height - labelHeight - 24, bounds.height - 80))
            let labelRect = NSRect(
                x: labelX,
                y: labelY,
                width: labelWidth,
                height: labelHeight
            )

            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: labelRect, xRadius: 10, yRadius: 10).fill()

            let textRect = NSRect(
                x: labelRect.origin.x + labelPadding,
                y: labelRect.origin.y + labelPadding,
                width: textSize.width,
                height: textSize.height
            )
            (instruction as NSString).draw(in: textRect, withAttributes: attrs)
        }

        // Draw crosshair at mouse position (when no selection in progress)
        if selectionRect == nil, let point = currentPoint {
            NSColor.white.withAlphaComponent(0.35).setStroke()

            let vLine = NSBezierPath()
            vLine.move(to: NSPoint(x: point.x, y: 0))
            vLine.line(to: NSPoint(x: point.x, y: bounds.height))
            vLine.lineWidth = 0.5
            vLine.setLineDash([4, 4], count: 2, phase: 0)
            vLine.stroke()

            let hLine = NSBezierPath()
            hLine.move(to: NSPoint(x: 0, y: point.y))
            hLine.line(to: NSPoint(x: bounds.width, y: point.y))
            hLine.lineWidth = 0.5
            hLine.setLineDash([4, 4], count: 2, phase: 0)
            hLine.stroke()
        }
    }

    private func resetSelection() {
        startPoint = nil
        currentPoint = nil
        selectionRect = nil
        isSpacePressed = false
        needsDisplay = true
    }
}
