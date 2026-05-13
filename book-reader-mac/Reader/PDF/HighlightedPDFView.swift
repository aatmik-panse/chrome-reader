import AppKit
import PDFKit

/// PDFView subclass that overlays `PDFAnnotation.highlight` on each saved
/// highlight. The owner calls `setHighlights(_:)` whenever the SwiftData
/// list changes; the view rebuilds the annotation set on each call.
final class HighlightedPDFView: PDFView {
    struct ResolvedHighlight {
        let id: UUID
        let pageIndex: Int
        let bounds: CGRect  // page coordinates
    }

    private var annotations: [UUID: PDFAnnotation] = [:]

    /// Replace the entire annotation set. Existing annotations are removed
    /// from their pages first.
    func setHighlights(_ items: [ResolvedHighlight], color: NSColor = NSColor.systemYellow.withAlphaComponent(0.4)) {
        for (_, annotation) in annotations {
            annotation.page?.removeAnnotation(annotation)
        }
        annotations.removeAll()

        guard let document else { return }
        for item in items {
            guard let page = document.page(at: item.pageIndex) else { continue }
            let annotation = PDFAnnotation(bounds: item.bounds,
                                           forType: .highlight,
                                           withProperties: nil)
            annotation.color = color
            annotation.userName = item.id.uuidString
            page.addAnnotation(annotation)
            annotations[item.id] = annotation
        }
    }
}
