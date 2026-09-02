import XCTest

@testable import BeamCore

final class URLSecurityTests: XCTestCase {

    // MARK: - URL Scheme Safety Tests

    func testURLSchemeSafety() {
        // Safe standard schemes
        XCTAssertTrue(ScanResult.isSafeScheme("http"))
        XCTAssertTrue(ScanResult.isSafeScheme("https"))
        XCTAssertTrue(ScanResult.isSafeScheme("mailto"))
        XCTAssertTrue(ScanResult.isSafeScheme("tel"))
        XCTAssertTrue(ScanResult.isSafeScheme("sms"))
        XCTAssertTrue(ScanResult.isSafeScheme("maps"))
        XCTAssertTrue(ScanResult.isSafeScheme("geo"))

        // Custom / potentially dangerous schemes that require explicit confirmation
        XCTAssertFalse(ScanResult.isSafeScheme("terminal"))
        XCTAssertFalse(ScanResult.isSafeScheme("applescript"))
        XCTAssertFalse(ScanResult.isSafeScheme("file"))
        XCTAssertFalse(ScanResult.isSafeScheme("javascript"))
        XCTAssertFalse(ScanResult.isSafeScheme("data"))
        XCTAssertFalse(ScanResult.isSafeScheme("slack"))
        XCTAssertFalse(ScanResult.isSafeScheme(nil))
    }

    // MARK: - Actionable Link Interpretation Tests

    func testActionableLinkInterpretation() {
        // Escaped spaces must not be double-encoded to %2520
        let spaceResult = ScanResult.success("example.com/a%20b")
        let spaceLink = LinkParser.parseActionableLink(from: spaceResult)
        XCTAssertNotNil(spaceLink)
        XCTAssertEqual(spaceLink?.url.absoluteString, "https://example.com/a%20b")

        // Hash fragments must be preserved as URL fragments rather than encoded path components
        let fragmentResult = ScanResult.success("example.com/path#fragment")
        let fragmentLink = LinkParser.parseActionableLink(from: fragmentResult)
        XCTAssertNotNil(fragmentLink)
        XCTAssertEqual(fragmentLink?.url.absoluteString, "https://example.com/path#fragment")
        XCTAssertEqual(fragmentLink?.url.fragment, "fragment")

        // Schemeless domains with port numbers must normalize to HTTPS rather than custom scheme
        let portResult = ScanResult.success("example.com:8080/path")
        let portLink = LinkParser.parseActionableLink(from: portResult)
        XCTAssertNotNil(portLink)
        XCTAssertEqual(portLink?.url.absoluteString, "https://example.com:8080/path")
        XCTAssertEqual(portLink?.isSafe, true)

        // Numbers, JSON objects, and JSON arrays must not be interpreted as actionable URLs
        XCTAssertNil(LinkParser.parseActionableLink(from: ScanResult.success("1.2")))
        XCTAssertNil(LinkParser.parseActionableLink(from: ScanResult.success("{\"x\":1.2}")))
        XCTAssertNil(LinkParser.parseActionableLink(from: ScanResult.success("[\"example.com\"]")))
    }
}
