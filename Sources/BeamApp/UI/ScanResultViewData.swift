import BeamCore

/// Captures the result's derived display values once so SwiftUI body updates don't
/// repeatedly parse the same scanned payload.
struct ScanResultViewData {
    let result: ScanResult
    let title: String
    let message: String
    let rawMessage: String
    let iconName: String
    let isSuccess: Bool
    let wifiInfo: WiFiInfo?
    let contactInfo: ContactInfo?
    let otpInfo: OTPInfo?
    let jsonInfo: JSONInfo?
    let actionableLink: ActionableLink?

    init(result: ScanResult) {
        self.result = result
        title = result.title
        message = result.message
        rawMessage = result.rawMessage
        iconName = result.iconName
        isSuccess = result.isSuccess
        wifiInfo = result.wifiInfo
        contactInfo = result.contactInfo
        otpInfo = result.otpInfo
        jsonInfo = result.jsonInfo
        actionableLink = LinkParser.parseActionableLink(from: result)
    }
}
