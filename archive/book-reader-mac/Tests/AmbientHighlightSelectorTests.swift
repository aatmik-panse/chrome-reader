import XCTest
@testable import InstantBookReader

final class AmbientHighlightSelectorTests: XCTestCase {
    private func makeHighlight(_ text: String, note: String? = nil) -> Highlight {
        Highlight(bookHash: "h",
                  text: text,
                  surroundingText: text,
                  offset: 0,
                  note: note)
    }

    func testEmptyPoolReturnsNil() {
        let selector = AmbientHighlightSelector(highlights: [], seed: 1)
        XCTAssertNil(selector.next())
        XCTAssertNil(selector.next())
    }

    func testSingleElementPoolRepeats() {
        let only = makeHighlight("Only one.")
        let selector = AmbientHighlightSelector(highlights: [only], seed: 1)
        XCTAssertEqual(selector.next()?.text, "Only one.")
        XCTAssertEqual(selector.next()?.text, "Only one.")
        XCTAssertEqual(selector.next()?.text, "Only one.")
    }

    func testNoteOnlyHighlightsAreSkipped() {
        let valid = makeHighlight("Valid quote.")
        let blank = makeHighlight("", note: "a note but no text")
        let whitespace = makeHighlight("   \n  ", note: "whitespace text")
        let selector = AmbientHighlightSelector(
            highlights: [blank, valid, whitespace],
            seed: 1
        )
        // 30 draws — none should ever return the blank-text rows.
        for _ in 0..<30 {
            XCTAssertEqual(selector.next()?.text, "Valid quote.")
        }
    }

    func testShufflePresentsEveryHighlightBeforeRepeating() {
        let pool = (0..<4).map { makeHighlight("h\($0)") }
        let selector = AmbientHighlightSelector(highlights: pool, seed: 42)

        var firstCycle: [String] = []
        for _ in 0..<4 {
            firstCycle.append(selector.next()!.text)
        }
        XCTAssertEqual(Set(firstCycle), Set(["h0", "h1", "h2", "h3"]),
                       "all four highlights appear in one cycle")

        var secondCycle: [String] = []
        for _ in 0..<4 {
            secondCycle.append(selector.next()!.text)
        }
        XCTAssertEqual(Set(secondCycle), Set(["h0", "h1", "h2", "h3"]),
                       "second cycle covers all again")
    }

    func testSameSeedReproducesSameShuffle() {
        let pool = (0..<5).map { makeHighlight("h\($0)") }
        let a = AmbientHighlightSelector(highlights: pool, seed: 7)
        let b = AmbientHighlightSelector(highlights: pool, seed: 7)
        for _ in 0..<10 {
            XCTAssertEqual(a.next()?.text, b.next()?.text)
        }
    }
}
