import Foundation

public struct WiFiInfo: Equatable, Sendable {
    public let ssid: String
    public let password: String?
    public let security: String?
    public let hidden: Bool

    public init(ssid: String, password: String?, security: String?, hidden: Bool) {
        self.ssid = ssid
        self.password = password
        self.security = security
        self.hidden = hidden
    }

    public var isPasswordRedacted: Bool {
        password == "••••••••"
    }
}

public struct ContactInfo: Equatable, Sendable {
    public let name: String?
    public let phone: String?
    public let email: String?
    public let org: String?
    public let title: String?
    public let url: String?
    public let address: String?
    public let rawVCard: String?

    public init(
        name: String?,
        phone: String?,
        email: String?,
        org: String?,
        title: String?,
        url: String?,
        address: String?,
        rawVCard: String?
    ) {
        self.name = name
        self.phone = phone
        self.email = email
        self.org = org
        self.title = title
        self.url = url
        self.address = address
        self.rawVCard = rawVCard
    }
}

public struct OTPInfo: Equatable, Sendable {
    public let secret: String
    public let issuer: String?
    public let account: String?
    public let url: URL

    public init(secret: String, issuer: String?, account: String?, url: URL) {
        self.secret = secret
        self.issuer = issuer
        self.account = account
        self.url = url
    }

    public var isRedacted: Bool {
        secret == "••••••••"
    }
}

public struct JSONInfo: Equatable, Sendable {
    public let formatted: String
    public let raw: String

    public init(formatted: String, raw: String) {
        self.formatted = formatted
        self.raw = raw
    }
}

public struct ScanHistoryItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let title: String
    public let summary: String
    public let rawPayload: String
    public let iconName: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String,
        summary: String,
        rawPayload: String,
        iconName: String
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.summary = summary
        self.rawPayload = rawPayload
        self.iconName = iconName
    }

    public var timeAgoString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
