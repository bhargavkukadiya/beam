import Carbon
import Cocoa

enum HotKeyError: Error, LocalizedError, Equatable, Sendable {
    case handlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .handlerInstallationFailed(let status):
            return "Failed to install keyboard event handler (OSStatus \(status))."
        case .registrationFailed(let status):
            if status == OSStatus(eventHotKeyExistsErr) {
                return "Shortcut ⌘⇧2 is already in use by another application."
            }
            return "Failed to register global hotkey (OSStatus \(status))."
        }
    }
}

@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    private var onTrigger: (@MainActor () -> Void)?

    private init() {}

    @discardableResult
    func register(onTrigger: @escaping @MainActor () -> Void) -> Result<Void, HotKeyError> {
        self.onTrigger = onTrigger
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let event = event, let userData = userData else { return noErr }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if status == noErr && hotKeyID.id == 1 {
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.onTrigger?()
                }
            }
            return noErr
        }

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )

        guard installStatus == noErr else {
            return .failure(.handlerInstallationFailed(installStatus))
        }

        // Default hotkey: ⌘ + ⇧ + 2 (kVK_ANSI_2 = 0x13 = 19)
        let hotKeyID = EventHotKeyID(signature: OSType(1_363_297_107), id: 1)  // 'QRSK'
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode: UInt32 = 19  // '2' key

        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard regStatus == noErr else {
            unregister()
            return .failure(.registrationFailed(regStatus))
        }

        return .success(())
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
