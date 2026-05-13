import AppKit

/// Owns the NSStatusItem. Menu items wire to closures supplied by AppDelegate.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let onToggleReader: () -> Void
    private let onToggleAmbientMode: () -> Void
    private let onOpenLibrary: () -> Void
    private let onAddBooks: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    init(onToggleReader: @escaping () -> Void,
         onToggleAmbientMode: @escaping () -> Void,
         onOpenLibrary: @escaping () -> Void,
         onAddBooks: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void,
         onDropFiles: @escaping ([URL]) -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onToggleReader = onToggleReader
        self.onToggleAmbientMode = onToggleAmbientMode
        self.onOpenLibrary = onOpenLibrary
        self.onAddBooks = onAddBooks
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        configure()
        statusItem.installDropTarget(onDrop: onDropFiles)
    }

    private func configure() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "book.closed",
                                   accessibilityDescription: "Instant Book Reader")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(makeItem(title: "Open Reader (⌃⌥B)",
                              action: #selector(toggleReaderClicked),
                              keyEquivalent: ""))
        menu.addItem(makeItem(title: "Toggle Wallpaper Mode",
                              action: #selector(toggleAmbientClicked),
                              keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Open Library",
                              action: #selector(openLibraryClicked),
                              keyEquivalent: "l"))
        menu.addItem(makeItem(title: "Add Books…",
                              action: #selector(addBooksClicked),
                              keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Settings…",
                              action: #selector(openSettingsClicked),
                              keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit Instant Book Reader",
                              action: #selector(quitClicked),
                              keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func makeItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func toggleReaderClicked() { onToggleReader() }
    @objc private func toggleAmbientClicked() { onToggleAmbientMode() }
    @objc private func openLibraryClicked() { onOpenLibrary() }
    @objc private func addBooksClicked() { onAddBooks() }
    @objc private func openSettingsClicked() { onOpenSettings() }
    @objc private func quitClicked() { onQuit() }
}
