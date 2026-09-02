import Foundation

extension Notification.Name {
    public static let scanHistoryDidChange = Notification.Name("scanHistoryDidChange")
}

@MainActor
public final class HistoryManager {
    public static let shared = HistoryManager()
    private let storageKey: String
    private let historyEnabledKey: String
    private let maxItems = 30
    private let userDefaults: UserDefaults

    public private(set) var items: [ScanHistoryItem] = []
    public private(set) var isHistoryEnabled: Bool = false

    public init(
        storageKey: String = "com.beam.scanHistory",
        historyEnabledKey: String = "com.beam.isHistoryEnabled",
        userDefaults: UserDefaults = .standard
    ) {
        self.storageKey = storageKey
        self.historyEnabledKey = historyEnabledKey
        self.userDefaults = userDefaults
        load()
    }

    /// Redacts sensitive credentials (Wi-Fi passwords, OTPauth seeds) to prevent insecure persistence
    public static func sanitizePayload(_ payload: String) -> String {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)

        // Redact Wi-Fi password with full escape-character and key canonicalization
        if trimmed.uppercased().hasPrefix("WIFI:") {
            let content = trimmed.dropFirst(5)
            var currentToken = ""
            var isEscaped = false
            var tokens: [String] = []

            for char in content {
                if isEscaped {
                    currentToken.append("\\")
                    currentToken.append(char)
                    isEscaped = false
                } else if char == "\\" {
                    isEscaped = true
                } else if char == ";" {
                    tokens.append(currentToken)
                    currentToken = ""
                } else {
                    currentToken.append(char)
                }
            }
            if isEscaped {
                currentToken.append("\\")
            }
            if !currentToken.isEmpty {
                tokens.append(currentToken)
            }

            var sanitizedTokens: [String] = []
            for token in tokens {
                let trimmedToken = token.trimmingCharacters(in: .whitespaces)
                if let colonIdx = trimmedToken.firstIndex(of: ":") {
                    let keyPart = String(trimmedToken[..<colonIdx])
                    let normalizedKey = keyPart.replacingOccurrences(of: "\\", with: "")
                        .trimmingCharacters(in: .whitespaces).uppercased()
                    if normalizedKey == "P" {
                        sanitizedTokens.append("P:••••••••")
                        continue
                    }
                }
                if !token.isEmpty {
                    sanitizedTokens.append(token)
                }
            }

            return "WIFI:" + sanitizedTokens.joined(separator: ";") + ";;"
        }

        // Redact OTPauth secret key with percent-encoding awareness
        if trimmed.lowercased().hasPrefix("otpauth://") {
            if let regex = try? NSRegularExpression(pattern: "([?&])([^=&#]+)=([^&#]*)", options: []) {
                let nsString = trimmed as NSString
                let matches = regex.matches(
                    in: trimmed, options: [], range: NSRange(location: 0, length: nsString.length))
                var result = trimmed
                var didRedact = false
                for match in matches.reversed() {
                    let nameRange = match.range(at: 2)
                    let name = nsString.substring(with: nameRange)
                    let decodedName = name.removingPercentEncoding ?? name
                    if decodedName.caseInsensitiveCompare("secret") == .orderedSame {
                        let valRange = match.range(at: 3)
                        let startIdx = result.index(result.startIndex, offsetBy: valRange.location)
                        let endIdx = result.index(startIdx, offsetBy: valRange.length)
                        result.replaceSubrange(startIdx..<endIdx, with: "••••••••")
                        didRedact = true
                    }
                }
                if didRedact {
                    return result
                }
            }
        }

        return payload
    }

    public func add(title: String, summary: String, rawPayload: String, iconName: String) {
        let sanitized = Self.sanitizePayload(rawPayload)
        let safeResult = ScanResult.success(sanitized)
        let safeSummary = safeResult.summary
        let safeTitle = safeResult.title
        let safeIcon = safeResult.iconName

        let newItem = ScanHistoryItem(
            title: safeTitle,
            summary: safeSummary,
            rawPayload: sanitized,
            iconName: safeIcon
        )

        // Remove duplicate if same raw payload exists recently
        items.removeAll { $0.rawPayload == sanitized }

        items.insert(newItem, at: 0)
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }

        if isHistoryEnabled {
            save()
        }
        NotificationCenter.default.post(name: .scanHistoryDidChange, object: nil)
    }

    public func setHistoryEnabled(_ enabled: Bool) {
        isHistoryEnabled = enabled
        userDefaults.set(enabled, forKey: historyEnabledKey)
        if enabled {
            save()
        } else {
            userDefaults.removeObject(forKey: storageKey)
        }
        NotificationCenter.default.post(name: .scanHistoryDidChange, object: nil)
    }

    public func clear() {
        items.removeAll()
        if isHistoryEnabled {
            save()
        }
        NotificationCenter.default.post(name: .scanHistoryDidChange, object: nil)
    }

    public func purgePersistedHistory() {
        items.removeAll()
        userDefaults.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: .scanHistoryDidChange, object: nil)
    }

    private func save() {
        guard isHistoryEnabled else { return }
        if let data = try? JSONEncoder().encode(items) {
            userDefaults.set(data, forKey: storageKey)
        }
    }

    public func load() {
        isHistoryEnabled = userDefaults.bool(forKey: historyEnabledKey)
        guard isHistoryEnabled else {
            // Privacy by default: if history is disabled, ensure no stale records remain on disk
            userDefaults.removeObject(forKey: storageKey)
            items = []
            return
        }

        guard let data = userDefaults.data(forKey: storageKey),
            let loaded = try? JSONDecoder().decode([ScanHistoryItem].self, from: data)
        else {
            items = []
            return
        }

        var migratedItems: [ScanHistoryItem] = []
        var didMigrate = false

        for item in loaded {
            let sanitized = Self.sanitizePayload(item.rawPayload)
            let safeResult = ScanResult.success(sanitized)
            let safeSummary = safeResult.summary
            let safeTitle = safeResult.title
            let safeIcon = safeResult.iconName

            if sanitized != item.rawPayload || item.summary != safeSummary {
                didMigrate = true
                migratedItems.append(
                    ScanHistoryItem(
                        id: item.id,
                        date: item.date,
                        title: safeTitle,
                        summary: safeSummary,
                        rawPayload: sanitized,
                        iconName: safeIcon
                    ))
            } else {
                migratedItems.append(item)
            }
        }

        items = migratedItems
        if didMigrate {
            save()
        }
    }
}
