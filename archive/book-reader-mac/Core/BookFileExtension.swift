import Foundation
import UniformTypeIdentifiers

/// Maps file URLs to the app's three supported formats. Single source of
/// truth for both the importer and the NSOpenPanel content-type filter.
enum BookFileExtension {
    /// All UTIs the app advertises in `CFBundleDocumentTypes`.
    static let supportedContentTypes: [UTType] = {
        var types: [UTType] = []
        if let epub = UTType("org.idpf.epub-container") { types.append(epub) }
        types.append(.pdf)
        types.append(.plainText)
        return types
    }()

    /// Returns the `BookFormat` for a file URL based on its extension.
    /// Returns nil for unsupported types.
    static func format(for url: URL) -> BookFormat? {
        switch url.pathExtension.lowercased() {
        case "epub": return .epub
        case "pdf": return .pdf
        case "txt", "text": return .txt
        default: return nil
        }
    }

    /// Canonical filesystem extension used when storing a copy under App Support.
    static func canonicalExtension(for format: BookFormat) -> String {
        switch format {
        case .epub: return "epub"
        case .pdf: return "pdf"
        case .txt: return "txt"
        }
    }
}
