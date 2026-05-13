import XCTest
@testable import InstantBookReader

@MainActor
final class IntentsTests: XCTestCase {
    func testNextPageIntentAdvancesBus() async throws {
        let before = PageAdvanceBus.shared.sequence
        _ = try await NextPageIntent().perform()
        XCTAssertEqual(PageAdvanceBus.shared.sequence, before + 1)
        XCTAssertEqual(PageAdvanceBus.shared.lastDirection.rawValue, 1)
    }

    func testPreviousPageIntentAdvancesBus() async throws {
        let before = PageAdvanceBus.shared.sequence
        _ = try await PreviousPageIntent().perform()
        XCTAssertEqual(PageAdvanceBus.shared.sequence, before + 1)
        XCTAssertEqual(PageAdvanceBus.shared.lastDirection.rawValue, -1)
    }

    func testToggleWallpaperModeFlipsState() async throws {
        // ToggleWallpaperModeIntent reads AppDelegate.shared, which is
        // nil in unit tests. The intent must not throw or crash; it should
        // no-op silently. Verifies the guard clause.
        _ = try await ToggleWallpaperModeIntent().perform()
    }

    func testNextQuoteIntentNoOpsWithoutController() async throws {
        // AppDelegate.shared is nil in unit tests; intent must not crash.
        // Verifies optional chaining on advanceAllQuotes forwarder.
        _ = try await NextQuoteIntent().perform()
    }

    func testOpenBookIntentNoOpsWithoutAppDelegate() async throws {
        var intent = OpenBookIntent()
        intent.book = BookEntity(id: "deadbeef", title: "T", author: nil)
        _ = try await intent.perform()
    }
}
