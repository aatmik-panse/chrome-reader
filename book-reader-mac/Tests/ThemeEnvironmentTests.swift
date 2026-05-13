import XCTest
import SwiftUI
@testable import InstantBookReader

final class ThemeEnvironmentTests: XCTestCase {
    func testClayDarkTokensHaveExpectedHexValues() {
        let theme = AppTheme.clayDark
        XCTAssertEqual(theme.ink.hexString, "#F0EDE8")
        XCTAssertEqual(theme.surface.hexString, "#1A1815")
        XCTAssertEqual(theme.border.hexString, "#3A362F")
    }

    func testClayLightTokensHaveExpectedHexValues() {
        let theme = AppTheme.clayLight
        XCTAssertEqual(theme.ink.hexString, "#1A1815")
        XCTAssertEqual(theme.surface.hexString, "#FAF9F7")
    }

    func testHexStringRoundTrip() {
        let color = AppColor(hex: "#ABCDEF")
        XCTAssertEqual(color.hexString.uppercased(), "#ABCDEF")
    }
}
