import SwiftData
import SwiftUI

/// Hosts the unified ten-tab Settings UI. Each tab is implemented in its
/// own file under Settings/Tabs/ and is rendered as a Form with grouped
/// style. Order matches §10 of the spec.
struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            AmbientTab()
                .tabItem { Label("Ambient", systemImage: "sparkles") }
            PageModeTab()
                .tabItem { Label("Page mode", systemImage: "doc.text") }
            ReadingTab()
                .tabItem { Label("Reading", systemImage: "text.book.closed") }
            LibraryTab()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            AITab()
                .tabItem { Label("AI", systemImage: "bolt.fill") }
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            PrivacyDataTab()
                .tabItem { Label("Privacy & Data", systemImage: "lock.shield") }
            AdvancedTab()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(minWidth: 640, minHeight: 480)
        .modelContainer(Self.sharedContainer())
    }

    private static func sharedContainer() -> ModelContainer {
        // Best-effort: try on-disk container, fall back to in-memory.
        if let c = try? PersistenceController.makeContainer() { return c }
        return try! PersistenceController.makeInMemoryContainer()
    }
}
