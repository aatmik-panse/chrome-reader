import AppIntents
import WidgetKit

struct PrevPageIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Previous Page"
    nonisolated(unsafe) static var description = IntentDescription("Go to the previous page")

    func perform() async throws -> some IntentResult {
        let manager = AppGroupManager.shared

        guard let bookID = manager.getCurrentBookID(),
              var position = manager.getReadingPosition(for: bookID) else {
            return .result()
        }

        guard position.pageIndex > 0 else { return .result() }

        position.pageIndex -= 1

        let format = manager.getCurrentBookFormat()
        let total: Int
        if format == .pdf {
            total = manager.pageImageCount(for: bookID)
        } else {
            total = manager.getPageCache(for: bookID)?.totalPages ?? 1
        }

        position.percentage = total > 1 ? Double(position.pageIndex) / Double(total - 1) : 0
        position.updatedAt = Date()
        manager.saveReadingPosition(position)
        manager.resetScrollOnPageChange()

        return .result()
    }
}
