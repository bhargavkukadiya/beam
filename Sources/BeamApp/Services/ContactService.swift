import BeamCore
@preconcurrency import Contacts
import Foundation

@MainActor
protocol ContactSaving {
    func save(_ contact: ContactInfo) async throws
}

@MainActor
final class ContactService: ContactSaving {
    static let shared = ContactService()

    func save(_ contact: ContactInfo) async throws {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .authorized:
            break
        case .notDetermined:
            do {
                guard try await store.requestAccess(for: .contacts) else {
                    throw ContactServiceError.accessNotGranted
                }
            } catch let error as ContactServiceError {
                throw error
            } catch {
                throw ContactServiceError.authorizationFailed(error.localizedDescription)
            }
        case .denied, .restricted:
            throw ContactServiceError.accessDenied
        @unknown default:
            throw ContactServiceError.unknownAuthorizationStatus
        }

        let saveRequest = CNSaveRequest()
        if let mutableContact = contactFromVCard(contact.rawVCard) {
            saveRequest.add(mutableContact, toContainerWithIdentifier: nil)
        } else {
            saveRequest.add(makeContact(from: contact), toContainerWithIdentifier: nil)
        }

        do {
            try store.execute(saveRequest)
        } catch {
            throw ContactServiceError.saveFailed(error.localizedDescription)
        }
    }

    private func contactFromVCard(_ rawVCard: String?) -> CNMutableContact? {
        guard let rawVCard,
            let data = rawVCard.data(using: .utf8),
            let contact = try? CNContactVCardSerialization.contacts(with: data).first,
            let mutable = contact.mutableCopy() as? CNMutableContact
        else {
            return nil
        }
        return mutable
    }

    private func makeContact(from contact: ContactInfo) -> CNMutableContact {
        let mutable = CNMutableContact()
        if let name = contact.name {
            let parts = name.split(separator: " ")
            if let first = parts.first {
                mutable.givenName = String(first)
                mutable.familyName = parts.dropFirst().joined(separator: " ")
            }
        }
        if let phone = contact.phone {
            mutable.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: phone))
            ]
        }
        if let email = contact.email {
            mutable.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
        }
        if let org = contact.org {
            mutable.organizationName = org
        }
        if let title = contact.title {
            mutable.jobTitle = title
        }
        if let url = contact.url {
            mutable.urlAddresses = [CNLabeledValue(label: CNLabelURLAddressHomePage, value: url as NSString)]
        }
        if let address = contact.address {
            let postal = CNMutablePostalAddress()
            postal.street = address
            mutable.postalAddresses = [CNLabeledValue(label: CNLabelHome, value: postal)]
        }
        return mutable
    }
}

private enum ContactServiceError: LocalizedError {
    case accessNotGranted
    case accessDenied
    case unknownAuthorizationStatus
    case authorizationFailed(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessNotGranted:
            return "Contacts access was not granted."
        case .accessDenied:
            return "Access to Contacts is denied. Please grant permission in:\nSystem Settings → Privacy & Security → Contacts"
        case .unknownAuthorizationStatus:
            return "Unknown Contacts authorization status."
        case .authorizationFailed(let message):
            return "Contacts authorization error: \(message)"
        case .saveFailed(let message):
            return "Failed to save contact: \(message)"
        }
    }
}
