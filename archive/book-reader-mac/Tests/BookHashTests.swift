import XCTest
@testable import InstantBookReader

final class BookHashTests: XCTestCase {
    func testHashOfKnownStringMatchesExpected() throws {
        let data = "hello world".data(using: .utf8)!
        let hex = BookHash.sha256Hex(of: data)
        XCTAssertEqual(hex, "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
    }

    func testHashOfFileMatchesHashOfData() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookhash-\(UUID().uuidString).bin")
        let bytes = Data((0..<4096).map { _ in UInt8.random(in: 0...255) })
        try bytes.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let fromData = BookHash.sha256Hex(of: bytes)
        let fromFile = try BookHash.sha256Hex(ofFileAt: tmp)
        XCTAssertEqual(fromData, fromFile)
    }
}
