import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Clay Color Palette

enum ClayColors {
    static let cream    = Color(red: 250 / 255, green: 249 / 255, blue: 247 / 255)
    static let oat      = Color(red: 232 / 255, green: 229 / 255, blue: 224 / 255)
    static let matcha600 = Color(red: 7 / 255,  green: 138 / 255, blue: 82 / 255)
    static let clayBlack = Color(red: 26 / 255, green: 24 / 255,  blue: 21 / 255)
}

// MARK: - Widget Entry

struct ReadingEntry: TimelineEntry {
    let date: Date
    let bookTitle: String
    let chapterTitle: String
    let pageText: String
    let currentPage: Int
    let totalPages: Int
    let percentage: Double
    let coverImageData: Data?
    let pageImageData: Data?
    let bookFormat: String
    let zoomLevel: Double
    let scrollOffsetY: Double
    let scrollOffsetX: Double
    let hasBook: Bool

    var isPDF: Bool { bookFormat == "pdf" }

    static let placeholder = ReadingEntry(
        date: .now,
        bookTitle: "The Great Gatsby",
        chapterTitle: "Chapter 3",
        pageText: """
        In my younger and more vulnerable years my father gave me some advice \
        that I've been turning over in my mind ever since.

        "Whenever you feel like criticizing anyone," he told me, "just remember \
        that all the people in this world haven't had the advantages that you've had."
        """,
        currentPage: 42,
        totalPages: 128,
        percentage: 0.328,
        coverImageData: nil,
        pageImageData: nil,
        bookFormat: "epub",
        zoomLevel: 1.0,
        scrollOffsetY: 0,
        scrollOffsetX: 0,
        hasBook: true
    )

    static let empty = ReadingEntry(
        date: .now,
        bookTitle: "",
        chapterTitle: "",
        pageText: "",
        currentPage: 0,
        totalPages: 0,
        percentage: 0,
        coverImageData: nil,
        pageImageData: nil,
        bookFormat: "",
        zoomLevel: 1.0,
        scrollOffsetY: 0,
        scrollOffsetX: 0,
        hasBook: false
    )
}

// MARK: - Widget Configuration Intent

struct ReadingWidgetConfigurationIntent: WidgetConfigurationIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Current Book"
    nonisolated(unsafe) static var description = IntentDescription("Shows your current reading progress")
}

// MARK: - Shared Data Fetcher

enum WidgetDataProvider {
    static func currentEntry() -> ReadingEntry {
        let manager = AppGroupManager.shared
        let format = manager.getCurrentBookFormat()

        guard let bookID = manager.getCurrentBookID(),
              let position = manager.getReadingPosition(for: bookID) else {
            return .empty
        }

        if format == .pdf {
            return pdfEntry(manager: manager, bookID: bookID, position: position)
        }

        return textEntry(manager: manager, bookID: bookID, position: position, format: format)
    }

    private static func pdfEntry(
        manager: AppGroupManager,
        bookID: UUID,
        position: ReadingPositionPayload
    ) -> ReadingEntry {
        let pageIndex = max(0, position.pageIndex)
        let totalPages = manager.pageImageCount(for: bookID)
        guard totalPages > 0 else { return .empty }

        let clampedPage = min(pageIndex, totalPages - 1)
        let imageData = manager.getPageImage(for: bookID, pageIndex: clampedPage)
        let percentage = Double(clampedPage) / Double(max(totalPages - 1, 1))

        return ReadingEntry(
            date: .now,
            bookTitle: manager.currentBookTitle ?? "Untitled",
            chapterTitle: "Page \(clampedPage + 1)",
            pageText: "",
            currentPage: clampedPage,
            totalPages: totalPages,
            percentage: min(percentage, 1.0),
            coverImageData: manager.currentBookCoverData,
            pageImageData: imageData,
            bookFormat: "pdf",
            zoomLevel: manager.widgetZoomLevel,
            scrollOffsetY: manager.widgetScrollOffset,
            scrollOffsetX: manager.widgetScrollOffsetX,
            hasBook: true
        )
    }

    private static func textEntry(
        manager: AppGroupManager,
        bookID: UUID,
        position: ReadingPositionPayload,
        format: BookFormat?
    ) -> ReadingEntry {
        guard let cache = manager.getPageCache(for: bookID), !cache.isEmpty else {
            return .empty
        }

        let pageIndex = min(max(0, position.pageIndex), cache.totalPages - 1)
        let page = cache.page(at: pageIndex)
        let percentage = cache.totalPages > 0
            ? Double(pageIndex) / Double(cache.totalPages)
            : 0

        return ReadingEntry(
            date: .now,
            bookTitle: manager.currentBookTitle ?? "Untitled",
            chapterTitle: page?.chapterTitle ?? "",
            pageText: page?.text ?? "",
            currentPage: pageIndex,
            totalPages: cache.totalPages,
            percentage: min(percentage, 1.0),
            coverImageData: manager.currentBookCoverData,
            pageImageData: nil,
            bookFormat: format?.rawValue ?? "txt",
            zoomLevel: 1.0,
            scrollOffsetY: 0,
            scrollOffsetX: 0,
            hasBook: true
        )
    }
}

// MARK: - Reading Widget Timeline Provider

struct ReadingTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = ReadingEntry
    typealias Intent = ReadingWidgetConfigurationIntent

    func placeholder(in context: Context) -> ReadingEntry {
        .placeholder
    }

    func snapshot(for configuration: Intent, in context: Context) async -> ReadingEntry {
        context.isPreview ? .placeholder : WidgetDataProvider.currentEntry()
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<ReadingEntry> {
        let entry = WidgetDataProvider.currentEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 5, to: .now)!
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}

// MARK: - Lock Screen Timeline Provider

struct LockScreenTimelineProvider: AppIntentTimelineProvider {
    typealias Entry = ReadingEntry
    typealias Intent = ReadingWidgetConfigurationIntent

    func placeholder(in context: Context) -> ReadingEntry {
        .placeholder
    }

    func snapshot(for configuration: Intent, in context: Context) async -> ReadingEntry {
        context.isPreview ? .placeholder : WidgetDataProvider.currentEntry()
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<ReadingEntry> {
        let entry = WidgetDataProvider.currentEntry()
        let refresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        return Timeline(entries: [entry], policy: .after(refresh))
    }
}
