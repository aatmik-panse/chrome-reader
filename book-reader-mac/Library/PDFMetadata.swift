import AppKit
import PDFKit

struct ParsedPDFMetadata: Equatable {
    let title: String?
    let author: String?
}

enum PDFMetadataError: Error, CustomStringConvertible {
    case cannotOpen
    case noPages

    var description: String {
        switch self {
        case .cannotOpen: return "PDFKit could not open this file"
        case .noPages:    return "PDF has no pages to render"
        }
    }
}

enum PDFMetadata {
    static func parse(at url: URL) throws -> ParsedPDFMetadata {
        guard let doc = PDFDocument(url: url) else { throw PDFMetadataError.cannotOpen }
        let attrs = doc.documentAttributes ?? [:]
        let title = (attrs[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (attrs[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedPDFMetadata(
            title: (title?.isEmpty ?? true) ? nil : title,
            author: (author?.isEmpty ?? true) ? nil : author
        )
    }

    /// Renders the first page as an NSImage of the requested size.
    static func renderCover(at url: URL, size: CGSize) throws -> NSImage {
        guard let doc = PDFDocument(url: url) else { throw PDFMetadataError.cannotOpen }
        guard let page = doc.page(at: 0) else { throw PDFMetadataError.noPages }
        return page.thumbnail(of: size, for: .mediaBox)
    }
}
