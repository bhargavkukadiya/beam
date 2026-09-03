import XCTest

@testable import BeamCore

final class ParsingTests: XCTestCase {

    // MARK: - vCard Tests

    func testVCardParsingWithSerialization() {
        let vcard = """
            BEGIN:VCARD
            VERSION:3.0
            N:Appleseed;John;;;
            FN:John Appleseed
            ORG:Apple Inc.;
            TITLE:Senior Director
            TEL;TYPE=WORK,VOICE:(555) 555-1234
            EMAIL;TYPE=PREF,INTERNET:john.appleseed@apple.com
            ADR;TYPE=WORK:;;One Apple Park Way;Cupertino;CA;95014;USA
            URL:https://www.apple.com
            END:VCARD
            """

        let result = ScanResult.success(vcard)
        guard let contact = result.contactInfo else {
            XCTFail("Failed to parse contactInfo from vCard")
            return
        }

        XCTAssertEqual(contact.name, "John Appleseed")
        XCTAssertEqual(contact.org, "Apple Inc.")
        XCTAssertEqual(contact.title, "Senior Director")
        XCTAssertEqual(contact.phone, "(555) 555-1234")
        XCTAssertEqual(contact.email, "john.appleseed@apple.com")
        XCTAssertEqual(contact.url, "https://www.apple.com")
        XCTAssertNotNil(contact.address)
        XCTAssertTrue(contact.address?.contains("Apple Park") ?? false)
    }

    // MARK: - MECARD Tests

    func testMECARDParsing() {
        let mecard = "MECARD:N:Doe,Jane;TEL:555-9876;EMAIL:jane@example.com;ADR:123 Main St, Springfield;;"
        let result = ScanResult.success(mecard)

        guard let contact = result.contactInfo else {
            XCTFail("Failed to parse MECARD")
            return
        }

        XCTAssertEqual(contact.name, "Doe,Jane")
        XCTAssertEqual(contact.phone, "555-9876")
        XCTAssertEqual(contact.email, "jane@example.com")
        XCTAssertEqual(contact.address, "123 Main St, Springfield")
    }

    // MARK: - WiFi Tests

    func testWiFiParsing() {
        let wifi = "WIFI:S:MyOfficeWiFi;T:WPA;P:SuperSecretPass;H:true;;"
        let result = ScanResult.success(wifi)

        guard let info = result.wifiInfo else {
            XCTFail("Failed to parse WiFi")
            return
        }

        XCTAssertEqual(info.ssid, "MyOfficeWiFi")
        XCTAssertEqual(info.security, "WPA")
        XCTAssertEqual(info.password, "SuperSecretPass")
        XCTAssertTrue(info.hidden)
    }

    // MARK: - JSON Formatting Tests

    func testJSONParsing() {
        let raw = "{\"name\":\"scanner\",\"active\":true,\"count\":42}"
        let result = ScanResult.success(raw)

        guard let json = result.jsonInfo else {
            XCTFail("Failed to parse JSON")
            return
        }

        XCTAssertTrue(
            json.formatted.contains("\"name\" : \"scanner\"") || json.formatted.contains("\"name\": \"scanner\""))
        XCTAssertEqual(json.raw, raw)
    }

    // MARK: - OTP Parsing Tests

    func testOTPInfoParsing() {
        let raw = "otpauth://totp/GitHub:alice?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=GitHub"
        let result = ScanResult.success(raw)

        guard let otp = result.otpInfo else {
            XCTFail("Failed to parse OTP")
            return
        }

        XCTAssertEqual(otp.secret, "HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ")
        XCTAssertEqual(otp.issuer, "GitHub")
        XCTAssertEqual(otp.account, "alice")
    }

    func testOTPEncodedSeparatorsInLabel() {
        let raw = "otpauth://totp/Issuer:alice%2Fdev?secret=JBSWY3DPEHPK3PXP"
        let result = ScanResult.success(raw)

        guard let otp = result.otpInfo else {
            XCTFail("Failed to parse OTP with encoded slash in label")
            return
        }

        XCTAssertEqual(otp.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(otp.issuer, "Issuer")
        XCTAssertEqual(otp.account, "alice/dev")
    }

    func testOTPPreservedLiteralPercentsInLabel() {
        let raw = "otpauth://totp/Acme%25Corp:alice?secret=JBSWY3DPEHPK3PXP"
        let result = ScanResult.success(raw)

        guard let otp = result.otpInfo else {
            XCTFail("Failed to parse OTP with percent sequence in label")
            return
        }

        XCTAssertEqual(otp.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(otp.issuer, "Acme%Corp")
        XCTAssertEqual(otp.account, "alice")
    }

    func testOTPEncodedSecretQueryParameter() {
        let singleEncoded = "otpauth://totp/Test:alice?%73ecret=JBSWY3DPEHPK3PXP&issuer=Test"
        let result = ScanResult.success(singleEncoded)
        guard let otp = result.otpInfo else {
            XCTFail("Failed to parse OTP with single percent-encoded secret parameter")
            return
        }
        XCTAssertEqual(otp.secret, "JBSWY3DPEHPK3PXP")
        XCTAssertEqual(otp.issuer, "Test")

        let doubleEncoded = "otpauth://totp/Test:alice?%2573ecret=JBSWY3DPEHPK3PXP&issuer=Test"
        XCTAssertNil(ScanResult.success(doubleEncoded).otpInfo, "Double-encoded parameter must not be parsed as secret")
    }

    // MARK: - Malformed Payload Validation Tests

    func testMalformedPayloadsRejected() {
        // Empty MECARD
        XCTAssertNil(ScanResult.success("MECARD:").contactInfo)
        XCTAssertNil(ScanResult.success("MECARD:;;").contactInfo)

        // Bare vCard without meaningful contact fields
        XCTAssertNil(ScanResult.success("BEGIN:VCARD\nEND:VCARD").contactInfo)
        XCTAssertNil(ScanResult.success("BEGIN:VCARD\nVERSION:3.0\nEND:VCARD").contactInfo)

        // Invalid OTP types and invalid secret seeds
        XCTAssertNil(ScanResult.success("otpauth://invalid-type/alice?secret=not-base32").otpInfo)
        XCTAssertNil(ScanResult.success("otpauth://totp/alice").otpInfo)
        XCTAssertNil(ScanResult.success("otpauth://totp/alice?secret=").otpInfo)
        XCTAssertNil(ScanResult.success("otpauth://totp/alice?secret=189").otpInfo)
    }
}
