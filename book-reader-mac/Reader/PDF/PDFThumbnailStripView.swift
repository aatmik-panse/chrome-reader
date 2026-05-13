import SwiftUI
import PDFKit

struct PDFThumbnailStripView: NSViewRepresentable {
    weak var pdfView: PDFView?
    let thumbnailSize: CGSize

    func makeNSView(context: Context) -> PDFThumbnailView {
        let strip = PDFThumbnailView()
        strip.thumbnailSize = thumbnailSize
        strip.backgroundColor = .clear
        strip.pdfView = pdfView
        return strip
    }

    func updateNSView(_ nsView: PDFThumbnailView, context: Context) {
        nsView.pdfView = pdfView
        nsView.thumbnailSize = thumbnailSize
    }
}
