import Foundation
import WidgetKit

// MARK: - SyncProvider Protocol

protocol SyncProvider {
    func syncReadingPosition(_ position: ReadingPositionPayload, for bookID: UUID) async throws
    func fetchReadingPosition(for bookID: UUID) async throws -> ReadingPositionPayload?
}

// MARK: - ReadingPositionPayload

struct ReadingPositionPayload: Codable, Equatable {
    var bookID: UUID
    var chapterIndex: Int
    var pageIndex: Int
    var scrollOffset: Double
    var percentage: Double
    var updatedAt: Date

    init(bookID: UUID, chapterIndex: Int = 0, pageIndex: Int = 0, scrollOffset: Double = 0, percentage: Double = 0) {
        self.bookID = bookID
        self.chapterIndex = chapterIndex
        self.pageIndex = pageIndex
        self.scrollOffset = scrollOffset
        self.percentage = percentage
        self.updatedAt = Date()
    }
}

// MARK: - AppGroupManager

final class AppGroupManager: @unchecked Sendable {
    static let shared = AppGroupManager()

    static let appGroupID = "group.com.flipside.reader"
    static let widgetKind = "FlipsideReadingWidget"

    private let currentBookKey = "currentBookID"
    private let currentBookFormatKey = "currentBookFormat"
    private let positionKeyPrefix = "readingPosition_"
    private let pageCacheDirectory = "PageCaches"
    private let chapterCacheDirectory = "ChapterCaches"
    private let pageImagesDirectory = "PageImages"

    let defaults: UserDefaults
    let containerURL: URL

    private init() {
        guard let defaults = UserDefaults(suiteName: AppGroupManager.appGroupID) else {
            fatalError("Failed to initialize shared UserDefaults for App Group: \(AppGroupManager.appGroupID)")
        }
        self.defaults = defaults

        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupManager.appGroupID) else {
            fatalError("Failed to get container URL for App Group: \(AppGroupManager.appGroupID)")
        }
        self.containerURL = url

        let fm = FileManager.default
        let cacheDir = url.appendingPathComponent(pageCacheDirectory, isDirectory: true)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let chapterDir = url.appendingPathComponent(chapterCacheDirectory, isDirectory: true)
        try? fm.createDirectory(at: chapterDir, withIntermediateDirectories: true)

        let imagesDir = url.appendingPathComponent(pageImagesDirectory, isDirectory: true)
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
    }

    // MARK: - Current Book

    func setCurrentBook(id: UUID, format: BookFormat? = nil) {
        defaults.set(id.uuidString, forKey: currentBookKey)
        if let format {
            defaults.set(format.rawValue, forKey: currentBookFormatKey)
        }
        reloadWidgetTimelines()
    }

    func getCurrentBookID() -> UUID? {
        guard let string = defaults.string(forKey: currentBookKey) else { return nil }
        return UUID(uuidString: string)
    }

    func getCurrentBookFormat() -> BookFormat? {
        guard let raw = defaults.string(forKey: currentBookFormatKey) else { return nil }
        return BookFormat(rawValue: raw)
    }

    // MARK: - PDF Page Images

    func savePageImage(_ imageData: Data, for bookID: UUID, pageIndex: Int) {
        let dir = pageImagesDirectoryURL(for: bookID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("\(pageIndex).jpg")
        try? imageData.write(to: fileURL, options: .atomic)
    }

    func getPageImage(for bookID: UUID, pageIndex: Int) -> Data? {
        let fileURL = pageImagesDirectoryURL(for: bookID).appendingPathComponent("\(pageIndex).jpg")
        return try? Data(contentsOf: fileURL)
    }

    func deletePageImages(for bookID: UUID) {
        let dir = pageImagesDirectoryURL(for: bookID)
        try? FileManager.default.removeItem(at: dir)
    }

    func pageImageCount(for bookID: UUID) -> Int {
        let dir = pageImagesDirectoryURL(for: bookID)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return files.filter { $0.hasSuffix(".jpg") }.count
    }

    // MARK: - Widget Zoom & Scroll

    private static let zoomKey = "widgetZoomLevel"
    private static let scrollYKey = "widgetScrollOffset"
    private static let scrollXKey = "widgetScrollOffsetX"
    static let zoomLevels: [Double] = [1.0, 1.25, 1.5, 2.0, 2.5, 3.0]
    static let scrollStep: Double = 0.15

    var widgetZoomLevel: Double {
        get {
            let val = defaults.double(forKey: Self.zoomKey)
            return val > 0 ? val : 1.0
        }
        set {
            defaults.set(newValue, forKey: Self.zoomKey)
            reloadWidgetTimelines()
        }
    }

    var widgetScrollOffset: Double {
        get { defaults.double(forKey: Self.scrollYKey) }
        set {
            defaults.set(newValue, forKey: Self.scrollYKey)
            reloadWidgetTimelines()
        }
    }

    var widgetScrollOffsetX: Double {
        get { defaults.double(forKey: Self.scrollXKey) }
        set {
            defaults.set(newValue, forKey: Self.scrollXKey)
            reloadWidgetTimelines()
        }
    }

    func zoomIn() {
        let current = widgetZoomLevel
        if let nextIdx = Self.zoomLevels.firstIndex(where: { $0 > current + 0.01 }) {
            widgetZoomLevel = Self.zoomLevels[nextIdx]
        }
    }

    func zoomOut() {
        let current = widgetZoomLevel
        if let prevIdx = Self.zoomLevels.lastIndex(where: { $0 < current - 0.01 }) {
            widgetZoomLevel = Self.zoomLevels[prevIdx]
            clampScrollOffsets()
        }
    }

    func scrollUp() {
        widgetScrollOffset = max(0, widgetScrollOffset - Self.scrollStep)
    }

    func scrollDown() {
        let maxY = max(0, 1.0 - (1.0 / widgetZoomLevel))
        widgetScrollOffset = min(maxY, widgetScrollOffset + Self.scrollStep)
    }

    func scrollLeft() {
        widgetScrollOffsetX = max(0, widgetScrollOffsetX - Self.scrollStep)
    }

    func scrollRight() {
        let newOffset = min(1.0, widgetScrollOffsetX + Self.scrollStep)
        widgetScrollOffsetX = newOffset
    }

    func resetScrollOnPageChange() {
        widgetScrollOffset = 0
        widgetScrollOffsetX = 0
    }

    private func clampScrollOffsets() {
        let maxOffset = max(0, 1.0 - (1.0 / widgetZoomLevel))
        if widgetScrollOffset > maxOffset { widgetScrollOffset = maxOffset }
        if widgetScrollOffsetX > maxOffset { widgetScrollOffsetX = maxOffset }
    }

    private func pageImagesDirectoryURL(for bookID: UUID) -> URL {
        containerURL
            .appendingPathComponent(pageImagesDirectory, isDirectory: true)
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
    }

    // MARK: - Page Navigation

    func advancePage(by delta: Int) {
        guard let bookID = getCurrentBookID(),
              var position = getReadingPosition(for: bookID) else { return }

        let newPage = max(0, position.pageIndex + delta)
        position.pageIndex = newPage
        position.updatedAt = Date()

        if let cache = getPageCache(for: bookID), cache.totalPages > 0 {
            position.percentage = Double(newPage) / Double(cache.totalPages)
        }

        saveReadingPosition(position)
    }

    // MARK: - Reading Position (UserDefaults JSON)

    func getReadingPosition(for bookID: UUID) -> ReadingPositionPayload? {
        let key = positionKeyPrefix + bookID.uuidString
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ReadingPositionPayload.self, from: data)
    }

    func saveReadingPosition(_ position: ReadingPositionPayload) {
        let key = positionKeyPrefix + position.bookID.uuidString
        if let data = try? JSONEncoder().encode(position) {
            defaults.set(data, forKey: key)
        }
        reloadWidgetTimelines()
    }

    // MARK: - Page Cache (File-based JSON)

    func getPageCache(for bookID: UUID) -> PageCache? {
        let fileURL = pageCacheFileURL(for: bookID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PageCache.self, from: data)
    }

    func savePageCache(_ cache: PageCache, for bookID: UUID) {
        let fileURL = pageCacheFileURL(for: bookID)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func deletePageCache(for bookID: UUID) {
        let fileURL = pageCacheFileURL(for: bookID)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Book Metadata (for widget display)

    private static let bookTitleKey = "currentBookTitle"
    private static let bookAuthorKey = "currentBookAuthor"
    private static let bookCoverKey = "currentBookCoverData"

    var currentBookTitle: String? {
        defaults.string(forKey: Self.bookTitleKey)
    }

    var currentBookAuthor: String? {
        defaults.string(forKey: Self.bookAuthorKey)
    }

    var currentBookCoverData: Data? {
        defaults.data(forKey: Self.bookCoverKey)
    }

    func setCurrentBookMetadata(title: String, author: String?, coverData: Data?) {
        defaults.set(title, forKey: Self.bookTitleKey)
        defaults.set(author, forKey: Self.bookAuthorKey)
        defaults.set(coverData, forKey: Self.bookCoverKey)
    }

    // MARK: - Widget Reload

    private func reloadWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: AppGroupManager.widgetKind)
    }

    // MARK: - Chapter HTML Cache (File-based JSON)

    func saveChapterHTML(_ chapters: [(title: String, html: String)], for bookID: UUID) {
        let entries = chapters.map { ChapterHTMLEntry(title: $0.title, html: $0.html) }
        let fileURL = chapterCacheFileURL(for: bookID)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func getChapterHTML(for bookID: UUID) -> [(title: String, html: String)]? {
        let fileURL = chapterCacheFileURL(for: bookID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let entries = try? JSONDecoder().decode([ChapterHTMLEntry].self, from: data) else { return nil }
        return entries.map { (title: $0.title, html: $0.html) }
    }

    func deleteChapterHTML(for bookID: UUID) {
        let fileURL = chapterCacheFileURL(for: bookID)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Helpers

    private func pageCacheFileURL(for bookID: UUID) -> URL {
        containerURL
            .appendingPathComponent(pageCacheDirectory, isDirectory: true)
            .appendingPathComponent("\(bookID.uuidString).json")
    }

    private func chapterCacheFileURL(for bookID: UUID) -> URL {
        containerURL
            .appendingPathComponent(chapterCacheDirectory, isDirectory: true)
            .appendingPathComponent("\(bookID.uuidString).json")
    }
}

// MARK: - Chapter HTML Entry

private struct ChapterHTMLEntry: Codable {
    let title: String
    let html: String
}
