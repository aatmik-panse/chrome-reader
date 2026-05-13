import AppKit
import XCTest
@testable import InstantBookReader

@MainActor
final class AccessibilityFlagsTests: XCTestCase {
    func testDefaultFlagsMatchWorkspaceState() {
        let flags = AccessibilityFlags()
        // Defaults should mirror NSWorkspace.shared values at init time.
        XCTAssertEqual(flags.reduceMotion, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        XCTAssertEqual(flags.reduceTransparency, NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        XCTAssertEqual(flags.increaseContrast, NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    }

    func testRefreshUpdatesFromWorkspace() {
        let flags = AccessibilityFlags()
        flags.reduceMotion = !flags.reduceMotion // simulate stale
        flags.refresh()
        XCTAssertEqual(flags.reduceMotion, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}
