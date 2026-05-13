import AppIntents

struct NextQuoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Quote"
    static var description = IntentDescription("Show the next quote on the wallpaper layer.")

    @MainActor
    func perform() async throws -> some IntentResult {
        // Plan 5 holds AmbientRotationController per-screen on the wallpaper
        // coordinator. AppDelegate exposes a thin process-wide forwarder that
        // advances every screen at once; this matches the menu-bar
        // "Next Quote" command and stays a no-op when AppDelegate is absent
        // (e.g. inside unit tests, where the delegate never bootstraps).
        AppDelegate.shared?.advanceAllQuotes()
        return .result()
    }
}
