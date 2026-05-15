import XCTest
@testable import InstantBookReader

final class EPUBMetadataTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "sample", withExtension: "epub")
        return try XCTUnwrap(url, "sample.epub fixture missing from test bundle")
    }

    func testParsesTitleAuthorAndCover() throws {
        let url = try fixtureURL()
        let parsed = try EPUBMetadata.parse(at: url)
        XCTAssertEqual(parsed.title, "The Lighthouse Keeper")
        XCTAssertEqual(parsed.author, "Joseph Marlow")
        XCTAssertNotNil(parsed.coverImageData, "cover bytes should be extracted")
        // The fixture's cover is a 1x1 PNG, so check the PNG magic header.
        let prefix = parsed.coverImageData!.prefix(8)
        let expected: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual(Array(prefix), expected)
    }

    func testParseThrowsForNonZIPFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-an-epub-\(UUID().uuidString).epub")
        try "definitely not a zip".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertThrowsError(try EPUBMetadata.parse(at: tmp))
    }
}
