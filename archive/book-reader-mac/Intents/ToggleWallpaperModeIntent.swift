import AppIntents

struct ToggleWallpaperModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Wallpaper Mode"
    static var description = IntentDescription("Switch between ambient and page wallpaper modes.")

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let state = AppDelegate.shared?.state else { return .result() }
        state.ambientMode = (state.ambientMode == .atomic) ? .page : .atomic
        return .result()
    }
}
