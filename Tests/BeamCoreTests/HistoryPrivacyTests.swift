import XCTest

@testable import BeamCore

final class HistoryPrivacyTests: XCTestCase {

    // MARK: - Credential Sanitization Tests (History Security)

    @MainActor
    func testWiFiPasswordSanitization() {
        let rawPayload = "WIFI:S:HomeNet;T:WPA;P:MySecretPassword123;;"
        let sanitized = HistoryManager.sanitizePayload(rawPayload)

        XCTAssertFalse(sanitized.contains("MySecretPassword123"), "Password must be redacted from persistent history")
        XCTAssertTrue(sanitized.contains("P:••••••••"), "Password should be replaced with redaction placeholder")
        XCTAssertTrue(sanitized.contains("HomeNet"), "SSID should remain intact")
    }

    @MainActor
    func testOTPSanitization() {
        let rawPayload = "otpauth://totp/Company:user@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Company"
        let sanitized = HistoryManager.sanitizePayload(rawPayload)

        XCTAssertFalse(sanitized.contains("JBSWY3DPEHPK3PXP"), "2FA Secret must be redacted from persistent history")
        XCTAssertTrue(sanitized.contains("secret=••••••••"), "2FA Secret should be replaced with redaction placeholder")
        XCTAssertTrue(sanitized.contains("Company"), "Issuer should remain intact")
    }

    @MainActor
    func testWiFiPasswordWithEscapedSemicolons() {
        // Verify escaped semicolons do not bypass password redaction
        let rawPayload = "WIFI:S:MyNetwork;T:WPA;P:part1\\;part2;H:false;;"
        let sanitized = HistoryManager.sanitizePayload(rawPayload)

        XCTAssertFalse(sanitized.contains("part1"), "part1 must be redacted")
        XCTAssertFalse(sanitized.contains("part2"), "part2 must be redacted and not leaked via escaped semicolon")
        XCTAssertTrue(sanitized.contains("P:••••••••"), "Password should be replaced with placeholder")
        XCTAssertTrue(sanitized.contains("MyNetwork"), "SSID should remain")
        XCTAssertTrue(sanitized.contains("T:WPA"), "Security type should remain")
        XCTAssertTrue(sanitized.contains("H:false"), "Hidden parameter should remain")
    }

    @MainActor
    func testEncodedOTPParameterRedaction() {
        let rawPayload = "otpauth://totp/Test:alice?%73ecret=JBSWY3DPEHPK3PXP&issuer=Test"
        let sanitized = HistoryManager.sanitizePayload(rawPayload)

        XCTAssertFalse(sanitized.contains("JBSWY3DPEHPK3PXP"), "Percent-encoded secret must be redacted")
        XCTAssertTrue(sanitized.contains("••••••••"), "Placeholder must be inserted")
        XCTAssertTrue(sanitized.contains("Test"), "Issuer must remain")
    }

    @MainActor
    func testEscapedWiFiKeyRedaction() {
        let rawPayload = "WIFI:S:Test;\\P:EXAMPLE_PASSWORD;;"
        let sanitized = HistoryManager.sanitizePayload(rawPayload)

        XCTAssertFalse(sanitized.contains("EXAMPLE_PASSWORD"), "Escaped WiFi key password must be redacted")
        XCTAssertTrue(sanitized.contains("P:••••••••"), "Placeholder must replace password")
        XCTAssertTrue(sanitized.contains("Test"), "SSID must remain")
    }

    @MainActor
    func testMissingSSIDWiFiSummaryNeverLeaksPassword() {
        let rawPayload = "WIFI:P:EXAMPLE_PASSWORD;;"
        let result = ScanResult.success(rawPayload)

        XCTAssertFalse(result.summary.contains("EXAMPLE_PASSWORD"), "ScanResult summary must not leak password")
        XCTAssertEqual(result.summary, "WiFi Network")

        let suiteName = "com.scanner.tests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }

        let testManager = HistoryManager(
            storageKey: "items",
            historyEnabledKey: "enabled",
            userDefaults: testDefaults
        )
        testManager.setHistoryEnabled(true)
        testManager.add(title: result.title, summary: result.summary, rawPayload: rawPayload, iconName: result.iconName)

        let first = testManager.items[0]
        XCTAssertFalse(first.rawPayload.contains("EXAMPLE_PASSWORD"), "Stored raw payload must not leak password")
        XCTAssertFalse(first.summary.contains("EXAMPLE_PASSWORD"), "Stored summary must not leak password")
        XCTAssertEqual(first.summary, "WiFi Network")
    }

    @MainActor
    func testReviewProbesHarness() throws {
        let suite = "com.beam.review.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = HistoryManager(storageKey: "items", historyEnabledKey: "enabled", userDefaults: defaults)
        manager.setHistoryEnabled(true)

        let samples: [(String, String, String)] = [
            ("standard OTP", "otpauth://totp/Test:alice?secret=JBSWY3DPEHPK3PXP&issuer=Test", "JBSWY3DPEHPK3PXP"),
            ("encoded OTP key", "otpauth://totp/Test:alice?%73ecret=JBSWY3DPEHPK3PXP&issuer=Test", "JBSWY3DPEHPK3PXP"),
            ("escaped WiFi key", "WIFI:S:Test;\\P:EXAMPLE_PASSWORD;;", "EXAMPLE_PASSWORD"),
            ("missing SSID", "WIFI:P:EXAMPLE_PASSWORD;;", "EXAMPLE_PASSWORD"),
            ("standard WiFi", "WIFI:S:Test;T:WPA;P:EXAMPLE_PASSWORD;;", "EXAMPLE_PASSWORD"),
        ]
        for (name, payload, secret) in samples {
            manager.purgePersistedHistory()
            let result = ScanResult.success(payload)
            manager.add(title: result.title, summary: result.summary, rawPayload: payload, iconName: result.iconName)
            guard let data = defaults.data(forKey: "items"),
                let stored = try? JSONDecoder().decode([ScanHistoryItem].self, from: data),
                !stored.isEmpty
            else {
                XCTFail("Failed to decode history items for \(name)")
                continue
            }
            let first = stored[0]
            XCTAssertFalse(first.rawPayload.contains(secret), "\(name) rawLeaks: secret found in rawPayload")
            XCTAssertFalse(first.summary.contains(secret), "\(name) summaryLeaks: secret found in summary")
        }
    }

    @MainActor
    func testExistingSecretsMigration() {
        let suiteName = "com.scanner.tests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            testDefaults.removePersistentDomain(forName: suiteName)
        }

        let storageKey = "com.scanner.scanHistory"
        let historyEnabledKey = "com.scanner.isHistoryEnabled"

        // Enable history for migration test
        testDefaults.set(true, forKey: historyEnabledKey)

        // Seed unredacted legacy items into isolated test suite
        let legacyWifi = ScanHistoryItem(
            title: "WiFi Network Found",
            summary: "WiFi: OldOffice",
            rawPayload: "WIFI:S:OldOffice;T:WPA;P:unredactedSecretPass\\;stillSecret;;",
            iconName: "wifi"
        )
        let legacyOTP = ScanHistoryItem(
            title: "2FA Auth Key Found",
            summary: "2FA: LegacyCorp",
            rawPayload: "otpauth://totp/LegacyCorp:bob?secret=LEAKEDLEGACYSECRET123&issuer=LegacyCorp",
            iconName: "lock.shield.fill"
        )

        let legacyData = try! JSONEncoder().encode([legacyWifi, legacyOTP])
        testDefaults.set(legacyData, forKey: storageKey)

        // Initialize an isolated HistoryManager pointing to test suite
        let testManager = HistoryManager(
            storageKey: storageKey,
            historyEnabledKey: historyEnabledKey,
            userDefaults: testDefaults
        )

        // Verify items in memory are sanitized upon load
        XCTAssertEqual(testManager.items.count, 2)
        let migratedWifi = testManager.items[0]
        let migratedOTP = testManager.items[1]

        XCTAssertFalse(migratedWifi.rawPayload.contains("unredactedSecretPass"))
        XCTAssertFalse(migratedWifi.rawPayload.contains("stillSecret"))
        XCTAssertTrue(migratedWifi.rawPayload.contains("P:••••••••"))

        XCTAssertFalse(migratedOTP.rawPayload.contains("LEAKEDLEGACYSECRET123"))
        XCTAssertTrue(migratedOTP.rawPayload.contains("secret=••••••••"))

        // Verify items in UserDefaults suite were immediately persisted in sanitized form
        guard let reloadedData = testDefaults.data(forKey: storageKey),
            let persistedItems = try? JSONDecoder().decode([ScanHistoryItem].self, from: reloadedData)
        else {
            XCTFail("Failed to decode persisted migrated items from UserDefaults")
            return
        }

        XCTAssertFalse(persistedItems[0].rawPayload.contains("unredactedSecretPass"))
        XCTAssertFalse(persistedItems[0].rawPayload.contains("stillSecret"))
        XCTAssertFalse(persistedItems[1].rawPayload.contains("LEAKEDLEGACYSECRET123"))
    }

    @MainActor
    func testHistoryOptInPrivacy() {
        let suiteName = "com.scanner.tests.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer {
            testDefaults.removePersistentDomain(forName: suiteName)
        }

        let storageKey = "com.scanner.scanHistory"
        let historyEnabledKey = "com.scanner.isHistoryEnabled"

        let testManager = HistoryManager(
            storageKey: storageKey,
            historyEnabledKey: historyEnabledKey,
            userDefaults: testDefaults
        )

        // 1. By default, history retention is disabled
        XCTAssertFalse(testManager.isHistoryEnabled)

        // 2. Adding an item stores it in memory for session, but NOT to disk
        testManager.add(title: "Test", summary: "Summary", rawPayload: "https://apple.com", iconName: "link")
        XCTAssertEqual(testManager.items.count, 1)
        XCTAssertNil(testDefaults.data(forKey: storageKey), "Payloads must not be persisted to disk without opt-in")

        // 3. Explicitly enabling history persists current items to disk
        testManager.setHistoryEnabled(true)
        XCTAssertTrue(testManager.isHistoryEnabled)
        XCTAssertNotNil(testDefaults.data(forKey: storageKey), "Items must be saved once opt-in is enabled")

        // 4. Disabling history immediately purges disk records
        testManager.setHistoryEnabled(false)
        XCTAssertFalse(testManager.isHistoryEnabled)
        XCTAssertNil(testDefaults.data(forKey: storageKey), "Stored records must be purged upon disabling history")

        // 5. Purging history removes both in-memory and disk records
        testManager.setHistoryEnabled(true)
        testManager.purgePersistedHistory()
        XCTAssertEqual(testManager.items.count, 0)
        XCTAssertNil(testDefaults.data(forKey: storageKey))
    }
}
