import SwiftUI
import PDFKit

/// Top-level PDF reader. Hosts a HighlightedPDFView and exposes display
/// mode, current page, selection, and TOC outline to SwiftUI bindings.
struct PDFReaderView: NSViewRepresentable {
    let book: Book
    let document: PDFDocument
    @Binding var displayMode: PDFDisplayModeOption
    @Binding var currentPageIndex: Int
    @Binding var currentSelection: PDFSelection?
    let onSelectionRect: (CGRect?) -> Void   // converted into pdfView.bounds coordinates

    func makeCoordinator() -> PDFReaderCoordinator {
        let coordinator = PDFReaderCoordinator()
        coordinator.onPageChanged = { idx in
            DispatchQueue.main.async { currentPageIndex = idx }
        }
        coordinator.onSelectionChanged = { selection in
            DispatchQueue.main.async {
                currentSelection = selection
                if let selection,
                   let page = selection.pages.first {
                    // bounds in page space → pdfView space
                    onSelectionRect(nil) // computed by the host in updateNSView
                    _ = page
                } else {
                    onSelectionRect(nil)
                }
            }
        }
        return coordinator
    }

    func makeNSView(context: Context) -> HighlightedPDFView {
        let view = HighlightedPDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = displayMode.pdfKit
        view.backgroundColor = .clear
        view.displaysPageBreaks = true
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
        if let selection = nsView.currentSelection,
           let page = selection.pages.first {
            let pageRect = selection.bounds(for: page)
            let viewRect = nsView.convert(pageRect, from: page)
            onSelectionRect(viewRect)
        } else {
            onSelectionRect(nil)
        }
    }
}
