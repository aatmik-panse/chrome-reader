import XCTest
import PDFKit
@testable import InstantBookReader

final class PDFDisplayModeTests: XCTestCase {
    func testMapsToPDFKitModes() {
        XCTAssertEqual(PDFDisplayModeOption.singlePage.pdfKit, .singlePage)
        XCTAssertEqual(PDFDisplayModeOption.singlePageContinuous.pdfKit, .singlePageContinuous)
        XCTAssertEqual(PDFDisplayModeOption.twoUp.pdfKit, .twoUp)
        XCTAssertEqual(PDFDisplayModeOption.twoUpContinuous.pdfKit, .twoUpContinuous)
    }

    func testAllCasesHaveLabels() {
        for option in PDFDisplayModeOption.allCases {
            XCTAssertFalse(option.label.isEmpty)
        }
    }
}
