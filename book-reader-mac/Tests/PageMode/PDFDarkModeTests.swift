import XCTest
import PDFKit
import CoreImage
import AppKit
@testable import InstantBookReader

final class PDFDarkModeTests: XCTestCase {

    private func fixture(_ name: String, ext: String) -> URL {
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }
        // XcodeGen copies fixtures with their original path; fall back to
        // the source tree path for local runs.
        let direct = URL(fileURLWithPath:
            "/Users/profitoniumapps/Documents/chromeApps-plan6/book-reader-mac/Tests/PageMode/Fixtures/\(name).\(ext)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: direct.path),
                      "fixture \(name).\(ext) missing")
        return direct
    }

    func testDarkRenderProducesPredominantlyDarkBitmap() throws {
        let url = fixture("sample", ext: "pdf")
        let doc = try XCTUnwrap(PDFDocument(url: url))
        let page = try XCTUnwrap(doc.page(at: 0))

        let bitmap = try XCTUnwrap(
            PageModePDFDarkRenderer.darkBitmap(for: page,
                                               size: CGSize(width: 612, height: 792))
        )
        let meanLum = bitmap.meanLuminance()
        XCTAssertLessThan(meanLum, 0.35,
                          "after inversion the mean luminance should be dark, got \(meanLum)")
    }

    func testDarkRenderMatchesReferencePNGWithinTolerance() throws {
        let pdfURL = fixture("sample", ext: "pdf")
        let referenceURL = fixture("pdf-dark-reference", ext: "png")

        let doc = try XCTUnwrap(PDFDocument(url: pdfURL))
        let page = try XCTUnwrap(doc.page(at: 0))
        let produced = try XCTUnwrap(
            PageModePDFDarkRenderer.darkBitmap(for: page,
                                               size: CGSize(width: 612, height: 792))
        )
        let reference = try XCTUnwrap(NSImage(contentsOf: referenceURL))

        let delta = produced.meanAbsoluteDifference(against: reference)
        XCTAssertLessThan(delta, 0.05,
                          "produced bitmap differs from reference by \(delta) (tolerance 0.05)")
    }
}

// MARK: - Test helpers

private extension NSImage {
    func meanLuminance() -> CGFloat {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return 0 }
        let pixels = rep.pixelsWide * rep.pixelsHigh
        var total: CGFloat = 0
        // Sub-sample on a coarse grid to keep the test fast.
        let stepX = max(1, rep.pixelsWide / 32)
        let stepY = max(1, rep.pixelsHigh / 32)
        var count = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                total += 0.2126 * r + 0.7152 * g + 0.0722 * b
                count += 1
            }
        }
        _ = pixels
        return count == 0 ? 0 : total / CGFloat(count)
    }

    func meanAbsoluteDifference(against other: NSImage) -> CGFloat {
        guard let a = tiffRepresentation, let ar = NSBitmapImageRep(data: a),
              let b = other.tiffRepresentation, let br = NSBitmapImageRep(data: b),
              ar.pixelsWide == br.pixelsWide, ar.pixelsHigh == br.pixelsHigh
        else { return 1.0 }
        var total: CGFloat = 0
        var count = 0
        // Sub-sample on a 16x16 grid to keep the test fast.
        let stepX = max(1, ar.pixelsWide / 16)
        let stepY = max(1, ar.pixelsHigh / 16)
        for y in stride(from: 0, to: ar.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: ar.pixelsWide, by: stepX) {
                guard let ca = ar.colorAt(x: x, y: y), let cb = br.colorAt(x: x, y: y)
                else { continue }
                let dr = abs(ca.redComponent - cb.redComponent)
                let dg = abs(ca.greenComponent - cb.greenComponent)
                let db = abs(ca.blueComponent - cb.blueComponent)
                total += (dr + dg + db) / 3
                count += 1
            }
        }
        return count == 0 ? 1.0 : total / CGFloat(count)
    }
}
