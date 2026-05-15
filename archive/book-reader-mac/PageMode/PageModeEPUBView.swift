import SwiftUI
import WebKit
import AppKit

/// Page-mode EPUB renderer.
///
/// Builds a dedicated WKWebView with the same `bookreader://` scheme handler
/// pipeline used by `WKWebViewReader` (Plan 3) but with three additions:
///   - a CSS user script that constrains `.prose-reader` to the safe column
///     width, disables CSS-columns, and sets a physical-size body font
///   - the `epub-pagination.js` paginator script (also injected as a
///     `WKUserScript`)
///   - an explicit JS hook for `window.__pageMode.advance(...)` invoked
///     when the user fires the page-mode hotkey
///
/// We do NOT reimplement EPUB parsing on the Swift side — the WKWebView loads
/// the same JS the extension uses via the WebReader bundle.
struct PageModeEPUBView: NSViewRepresentable {

    let book: Book
    let safeColumnWidth: CGFloat
    let bodyPointSize: CGFloat
    /// When the user fires the page hotkey, `pendingScrollDirection` flips
    /// to "next" or "previous". We consume it, scroll, then clear it.
    let pendingScrollDirection: String?
    let onPendingConsumed: () -> Void

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var webView: WKWebView?
        var bridge: WebReaderBridge?
        var schemeHandler: BookURLSchemeHandler?
        var lastConsumedDirection: String?
        var paginationScript: String = ""
        var didFinishInitialLoad: Bool = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            didFinishInitialLoad = true
            // Re-evaluate the paginator after navigation so `window.__pageMode`
            // exists for already-loaded documents.
            webView.evaluateJavaScript(paginationScript, completionHandler: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let css = Self.injectedCSS(
            safeColumnWidth: safeColumnWidth,
            bodyPointSize: bodyPointSize
        )

        let config = WKWebViewConfiguration()
        let storage = WebReaderStorage()
        let bridge = WebReaderBridge(storage: storage)
        context.coordinator.bridge = bridge

        let bundleURL = Bundle.main.url(forResource: "WebReader", withExtension: "bundle")
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/WebReader.bundle")
        let loader = BookContentLoader()
        let getCurrent: () -> (hash: String, ext: String)? = { [book] in
            (hash: book.sha256, ext: book.format.rawValue)
        }
        let scheme = BookURLSchemeHandler(loader: loader,
                                          bundleURL: bundleURL,
                                          getCurrent: getCurrent)
        context.coordinator.schemeHandler = scheme
        config.setURLSchemeHandler(scheme, forURLScheme: "bookreader")
        config.userContentController.add(bridge, name: WebReaderBridge.messageName)

        // 1. Bootstrap (reuse the same script the active reader uses).
        config.userContentController.addUserScript(
            WKUserScript(source: WKWebViewReader.bootstrapJS,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true)
        )

        // 2. Page-mode CSS — injected at document start to override the
        // extension's own theme styles.
        let cssScript = Self.cssInjectionScript(css: css)
        config.userContentController.addUserScript(
            WKUserScript(source: cssScript,
                         injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true)
        )

        // 3. Paginator.
        let paginationScript = Self.loadPaginationScript()
        context.coordinator.paginationScript = paginationScript
        config.userContentController.addUserScript(
            WKUserScript(source: paginationScript,
                         injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true)
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.navigationDelegate = context.coordinator
        bridge.attach(to: webView)

        let indexURL: URL = {
            let direct = bundleURL.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            return bundleURL.appendingPathComponent("src/newtab/index.html")
        }()
        if FileManager.default.fileExists(atPath: indexURL.path) {
            webView.loadFileURL(indexURL, allowingReadAccessTo: bundleURL)
        }

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coord = context.coordinator
        guard let direction = pendingScrollDirection,
              direction != coord.lastConsumedDirection else { return }
        coord.lastConsumedDirection = direction
        let js = "window.__pageMode && window.__pageMode.advance(\(stringLiteral(direction)));"
        webView.evaluateJavaScript(js) { _, _ in
            DispatchQueue.main.async { onPendingConsumed() }
        }
    }

    // MARK: - CSS

    /// Builds the CSS that the WKWebView will inject as a `WKUserScript` at
    /// document-end. Public so tests can assert content without firing up
    /// WebKit.
    static func injectedCSS(safeColumnWidth: CGFloat, bodyPointSize: CGFloat) -> String {
        """
        :root {
          --page-mode-column: \(Int(safeColumnWidth))px;
          --page-mode-body: \(Int(bodyPointSize))pt;
        }
        html, body {
          background: transparent !important;
          overflow: hidden !important;
          margin: 0 !important;
          padding: 0 !important;
        }
        .prose-reader {
          max-width: \(Int(safeColumnWidth))px;
          margin: 0 auto;
          padding: 2em 0;
          column-width: none;
          column-count: 1;
          font-size: \(Int(bodyPointSize))pt;
          line-height: 1.55;
        }
        .prose-reader img, .prose-reader figure {
          max-width: 100%;
          height: auto;
        }
        """
    }

    private static func cssInjectionScript(css: String) -> String {
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        return """
        (function() {
          var style = document.createElement('style');
          style.id = '__page_mode_css';
          style.textContent = `\(escaped)`;
          (document.head || document.documentElement).appendChild(style);
        })();
        """
    }

    private static func loadPaginationScript() -> String {
        if let url = Bundle.main.url(forResource: "epub-pagination",
                                      withExtension: "js"),
           let src = try? String(contentsOf: url, encoding: .utf8) {
            return src
        }
        // Fallback for test/dev runs where the resource isn't yet in the bundle.
        let direct = URL(fileURLWithPath:
            "/Users/profitoniumapps/Documents/chromeApps-plan6/book-reader-mac/PageMode/Resources/epub-pagination.js")
        return (try? String(contentsOf: direct, encoding: .utf8)) ?? ""
    }

    private func stringLiteral(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                           .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
