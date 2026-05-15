import AppIntents
import WidgetKit

struct ZoomInIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Zoom In"
    nonisolated(unsafe) static var description = IntentDescription("Zoom into the page")

    func perform() async throws -> some IntentResult {
        AppGroupManager.shared.zoomIn()
        return .result()
    }
}
