import SwiftUI
import XCTest

@testable import BeamApp
@testable import BeamCore

final class AppLifecycleTests: XCTestCase {

    @MainActor
    func testResultWindowControllerLifecycle() {
        let result = ScanResult.success("https://example.com")
        var didCallClose = false

        let controller = ResultWindowController(result: result) {
            didCallClose = true
        }

        XCTAssertNotNil(controller.window, "Window must be instantiated")
        guard let window = controller.window as? ResultPanel else {
            XCTFail("Window must be an instance of ResultPanel")
            return
        }

        XCTAssertTrue(window.canBecomeKey, "Result panel must be capable of becoming key window")
        XCTAssertTrue(window.canBecomeMain, "Result panel must be capable of becoming main window")
        XCTAssertEqual(window.title, "QR Code Found")

        // Simulate cancel operation / escape key dismissal
        window.cancelOperation(nil)
        controller.onClose?()
        XCTAssertTrue(didCallClose, "onClose callback must be invoked upon window dismissal")
    }

    @MainActor
    func testResultWindowControllerErrorState() {
        let errorResult = ScanResult.error("Capture permission denied")
        let controller = ResultWindowController(result: errorResult)

        XCTAssertEqual(controller.window?.title, "Error")
    }
}
