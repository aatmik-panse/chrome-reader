import XCTest
@testable import InstantBookReader

@MainActor
final class UpdateControllerTests: XCTestCase {
    func testCanInstantiateController() {
        let controller = UpdateController.shared
        XCTAssertNotNil(controller.updater)
    }

    func testCheckForUpdatesInvokesUpdater() {
        // checkForUpdates is fire-and-forget; just verify it doesn't crash.
        UpdateController.shared.checkForUpdates(nil)
    }
}
