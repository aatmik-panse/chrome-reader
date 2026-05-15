import AppIntents
import WidgetKit

struct NextPageIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Next Page"
    nonisolated(unsafe) static var description = IntentDescription("Go to the next page")

    func perform() async throws -> some IntentResult {
        let manager = AppGroupManager.shared

        guard let bookID = manager.getCurrentBookID(),
              var position = manager.getReadingPosition(for: bookID) else {
            return .result()
        }

        let format = manager.getCurrentBookFormat()
        let maxPage: Int

        if format == .pdf {
            maxPage = manager.pageImageCount(for: bookID) - 1
        } else if let cache = manager.getPageCache(for: bookID) {
            maxPage = cache.totalPages - 1
        } else {
            return .result()
        }

        guard position.pageIndex < maxPage else { return .result() }

        position.pageIndex += 1
        position.percentage = maxPage > 0 ? Double(position.pageIndex) / Double(maxPage) : 0
        position.updatedAt = Date()
        manager.saveReadingPosition(position)
        manager.resetScrollOnPageChange()

        return .result()
    }
}
