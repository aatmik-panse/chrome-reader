import XCTest
import AppKit
@testable import InstantBookReader

final class CoverExtractorTests: XCTestCase {
    private var tempCoverDir: URL!

    override func setUpWithError() throws {
        tempCoverDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoverExtractorTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempCoverDir,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempCoverDir)
    }

    private func fixture(_ name: String, ext: String) throws -> URL {
        let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: ext)
        return try XCTUnwrap(url, "\(name).\(ext) fixture missing")
    }

    func testEPUBCoverWritesPNGAtSha256Path() throws {
        let src = try fixture("sample", ext: "epub")
        let written = try CoverExtractor.extract(
            from: src, format: .epub, sha256: "abc123",
            coversDirectory: tempCoverDir
        )
        XCTAssertEqual(written.lastPathComponent, "abc123.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path))
        let data = try Data(contentsOf: written)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])  // PNG magic
    }

    func testPDFCoverWritesPNG() throws {
        let src = try fixture("sample", ext: "pdf")
        let written = try CoverExtractor.extract(
            from: src, format: .pdf, sha256: "pdf-1",
            coversDirectory: tempCoverDir
        )
        XCTAssertEqual(written.lastPathComponent, "pdf-1.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path))
    }

    func testTXTCoverWritesPNG() throws {
        let src = try fixture("sample", ext: "txt")
        let written = try CoverExtractor.extract(
            from: src, format: .txt, sha256: "txt-1",
            coversDirectory: tempCoverDir
        )
        XCTAssertEqual(written.lastPathComponent, "txt-1.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path))
    }
}
