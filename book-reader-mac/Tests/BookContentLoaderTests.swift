import XCTest
@testable import InstantBookReader

final class BookContentLoaderTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testReadsBytesByHash() throws {
        let payload = Data([0x42, 0x4F, 0x4F, 0x4B]) // "BOOK"
        let file = tmp.appendingPathComponent("abc123.epub")
        try payload.write(to: file)
        let loader = BookContentLoader(booksDirectory: tmp)
        let data = try loader.read(hash: "abc123", ext: "epub")
        XCTAssertEqual(data, payload)
    }

    func testMimeTypeForEachFormat() {
        XCTAssertEqual(BookContentLoader.mimeType(forExtension: "epub"), "application/epub+zip")
        XCTAssertEqual(BookContentLoader.mimeType(forExtension: "pdf"), "application/pdf")
        XCTAssertEqual(BookContentLoader.mimeType(forExtension: "txt"), "text/plain; charset=utf-8")
        XCTAssertEqual(BookContentLoader.mimeType(forExtension: "unknown"), "application/octet-stream")
    }

    func testReadThrowsWhenMissing() {
        let loader = BookContentLoader(booksDirectory: tmp)
        XCTAssertThrowsError(try loader.read(hash: "nope", ext: "epub")) { error in
            XCTAssertTrue("\(error)".contains("nope"))
        }
    }
}
