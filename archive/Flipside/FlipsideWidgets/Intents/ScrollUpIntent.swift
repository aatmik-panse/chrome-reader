import AppIntents
import WidgetKit

struct ScrollUpIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Scroll Up"
    nonisolated(unsafe) static var description = IntentDescription("Scroll up on the page")

    func perform() async throws -> some IntentResult {
        AppGroupManager.shared.scrollUp()
        return .result()
    }
}

struct ScrollLeftIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Scroll Left"
    nonisolated(unsafe) static var description = IntentDescription("Scroll left on the page")

    func perform() async throws -> some IntentResult {
        AppGroupManager.shared.scrollLeft()
        return .result()
    }
}
