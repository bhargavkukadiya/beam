import Contacts
import Foundation

public enum ScanResult: Equatable, Sendable {
    case success(String)
    case noQRCodeFound
    case error(String)

    // Set of URL schemes recognized as safe to open directly
    public static var safeURLSchemes: Set<String> {
        LinkParser.safeURLSchemes
    }

    public static func isSafeScheme(_ scheme: String?) -> Bool {
        LinkParser.isSafeScheme(scheme)
    }

    public var title: String {
        switch self {
        case .success:
            if wifiInfo != nil { return "WiFi Network Found" }
            if contactInfo != nil { return "Contact Found" }
            if otpInfo != nil { return "2FA Auth Key Found" }
            if jsonInfo != nil { return "JSON Data Found" }
            return "QR Code Found"
        case .noQRCodeFound:
            return "No QR Code Found"
        case .error:
            return "Error"
        }
    }

    public var message: String {
        switch self {
        case .success(let value): return formatPayload(value)
        case .noQRCodeFound: return "No QR code was detected in the selected area. Try again with a clearer image."
        case .error(let msg): return msg
        }
    }

    public var rawMessage: String {
        switch self {
        case .success(let value): return value
        case .noQRCodeFound: return message
        case .error: return message
        }
    }

    public var summary: String {
        switch self {
        case .success(let payload):
            if let wifi = wifiInfo { return "WiFi: \(wifi.ssid)" }
            if let contact = contactInfo {
                return "Contact: \(contact.name ?? contact.phone ?? contact.email ?? "Unknown")"
            }
            if let otp = otpInfo { return "2FA: \(otp.issuer ?? otp.account ?? "Auth Key")" }

            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            let upper = trimmed.uppercased()
            if upper.hasPrefix("WIFI:") {
                return "WiFi Network"
            }
            if trimmed.lowercased().hasPrefix("otpauth://") {
                return "2FA Auth Key"
            }
            if trimmed.count > 45 {
                return String(trimmed.prefix(45)) + "..."
            }
            return trimmed
        case .noQRCodeFound:
            return "No QR Code"
        case .error(let msg):
            return msg
        }
    }

    public var wifiInfo: WiFiInfo? {
        guard case .success(let payload) = self else { return nil }
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("WIFI:") else { return nil }
        let fields = parseKeyValuePairs(from: trimmed, prefixLength: 5)
        guard let ssid = fields["S"], !ssid.isEmpty else { return nil }
        return WiFiInfo(
            ssid: ssid,
            password: fields["P"],
            security: fields["T"],
            hidden: fields["H"]?.lowercased() == "true"
        )
    }

    public var contactInfo: ContactInfo? {
        guard case .success(let payload) = self else { return nil }
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)

        // MECARD
        if trimmed.uppercased().hasPrefix("MECARD:") {
            let fields = parseKeyValuePairs(from: trimmed, prefixLength: 7)
            let contact = ContactInfo(
                name: fields["N"],
                phone: fields["TEL"],
                email: fields["EMAIL"],
                org: fields["ORG"],
                title: nil,
                url: fields["URL"],
                address: fields["ADR"],
                rawVCard: nil
            )
            guard
                (contact.name != nil && !contact.name!.isEmpty) || (contact.phone != nil && !contact.phone!.isEmpty)
                    || (contact.email != nil && !contact.email!.isEmpty)
                    || (contact.org != nil && !contact.org!.isEmpty)
            else {
                return nil
            }
            return contact
        }

        // vCard
        if trimmed.uppercased().hasPrefix("BEGIN:VCARD") {
            // First attempt: standard Apple CNContactVCardSerialization for full fidelity
            if let data = trimmed.data(using: .utf8),
                let contacts = try? CNContactVCardSerialization.contacts(with: data),
                let contact = contacts.first
            {
                let name: String? = {
                    let formatted = CNContactFormatter.string(from: contact, style: .fullName)
                    if let f = formatted, !f.trimmingCharacters(in: .whitespaces).isEmpty {
                        return f
                    }
                    let combined = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                    return combined.isEmpty ? nil : combined
                }()

                let phone = contact.phoneNumbers.first?.value.stringValue
                let email = contact.emailAddresses.first?.value as String?
                let org = contact.organizationName.isEmpty ? nil : contact.organizationName
                let title = contact.jobTitle.isEmpty ? nil : contact.jobTitle
                let url = contact.urlAddresses.first?.value as String?

                var addressStr: String? = nil
                if let postal = contact.postalAddresses.first?.value {
                    let formatted = CNPostalAddressFormatter.string(from: postal, style: .mailingAddress)
                    let singleLine = formatted.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(
                        separator: ", ")
                    addressStr = singleLine.isEmpty ? nil : singleLine
                }

                let contact = ContactInfo(
                    name: name,
                    phone: phone,
                    email: email,
                    org: org,
                    title: title,
                    url: url,
                    address: addressStr,
                    rawVCard: trimmed
                )
                if (contact.name != nil && !contact.name!.isEmpty) || (contact.phone != nil && !contact.phone!.isEmpty)
                    || (contact.email != nil && !contact.email!.isEmpty)
                    || (contact.org != nil && !contact.org!.isEmpty)
                {
                    return contact
                }
            }

            // Fallback line parser for non-standard/partially formatted vCards
            var name: String?
            var org: String?
            var title: String?
            var phone: String?
            var email: String?
            var url: String?
            var address: String?

            let lines = trimmed.components(separatedBy: .newlines)
            for line in lines {
                let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                let upper = trimmedLine.uppercased()

                if upper.hasPrefix("FN:") {
                    name = String(trimmedLine.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                } else if upper.hasPrefix("N:") && name == nil {
                    let parts = trimmedLine.dropFirst(2).split(separator: ";", omittingEmptySubsequences: false).map {
                        String($0).trimmingCharacters(in: .whitespaces)
                    }
                    let lastName = parts.indices.contains(0) ? parts[0] : ""
                    let firstName = parts.indices.contains(1) ? parts[1] : ""
                    let combined = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
                    if !combined.isEmpty { name = combined }
                } else if upper.hasPrefix("ORG:") {
                    org = String(trimmedLine.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                } else if upper.hasPrefix("TITLE:") {
                    title = String(trimmedLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                } else if upper.hasPrefix("TEL") && phone == nil {
                    let comps = trimmedLine.split(separator: ":", maxSplits: 1)
                    if comps.count == 2 { phone = String(comps[1]).trimmingCharacters(in: .whitespaces) }
                } else if upper.hasPrefix("EMAIL") && email == nil {
                    let comps = trimmedLine.split(separator: ":", maxSplits: 1)
                    if comps.count == 2 { email = String(comps[1]).trimmingCharacters(in: .whitespaces) }
                } else if upper.hasPrefix("URL") && url == nil {
                    let comps = trimmedLine.split(separator: ":", maxSplits: 1)
                    if comps.count == 2 { url = String(comps[1]).trimmingCharacters(in: .whitespaces) }
                } else if upper.hasPrefix("ADR") && address == nil {
                    let comps = trimmedLine.split(separator: ":", maxSplits: 1)
                    if comps.count == 2 {
                        let adrParts = comps[1].split(separator: ";").map {
                            String($0).trimmingCharacters(in: .whitespaces)
                        }.filter { !$0.isEmpty }
                        address = adrParts.joined(separator: ", ")
                    }
                }
            }

            let contact = ContactInfo(
                name: name,
                phone: phone,
                email: email,
                org: org,
                title: title,
                url: url,
                address: address,
                rawVCard: trimmed
            )
            guard
                (contact.name != nil && !contact.name!.isEmpty) || (contact.phone != nil && !contact.phone!.isEmpty)
                    || (contact.email != nil && !contact.email!.isEmpty)
                    || (contact.org != nil && !contact.org!.isEmpty)
            else {
                return nil
            }
            return contact
        }

        return nil
    }

    /// Determines whether a query parameter name matches the OTP secret key parameter.
    public static func isSecretQueryParam(named name: String) -> Bool {
        name.caseInsensitiveCompare("secret") == .orderedSame
    }

    public var otpInfo: OTPInfo? {
        guard case .success(let payload) = self else { return nil }
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("otpauth://"), let url = URL(string: trimmed) else { return nil }
        guard let host = url.host?.lowercased(), host == "totp" || host == "hotp" else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }

        var secret = ""
        var issuer: String?
        var account: String?

        if let rawLabel = components.percentEncodedPath.split(separator: "/").last {
            let decoded = String(rawLabel).removingPercentEncoding ?? String(rawLabel)
            if let colonIdx = decoded.firstIndex(of: ":") {
                let pathIssuer = String(decoded[..<colonIdx]).trimmingCharacters(in: .whitespaces)
                let pathAccount = String(decoded[decoded.index(after: colonIdx)...]).trimmingCharacters(
                    in: .whitespaces)
                if issuer == nil && !pathIssuer.isEmpty {
                    issuer = pathIssuer
                }
                account = pathAccount.isEmpty ? decoded : pathAccount
            } else {
                account = decoded
            }
        }

        for item in components.queryItems ?? [] {
            if Self.isSecretQueryParam(named: item.name), let val = item.value {
                secret = val
            } else if item.name.caseInsensitiveCompare("issuer") == .orderedSame, let val = item.value {
                issuer = val
            }
        }

        guard !secret.isEmpty else { return nil }
        if secret != "••••••••" {
            let validBase32 = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=")
            guard secret.uppercased().unicodeScalars.allSatisfy({ validBase32.contains($0) }) else {
                return nil
            }
        }
        return OTPInfo(secret: secret, issuer: issuer, account: account, url: url)
    }

    public var jsonInfo: JSONInfo? {
        guard case .success(let payload) = self else { return nil }
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
        else { return nil }

        if let data = trimmed.data(using: .utf8),
            let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
            let prettyData = try? JSONSerialization.data(
                withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
            let prettyString = String(data: prettyData, encoding: .utf8)
        {
            return JSONInfo(formatted: prettyString, raw: trimmed)
        }
        return nil
    }

    private func formatPayload(_ payload: String) -> String {
        // 1. JSON
        if let json = jsonInfo {
            return json.formatted
        }

        // 2. WiFi
        if let wifi = wifiInfo {
            var formatted = "📶 WiFi Network\n\n"
            formatted += "Network (SSID): \(wifi.ssid)\n"
            if let pass = wifi.password { formatted += "Password:       \(pass)\n" }
            if let sec = wifi.security { formatted += "Security:       \(sec)\n" }
            if wifi.hidden { formatted += "Hidden:         Yes\n" }
            return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 3. Contact
        if let contact = contactInfo {
            var formatted = "👤 Contact Card\n\n"
            if let name = contact.name { formatted += "Name:     \(name)\n" }
            if let title = contact.title { formatted += "Title:    \(title)\n" }
            if let org = contact.org { formatted += "Company:  \(org)\n" }
            if let phone = contact.phone { formatted += "Phone:    \(phone)\n" }
            if let email = contact.email { formatted += "Email:    \(email)\n" }
            if let url = contact.url { formatted += "Website:  \(url)\n" }
            if let address = contact.address { formatted += "Address:  \(address)\n" }
            return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 4. OTP
        if let otp = otpInfo {
            var formatted = "🔐 Two-Factor Authentication\n\n"
            if let issuer = otp.issuer { formatted += "Issuer:  \(issuer)\n" }
            if let account = otp.account { formatted += "Account: \(account)\n" }
            formatted += "Secret:  \(otp.secret)\n"
            return formatted.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return payload
    }

    private func parseKeyValuePairs(from payload: String, prefixLength: Int) -> [String: String] {
        let content = payload.dropFirst(prefixLength)
        var fields: [String: String] = [:]

        var current = ""
        var isEscaped = false
        var tokens: [String] = []

        for char in content {
            if isEscaped {
                current.append(char)
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == ";" {
                if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                    tokens.append(current)
                }
                current = ""
            } else {
                current.append(char)
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            tokens.append(current)
        }

        for token in tokens {
            if let colonIndex = token.firstIndex(of: ":") {
                let key = String(token[..<colonIndex]).uppercased()
                let value = String(token[token.index(after: colonIndex)...])
                fields[key] = value
            }
        }
        return fields
    }

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }

    public var iconName: String {
        switch self {
        case .success:
            if wifiInfo != nil { return "wifi" }
            if contactInfo != nil { return "person.crop.circle.fill" }
            if otpInfo != nil { return "lock.shield.fill" }
            if jsonInfo != nil { return "curlybraces" }
            return "checkmark.circle.fill"
        case .noQRCodeFound:
            return "viewfinder"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}
