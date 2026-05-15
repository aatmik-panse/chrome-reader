import AppIntents
import WidgetKit

struct ScrollDownIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Scroll Down"
    nonisolated(unsafe) static var description = IntentDescription("Scroll down on the page")

    func perform() async throws -> some IntentResult {
        AppGroupManager.shared.scrollDown()
        return .result()
    }
}

struct ScrollRightIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Scroll Right"
    nonisolated(unsafe) static var description = IntentDescription("Scroll right on the page")

    func perform() async throws -> some IntentResult {
        AppGroupManager.shared.scrollRight()
        return .result()
    }
}
