import SwiftUI

@main
struct InstantBookReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app has no SwiftUI WindowGroup. All windows are managed by
        // AppDelegate via AppKit so we can control NSWindow.level, which
        // SwiftUI cannot express. The unified Settings scene is provided
        // by Plan 7's SettingsScene type.
        SettingsScene()
    }
}
