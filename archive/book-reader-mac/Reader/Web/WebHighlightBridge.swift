import Foundation
import WebKit

/// Sends apply/remove highlight commands into the WKWebView. The web side
/// already knows how to wrap ranges in `[data-highlight-id]` spans; this
/// bridge calls into `window.__wkHighlights` exposed by the reader bootstrap
/// shim (Task 9).
@MainActor
struct WebHighlightBridge {
    weak var webView: WKWebView?

    func apply(id: UUID, anchor: HighlightAnchor) {
        guard let webView else { return }
        let payload: [String: Any] = [
            "id": id.uuidString,
            "startOffset": anchor.startOffset,
            "length": anchor.length,
            "contextBefore": anchor.contextBefore,
            "contextAfter": anchor.contextAfter
        ]
        emit(method: "apply", payload: payload, on: webView)
    }

    func remove(id: UUID) {
        guard let webView else { return }
        emit(method: "remove", payload: ["id": id.uuidString], on: webView)
    }

    func replaceAll(_ items: [(id: UUID, anchor: HighlightAnchor)]) {
        guard let webView else { return }
        let arr: [[String: Any]] = items.map { item in
            [
                "id": item.id.uuidString,
                "startOffset": item.anchor.startOffset,
                "length": item.anchor.length,
                "contextBefore": item.anchor.contextBefore,
                "contextAfter": item.anchor.contextAfter
            ]
        }
        emit(method: "replaceAll", payload: ["items": arr], on: webView)
    }

    private func emit(method: String, payload: Any, on webView: WKWebView) {
        let json = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let js = "window.__wkHighlights && window.__wkHighlights.\(method)(\(json));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
