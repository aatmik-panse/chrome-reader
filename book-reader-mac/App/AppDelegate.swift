import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: ReadingState!
    private var modelContainer: ModelContainer!
    private var wallpaperCoordinator: WallpaperWindowCoordinator!
    private var readerController: ReaderWindowController!
    private var menuBar: MenuBarController!
    private var hotkey: GlobalHotkey!
    private var systemEvents: SystemEventObserver!

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

        wallpaperCoordinator = WallpaperWindowCoordinator(
            state: state, modelContainer: modelContainer, theme: theme)
        readerController = ReaderWindowController(
            state: state, modelContainer: modelContainer, theme: theme)

        menuBar = MenuBarController(
            onToggleReader: { [weak self] in self?.readerController.toggle() },
            onToggleAmbientMode: { [weak self] in
                guard let self else { return }
                state.ambientMode = state.ambientMode == .atomic ? .page : .atomic
            },
            onOpenSettings: {
                if #available(macOS 14.0, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            },
            onQuit: { NSApp.terminate(nil) }
        )

        hotkey = GlobalHotkey(onToggle: { [weak self] in self?.readerController.toggle() })
        hotkey.register()

        systemEvents = SystemEventObserver(
            onWillSleep: { [weak self] in
                try? self?.modelContainer.mainContext.save()
            },
            onDidWake: { [weak self] in
                // Wallpaper coordinator handles its own reconcile on screen-param
                // changes; the wake observer here is reserved for later plans.
                _ = self
            },
            onLowPowerModeChange: { _ in
                // Reserved for energy policy in later plans.
            }
        )
        systemEvents.start()

        wallpaperCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperCoordinator?.stop()
        systemEvents?.stop()
        try? modelContainer?.mainContext.save()
    }
}
