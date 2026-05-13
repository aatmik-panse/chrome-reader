import XCTest
@testable import InstantBookReader

final class PageModeEPUBCSSTests: XCTestCase {

    func testCSSConstrainsToSafeColumnWidth() {
        let css = PageModeEPUBView.injectedCSS(
            safeColumnWidth: 720,
            bodyPointSize: 22
        )
        XCTAssertTrue(css.contains("max-width: 720px"),
                      "expected max-width directive, got:\n\(css)")
    }

    func testCSSDisablesAutoColumns() {
        let css = PageModeEPUBView.injectedCSS(
            safeColumnWidth: 720,
            bodyPointSize: 22
        )
        XCTAssertTrue(css.contains("column-width: none"),
                      "expected `column-width: none`, got:\n\(css)")
        XCTAssertTrue(css.contains("column-count: 1"),
                      "expected `column-count: 1`, got:\n\(css)")
    }

    func testCSSAppliesPhysicalBodyPointSize() {
        let css = PageModeEPUBView.injectedCSS(
            safeColumnWidth: 720,
            bodyPointSize: 28
        )
        XCTAssertTrue(css.contains("font-size: 28pt"),
                      "expected font-size: 28pt, got:\n\(css)")
    }

    func testCSSChangesWithBodySize() {
        let small = PageModeEPUBView.injectedCSS(safeColumnWidth: 720, bodyPointSize: 22)
        let large = PageModeEPUBView.injectedCSS(safeColumnWidth: 720, bodyPointSize: 30)
        XCTAssertNotEqual(small, large)
    }
}
