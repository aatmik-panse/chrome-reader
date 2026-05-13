import Foundation
import SwiftData

/// Helpers that mutate `Position` in response to page-mode advance commands.
/// Page mode is static-only: the page changes only when the active reader
/// advances OR when these helpers fire from the global hotkey.
@MainActor
enum PageModeAdvance {

    /// Apply a one-page advance to the currently-tracked Position. The format
    /// determines how `anchor` is decoded and re-encoded:
    /// - PDF: anchor is `"page:offset"`. We bump the page number by ±1,
    ///   clamped to `[1, pageCount]`.
    /// - EPUB / TXT: anchor is opaque to this helper; we set a
    ///   `pendingScrollDirection` flag on the Position which the relevant
    ///   page-mode view observes and consumes. The view does the actual
    ///   screen-height scroll because only it knows the rendered geometry.
    static func advance(
        position: Position,
        format: BookFormat,
        direction: Direction,
        pdfPageCount: Int? = nil
    ) {
        switch format {
        case .pdf:
            let (page, offset) = decodePDFAnchor(position.anchor)
            let next = max(1, page + (direction == .next ? 1 : -1))
            let clamped = pdfPageCount.map { max(1, min($0, next)) } ?? next
            position.anchor = "\(clamped):\(offset)"
            position.updatedAt = .now
        case .epub, .txt:
            position.pendingScrollDirection = direction.rawValue
            position.updatedAt = .now
        }
    }

    enum Direction: String, Sendable {
        case next
        case previous
    }

    private static func decodePDFAnchor(_ anchor: String) -> (page: Int, offset: Int) {
        let parts = anchor.split(separator: ":")
        let page = Int(parts.first ?? "1") ?? 1
        let offset = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return (page, offset)
    }
}
