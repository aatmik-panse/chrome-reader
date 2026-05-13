import SwiftUI
import SwiftData
import PDFKit
import AppKit

/// Top-level router for the active reader. Resolves the current book from
/// ReadingState and dispatches to the format-specific view. Owns the
/// PositionRecorder and the selection popover.
struct ReaderRouter: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(ReadingState.self) private var state
    @Query private var books: [Book]
    @Query private var highlights: [Highlight]

    @State private var pdfDocument: PDFDocument?
    @State private var pdfDisplayMode: PDFDisplayModeOption = .singlePageContinuous
    @State private var pdfPageIndex: Int = 0
    @State private var pdfSelection: PDFSelection?
    @State private var pdfSelectionRect: CGRect?
    @State private var pdfViewRef = WeakBox<HighlightedPDFView>()

    @State private var txtPlainText: String = ""
    @State private var txtOffset: Int = 0
    @State private var txtSelectedRange: NSRange?

    @State private var webSelectionRect: CGRect?
    @State private var webSelectionText: String = ""

    @State private var recorder: PositionRecorder?
    @StateObject private var popoverHost = SelectionPopoverHost()

    private var currentBook: Book? {
        guard let hash = state.currentBookHash else { return nil }
        return books.first(where: { $0.sha256 == hash })
    }

    var body: some View {
        Group {
            if let book = currentBook {
                content(for: book)
            } else {
                emptyState
            }
        }
        .background(theme.surface.swiftUI)
        .onAppear { ensureRecorder() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No book open")
                .font(.system(size: 24, weight: .medium, design: .serif))
                .foregroundStyle(theme.ink.swiftUI)
            Text("Open a book from the Library window")
                .font(.system(size: 13))
                .foregroundStyle(theme.ink.swiftUI.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for book: Book) -> some View {
        switch book.format {
        case .pdf:
            pdfContent(book: book)
        case .epub:
            webContent(book: book)
        case .txt:
            txtContent(book: book)
        }
    }

    @ViewBuilder
    private func pdfContent(book: Book) -> some View {
        let savedHighlights = highlights.filter { $0.bookHash == book.sha256 }
        if let doc = pdfDocument {
            HStack(spacing: 0) {
                PDFOutlinePanel(document: doc, pdfView: pdfViewRef.value)
                    .frame(width: 240)
                VStack(spacing: 0) {
                    PDFReaderView(book: book,
                                  document: doc,
                                  displayMode: $pdfDisplayMode,
                                  currentPageIndex: $pdfPageIndex,
                                  currentSelection: $pdfSelection,
                                  theme: theme,
                                  aiConfigured: false,
                                  onSaveHighlight: { anchor, text in
                                      saveHighlight(book: book, anchor: anchor, text: text)
                                  },
                                  onCopyText: { text in
                                      NSPasteboard.general.clearContents()
                                      NSPasteboard.general.setString(text, forType: .string)
                                  },
                                  onExplain: { _ in })
                    .background(
                        PDFViewCapture(pdfViewRef: pdfViewRef)
                    )
                    PDFThumbnailStripView(pdfView: pdfViewRef.value,
                                          thumbnailSize: CGSize(width: 80, height: 100))
                        .frame(height: 110)
                }
            }
            .onChange(of: pdfPageIndex) { _, newValue in
                let pct = Double(newValue) / Double(max(1, doc.pageCount - 1))
                recorder?.record(bookHash: book.sha256,
                                 anchor: "\(newValue):0",
                                 percentage: pct,
                                 chapterTitle: nil)
            }
            .onChange(of: savedHighlights.count) { _, _ in
                rebuildPDFHighlights(book: book, document: doc, highlights: savedHighlights)
            }
            .task { rebuildPDFHighlights(book: book, document: doc, highlights: savedHighlights) }
        } else {
            ProgressView()
                .onAppear {
                    let url = AppSupportPaths.books.appendingPathComponent("\(book.sha256).pdf")
                    pdfDocument = PDFDocument(url: url)
                }
        }
    }

    private func rebuildPDFHighlights(book: Book,
                                      document: PDFDocument,
                                      highlights: [Highlight]) {
        guard let view = pdfViewRef.value else { return }
        let resolver = PDFAnchorResolver()
        let serializer = PDFHighlightSerializer()
        var resolved: [HighlightedPDFView.ResolvedHighlight] = []
        for h in highlights {
            guard let anchor = try? serializer.decode(h.surroundingText),
                  let r = resolver.resolve(anchor: anchor, in: document),
                  let page = r.selection.pages.first else { continue }
            let bounds = r.selection.bounds(for: page)
            resolved.append(.init(id: h.clientID,
                                  pageIndex: r.pageIndex,
                                  bounds: bounds))
        }
        view.setHighlights(resolved)
    }

    private func saveHighlight(book: Book,
                               anchor: PDFAnchorResolver.Anchor,
                               text: String) {
        let serializer = PDFHighlightSerializer()
        let encoded = serializer.encode(anchor)
        let highlight = Highlight(bookHash: book.sha256,
                                  text: text,
                                  surroundingText: encoded,
                                  offset: anchor.inner.startOffset)
        highlight.book = book
        modelContext.insert(highlight)
        try? modelContext.save()
    }

    @ViewBuilder
    private func webContent(book: Book) -> some View {
        ZStack {
            WKWebViewReader(
                book: book,
                theme: theme,
                onPositionChange: { anchor, pct, chapter in
                    recorder?.record(bookHash: book.sha256,
                                     anchor: anchor,
                                     percentage: pct,
                                     chapterTitle: chapter)
                },
                onSelectionChanged: { rect, text in
                    webSelectionRect = rect
                    webSelectionText = text
                },
                onSelectionCleared: {
                    webSelectionRect = nil
                    webSelectionText = ""
                }
            )
            if let rect = webSelectionRect, !webSelectionText.isEmpty {
                WebSelectionOverlay(rect: rect,
                                    text: webSelectionText,
                                    theme: theme,
                                    onHighlight: { /* Plan 4 wires JS-side anchor */ },
                                    onCopy: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(webSelectionText, forType: .string)
                                    },
                                    onExplain: {})
            }
        }
    }

    @ViewBuilder
    private func txtContent(book: Book) -> some View {
        TXTReaderView(book: book,
                      plainText: txtPlainText,
                      currentOffset: $txtOffset,
                      selectedRange: $txtSelectedRange,
                      onSelectionRect: { _, _ in })
            .onAppear {
                let url = AppSupportPaths.books.appendingPathComponent("\(book.sha256).txt")
                txtPlainText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            }
            .onChange(of: txtOffset) { _, newValue in
                let total = max(1, txtPlainText.utf16.count)
                recorder?.record(bookHash: book.sha256,
                                 anchor: "\(newValue)",
                                 percentage: Double(newValue) / Double(total),
                                 chapterTitle: nil)
            }
    }

    private func ensureRecorder() {
        guard recorder == nil else { return }
        recorder = PositionRecorder(modelContainer: modelContext.container)
    }
}

/// Tiny @Observable container for the SelectionPopover so we can mutate it
/// without re-creating per render. The popover itself is AppKit; we hold it
/// via a class so SwiftUI doesn't try to compare or recreate it.
@MainActor
final class SelectionPopoverHost: ObservableObject {
    let popover = SelectionPopover(theme: .clayDark)
}

@MainActor
final class WeakBox<T: AnyObject> {
    weak var value: T?
}

private struct WebSelectionOverlay: View {
    let rect: CGRect
    let text: String
    let theme: AppTheme
    let onHighlight: () -> Void
    let onCopy: () -> Void
    let onExplain: () -> Void

    var body: some View {
        SelectionToolbarView(selectedText: text,
                             onHighlight: onHighlight,
                             onCopy: onCopy,
                             onExplain: onExplain,
                             aiConfigured: false)
            .environment(\.appTheme, theme)
            .fixedSize()
            .offset(x: rect.minX, y: rect.maxY + 8)
            .allowsHitTesting(true)
    }
}

private struct PDFViewCapture: NSViewRepresentable {
    let pdfViewRef: WeakBox<HighlightedPDFView>

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Walk up until we find the HighlightedPDFView sibling.
        DispatchQueue.main.async {
            guard let parent = nsView.superview else { return }
            for sibling in parent.subviews {
                if let pdfView = sibling as? HighlightedPDFView {
                    pdfViewRef.value = pdfView
                    return
                }
                if let pdfView = findPDFView(in: sibling) {
                    pdfViewRef.value = pdfView
                    return
                }
            }
        }
    }

    private func findPDFView(in view: NSView) -> HighlightedPDFView? {
        if let v = view as? HighlightedPDFView { return v }
        for sub in view.subviews {
            if let found = findPDFView(in: sub) { return found }
        }
        return nil
    }
}
