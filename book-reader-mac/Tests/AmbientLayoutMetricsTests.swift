import XCTest
@testable import InstantBookReader

final class AmbientLayoutMetricsTests: XCTestCase {
    func testCardWidthMatchesSpec() {
        XCTAssertEqual(AmbientLayoutMetrics.cardWidth, 360)
    }

    func testCoverSizeMatchesSpec() {
        XCTAssertEqual(AmbientLayoutMetrics.coverSize.width, 60)
        XCTAssertEqual(AmbientLayoutMetrics.coverSize.height, 80)
    }

    func testQuoteFontSizeShortQuoteIsLarge() {
        XCTAssertEqual(AmbientLayoutMetrics.quoteFontSize(for: "Short."), 44)
    }

    func testQuoteFontSizeBoundaryAt120CharsIsLarge() {
        let s = String(repeating: "a", count: 120)
        XCTAssertEqual(AmbientLayoutMetrics.quoteFontSize(for: s), 44)
    }

    func testQuoteFontSizeAbove120CharsIsSmall() {
        let s = String(repeating: "a", count: 121)
        XCTAssertEqual(AmbientLayoutMetrics.quoteFontSize(for: s), 28)
    }

    func testQuoteLeadingMatchesLengthBucket() {
        XCTAssertEqual(AmbientLayoutMetrics.quoteLeadingMultiple(for: "Short."), 1.25, accuracy: 0.001)
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(AmbientLayoutMetrics.quoteLeadingMultiple(for: long), 1.45, accuracy: 0.001)
    }

    func testQuoteTruncationCapAt280() {
        let raw = String(repeating: "x", count: 400)
        let result = AmbientLayoutMetrics.truncateForDisplay(raw)
        XCTAssertTrue(result.wasTruncated)
        XCTAssertLessThanOrEqual(result.text.count, 280)
    }

    func testShortQuoteIsNotTruncated() {
        let raw = "Hello world."
        let result = AmbientLayoutMetrics.truncateForDisplay(raw)
        XCTAssertFalse(result.wasTruncated)
        XCTAssertEqual(result.text, raw)
    }

    func testLabelTrackingMatchesClay() {
        XCTAssertEqual(AmbientLayoutMetrics.labelTracking, 1.08, accuracy: 0.001)
    }
}
