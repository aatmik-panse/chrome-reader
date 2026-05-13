import Foundation
import SwiftData

/// Content-addressed anchor: stores surrounding text + offset rather than
/// DOM ranges, so highlights survive re-renders and reflow. Ported from
/// `book-reader-extension/src/newtab/lib/highlights/anchor.ts`.
@Model
final class Highlight {
    @Attribute(.unique) var clientID: UUID
    var bookHash: String
    var text: String
    var surroundingText: String
    var offset: Int
    var color: String?
    var note: String?
    var createdAt: Date
    var updatedAt: Date

    var book: Book?

    init(clientID: UUID = UUID(),
         bookHash: String,
         text: String,
         surroundingText: String,
         offset: Int,
         color: String? = nil,
         note: String? = nil,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.clientID = clientID
        self.bookHash = bookHash
        self.text = text
        self.surroundingText = surroundingText
        self.offset = offset
        self.color = color
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
