import XCTest
import WebKit
import AppKit
@testable import InstantBookReader

/// Verifies that page-mode's screen-height pagination advances exactly one
/// viewport per call and that consecutive pages do not skip content.
///
/// Uses a WKWebView loaded with a static HTML document that mimics the
/// flattened EPUB the extension's reader would produce — we don't drive the
/// real extension reader here because that requires the full WebReader bundle.
/// What we are testing is `epub-pagination.js`, not the React app.
@MainActor
final class PageModeEPUBPaginationTests: XCTestCase {

    private func loadScript() throws -> String {
        let direct = URL(fileURLWithPath:
            "/Users/profitoniumapps/Documents/chromeApps-plan6/book-reader-mac/PageMode/Resources/epub-pagination.js")
        return try String(contentsOf: direct, encoding: .utf8)
    }

    private func makeWebView() -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 720, height: 400),
                             configuration: cfg)
        return view
    }

    private func loadHTML(_ webView: WKWebView, body: String) async {
        let html = """
        <!doctype html><html><head>
          <style>
            html, body { margin:0; padding:0; }
            .prose-reader { width: 720px; font-size: 22pt; line-height: 1.55; }
            p { margin: 0 0 1em 0; }
          </style>
        </head><body><div class="prose-reader">\(body)</div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        // Wait until the document is interactive.
        for _ in 0..<50 {
            let state: String = (try? await webView.evaluateJavaScript("document.readyState") as? String) ?? ""
            if state == "complete" || state == "interactive" { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func testAdvanceMovesExactlyOneViewportAndDoesNotSkipContent() async throws {
        let webView = makeWebView()
        let script = try loadScript()
        let body = (1...80).map { "<p>line \($0) — sentinel \($0)</p>" }.joined()
        await loadHTML(webView, body: body)

        // Inject the paginator.
        _ = try await webView.evaluateJavaScript(script)

        // Page 1: capture the bottom-most visible line.
        let firstState = try await webView.evaluateJavaScript(
            "JSON.stringify(window.__pageMode.measure())"
        ) as? String
        XCTAssertNotNil(firstState)

        // Identify the line that sits at scrollTop + viewportHeight (the
        // last visible on page 1; equals the first visible on page 2 after
        // advance).
        let beforeBottom = try await webView.evaluateJavaScript("""
            (function(){
              const reader = document.querySelector('.prose-reader');
              const viewport = window.innerHeight;
              const bottom = (reader.scrollTop || window.scrollY || 0) + viewport;
              const paragraphs = Array.from(document.querySelectorAll('.prose-reader p'));
              const target = paragraphs.find(p => {
                const top = p.offsetTop;
                const bot = top + p.offsetHeight;
                return top < bottom && bot >= bottom - 4;
              });
              return target ? target.textContent : null;
            })()
        """) as? String

        // Advance one page.
        let advance = try await webView.evaluateJavaScript(
            "JSON.stringify(window.__pageMode.advance('next'))"
        ) as? String
        XCTAssertNotNil(advance)

        // After advance, the first visible line should be the same paragraph
        // that was at the bottom edge of page 1.
        let afterTop = try await webView.evaluateJavaScript("""
            (function(){
              const reader = document.querySelector('.prose-reader');
              const top = (reader.scrollTop || window.scrollY || 0);
              const paragraphs = Array.from(document.querySelectorAll('.prose-reader p'));
              const target = paragraphs.find(p => {
                const ptop = p.offsetTop;
                const pbot = ptop + p.offsetHeight;
                return pbot > top + 1 && ptop <= top + 4;
              });
              return target ? target.textContent : null;
            })()
        """) as? String

        XCTAssertNotNil(beforeBottom)
        XCTAssertNotNil(afterTop)
        XCTAssertEqual(beforeBottom, afterTop,
                       "page 2 should start where page 1 ended — no content skipped")
    }

    func testAdvancePreviousReturnsToOrigin() async throws {
        let webView = makeWebView()
        let script = try loadScript()
        let body = (1...80).map { "<p>line \($0)</p>" }.joined()
        await loadHTML(webView, body: body)
        _ = try await webView.evaluateJavaScript(script)

        _ = try await webView.evaluateJavaScript("window.__pageMode.advance('next')")
        _ = try await webView.evaluateJavaScript("window.__pageMode.advance('previous')")
        let top = try await webView.evaluateJavaScript("""
            (document.querySelector('.prose-reader').scrollTop || window.scrollY || 0)
        """) as? NSNumber
        XCTAssertNotNil(top)
        XCTAssertEqual(top!.doubleValue, 0, accuracy: 1.5)
    }
}
