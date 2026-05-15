import Foundation
import SwiftData

@Model
final class Book {
    var id: UUID
    var title: String
    var author: String
    var formatRaw: String
    var fileName: String
    var fileSize: Int64
    var pageCount: Int
    @Attribute(.externalStorage) var coverImageData: Data?
    var dateAdded: Date
    var lastOpened: Date?
    var readingProgress: Double

    @Transient var format: BookFormat {
        get { BookFormat(rawValue: formatRaw) ?? .txt }
        set { formatRaw = newValue.rawValue }
    }

    @Transient var fileURL: URL {
        AppGroupManager.shared.containerURL
            .appendingPathComponent("Books", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    init(
        title: String,
        author: String = "Unknown Author",
        format: BookFormat,
        fileName: String,
        fileSize: Int64 = 0,
        pageCount: Int = 0,
        coverImageData: Data? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.formatRaw = format.rawValue
        self.fileName = fileName
        self.fileSize = fileSize
        self.pageCount = pageCount
        self.coverImageData = coverImageData
        self.dateAdded = Date()
        self.lastOpened = nil
        self.readingProgress = 0
    }
}
