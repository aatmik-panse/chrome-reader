import Foundation
import WebKit

/// Builds a `<style>` block of Clay CSS variables and injects it as a
/// WKUserScript at document-start. Re-injection on theme change calls
/// `reinject(into:)` which removes the previous style node and inserts the new one.
@MainActor
struct WebThemeInjector {
    let theme: AppTheme

    static let styleNodeID = "wk-theme-injected"

    func userScript() -> WKUserScript {
        let js = """
        (function() {
            const id = "\(Self.styleNodeID)";
            const existing = document.getElementById(id);
            if (existing) existing.remove();
            const style = document.createElement('style');
            style.id = id;
            style.textContent = \(jsLiteral(cssBody()));
            (document.head || document.documentElement).appendChild(style);
        })();
        """
        return WKUserScript(source: js,
                            injectionTime: .atDocumentStart,
                            forMainFrameOnly: true)
    }

    func reinject(into webView: WKWebView) {
        let js = """
        (function() {
            const id = "\(Self.styleNodeID)";
            const existing = document.getElementById(id);
            if (existing) existing.remove();
            const style = document.createElement('style');
            style.id = id;
            style.textContent = \(jsLiteral(cssBody()));
            (document.head || document.documentElement).appendChild(style);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func cssBody() -> String {
        return """
        :root {
            --clay-ink: \(theme.ink.hexString);
            --clay-surface: \(theme.surface.hexString);
            --clay-border: \(theme.border.hexString);
        }
        body { background: var(--clay-surface); color: var(--clay-ink); }
        """
    }

    private func jsLiteral(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
        let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(str.dropFirst().dropLast())
    }
}
