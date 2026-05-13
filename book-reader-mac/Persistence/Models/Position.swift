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

    var book: Book?

    init(bookHash: String,
         anchor: String,
         percentage: Double,
         chapterTitle: String? = nil,
         updatedAt: Date = .now) {
        self.bookHash = bookHash
        self.anchor = anchor
        self.percentage = percentage
        self.chapterTitle = chapterTitle
        self.updatedAt = updatedAt
    }
}
