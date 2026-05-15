import XCTest
@testable import InstantBookReader

final class HighlightAnchorTests: XCTestCase {
    private let text = """
    The quick brown fox jumps over the lazy dog. The river ran deep \
    and dark beside the rocky path. Somewhere far off a wolf began to \
    howl beneath the silver moon, low and lonely. The brown fox stopped \
    and listened, then trotted on.
    """

    func testBuildAnchorCapturesSurroundingText() {
        let anchor = HighlightAnchor.build(plainText: text, startOffset: 16, length: 3) // "fox"
        XCTAssertEqual(anchor.startOffset, 16)
        XCTAssertEqual(anchor.length, 3)
        XCTAssertEqual(String(anchor.contextBefore.suffix(9)), "ck brown ")
        XCTAssertEqual(String(anchor.contextAfter.prefix(10)), " jumps ove")
    }

    func testResolveAnchorRecoversTextAtSameOffset() {
        let anchor = HighlightAnchor.build(plainText: text, startOffset: 16, length: 3)
        let resolved = HighlightAnchor.resolve(plainText: text, anchor: anchor)
        XCTAssertEqual(resolved?.startOffset, 16)
        XCTAssertEqual(resolved?.length, 3)
        let nsText = text as NSString
        XCTAssertEqual(nsText.substring(with: NSRange(location: 16, length: 3)), "fox")
    }

    func testResolveAnchorRecoversAfterPrefixShift() {
        let anchor = HighlightAnchor.build(plainText: text, startOffset: 16, length: 3)
        let shifted = "PREFIX_INSERTED. " + text
        let resolved = HighlightAnchor.resolve(plainText: shifted, anchor: anchor)
        XCTAssertNotNil(resolved)
        let nsShifted = shifted as NSString
        XCTAssertEqual(
            nsShifted.substring(with: NSRange(location: resolved!.startOffset, length: resolved!.length)),
            "fox"
        )
    }

    func testResolveAnchorPrefersFirstUniqueMatch() {
        // "brown fox" appears twice in `text`. Anchor built around the first
        // occurrence must resolve to the first occurrence, not the second.
        let firstStart = (text as NSString).range(of: "brown fox").location
        let anchor = HighlightAnchor.build(plainText: text, startOffset: firstStart, length: 9)
        let resolved = HighlightAnchor.resolve(plainText: text, anchor: anchor)
        XCTAssertEqual(resolved?.startOffset, firstStart)
    }

    func testResolveAnchorReturnsNilWhenContextDestroyed() {
        let anchor = HighlightAnchor.build(plainText: text, startOffset: 16, length: 3)
        let resolved = HighlightAnchor.resolve(plainText: "completely unrelated content", anchor: anchor)
        XCTAssertNil(resolved)
    }
}
