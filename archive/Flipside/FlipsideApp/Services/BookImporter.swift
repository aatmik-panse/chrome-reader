import Foundation
import PDFKit
import UIKit
import UniformTypeIdentifiers

// MARK: - Import Errors

enum BookImportError: LocalizedError {
    case unsupportedFormat(String)
    case fileCopyFailed(underlying: Error)
    case fileNotReadable
    case metadataExtractionFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            "Unsupported book format: .\(ext)"
        case .fileCopyFailed(let error):
            "Failed to copy file to library: \(error.localizedDescription)"
        case .fileNotReadable:
            "The selected file could not be read"
        case .metadataExtractionFailed:
            "Could not extract book metadata"
        }
    }
}

// MARK: - BookImporter

struct BookImporter: Sendable {

    private static let booksSubdirectory = "Books"

    func importBook(from url: URL) async throws -> Book {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        guard fm.isReadableFile(atPath: url.path) else {
            throw BookImportError.fileNotReadable
        }

        let format = try detectFormat(from: url)
        let storedFileName = "\(UUID().uuidString).\(format.rawValue)"
        let destination = try copyToLibrary(from: url, storedFileName: storedFileName)

        let originalName = url.deletingPathExtension().lastPathComponent
        let metadata = extractMetadata(from: destination, format: format, fallbackTitle: originalName)

        let book = Book(
            title: metadata.title,
            author: metadata.author,
            format: format,
            fileName: storedFileName,
            fileSize: fileSize(at: destination),
            pageCount: metadata.pageCount,
            coverImageData: metadata.coverData
        )

        let pageCache = generatePageCache(from: destination, format: format, bookID: book.id, epubBook: metadata.epubBook)
        AppGroupManager.shared.savePageCache(pageCache, for: book.id)

        if format == .epub, let epub = metadata.epubBook {
            let chapters = epub.chapters.map { (title: $0.title, html: $0.htmlContent) }
            AppGroupManager.shared.saveChapterHTML(chapters, for: book.id)
        }

        if format == .pdf {
            prerenderPDFPages(from: destination, bookID: book.id, pageCount: metadata.pageCount)
        }

        AppGroupManager.shared.setCurrentBook(id: book.id, format: format)
        AppGroupManager.shared.setCurrentBookMetadata(
            title: book.title,
            author: book.author,
            coverData: book.coverImageData
        )

        let initialPosition = ReadingPositionPayload(bookID: book.id)
        AppGroupManager.shared.saveReadingPosition(initialPosition)

        return book
    }

    // MARK: - Format Detection

    private func detectFormat(from url: URL) throws -> BookFormat {
        let ext = url.pathExtension.lowercased()

        if let format = BookFormat(rawValue: ext) {
            return format
        }

        if let utType = UTType(filenameExtension: ext) {
            if utType.conforms(to: .pdf) { return .pdf }
            if utType.conforms(to: .plainText) { return .txt }
            if utType.conforms(to: .epub) { return .epub }
        }

        throw BookImportError.unsupportedFormat(ext)
    }

    // MARK: - File Copy

    private func copyToLibrary(from source: URL, storedFileName: String) throws -> URL {
        let container = AppGroupManager.shared.containerURL
        let booksDir = container.appendingPathComponent(Self.booksSubdirectory, isDirectory: true)
        let fm = FileManager.default

        if !fm.fileExists(atPath: booksDir.path) {
            try fm.createDirectory(at: booksDir, withIntermediateDirectories: true)
        }

        let destination = booksDir.appendingPathComponent(storedFileName)

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        do {
            try fm.copyItem(at: source, to: destination)
        } catch {
            throw BookImportError.fileCopyFailed(underlying: error)
        }

        return destination
    }

    // MARK: - Metadata Extraction

    private struct BookMetadata {
        var title: String
        var author: String
        var pageCount: Int
        var coverData: Data?
        var epubBook: EPUBBook?
    }

    private func extractMetadata(from url: URL, format: BookFormat, fallbackTitle: String) -> BookMetadata {
        switch format {
        case .pdf:
            return extractPDFMetadata(from: url, fallbackTitle: fallbackTitle)
        case .txt:
            return extractTXTMetadata(from: url, fallbackTitle: fallbackTitle)
        case .epub:
            return extractEPUBMetadata(from: url, fallbackTitle: fallbackTitle)
        }
    }

    private func extractPDFMetadata(from url: URL, fallbackTitle: String) -> BookMetadata {
        guard let document = PDFDocument(url: url) else {
            return BookMetadata(title: fallbackTitle, author: "Unknown Author", pageCount: 0)
        }

        var title = fallbackTitle
        var author = "Unknown Author"

        if let attrs = document.documentAttributes {
            if let pdfTitle = attrs[PDFDocumentAttribute.titleAttribute] as? String,
               !pdfTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                title = pdfTitle
            }
            if let pdfAuthor = attrs[PDFDocumentAttribute.authorAttribute] as? String,
               !pdfAuthor.trimmingCharacters(in: .whitespaces).isEmpty {
                author = pdfAuthor
            }
        }

        return BookMetadata(
            title: title,
            author: author,
            pageCount: document.pageCount
        )
    }

    private func extractTXTMetadata(from url: URL, fallbackTitle: String) -> BookMetadata {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return BookMetadata(title: fallbackTitle, author: "Unknown Author", pageCount: 1)
        }

        let estimatedPages = max(1, content.count / TextExtractor.defaultCharsPerPage)
        return BookMetadata(
            title: fallbackTitle,
            author: "Unknown Author",
            pageCount: estimatedPages
        )
    }

    private func extractEPUBMetadata(from url: URL, fallbackTitle: String) -> BookMetadata {
        let parser = EPUBParser()

        guard let epub = try? parser.parse(epubAt: url) else {
            return BookMetadata(title: fallbackTitle, author: "Unknown Author", pageCount: 0)
        }

        let estimatedPages = max(1, epub.totalCharacterCount / TextExtractor.defaultCharsPerPage)

        return BookMetadata(
            title: epub.title,
            author: epub.author,
            pageCount: estimatedPages,
            coverData: epub.coverImageData,
            epubBook: epub
        )
    }

    // MARK: - Page Cache Generation

    private func generatePageCache(
        from url: URL,
        format: BookFormat,
        bookID: UUID,
        epubBook: EPUBBook?
    ) -> PageCache {
        switch format {
        case .pdf, .txt:
            return TextExtractor().extractPages(from: url, format: format, bookID: bookID)
        case .epub:
            return generateEPUBPageCache(bookID: bookID, epub: epubBook)
        }
    }

    private func generateEPUBPageCache(bookID: UUID, epub: EPUBBook?) -> PageCache {
        guard let epub, !epub.chapters.isEmpty else {
            return PageCache(bookID: bookID, format: .epub, totalPages: 0, pages: [], createdAt: Date())
        }

        var pages: [CachedPage] = []

        for chapter in epub.chapters {
            let chapterPages = splitTextIntoPages(chapter.plainText, charsPerPage: TextExtractor.defaultCharsPerPage)
            for pageText in chapterPages {
                pages.append(CachedPage(
                    index: pages.count,
                    text: pageText,
                    chapterTitle: chapter.title
                ))
            }
        }

        return PageCache(
            bookID: bookID,
            format: .epub,
            totalPages: pages.count,
            pages: pages,
            createdAt: Date()
        )
    }

    // MARK: - Utilities

    private func splitTextIntoPages(_ text: String, charsPerPage: Int) -> [String] {
        guard !text.isEmpty, charsPerPage > 0 else { return [] }

        var pages: [String] = []
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            if remaining.count <= charsPerPage {
                let page = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !page.isEmpty { pages.append(page) }
                break
            }

            let endBound = remaining.index(remaining.startIndex, offsetBy: charsPerPage)
            var breakPoint = endBound

            if let paragraphBreak = remaining[remaining.startIndex..<endBound].lastIndex(of: "\n") {
                let afterBreak = remaining.index(after: paragraphBreak)
                let distance = remaining.distance(from: remaining.startIndex, to: afterBreak)
                if distance > charsPerPage / 2 {
                    breakPoint = afterBreak
                }
            } else if let spaceBreak = remaining[remaining.startIndex..<endBound].lastIndex(of: " ") {
                breakPoint = remaining.index(after: spaceBreak)
            }

            let pageText = String(remaining[remaining.startIndex..<breakPoint])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !pageText.isEmpty {
                pages.append(pageText)
            }
            remaining = remaining[breakPoint...]
        }

        return pages
    }

    private func prerenderPDFPages(from url: URL, bookID: UUID, pageCount: Int) {
        guard let document = PDFDocument(url: url) else { return }

        let targetWidth: CGFloat = 500
        let manager = AppGroupManager.shared

        for i in 0..<min(document.pageCount, pageCount) {
            guard let page = document.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = targetWidth / bounds.width
            let size = CGSize(width: targetWidth, height: bounds.height * scale)

            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }

            if let data = image.jpegData(compressionQuality: 0.7) {
                manager.savePageImage(data, for: bookID, pageIndex: i)
            }
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attrs?[.size] as? Int64 ?? 0
    }
}

// MARK: - UTType EPUB Extension

private extension UTType {
    static let epub = UTType("org.idpf.epub-container") ?? UTType("public.epub") ?? UTType.data
}
