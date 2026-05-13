import SwiftUI

@main
struct InstantBookReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app has no SwiftUI WindowGroup. Wallpaper/reader/library windows
        // are managed by AppDelegate via AppKit so we can control NSWindow.level,
        // which SwiftUI cannot express.

        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image(systemName: "book.closed")
        }
        .menuBarExtraStyle(.menu)

        SettingsScene()
    }
}

/// Menu shown when the status item is clicked. Action methods are exposed
/// on `AppDelegate.shared`; `Settings…` uses `SettingsLink` so it goes
/// through the SwiftUI-recommended path.
private struct MenuBarContent: View {
    var body: some View {
        Button("Open Reader (⌃⌥B)") {
            AppDelegate.shared?.toggleReader()
        }
        Button("Next Quote") {
            AppDelegate.shared?.advanceAllQuotes()
        }
        Button("Toggle Wallpaper Mode") {
            AppDelegate.shared?.toggleAmbientMode()
        }

        Divider()

        Button("Open Library") {
            AppDelegate.shared?.showLibrary()
        }
        .keyboardShortcut("l")
        Button("Add Books…") {
            AppDelegate.shared?.presentAddBooksPanel()
        }
        .keyboardShortcut("o")

        Divider()

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Button("Check for Updates…") {
            UpdateController.shared.checkForUpdates(nil)
        }

        Divider()

        Button("Quit Instant Book Reader") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
