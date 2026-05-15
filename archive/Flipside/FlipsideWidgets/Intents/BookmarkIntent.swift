import AppIntents
import WidgetKit

struct BookmarkIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Bookmark Page"
    nonisolated(unsafe) static var description = IntentDescription("Bookmark the current page for later")

    func perform() async throws -> some IntentResult {
        let manager = AppGroupManager.shared

        guard let bookID = manager.getCurrentBookID(),
              let position = manager.getReadingPosition(for: bookID) else {
            return .result()
        }

        let key = "bookmarks_\(bookID.uuidString)"
        var bookmarks = manager.defaults.array(forKey: key) as? [Int] ?? []

        let page = position.pageIndex
        if !bookmarks.contains(page) {
            bookmarks.append(page)
            bookmarks.sort()
            manager.defaults.set(bookmarks, forKey: key)
        }

        return .result()
    }
}
