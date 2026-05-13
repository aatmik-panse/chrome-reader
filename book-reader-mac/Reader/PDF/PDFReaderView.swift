import SwiftUI
import PDFKit

struct PDFReaderView: NSViewRepresentable {
    let book: Book
    let document: PDFDocument
    @Binding var displayMode: PDFDisplayModeOption
    @Binding var currentPageIndex: Int
    @Binding var currentSelection: PDFSelection?
    let theme: AppTheme
    let aiConfigured: Bool
    let onSaveHighlight: (PDFAnchorResolver.Anchor, String) -> Void
    let onCopyText: (String) -> Void
    let onExplain: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> HighlightedPDFView {
        let view = HighlightedPDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = displayMode.pdfKit
        view.backgroundColor = .clear
        view.displaysPageBreaks = true
        context.coordinator.popover = SelectionPopover(theme: theme)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: HighlightedPDFView, context: Context) {
        if nsView.displayMode != displayMode.pdfKit {
            nsView.displayMode = displayMode.pdfKit
        }
        if nsView.document !== document {
            nsView.document = document
        }
        if let target = document.page(at: currentPageIndex),
           nsView.currentPage !== target {
            nsView.go(to: target)
        }
        context.coordinator.theme = theme
        context.coordinator.aiConfigured = aiConfigured
    }

    @MainActor
    final class Coordinator: NSObject {
        let parent: PDFReaderView
        weak var pdfView: HighlightedPDFView?
        var popover: SelectionPopover?
        var theme: AppTheme
        var aiConfigured: Bool
        private var observers: [NSObjectProtocol] = []
        private let resolver = PDFAnchorResolver()

        init(parent: PDFReaderView) {
            self.parent = parent
            self.theme = parent.theme
            self.aiConfigured = parent.aiConfigured
        }

        func attach(to view: HighlightedPDFView) {
            self.pdfView = view
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: .PDFViewPageChanged, object: view, queue: .main
            ) { [weak self] _ in
                guard let self,
                      let view = self.pdfView,
                      let current = view.currentPage,
                      let index = view.document?.index(for: current) else { return }
                self.parent.currentPageIndex = index
            })
            observers.append(center.addObserver(
                forName: .PDFViewSelectionChanged, object: view, queue: .main
            ) { [weak self] _ in
                self?.handleSelectionChanged()
            })
        }

        private func handleSelectionChanged() {
            guard let view = pdfView,
                  let selection = view.currentSelection,
                  let page = selection.pages.first,
                  let text = selection.string,
                  !text.isEmpty,
                  let pageIndex = view.document?.index(for: page) else {
                popover?.dismiss()
                parent.currentSelection = nil
                return
            }
            parent.currentSelection = selection
            let pageRect = selection.bounds(for: page)
            let viewRect = view.convert(pageRect, from: page)
            let anchor = resolver.makeAnchor(from: selection, on: page, pageIndex: pageIndex)
            popover?.show(
                over: view,
                rect: viewRect,
                selectedText: text,
                aiConfigured: aiConfigured,
                onHighlight: { [weak self] in
                    self?.parent.onSaveHighlight(anchor, text)
                },
                onCopy: { [weak self] in
                    self?.parent.onCopyText(text)
                },
                onExplain: { [weak self] in
                    self?.parent.onExplain(text)
                }
            )
        }

        deinit {
            for o in observers { NotificationCenter.default.removeObserver(o) }
        }
    }
}
