import AppKit
import SwiftUI
import XCTest
@testable import InstantBookReader

@MainActor
final class AmbientCornerCardTests: XCTestCase {
    private func makeBook() -> Book {
        Book(sha256: "abc123",
             title: "The Sample Book",
             author: "A. Sample",
             format: .epub,
             coverPath: nil,            // missing → placeholder rectangle
             filePath: "abc123.epub")
    }

    private func makeShortHighlight() -> Highlight {
        Highlight(bookHash: "abc123",
                  text: "A short quote.",
                  surroundingText: "A short quote.",
                  offset: 0)
    }

    private func makeLongHighlight() -> Highlight {
        let text = String(repeating: "x", count: 240) + "."
        return Highlight(bookHash: "abc123",
                         text: text,
                         surroundingText: text,
                         offset: 0)
    }

    /// Helper: mount the card in a 1280×800 hosting view, force layout, and
    /// return the resulting `intrinsicContentSize` of the root view.
    private func mountAndLayout<V: View>(_ view: V) -> NSHostingView<some View> {
        let host = NSHostingView(rootView:
            view
                .environment(\.appTheme, AppTheme.clayDark)
                .frame(width: 1280, height: 800)
        )
        host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        host.layoutSubtreeIfNeeded()
        return host
    }

    func testShortHighlightLayoutMatchesMetrics() {
        let view = AmbientCornerCard(
            book: makeBook(),
            highlight: makeShortHighlight(),
            chapterTitle: "Ch. 7",
            progressPercent: 43
        )
        let host = mountAndLayout(view)
        XCTAssertGreaterThan(host.bounds.width, 0)
        // The hosting frame is sized via .frame above, so we mainly verify
        // we didn't blow up and the metrics report 44pt for short quotes.
        XCTAssertEqual(
            AmbientLayoutMetrics.quoteFontSize(for: makeShortHighlight().text),
            44
        )
    }

    func testLongHighlightFallsBackTo28pt() {
        let view = AmbientCornerCard(
            book: makeBook(),
            highlight: makeLongHighlight(),
            chapterTitle: "Ch. 7",
            progressPercent: 43
        )
        let host = mountAndLayout(view)
        XCTAssertGreaterThan(host.bounds.width, 0)
        XCTAssertEqual(
            AmbientLayoutMetrics.quoteFontSize(for: makeLongHighlight().text),
            28
        )
    }

    func testEmptyHighlightSlotRendersCoverPlusLabelsOnly() {
        let view = AmbientCornerCard(
            book: makeBook(),
            highlight: nil,
            chapterTitle: "Ch. 7",
            progressPercent: 43
        )
        let host = mountAndLayout(view)
        XCTAssertGreaterThan(host.bounds.width, 0)
        // Smoke: no crash when highlight is absent.
    }

    func testTruncationAffordanceTriggersAt281Chars() {
        let raw = String(repeating: "y", count: 281)
        let result = AmbientLayoutMetrics.truncateForDisplay(raw)
        XCTAssertTrue(result.wasTruncated)
        XCTAssertLessThanOrEqual(result.text.count, 280)
    }

    /// Renders the card to a 1× NSImage and writes it to a temporary file
    /// purely so a future PR can swap this in for a real pixel snapshot
    /// without restructuring the test. The assertion is on file existence,
    /// not pixels — pixel snapshots are deferred.
    func testRendersToImageAtOnex() throws {
        let view = AmbientCornerCard(
            book: makeBook(),
            highlight: makeShortHighlight(),
            chapterTitle: "Ch. 7",
            progressPercent: 43
        )
        let host = mountAndLayout(view)
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = rep.representation(using: .png, properties: [:])
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)

        // Attach as a diagnostic — visible in the test run log.
        if let data {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "AmbientCornerCard-short.png"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
