import XCTest
@testable import InstantBookReader

final class TXTAnchorResolverTests: XCTestCase {
    func testRoundTripAgainstFixtureTXT() throws {
        let text = try String(contentsOf: Fixtures.txtURL, encoding: .utf8)
        XCTAssertGreaterThan(text.utf16.count, 120, "fixture TXT must have enough text to anchor in")

        let start = 60
        let length = 12
        let nsText = text as NSString
        let original = nsText.substring(with: NSRange(location: start, length: length))

        let resolver = TXTAnchorResolver()
        let anchor = resolver.makeAnchor(in: text, startOffset: start, length: length)
        XCTAssertEqual(anchor.text, original)

        let resolved = try XCTUnwrap(resolver.resolve(anchor: anchor, in: text))
        XCTAssertEqual(resolved.startOffset, start)
        XCTAssertEqual(resolved.length, length)
        let resolvedText = nsText.substring(with: NSRange(location: resolved.startOffset, length: resolved.length))
        XCTAssertEqual(resolvedText, original)
    }
}
