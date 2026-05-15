import SwiftUI
import WebKit

/// SwiftUI host for the embedded React reader. Loads
/// `WebReader.bundle/index.html` and registers the bookreader:// scheme,
/// the WebReaderBridge, and the theme injector.
struct WKWebViewReader: NSViewRepresentable {
    let book: Book
    let theme: AppTheme
    let onPositionChange: (String, Double, String?) -> Void
    let onSelectionChanged: (CGRect, String) -> Void
    let onSelectionCleared: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(book: book, theme: theme)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let storage = WebReaderStorage()
        let bridge = WebReaderBridge(storage: storage)
        bridge.onSelectionChanged = onSelectionChanged
        bridge.onSelectionCleared = onSelectionCleared
        bridge.onPositionChanged = onPositionChange
        context.coordinator.bridge = bridge

        let bundleURL = Bundle.main.url(forResource: "WebReader", withExtension: "bundle")!
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
        config.userContentController.addUserScript(
            WKUserScript(source: Self.bootstrapJS,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true)
        )
        config.userContentController.addUserScript(WebThemeInjector(theme: theme).userScript())

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.navigationDelegate = context.coordinator
        bridge.attach(to: webView)

        // The extension's Vite build emits index.html at src/newtab/index.html
        // within dist/. Probe for the file in either location for resilience.
        let indexURL: URL = {
            let direct = bundleURL.appendingPathComponent("index.html")
            if FileManager.default.fileExists(atPath: direct.path) { return direct }
            return bundleURL.appendingPathComponent("src/newtab/index.html")
        }()
        webView.loadFileURL(indexURL, allowingReadAccessTo: bundleURL)

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.theme != theme {
            context.coordinator.theme = theme
            WebThemeInjector(theme: theme).reinject(into: webView)
        }
    }

    /// JS bootstrap. Defines window.__wkBridge.* and selection plumbing.
    static let bootstrapJS: String = #"""
    (function() {
        const pending = new Map();
        let nextID = 1;
        function call(api, args) {
            return new Promise((resolve) => {
                const id = "wk-" + (nextID++);
                pending.set(id, resolve);
                window.webkit.messageHandlers.bridge.postMessage({ id, api, args });
            });
        }
        window.__wkBridgeReply = function(id, payload) {
            const resolve = pending.get(id);
            if (resolve) { pending.delete(id); resolve(payload); }
        };
        window.__wkBridge = {
            storage: {
                get: (keys) => call('storage.get', { keys }),
                set: (items) => call('storage.set', { items }),
                remove: (keys) => call('storage.remove', { keys }),
                allKeys: () => call('storage.allKeys', {})
            },
            runtime: {
                getURL: (path) => "bookreader://app/" + String(path || "").replace(/^\/+/, ''),
                openOptionsPage: () => call('runtime.openOptionsPage', {})
            },
            identity: {
                getAuthToken: () => call('identity.getAuthToken', {}),
                clearAllCachedAuthTokens: () => call('identity.clearAllCachedAuthTokens', {})
            },
            ai: {
                stream: (req) => call('ai.stream', req)
            }
        };

        // Storage change fanout
        const changeListeners = [];
        window.__wkStorageChanged = function(changes, areaName) {
            for (const l of changeListeners) l(changes, areaName);
        };
        window.__wkBridge.storage.onChanged = {
            addListener: (cb) => changeListeners.push(cb),
            removeListener: (cb) => {
                const i = changeListeners.indexOf(cb);
                if (i >= 0) changeListeners.splice(i, 1);
            }
        };

        window.__wkHighlights = window.__wkHighlights || {
            apply: function() {},
            remove: function() {},
            replaceAll: function() {}
        };

        // Selection plumbing
        document.addEventListener('selectionchange', function() {
            const sel = window.getSelection();
            if (!sel || sel.isCollapsed || sel.rangeCount === 0) {
                window.webkit.messageHandlers.bridge.postMessage({
                    id: 'sel-' + Date.now(), api: 'selection.clear', args: {}
                });
                return;
            }
            const range = sel.getRangeAt(0);
            const rect = range.getBoundingClientRect();
            window.webkit.messageHandlers.bridge.postMessage({
                id: 'sel-' + Date.now(), api: 'selection.changed',
                args: { rect: { x: rect.x, y: rect.y, w: rect.width, h: rect.height }, text: sel.toString() }
            });
        });

        // Position
        window.__wkReportPosition = function(anchor, pct, chapter) {
            window.webkit.messageHandlers.bridge.postMessage({
                id: 'pos-' + Date.now(), api: 'position.changed',
                args: { anchor, percentage: pct, chapterTitle: chapter || null }
            });
        };
    })();
    """#

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let book: Book
        var theme: AppTheme
        var bridge: WebReaderBridge?
        var schemeHandler: BookURLSchemeHandler?
        weak var webView: WKWebView?

        init(book: Book, theme: AppTheme) {
            self.book = book
            self.theme = theme
        }
    }
}
