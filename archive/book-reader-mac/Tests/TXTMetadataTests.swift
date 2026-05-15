import XCTest
import AppKit
@testable import InstantBookReader

final class TXTMetadataTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        let url = Bundle(for: type(of: self)).url(forResource: "sample", withExtension: "txt")
        return try XCTUnwrap(url, "sample.txt fixture missing")
    }

    func testTitleDerivedFromFilename() throws {
        let parsed = try TXTMetadata.parse(at: try fixtureURL())
        XCTAssertEqual(parsed.title, "sample")
        XCTAssertNil(parsed.author)
    }

    func testTitleStripsExtensionAndUnderscores() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("the_pale_horse_v2.txt")
        try "body".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let parsed = try TXTMetadata.parse(at: tmp)
        XCTAssertEqual(parsed.title, "the pale horse v2")
    }

    func testRenderCoverProducesNonEmptyImage() throws {
        let image = try TXTMetadata.renderCover(at: try fixtureURL(),
                                                size: CGSize(width: 400, height: 600))
        XCTAssertEqual(image.size, CGSize(width: 400, height: 600))
    }
}
