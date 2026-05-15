import XCTest
import AppKit
@testable import InstantBookReader

final class SafeColumnTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    func testCenteredColumnIsCenteredHorizontally() {
        let col = SafeColumn.frame(for: screen, placement: .center, width: 720)
        let expectedX = (screen.width - 720) / 2
        XCTAssertEqual(col.minX, expectedX, accuracy: 0.5)
        XCTAssertEqual(col.width, 720, accuracy: 0.5)
        XCTAssertEqual(col.height, screen.height, accuracy: 0.5)
    }

    func testLeftPlacementHasLeftMargin() {
        let col = SafeColumn.frame(for: screen, placement: .left, width: 720)
        XCTAssertGreaterThan(col.minX, 40)
        XCTAssertLessThan(col.minX, 200)
    }

    func testRightPlacementReservesIconArea() {
        let col = SafeColumn.frame(for: screen, placement: .right, width: 720)
        let rightGap = screen.width - col.maxX
        XCTAssertGreaterThanOrEqual(rightGap, SafeColumn.reservedRightInsetForIcons,
            "right placement must keep \(SafeColumn.reservedRightInsetForIcons)pt clear for desktop icons")
    }

    func testCenterPlacementOnUltraWideStillReservesIconArea() {
        // 5K Studio Display logical 5120x2880 — center column is still well
        // clear of the right 200pt strip.
        let big = CGRect(x: 0, y: 0, width: 5120, height: 2880)
        let col = SafeColumn.frame(for: big, placement: .center, width: 720)
        let rightGap = big.width - col.maxX
        XCTAssertGreaterThanOrEqual(rightGap, SafeColumn.reservedRightInsetForIcons)
    }

    func testWidthIsConfigurable() {
        let col = SafeColumn.frame(for: screen, placement: .center, width: 900)
        XCTAssertEqual(col.width, 900, accuracy: 0.5)
    }

    func testReservedRightInsetIs200() {
        // Spec §6.3: Right ~200pt always reserved for desktop icons.
        XCTAssertEqual(SafeColumn.reservedRightInsetForIcons, 200)
    }
}
