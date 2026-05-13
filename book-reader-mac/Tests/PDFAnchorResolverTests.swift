import XCTest
import PDFKit
@testable import InstantBookReader

final class PDFAnchorResolverTests: XCTestCase {
    func testRoundTripSelectionToAnchorBackToSelection() throws {
        let url = Fixtures.pdfURL
        let doc = try XCTUnwrap(PDFDocument(url: url))
        let page = try XCTUnwrap(doc.page(at: 0))
        let pageText = page.string ?? ""
        XCTAssertGreaterThan(pageText.count, 8, "fixture PDF must have at least 8 chars of text on page 0")

        // Pick a probe slice from the middle so context is real on both sides.
        let total = (pageText as NSString).length
        let probeLen = min(4, max(1, total / 4))
        let lower = max(1, total / 2 - probeLen / 2)
        let safeLower = min(lower, total - probeLen)
        let nsText = pageText as NSString
        let probeRange = NSRange(location: safeLower, length: probeLen)
        let probeText = nsText.substring(with: probeRange)
        let selection = try XCTUnwrap(page.selection(for: probeRange))
        XCTAssertEqual(selection.string, probeText)

        let resolver = PDFAnchorResolver()
        let anchor = resolver.makeAnchor(from: selection, on: page, pageIndex: 0)
        XCTAssertEqual(anchor.text, probeText)
        XCTAssertEqual(anchor.pageIndex, 0)

        let resolved = try XCTUnwrap(resolver.resolve(anchor: anchor, in: doc))
        XCTAssertEqual(resolved.selection.string, probeText)
        XCTAssertEqual(resolved.pageIndex, 0)
    }

    func testResolveReturnsNilWhenContextDoesNotMatch() throws {
        let url = Fixtures.pdfURL
        let doc = try XCTUnwrap(PDFDocument(url: url))
        let resolver = PDFAnchorResolver()
        let anchor = PDFAnchorResolver.Anchor(
            pageIndex: 0,
            text: "definitely-not-in-this-pdf-xyzzy-987",
            inner: HighlightAnchor(startOffset: 0, length: 36,
                                   contextBefore: "nope-no-such-context-before-anywhere",
                                   contextAfter: "nope-no-such-context-after-anywhere")
        )
        XCTAssertNil(resolver.resolve(anchor: anchor, in: doc))
    }
}
