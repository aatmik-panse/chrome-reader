import XCTest
import AppKit
@testable import InstantBookReader

final class PDFMetadataTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        let url = Bundle(for: type(of: self)).url(forResource: "sample", withExtension: "pdf")
        return try XCTUnwrap(url, "sample.pdf fixture missing")
    }

    func testParseReadsTitleAndAuthor() throws {
        let parsed = try PDFMetadata.parse(at: try fixtureURL())
        XCTAssertEqual(parsed.title, "The Lighthouse Keeper")
        XCTAssertEqual(parsed.author, "Joseph Marlow")
    }

    func testRenderCoverProducesAtLeastOnePixel() throws {
        let image = try PDFMetadata.renderCover(at: try fixtureURL(),
                                                size: CGSize(width: 400, height: 600))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }
}
