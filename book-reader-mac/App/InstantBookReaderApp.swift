import SwiftUI
import SwiftData

@main
struct InstantBookReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The app has no SwiftUI WindowGroup. All windows are managed by
        // AppDelegate via AppKit so we can control NSWindow.level, which
        // SwiftUI cannot express. The Settings scene is added in Plan 7.
        Settings {
            SettingsRootView()
        }
    }
}

private struct SettingsRootView: View {
    var body: some View {
        TabView {
            AISettingsTab()
                .tabItem { Label("AI", systemImage: "sparkles") }
        }
        .modelContainer(sharedContainer())
    }

    private func sharedContainer() -> ModelContainer {
        // Best-effort: try on-disk container, fall back to in-memory.
        if let c = try? PersistenceController.makeContainer() { return c }
        return try! PersistenceController.makeInMemoryContainer()
    }
}
