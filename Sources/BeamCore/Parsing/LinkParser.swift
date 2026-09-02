import Foundation

public struct ActionableLink: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let icon: String
    public let isSafe: Bool

    public init(url: URL, title: String, icon: String, isSafe: Bool) {
        self.url = url
        self.title = title
        self.icon = icon
        self.isSafe = isSafe
    }
}

public enum LinkParser {
    // Set of URL schemes recognized as safe to open directly
    public static let safeURLSchemes: Set<String> = ["http", "https", "mailto", "tel", "sms", "maps", "geo"]

    public static func isSafeScheme(_ scheme: String?) -> Bool {
        guard let scheme = scheme?.lowercased(), !scheme.isEmpty else { return false }
        return safeURLSchemes.contains(scheme)
    }

    public static func parseActionableLink(from result: ScanResult) -> ActionableLink? {
        guard result.isSuccess else { return nil }
        // Exclude structured payloads (JSON, Wi-Fi, Contact, OTP) from actionable link heuristics
        guard result.jsonInfo == nil, result.wifiInfo == nil, result.contactInfo == nil, result.otpInfo == nil else {
            return nil
        }
        let trimmed = result.rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Direct standard scheme with authority (e.g. "https://...", "http://...", "custom://...")
        if trimmed.contains("://"), let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
            let isSafe = isSafeScheme(scheme)
            switch scheme {
            case "http", "https":
                return ActionableLink(url: url, title: "Open in Browser", icon: "safari", isSafe: true)
            default:
                return ActionableLink(
                    url: url,
                    title: "Open \"\(scheme):\" Link",
                    icon: "arrow.up.right.square",
                    isSafe: isSafe
                )
            }
        }

        // 2. Known standard schemes without authority (mailto:, tel:, sms:, maps:, geo:)
        let directSchemes = ["mailto", "tel", "sms", "maps", "geo"]
        if let colonIdx = trimmed.firstIndex(of: ":") {
            let schemeCandidate = String(trimmed[..<colonIdx]).lowercased()
            if directSchemes.contains(schemeCandidate), let url = URL(string: trimmed) {
                switch schemeCandidate {
                case "mailto":
                    return ActionableLink(url: url, title: "Send Email", icon: "envelope", isSafe: true)
                case "tel":
                    return ActionableLink(url: url, title: "Call Number", icon: "phone", isSafe: true)
                case "sms":
                    return ActionableLink(url: url, title: "Send Message", icon: "message", isSafe: true)
                case "maps", "geo":
                    return ActionableLink(url: url, title: "Open in Maps", icon: "map", isSafe: true)
                default:
                    break
                }
            }
        }

        // 3. Schemeless domain or domain:port (e.g. "github.com", "example.com:8080/path", "example.com/a%20b")
        if !trimmed.contains(" ") && !trimmed.contains("\n") {
            let candidateString = "https://" + trimmed
            if let url = URL(string: candidateString), let host = url.host {
                let hostParts = host.split(separator: ".")
                let isLocalhost = host.lowercased() == "localhost"
                let hasValidTLD =
                    hostParts.count >= 2 && (hostParts.last?.count ?? 0) >= 2
                    && hostParts.last!.allSatisfy({
                        $0.isLetter
                    })
                if isLocalhost || hasValidTLD {
                    return ActionableLink(url: url, title: "Open in Browser", icon: "safari", isSafe: true)
                }
            }
        }

        return nil
    }
}
