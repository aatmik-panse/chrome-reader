import Foundation
import PDFKit

// MARK: - Page Cache Models

struct CachedPage: Codable, Equatable {
    let index: Int
    let text: String
    let chapterTitle: String?
}

struct PageCache: Codable, Equatable {
    let bookID: UUID
    let format: BookFormat
    let totalPages: Int
    let pages: [CachedPage]
    let createdAt: Date

    var isEmpty: Bool { pages.isEmpty }

    func page(at index: Int) -> CachedPage? {
        guard index >= 0, index < pages.count else { return nil }
        return pages[index]
    }
}

// MARK: - TextExtractor

struct TextExtractor {
    static let defaultCharsPerPage = 650

    func extractPages(
        from url: URL,
        format: BookFormat,
        targetCharsPerPage: Int = TextExtractor.defaultCharsPerPage
    ) -> PageCache {
        let bookID = UUID()
        switch format {
        case .txt:
            return extractTXTPages(from: url, bookID: bookID, charsPerPage: targetCharsPerPage)
        case .pdf:
            return extractPDFPages(from: url, bookID: bookID, charsPerPage: targetCharsPerPage)
        case .epub:
            return extractEPUBPages(from: url, bookID: bookID, charsPerPage: targetCharsPerPage)
        }
    }

    func extractPages(
        from url: URL,
        format: BookFormat,
        bookID: UUID,
        targetCharsPerPage: Int = TextExtractor.defaultCharsPerPage
    ) -> PageCache {
        switch format {
        case .txt:
            return extractTXTPages(from: url, bookID: bookID, charsPerPage: targetCharsPerPage)
        case .pdf:
            return extractPDFPages(from: url, bookID: bookID, charsPerPage: targetCharsPerPage)
        case .epub:
            return extractEPUBPages(from: url, bookID: bookID, charsPerPage: targetCharsPerPage)
        }
    }

    // MARK: - TXT Extraction

    private func extractTXTPages(from url: URL, bookID: UUID, charsPerPage: Int) -> PageCache {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return emptyCache(bookID: bookID, format: .txt)
        }

        let pages = splitTextIntoPages(content, charsPerPage: charsPerPage)
            .enumerated()
            .map { index, text in
                CachedPage(index: index, text: text, chapterTitle: nil)
            }

        return PageCache(
            bookID: bookID,
            format: .txt,
            totalPages: pages.count,
            pages: pages,
            createdAt: Date()
        )
    }

    // MARK: - PDF Extraction

    private func extractPDFPages(from url: URL, bookID: UUID, charsPerPage: Int) -> PageCache {
        guard let document = PDFDocument(url: url) else {
            return emptyCache(bookID: bookID, format: .pdf)
        }

        var allPages: [CachedPage] = []

        for pdfPageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pdfPageIndex) else { continue }
            let fullText = page.string ?? ""
            if fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

            let chunks = splitTextIntoPages(fullText, charsPerPage: charsPerPage)
            let pageLabel = "Page \(pdfPageIndex + 1)"

            for chunk in chunks {
                allPages.append(CachedPage(
                    index: allPages.count,
                    text: chunk,
                    chapterTitle: pageLabel
                ))
            }
        }

        return PageCache(
            bookID: bookID,
            format: .pdf,
            totalPages: allPages.count,
            pages: allPages,
            createdAt: Date()
        )
    }

    // MARK: - EPUB Extraction (stub — real parsing handled by a dedicated EPUB parser)

    private func extractEPUBPages(from url: URL, bookID: UUID, charsPerPage: Int) -> PageCache {
        return PageCache(
            bookID: bookID,
            format: .epub,
            totalPages: 0,
            pages: [],
            createdAt: Date()
        )
    }

    // MARK: - Text Splitting

    fileprivate func splitTextIntoPages(_ text: String, charsPerPage: Int) -> [String] {
        guard !text.isEmpty, charsPerPage > 0 else { return [] }

        var pages: [String] = []
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            if remaining.count <= charsPerPage {
                pages.append(String(remaining))
                break
            }

            let endBound = remaining.index(remaining.startIndex, offsetBy: charsPerPage)
            var breakPoint = endBound

            // Walk backward to find a natural break (paragraph, sentence, or word boundary)
            if let paragraphBreak = remaining[remaining.startIndex..<endBound].lastIndex(of: "\n") {
                let afterBreak = remaining.index(after: paragraphBreak)
                if remaining.distance(from: remaining.startIndex, to: afterBreak) > charsPerPage / 2 {
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

    // MARK: - Helpers

    private func emptyCache(bookID: UUID, format: BookFormat) -> PageCache {
        PageCache(bookID: bookID, format: format, totalPages: 0, pages: [], createdAt: Date())
    }
}
