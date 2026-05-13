import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: ReadingState!
    private var modelContainer: ModelContainer!
    private var wallpaperCoordinator: WallpaperWindowCoordinator!
    private var readerController: ReaderWindowController!
    private var libraryController: LibraryWindowController!
    private var menuBar: MenuBarController!
    private var hotkey: GlobalHotkey!
    private var systemEvents: SystemEventObserver!
    private var advanceTrigger: AmbientAdvanceTrigger!
    private var reduceMotion: AmbientReduceMotion!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try AppSupportPaths.ensureCreated()
            modelContainer = try PersistenceController.makeContainer()
        } catch {
            NSApp.presentError(error)
            NSApp.terminate(nil)
            return
        }

        state = ReadingState()
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

        menuBar = MenuBarController(
            onToggleReader: { [weak self] in self?.readerController.toggle() },
            onToggleAmbientMode: { [weak self] in
                guard let self else { return }
                state.ambientMode = state.ambientMode == .atomic ? .page : .atomic
            },
            onNextQuote: { [weak self] in self?.wallpaperCoordinator.advanceAllQuotes() },
            onOpenLibrary: { [weak self] in self?.libraryController.show() },
            onAddBooks: { [weak self] in self?.libraryController.presentOpenPanel() },
            onOpenSettings: {
                if #available(macOS 14.0, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            },
            onQuit: { NSApp.terminate(nil) },
            onDropFiles: { [weak self] urls in self?.libraryController.importMany(urls) }
        )

        hotkey = GlobalHotkey(onToggle: { [weak self] in self?.readerController.toggle() })
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

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperCoordinator?.stop()
        systemEvents?.stop()
        reduceMotion?.stop()
        try? modelContainer?.mainContext.save()
    }
}
