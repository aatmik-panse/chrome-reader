import Foundation
import SwiftData

@Model
class ReadingPosition {
    @Attribute(.unique) var bookID: UUID
    var chapterIndex: Int
    var pageIndex: Int
    var scrollOffset: Double
    var percentage: Double
    var updatedAt: Date

    init(
        bookID: UUID,
        chapterIndex: Int = 0,
        pageIndex: Int = 0,
        scrollOffset: Double = 0,
        percentage: Double = 0
    ) {
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.pageIndex = pageIndex
        self.scrollOffset = scrollOffset
        self.percentage = percentage
        self.updatedAt = Date()
    }
}
