import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryWindowController {
    private let window: LibraryWindow
    private let state: ReadingState
    private let modelContainer: ModelContainer
    private let theme: AppTheme

    init(state: ReadingState, modelContainer: ModelContainer, theme: AppTheme) {
        self.state = state
        self.modelContainer = modelContainer
        self.theme = theme
        self.window = LibraryWindow()

        let root = LibraryView(onAddBooks: { [weak self] in self?.presentOpenPanel() })
            .environment(\.appTheme, theme)
            .environment(state)
            .modelContainer(modelContainer)
        window.contentView = NSHostingView(rootView: root)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Opens an NSOpenPanel filtered to EPUB/PDF/TXT and imports each pick.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = BookFileExtension.supportedContentTypes
        panel.prompt = "Add to Library"
        panel.message = "Select EPUB, PDF, or TXT files to add"

        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            Task { @MainActor in
                self.importMany(panel.urls)
            }
        }
    }

    /// Public hook used by AppDelegate (Open With) and the menu bar drop target.
    func importMany(_ urls: [URL]) {
        let importer = BookImporter()
        let context = ModelContext(modelContainer)
        for url in urls {
            do {
                _ = try importer.importBook(from: url, into: context)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        try? context.save()
        show()
    }
}
