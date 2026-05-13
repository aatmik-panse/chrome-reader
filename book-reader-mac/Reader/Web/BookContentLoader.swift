import Foundation

/// Reads book bytes by SHA-256 hash from the on-disk Books directory.
/// Returned through the bookreader:// URL scheme so the WKWebView reader can
/// `fetch('bookreader://current')` instead of going through IndexedDB.
struct BookContentLoader {
    let booksDirectory: URL

    init(booksDirectory: URL = AppSupportPaths.books) {
        self.booksDirectory = booksDirectory
    }

    enum LoaderError: Error, CustomStringConvertible {
        case notFound(hash: String)
        var description: String {
            switch self {
            case .notFound(let hash): return "book not found: \(hash)"
            }
        }
    }

    func read(hash: String, ext: String) throws -> Data {
        let url = booksDirectory.appendingPathComponent("\(hash).\(ext)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoaderError.notFound(hash: hash)
        }
        return try Data(contentsOf: url)
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "epub": return "application/epub+zip"
        case "pdf":  return "application/pdf"
        case "txt":  return "text/plain; charset=utf-8"
        default:     return "application/octet-stream"
        }
    }
}
