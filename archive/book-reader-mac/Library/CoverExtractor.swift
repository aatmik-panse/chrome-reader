import AppKit
import Foundation

enum CoverExtractorError: Error, CustomStringConvertible {
    case noCoverFound
    case pngEncodingFailed

    var description: String {
        switch self {
        case .noCoverFound:       return "No cover image could be derived from this file"
        case .pngEncodingFailed:  return "Failed to encode generated cover as PNG"
        }
    }
}

enum CoverExtractor {
    /// Writes `<sha256>.png` into `coversDirectory` and returns the URL.
    /// Overwrites an existing file at the same path (idempotent).
    static func extract(from source: URL,
                        format: BookFormat,
                        sha256: String,
                        coversDirectory: URL) throws -> URL {
        let target = coversDirectory.appendingPathComponent("\(sha256).png")

        let image: NSImage
        switch format {
        case .epub:
            let parsed = try EPUBMetadata.parse(at: source)
            guard let data = parsed.coverImageData,
                  let nsimage = NSImage(data: data) else {
                throw CoverExtractorError.noCoverFound
            }
            image = nsimage
        case .pdf:
            image = try PDFMetadata.renderCover(at: source,
                                                size: CGSize(width: 400, height: 600))
        case .txt:
            image = try TXTMetadata.renderCover(at: source,
                                                size: CGSize(width: 400, height: 600))
        }

        guard let pngData = pngData(from: image) else {
            throw CoverExtractorError.pngEncodingFailed
        }

        try FileManager.default.createDirectory(at: coversDirectory,
                                                withIntermediateDirectories: true)
        try pngData.write(to: target, options: .atomic)
        return target
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
