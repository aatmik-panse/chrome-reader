import AppIntents
import WidgetKit

struct ZoomOutIntent: AppIntent {
    nonisolated(unsafe) static var title: LocalizedStringResource = "Zoom Out"
    nonisolated(unsafe) static var description = IntentDescription("Zoom out of the page")

    func perform() async throws -> some IntentResult {
        AppGroupManager.shared.zoomOut()
        return .result()
    }
}
