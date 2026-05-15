import AppIntents

/// Registers all intents so they appear in Shortcuts, Spotlight, and Siri.
/// Phrase strings include "${applicationName}" so the app name resolves
/// from Info.plist at runtime.
struct InstantBookReaderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenBookIntent(),
            phrases: ["Open \(.applicationName) book \(\.$book)"],
            shortTitle: "Open Book",
            systemImageName: "book"
        )
        AppShortcut(
            intent: ToggleWallpaperModeIntent(),
            phrases: ["Toggle \(.applicationName) wallpaper mode"],
            shortTitle: "Toggle Wallpaper Mode",
            systemImageName: "rectangle.on.rectangle"
        )
        AppShortcut(
            intent: NextPageIntent(),
            phrases: ["\(.applicationName) next page"],
            shortTitle: "Next Page",
            systemImageName: "arrow.right"
        )
        AppShortcut(
            intent: PreviousPageIntent(),
            phrases: ["\(.applicationName) previous page"],
            shortTitle: "Previous Page",
            systemImageName: "arrow.left"
        )
        AppShortcut(
            intent: NextQuoteIntent(),
            phrases: ["\(.applicationName) next quote"],
            shortTitle: "Next Quote",
            systemImageName: "quote.bubble"
        )
    }
}
