import AppIntents
import AppKit
import PDFKit
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set during `applicationDidFinishLaunching`. Read by App Intents.
    static private(set) weak var shared: AppDelegate?

    private(set) var state: ReadingState!
    private var modelContainer: ModelContainer!
    private var wallpaperCoordinator: WallpaperWindowCoordinator!
    private var readerController: ReaderWindowController!
    private var libraryController: LibraryWindowController!
    private var hotkey: GlobalHotkey!
    private var systemEvents: SystemEventObserver!
    private var advanceTrigger: AmbientAdvanceTrigger!
    private var reduceMotion: AmbientReduceMotion!
    private(set) var accessibilityFlags: AccessibilityFlags!
    private var accessibilityObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        do {
            try AppSupportPaths.ensureCreated()
            modelContainer = try PersistenceController.makeContainer()
        } catch {
            NSApp.presentError(error)
            NSApp.terminate(nil)
            return
        }

        // AI cache eviction on launch (LRU under 200 MB).
        Task { @MainActor in
            AICache(container: self.modelContainer).evict()
        }

        state = ReadingState()
        accessibilityFlags = AccessibilityFlags()
        let theme: AppTheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .clayDark : .clayLight

        advanceTrigger = AmbientAdvanceTrigger()
        reduceMotion = AmbientReduceMotion()
        reduceMotion.start()

        wallpaperCoordinator = WallpaperWindowCoordinator(
            state: state,
            modelContainer: modelContainer,
            theme: theme,
            advanceTrigger: advanceTrigger,
            reduceMotion: reduceMotion
        )
        readerController = ReaderWindowController(
            state: state, modelContainer: modelContainer, theme: theme)
        libraryController = LibraryWindowController(
            state: state, modelContainer: modelContainer, theme: theme)

        // Menu bar lives in SwiftUI as `MenuBarExtra` in InstantBookReaderApp.swift.
        // It calls the action methods exposed below via `AppDelegate.shared`.

        hotkey = GlobalHotkey(
            onToggleReader: { [weak self] in self?.readerController.toggle() },
            onPageNext: { [weak self] in self?.advancePageMode(.next) },
            onPagePrevious: { [weak self] in self?.advancePageMode(.previous) }
        )
        hotkey.register()

        systemEvents = SystemEventObserver(
            onWillSleep: { [weak self] in
                try? self?.modelContainer.mainContext.save()
            },
            onDidWake: {
                // Plan 5: handled by the coordinator's screensDidWakeNotification observer.
            },
            onLowPowerModeChange: { _ in
                // Reserved for energy policy in later plans.
            }
        )
        systemEvents.start()

        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.accessibilityFlags.refresh() }
        }

        wallpaperCoordinator.start()
    }

    /// Handles Finder "Open With → Instant Book Reader". The app is launched
    /// (or activated) with one or more file URLs; we route them through the
    /// importer and surface the library.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let libraryController else {
            // Launched specifically to open these files — defer until bootstrap completes.
            DispatchQueue.main.async { [weak self] in
                self?.application(application, open: urls)
            }
            return
        }
        libraryController.importMany(urls)
    }

    /// Called by `OpenBookIntent`. Resolves the book by hash, marks it
    /// current, and summons the active reader window.
    func openBook(withHash hash: String) {
        state.currentBookHash = hash
        UserDefaults.standard.set(hash, forKey: "currentBookHash")
        if let book = try? modelContainer.mainContext.fetch(
            FetchDescriptor<Book>(predicate: #Predicate { $0.sha256 == hash })
        ).first {
            book.lastOpenedAt = .now
            try? modelContainer.mainContext.save()
        }
        if !readerController.isVisible {
            readerController.toggle()
        }
    }

    /// Process-wide forwarder for the `NextQuoteIntent`. Mirrors the
    /// menu-bar "Next Quote" command by asking the wallpaper coordinator
    /// to advance every screen's rotation controller.
    func advanceAllQuotes() {
        wallpaperCoordinator?.advanceAllQuotes()
    }

    // MARK: - Menu bar actions

    func toggleReader() {
        readerController?.toggle()
    }

    func toggleAmbientMode() {
        state.ambientMode = state.ambientMode == .atomic ? .page : .atomic
    }

    func showLibrary() {
        libraryController?.show()
    }

    func presentAddBooksPanel() {
        libraryController?.presentOpenPanel()
    }

    @MainActor
    private func advancePageMode(_ direction: PageModeAdvance.Direction) {
        guard state.ambientMode == .page,
              let hash = state.currentBookHash else { return }
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.sha256 == hash })
        guard let book = try? context.fetch(descriptor).first else { return }
        let position: Position
        if let existing = book.position {
            position = existing
        } else {
            let p = Position(
                bookHash: hash,
                anchor: book.format == .pdf ? "1:0" : "0",
                percentage: 0,
                updatedAt: .now
            )
            context.insert(p)
            book.position = p
            position = p
        }

        let pdfPageCount: Int? = {
            guard book.format == .pdf else { return nil }
            let url = AppSupportPaths.books.appendingPathComponent(book.filePath)
            return PDFDocument(url: url)?.pageCount
        }()

        PageModeAdvance.advance(position: position,
                                format: book.format,
                                direction: direction,
                                pdfPageCount: pdfPageCount)
        try? context.save()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperCoordinator?.stop()
        systemEvents?.stop()
        reduceMotion?.stop()
        if let observer = accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        try? modelContainer?.mainContext.save()
    }
}
