import Foundation
import SwiftData

@Model
final class Position {
    var bookHash: String
    /// Format-dependent serialized anchor: CFI for EPUB, "page:offset" for PDF,
    /// "charOffset" for TXT. Renderer modules in Plan 3 decode/encode.
    var anchor: String
    var percentage: Double
    var chapterTitle: String?
    var updatedAt: Date

    /// Transient hint set by page-mode hotkeys when format is EPUB or TXT.
    /// "next" or "previous". The active page-mode view reads, applies a
    /// screen-height scroll, and resets this to nil. Persisted because page-mode
    /// views are recreated on every `@Query` update — the hint must survive
    /// the SwiftData refresh.
    var pendingScrollDirection: String?

    var book: Book?

    init(bookHash: String,
         anchor: String,
         percentage: Double,
         chapterTitle: String? = nil,
         updatedAt: Date = .now,
         pendingScrollDirection: String? = nil) {
        self.bookHash = bookHash
        self.anchor = anchor
        self.percentage = percentage
        self.chapterTitle = chapterTitle
        self.updatedAt = updatedAt
        self.pendingScrollDirection = pendingScrollDirection
    }
}
