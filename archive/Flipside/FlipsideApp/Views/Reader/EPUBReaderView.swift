import SwiftUI
import WebKit

// MARK: - Chapter Model

private struct EPUBChapterContent: Equatable {
    let title: String
    let html: String
}

// MARK: - EPUBReaderView

struct EPUBReaderView: View {
    let book: Book
    var position: ReadingPosition

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: ReaderSettings

    @State private var chapters: [EPUBChapterContent] = []
    @State private var currentChapterIndex: Int = 0
    @State private var showingChapterList = false
    @State private var chapterScrollProgress: Double = 0
    @State private var pendingScrollOffset: Double? = nil
    @State private var webViewID = UUID()

    private var theme: Theme {
        settings.resolvedTheme(for: colorScheme)
    }

    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()

            if chapters.isEmpty {
                epubPlaceholder
            } else {
                readerBody
            }
        }
        .onAppear(perform: loadContent)
        .animation(.easeInOut(duration: 0.25), value: showingChapterList)
    }

    // MARK: - Reader Body

    private var readerBody: some View {
        ZStack(alignment: .leading) {
            EPUBWebViewRepresentable(
                htmlContent: buildStyledHTML(),
                scrollOffset: pendingScrollOffset,
                onTapRegion: handleTapRegion,
                onScrollProgress: handleScrollProgress,
                onScrollRestored: { pendingScrollOffset = nil }
            )
            .id(webViewID)
            .ignoresSafeArea(edges: .bottom)

            if showingChapterList {
                chapterListOverlay
            }
        }
        .overlay(alignment: .bottom) {
            chapterProgressBar
        }
    }

    // MARK: - Chapter Progress

    private var chapterProgressBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text(chapters[currentChapterIndex].title)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)

                Spacer()

                Text("\(currentChapterIndex + 1)/\(chapters.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.divider)
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.matcha600)
                        .frame(width: max(0, geo.size.width * overallProgress), height: 3)
                        .animation(.easeOut(duration: 0.3), value: overallProgress)
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, ClayConstants.spacingMD)
        .padding(.bottom, ClayConstants.spacingSM)
        .background(
            LinearGradient(
                colors: [theme.backgroundColor.opacity(0), theme.backgroundColor],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 60)
            .allowsHitTesting(false)
        )
    }

    // MARK: - Chapter List Overlay

    private var chapterListOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CHAPTERS")
                    .clayLabel()
                    .foregroundStyle(theme.secondaryText)
                Spacer()
                Button {
                    showingChapterList = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .padding(.horizontal, ClayConstants.spacingMD)
            .padding(.vertical, ClayConstants.spacingSM)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(chapters.indices, id: \.self) { idx in
                            Button {
                                navigateToChapter(idx)
                                showingChapterList = false
                            } label: {
                                HStack {
                                    Text(chapters[idx].title)
                                        .font(.system(
                                            size: 15,
                                            weight: idx == currentChapterIndex ? .semibold : .regular,
                                            design: .serif
                                        ))
                                        .foregroundStyle(
                                            idx == currentChapterIndex
                                                ? theme.accent
                                                : theme.primaryText
                                        )
                                        .lineLimit(2)

                                    Spacer()

                                    if idx == currentChapterIndex {
                                        Circle()
                                            .fill(theme.accent)
                                            .frame(width: 6, height: 6)
                                    }
                                }
                                .padding(.horizontal, ClayConstants.spacingMD)
                                .padding(.vertical, 10)
                            }
                            .id(idx)
                        }
                    }
                }
                .onAppear {
                    proxy.scrollTo(currentChapterIndex, anchor: .center)
                }
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 420)
        .background(theme.surfaceColor)
        .clipShape(RoundedRectangle(cornerRadius: ClayConstants.cornerRadiusMedium))
        .clayShadow(theme: theme)
        .padding(ClayConstants.spacingMD)
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    // MARK: - Placeholder

    private var epubPlaceholder: some View {
        VStack(spacing: ClayConstants.spacingMD) {
            ZStack {
                Circle()
                    .fill(Color.oat.opacity(0.4))
                    .frame(width: 100, height: 100)

                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.secondaryText)
            }

            Text("EPUB Reader")
                .clayHeading()
                .foregroundStyle(theme.primaryText)

            Text("EPUB chapter parsing is being finalized.\nThe full reading experience is on the way.")
                .clayBody(size: 15)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(ClayConstants.spacingXL)
    }

    // MARK: - Content Loading

    private func loadContent() {
        currentChapterIndex = position.chapterIndex

        if let htmlChapters = AppGroupManager.shared.getChapterHTML(for: book.id), !htmlChapters.isEmpty {
            chapters = htmlChapters.map { EPUBChapterContent(title: $0.title, html: $0.html) }
        } else if let cache = AppGroupManager.shared.getPageCache(for: book.id), !cache.isEmpty {
            var seen = Set<String>()
            var grouped: [EPUBChapterContent] = []
            var currentTitle = "Chapter 1"
            var currentText = ""

            for page in cache.pages {
                let title = page.chapterTitle ?? "Chapter"
                if !seen.contains(title) && !currentText.isEmpty {
                    grouped.append(EPUBChapterContent(
                        title: currentTitle,
                        html: plainTextToHTML(currentText)
                    ))
                    currentText = ""
                }
                seen.insert(title)
                currentTitle = title
                if !currentText.isEmpty { currentText += "\n\n" }
                currentText += page.text
            }
            if !currentText.isEmpty {
                grouped.append(EPUBChapterContent(
                    title: currentTitle,
                    html: plainTextToHTML(currentText)
                ))
            }
            chapters = grouped
        }

        if position.scrollOffset > 0 {
            pendingScrollOffset = position.scrollOffset
        }
    }

    private func plainTextToHTML(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        let paragraphs = escaped
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "<p>\($0)</p>" }
            .joined(separator: "\n")

        return "<body>\(paragraphs)</body>"
    }

    // MARK: - HTML Builder

    private func buildStyledHTML() -> String {
        guard currentChapterIndex < chapters.count else { return "" }

        let chapter = chapters[currentChapterIndex]
        let isDark = theme == .dark
        let bgColor = isDark ? "#1a1815" : "#faf9f7"
        let textColor = isDark ? "#e8e5e0" : "#3d3c39"
        let secondaryColor = isDark ? "#8c8985" : "#9a9895"
        let accentColor = isDark ? "#93c47d" : "#5c8748"
        let dividerColor = isDark ? "#383530" : "#ede9e3"
        let surfaceColor = isDark ? "#242220" : "#f5f3f0"
        let selectionBg = isDark ? "rgba(147, 196, 125, 0.25)" : "rgba(92, 135, 72, 0.20)"
        let fontSize = Int(settings.fontSize)
        let lineHeight = settings.lineHeight
        let fontStack = settings.cssFont

        let bodyContent = extractBody(from: chapter.html)

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style>
        *, *::before, *::after {
            box-sizing: border-box;
            -webkit-text-size-adjust: none;
            -webkit-tap-highlight-color: transparent;
        }
        html {
            overflow-y: scroll;
            scroll-behavior: smooth;
        }
        body {
            font-family: \(fontStack);
            font-size: \(fontSize)px;
            line-height: \(lineHeight);
            color: \(textColor);
            background: \(bgColor);
            padding: 32px 24px 100px;
            margin: 0;
            -webkit-font-smoothing: antialiased;
            -moz-osx-font-smoothing: grayscale;
            word-wrap: break-word;
            overflow-wrap: break-word;
            hyphens: auto;
            -webkit-hyphens: auto;
            text-rendering: optimizeLegibility;
            font-feature-settings: "kern" 1, "liga" 1;
        }

        /* Typography */
        p {
            margin: 0 0 1.1em 0;
            text-align: justify;
            orphans: 2;
            widows: 2;
        }
        h1 {
            font-size: 1.75em;
            font-weight: 700;
            line-height: 1.25;
            margin: 1.4em 0 0.6em;
            letter-spacing: -0.01em;
            color: \(textColor);
        }
        h2 {
            font-size: 1.45em;
            font-weight: 600;
            line-height: 1.3;
            margin: 1.3em 0 0.5em;
            color: \(textColor);
        }
        h3 {
            font-size: 1.2em;
            font-weight: 600;
            line-height: 1.35;
            margin: 1.2em 0 0.4em;
            color: \(textColor);
        }
        h4, h5, h6 {
            font-size: 1.05em;
            font-weight: 600;
            line-height: 1.4;
            margin: 1em 0 0.3em;
            color: \(textColor);
        }

        /* First paragraph after heading: no indent, slight emphasis */
        h1 + p, h2 + p, h3 + p, h4 + p {
            text-indent: 0;
        }

        /* Links */
        a {
            color: \(accentColor);
            text-decoration: none;
            border-bottom: 1px solid \(accentColor)44;
        }
        a:active {
            opacity: 0.7;
        }

        /* Blockquotes */
        blockquote {
            border-left: 3px solid \(accentColor);
            padding: 0.4em 0 0.4em 1.2em;
            margin: 1.2em 0;
            font-style: italic;
            color: \(secondaryColor);
        }
        blockquote p {
            margin-bottom: 0.6em;
        }
        blockquote p:last-child {
            margin-bottom: 0;
        }

        /* Lists */
        ul, ol {
            margin: 0.8em 0;
            padding-left: 1.8em;
        }
        li {
            margin-bottom: 0.35em;
            line-height: \(lineHeight);
        }
        li p {
            margin-bottom: 0.3em;
        }

        /* Images */
        img {
            max-width: 100%;
            height: auto;
            display: block;
            margin: 1.2em auto;
            border-radius: 4px;
        }
        figure {
            margin: 1.4em 0;
            text-align: center;
        }
        figcaption {
            font-size: 0.85em;
            color: \(secondaryColor);
            margin-top: 0.5em;
            text-align: center;
            font-style: italic;
        }

        /* Code */
        code {
            font-family: 'SF Mono', ui-monospace, Menlo, monospace;
            font-size: 0.88em;
            background: \(surfaceColor);
            padding: 0.15em 0.4em;
            border-radius: 3px;
        }
        pre {
            background: \(surfaceColor);
            padding: 1em 1.2em;
            border-radius: 6px;
            overflow-x: auto;
            margin: 1em 0;
            line-height: 1.5;
            font-size: 0.88em;
        }
        pre code {
            background: none;
            padding: 0;
            border-radius: 0;
        }

        /* Horizontal rule */
        hr {
            border: none;
            height: 1px;
            background: \(dividerColor);
            margin: 2em 0;
        }

        /* Tables */
        table {
            border-collapse: collapse;
            width: 100%;
            margin: 1em 0;
            font-size: 0.92em;
        }
        th, td {
            border: 1px solid \(dividerColor);
            padding: 0.5em 0.7em;
            text-align: left;
        }
        th {
            background: \(surfaceColor);
            font-weight: 600;
        }

        /* Selection */
        ::selection {
            background: \(selectionBg);
        }
        ::-webkit-selection {
            background: \(selectionBg);
        }

        /* Drop cap for first chapter paragraph (optional, only if first element) */
        body > p:first-child::first-letter,
        body > div:first-child > p:first-child::first-letter {
            font-size: 3.2em;
            float: left;
            line-height: 0.8;
            margin: 0.05em 0.1em 0 0;
            font-weight: 700;
            color: \(accentColor);
        }

        /* Superscript/subscript */
        sup { font-size: 0.75em; vertical-align: super; }
        sub { font-size: 0.75em; vertical-align: sub; }

        /* Emphasis */
        em { font-style: italic; }
        strong { font-weight: 700; }

        /* Remove EPUB-embedded styles that may fight our theme */
        [style] { background: transparent !important; }
        </style>
        <script>
        (function() {
            document.addEventListener('click', function(e) {
                if (e.target.closest('a')) return;
                var x = e.clientX;
                var w = window.innerWidth;
                var region = x < w * 0.33 ? 'prev' : (x > w * 0.67 ? 'next' : 'center');
                window.webkit.messageHandlers.tapHandler.postMessage(region);
            });

            var scrollTimer = null;
            window.addEventListener('scroll', function() {
                if (scrollTimer) clearTimeout(scrollTimer);
                scrollTimer = setTimeout(function() {
                    var top = document.documentElement.scrollTop || document.body.scrollTop;
                    var height = document.documentElement.scrollHeight - document.documentElement.clientHeight;
                    var pct = height > 0 ? (top / height) : 0;
                    window.webkit.messageHandlers.scrollHandler.postMessage(String(pct));
                }, 60);
            });
        })();

        function restoreScroll(pct) {
            var height = document.documentElement.scrollHeight - document.documentElement.clientHeight;
            if (height > 0) {
                window.scrollTo(0, height * pct);
            }
        }
        </script>
        </head>
        <body>
        \(bodyContent)
        </body>
        </html>
        """
    }

    private func extractBody(from html: String) -> String {
        let lower = html.lowercased()

        if let bodyStart = lower.range(of: "<body"),
           let bodyTagClose = html[bodyStart.upperBound...].range(of: ">") {
            let contentStart = bodyTagClose.upperBound
            if let bodyEnd = lower.range(of: "</body>", range: contentStart..<html.endIndex) {
                return String(html[contentStart..<bodyEnd.lowerBound])
            }
            return String(html[contentStart...])
        }

        return html
    }

    // MARK: - Interactions

    private func handleTapRegion(_ region: String) {
        switch region {
        case "next":
            if currentChapterIndex < chapters.count - 1 {
                navigateToChapter(currentChapterIndex + 1)
            }
        case "prev":
            if currentChapterIndex > 0 {
                navigateToChapter(currentChapterIndex - 1)
            }
        case "center":
            showingChapterList.toggle()
        default:
            break
        }
    }

    private func navigateToChapter(_ index: Int) {
        currentChapterIndex = index
        position.chapterIndex = index
        position.scrollOffset = 0
        chapterScrollProgress = 0
        pendingScrollOffset = nil
        updateOverallProgress()
        webViewID = UUID()
    }

    private func handleScrollProgress(_ progress: Double) {
        chapterScrollProgress = progress
        position.scrollOffset = progress
        updateOverallProgress()
    }

    private var overallProgress: Double {
        guard !chapters.isEmpty else { return 0 }
        let chapterWeight = 1.0 / Double(chapters.count)
        return Double(currentChapterIndex) * chapterWeight + chapterScrollProgress * chapterWeight
    }

    private func updateOverallProgress() {
        position.percentage = overallProgress
        position.updatedAt = Date()
    }
}

// MARK: - WKWebView UIViewRepresentable

struct EPUBWebViewRepresentable: UIViewRepresentable {
    let htmlContent: String
    let scrollOffset: Double?
    var onTapRegion: (String) -> Void
    var onScrollProgress: (Double) -> Void
    var onScrollRestored: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTapRegion: onTapRegion,
            onScrollProgress: onScrollProgress,
            onScrollRestored: onScrollRestored
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "tapHandler")
        config.userContentController.add(context.coordinator, name: "scrollHandler")
        config.suppressesIncrementalRendering = true
        config.dataDetectorTypes = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.showsHorizontalScrollIndicator = false
        webView.scrollView.bounces = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator

        context.coordinator.webView = webView
        context.coordinator.pendingScrollOffset = scrollOffset

        if !htmlContent.isEmpty {
            context.coordinator.lastLoadedHTML = htmlContent
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onTapRegion = onTapRegion
        context.coordinator.onScrollProgress = onScrollProgress
        context.coordinator.onScrollRestored = onScrollRestored

        if let offset = scrollOffset {
            context.coordinator.pendingScrollOffset = offset
        }

        guard htmlContent != context.coordinator.lastLoadedHTML else { return }

        context.coordinator.lastLoadedHTML = htmlContent
        context.coordinator.pendingScrollOffset = scrollOffset

        if !htmlContent.isEmpty {
            webView.loadHTMLString(htmlContent, baseURL: nil)
        }
    }

    class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onTapRegion: (String) -> Void
        var onScrollProgress: (Double) -> Void
        var onScrollRestored: () -> Void
        var lastLoadedHTML: String = ""
        var pendingScrollOffset: Double?
        weak var webView: WKWebView?

        init(
            onTapRegion: @escaping (String) -> Void,
            onScrollProgress: @escaping (Double) -> Void,
            onScrollRestored: @escaping () -> Void
        ) {
            self.onTapRegion = onTapRegion
            self.onScrollProgress = onScrollProgress
            self.onScrollRestored = onScrollRestored
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "tapHandler":
                if let region = message.body as? String {
                    DispatchQueue.main.async { [weak self] in
                        self?.onTapRegion(region)
                    }
                }
            case "scrollHandler":
                if let pctString = message.body as? String, let pct = Double(pctString) {
                    DispatchQueue.main.async { [weak self] in
                        self?.onScrollProgress(min(1, max(0, pct)))
                    }
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let offset = pendingScrollOffset, offset > 0 else { return }
            let js = "restoreScroll(\(offset));"
            webView.evaluateJavaScript(js) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.pendingScrollOffset = nil
                    self?.onScrollRestored()
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
