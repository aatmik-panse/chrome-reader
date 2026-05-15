import AppKit
import PDFKit

/// Owns notification subscriptions for a HighlightedPDFView and translates
/// them into typed Swift callbacks.
@MainActor
final class PDFReaderCoordinator: NSObject {
    private weak var pdfView: HighlightedPDFView?
    private var observers: [NSObjectProtocol] = []

    var onPageChanged: ((Int) -> Void)?
    var onSelectionChanged: ((PDFSelection?) -> Void)?

    func attach(to view: HighlightedPDFView) {
        self.pdfView = view
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .PDFViewPageChanged, object: view, queue: .main
        ) { [weak self] _ in
            guard let pdfView = self?.pdfView,
                  let current = pdfView.currentPage,
                  let index = pdfView.document?.index(for: current) else { return }
            self?.onPageChanged?(index)
        })
        observers.append(center.addObserver(
            forName: .PDFViewSelectionChanged, object: view, queue: .main
        ) { [weak self] _ in
            self?.onSelectionChanged?(self?.pdfView?.currentSelection)
        })
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }
}
