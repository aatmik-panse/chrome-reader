import Foundation
import OSLog
import SwiftData

enum BookImporterError: Error, CustomStringConvertible {
    case unsupportedFormat(String)

    var description: String {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported file extension: .\(ext)"
        }
    }
}

/// Single entry point for adding a book to the library.
/// All side effects happen against the injected directories + ModelContext,
/// so tests can run against tmp dirs and an in-memory container.
@MainActor
final class BookImporter {
    private let booksDirectory: URL
    private let coversDirectory: URL
    private let log = Logger(subsystem: "com.profitoniumapps.instantbookreader",
                             category: "BookImporter")

    init(booksDirectory: URL, coversDirectory: URL) {
        self.booksDirectory = booksDirectory
        self.coversDirectory = coversDirectory
    }

    /// Convenience initializer that imports into the user's real App Support
    /// directories. Production code uses this; tests use the explicit init.
    convenience init() {
        self.init(booksDirectory: AppSupportPaths.books,
                  coversDirectory: AppSupportPaths.covers)
    }

    /// Imports `source` and returns the resulting `Book`. Idempotent: a second
    /// call with the same content hashes returns the existing row unchanged.
    @discardableResult
    func importBook(from source: URL, into context: ModelContext) throws -> Book {
        guard let format = BookFileExtension.format(for: source) else {
            throw BookImporterError.unsupportedFormat(source.pathExtension)
        }

        try FileManager.default.createDirectory(at: booksDirectory,
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coversDirectory,
                                                withIntermediateDirectories: true)

        let sha = try BookHash.sha256Hex(ofFileAt: source)

        // Dedup: return the existing row if any.
        let predicate = #Predicate<Book> { $0.sha256 == sha }
        if let existing = try context.fetch(FetchDescriptor<Book>(predicate: predicate)).first {
            log.info("re-import noop for \(sha, privacy: .public)")
            return existing
        }

        // 1. Copy bytes to <booksDir>/<sha>.<ext>
        let ext = BookFileExtension.canonicalExtension(for: format)
        let stored = booksDirectory.appendingPathComponent("\(sha).\(ext)")
        if FileManager.default.fileExists(atPath: stored.path) {
            try FileManager.default.removeItem(at: stored)
        }
        try FileManager.default.copyItem(at: source, to: stored)

        // 2. Parse metadata.
        let title: String
        let author: String?
        switch format {
        case .epub:
            let parsed = try EPUBMetadata.parse(at: stored)
            title = parsed.title ?? source.deletingPathExtension().lastPathComponent
            author = parsed.author
        case .pdf:
            let parsed = try PDFMetadata.parse(at: stored)
            title = parsed.title ?? source.deletingPathExtension().lastPathComponent
            author = parsed.author
        case .txt:
            // TXTMetadata derives title from the filename, so parse the
            // original source rather than the SHA-named copy.
            let parsed = try TXTMetadata.parse(at: source)
            title = parsed.title ?? source.deletingPathExtension().lastPathComponent
            author = parsed.author
        }

        // 3. Cover (best-effort).
        var coverRelative: String? = nil
        do {
            let coverURL = try CoverExtractor.extract(from: stored,
                                                      format: format,
                                                      sha256: sha,
                                                      coversDirectory: coversDirectory)
            coverRelative = "Covers/" + coverURL.lastPathComponent
        } catch {
            log.warning("cover extraction failed for \(sha, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        // 4. Insert.
        let book = Book(
            sha256: sha,
            title: title,
            author: author,
            format: format,
            coverPath: coverRelative,
            filePath: "Books/\(sha).\(ext)",
            addedAt: .now,
            lastOpenedAt: nil
        )
        context.insert(book)
        return book
    }

    /// Walks `folder` recursively and attempts to import every supported file.
    /// Returns a report listing successful imports and a per-file reason for
    /// each skipped item. The caller is expected to surface skipped errors.
    static func importFolder(at folder: URL,
                             into context: ModelContext) async throws -> BookImportReport {
        var imported: [Book] = []
        var skipped: [BookImportReport.Skipped] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder,
                                             includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return BookImportReport(imported: [], skipped: [])
        }
        let importer = BookImporter()
        for case let url as URL in enumerator {
            let isRegular = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            guard isRegular else { continue }
            guard BookFileExtension.format(for: url) != nil else {
                continue // not a supported extension — silently skip
            }
            do {
                let book = try importer.importBook(from: url, into: context)
                imported.append(book)
            } catch {
                skipped.append(BookImportReport.Skipped(url: url,
                                                       reason: error.localizedDescription))
            }
        }
        try? context.save()
        return BookImportReport(imported: imported, skipped: skipped)
    }
}

/// Outcome of a folder import. Used by the Library tab to surface a
/// human-readable list of files that did not make it into the library.
struct BookImportReport {
    struct Skipped {
        let url: URL
        let reason: String
    }
    let imported: [Book]
    let skipped: [Skipped]
}
