import Foundation
import PDFKit
import UIKit
import Observation

@Observable
@MainActor
final class PDFService {

    private(set) var document: PDFDocument?
    private(set) var pageCount: Int = 0
    var currentPage: Int = 0 {
        didSet { currentPage = clamp(currentPage, min: 0, max: max(0, pageCount - 1)) }
    }
    var zoom: CGFloat = 1.0

    var isLoaded: Bool { document != nil }

    var title: String? {
        document?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String
    }

    var author: String? {
        document?.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String
    }

    var subject: String? {
        document?.documentAttributes?[PDFDocumentAttribute.subjectAttribute] as? String
    }

    var currentPageLabel: String {
        guard pageCount > 0 else { return "–" }
        return "\(currentPage + 1) of \(pageCount)"
    }

    var progress: Double {
        guard pageCount > 1 else { return 0 }
        return Double(currentPage) / Double(pageCount - 1)
    }

    // MARK: - Document Loading

    func loadDocument(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        document = PDFDocument(url: url)
        pageCount = document?.pageCount ?? 0
        currentPage = 0
        zoom = 1.0
    }

    func unloadDocument() {
        document = nil
        pageCount = 0
        currentPage = 0
        zoom = 1.0
    }

    // MARK: - Page Navigation

    func goToPage(_ index: Int) {
        guard pageCount > 0 else { return }
        currentPage = clamp(index, min: 0, max: pageCount - 1)
    }

    func nextPage() {
        goToPage(currentPage + 1)
    }

    func previousPage() {
        goToPage(currentPage - 1)
    }

    func goToStart() {
        goToPage(0)
    }

    func goToEnd() {
        goToPage(pageCount - 1)
    }

    // MARK: - Text Extraction

    func pageText(at index: Int) -> String? {
        guard let page = document?.page(at: index) else { return nil }
        return page.string
    }

    func fullText() -> String {
        guard let document else { return "" }
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
    }

    // MARK: - Thumbnails

    func pageThumbnail(at index: Int, size: CGSize) -> UIImage? {
        guard let page = document?.page(at: index) else { return nil }
        return page.thumbnail(of: size, for: .mediaBox)
    }

    nonisolated func pageThumbnailOffMain(at index: Int, size: CGSize, document: PDFDocument) -> UIImage? {
        guard let page = document.page(at: index) else { return nil }
        return page.thumbnail(of: size, for: .mediaBox)
    }

    // MARK: - Search

    func search(for text: String) -> [PDFSelection] {
        guard let document, !text.isEmpty else { return [] }
        return document.findString(text, withOptions: .caseInsensitive)
    }

    // MARK: - Metadata

    func documentMetadata() -> [AnyHashable: Any] {
        document?.documentAttributes ?? [:]
    }

    // MARK: - Private

    private func clamp(_ value: Int, min minVal: Int, max maxVal: Int) -> Int {
        Swift.min(Swift.max(value, minVal), maxVal)
    }
}
