import SwiftUI
import PDFKit
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Core Image pipeline for dark-mode PDF rendering. Spec §6.4: invert color
/// to flip black-on-white → white-on-black, then hue-rotate ~180° so diagrams
/// don't end up as their literal color complement (red→cyan). Pure function,
/// unit-tested without touching any view layer.
public enum PageModePDFDarkRenderer {

    public static func darkBitmap(for page: PDFPage, size: CGSize) -> NSImage? {
        let thumb = page.thumbnail(of: size, for: .mediaBox)
        guard let tiff = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage else { return nil }

        let ciImage = CIImage(cgImage: cg)
        let invert = CIFilter.colorInvert()
        invert.inputImage = ciImage
        guard let inverted = invert.outputImage else { return nil }

        let hue = CIFilter.hueAdjust()
        hue.inputImage = inverted
        hue.angle = Float.pi // ~180°
        guard let rotated = hue.outputImage else { return nil }

        let ctx = CIContext()
        guard let outCG = ctx.createCGImage(rotated, from: rotated.extent) else { return nil }
        return NSImage(cgImage: outCG, size: size)
    }
}

/// Page-mode PDF renderer.
///
/// Light appearance: live `PDFView` so text selection is preserved if the
/// wallpaper window ever becomes key.
///
/// Dark appearance: rendered `PDFPage` bitmap inverted through Core Image.
/// Selection unavailable in this branch — accepted tradeoff per spec §6.4.
/// (Live PDFView under dark appearance renders ink as black-on-black; we
/// preserve diagrams at the cost of interactivity.)
struct PageModePDFView: NSViewRepresentable {

    let book: Book
    let pageIndex: Int   // 0-based; comes from Position.anchor "page:offset"
    let isDark: Bool

    final class Coordinator {
        var hostingPDFView: PDFView?
        var darkImageView: NSImageView?
        var appearanceObservation: NSKeyValueObservation?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear

        // Re-render when system appearance flips.
        context.coordinator.appearanceObservation = NSApp.observe(
            \.effectiveAppearance, options: [.new]
        ) { _, _ in
            DispatchQueue.main.async { [weak container] in
                guard let c = container else { return }
                c.needsDisplay = true
            }
        }

        rebuild(into: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        rebuild(into: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.appearanceObservation?.invalidate()
        coordinator.appearanceObservation = nil
    }

    private func rebuild(into container: NSView, coordinator: Coordinator) {
        let url = AppSupportPaths.books.appendingPathComponent(book.filePath)

        container.subviews.forEach { $0.removeFromSuperview() }
        coordinator.hostingPDFView = nil
        coordinator.darkImageView = nil

        if isDark {
            guard let doc = PDFDocument(url: url),
                  pageIndex < doc.pageCount,
                  let page = doc.page(at: pageIndex) else { return }
            let size = container.bounds.size == .zero
                ? CGSize(width: 720, height: 1000)
                : container.bounds.size
            let image = PageModePDFDarkRenderer.darkBitmap(for: page, size: size)
            let imageView = NSImageView(frame: container.bounds)
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.autoresizingMask = [.width, .height]
            container.addSubview(imageView)
            coordinator.darkImageView = imageView
            return
        }

        guard let doc = PDFDocument(url: url) else { return }
        let pdfView = PDFView(frame: container.bounds)
        pdfView.document = doc
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
        pdfView.backgroundColor = .clear
        pdfView.autoresizingMask = [.width, .height]
        if pageIndex < doc.pageCount, let page = doc.page(at: pageIndex) {
            pdfView.go(to: page)
        }
        container.addSubview(pdfView)
        coordinator.hostingPDFView = pdfView
    }
}
