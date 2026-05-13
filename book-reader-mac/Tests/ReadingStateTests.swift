import XCTest
import Observation
@testable import InstantBookReader

final class ReadingStateTests: XCTestCase {
    @MainActor
    func testInitialStateHasNoCurrentBook() {
        let state = ReadingState()
        XCTAssertNil(state.currentBookHash)
        XCTAssertEqual(state.ambientMode, .atomic)
    }

    @MainActor
    func testSettingCurrentBookHashEmitsObservation() async {
        let state = ReadingState()
        var observed: [String?] = []
        let exp = expectation(description: "two observations")
        exp.expectedFulfillmentCount = 2

        let task = Task { @MainActor in
            withObservationTracking {
                observed.append(state.currentBookHash)
                exp.fulfill()
            } onChange: {
                Task { @MainActor in
                    observed.append(state.currentBookHash)
                    exp.fulfill()
                }
            }
        }
        await task.value

        state.currentBookHash = "abc123"
        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(observed, [nil, "abc123"])
    }

    @MainActor
    func testToggleAmbientMode() {
        let state = ReadingState()
        XCTAssertEqual(state.ambientMode, .atomic)
        state.ambientMode = .page
        XCTAssertEqual(state.ambientMode, .page)
    }
}
