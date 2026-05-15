import AppKit
import Foundation

struct ParsedTXTMetadata: Equatable {
    let title: String?
    let author: String?
}

enum TXTMetadataError: Error {
    case cannotRead
}

enum TXTMetadata {
    static func parse(at url: URL) throws -> ParsedTXTMetadata {
        let raw = (url.deletingPathExtension().lastPathComponent)
        let cleaned = raw
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedTXTMetadata(title: cleaned.isEmpty ? nil : cleaned, author: nil)
    }

    /// Renders the first 300 characters as an NSAttributedString into an
    /// NSImage of the requested size, using a serif body face on a warm cream
    /// background. Plan 5 may revisit styling.
    static func renderCover(at url: URL, size: CGSize) throws -> NSImage {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            throw TXTMetadataError.cannotRead
        }
        let snippet = String(raw.prefix(300))

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        // Background — clay cream.
        NSColor(calibratedRed: 0.984, green: 0.976, blue: 0.969, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: size).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "New York Medium", size: 16)
                ?? NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor(calibratedRed: 0.102, green: 0.094, blue: 0.082,
                                      alpha: 1.0),
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: snippet, attributes: attributes)
        let inset: CGFloat = 32
        let drawRect = NSRect(x: inset, y: inset,
                              width: size.width - inset * 2,
                              height: size.height - inset * 2)
        attributed.draw(in: drawRect)

        return image
    }
}
