import Foundation
import SwiftData

enum BookFormat: String, Codable, Sendable {
    case epub
    case pdf
    case txt
}

@Model
final class Book {
    @Attribute(.unique) var sha256: String
    var title: String
    var author: String?
    var format: BookFormat
    /// Relative path under AppSupportPaths.covers; nil until cover extraction runs.
    var coverPath: String?
    /// Relative path under AppSupportPaths.books.
    var filePath: String
    var addedAt: Date
    var lastOpenedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Position.book)
    var position: Position?

    @Relationship(deleteRule: .cascade, inverse: \Highlight.book)
    var highlights: [Highlight] = []

    init(sha256: String,
         title: String,
         author: String? = nil,
         format: BookFormat,
         coverPath: String? = nil,
         filePath: String,
         addedAt: Date = .now,
         lastOpenedAt: Date? = nil) {
        self.sha256 = sha256
        self.title = title
        self.author = author
        self.format = format
        self.coverPath = coverPath
        self.filePath = filePath
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
    }
}
