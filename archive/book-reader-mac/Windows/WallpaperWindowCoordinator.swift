import AppKit
import SwiftData
import SwiftUI

/// Owns one AmbientScreenInstance per NSScreen. Hosts the real
/// AmbientHostView (Plan 5 atomic mode). The .page branch is filled in
/// by Plan 6; this coordinator hosts an empty view there so the wallpaper
/// window stays alive without crashing.
@MainActor
final class WallpaperWindowCoordinator {
    private var instances: [String: AmbientScreenInstance] = [:]
    private let state: ReadingState
    private let modelContainer: ModelContainer
    private let theme: AppTheme
    private let advanceTrigger: AmbientAdvanceTrigger
    private let reduceMotion: AmbientReduceMotion
    private var observer: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?
    private var finderActivationObserver: NSObjectProtocol?

    init(state: ReadingState,
         modelContainer: ModelContainer,
         theme: AppTheme,
         advanceTrigger: AmbientAdvanceTrigger,
         reduceMotion: AmbientReduceMotion) {
        self.state = state
        self.modelContainer = modelContainer
        self.theme = theme
        self.advanceTrigger = advanceTrigger
        self.reduceMotion = reduceMotion
    }

    func start() {
        reconcile()

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }

        screenWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.advanceTrigger.fireAll() }
        }

        finderActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == "com.apple.finder"
            else { return }
            Task { @MainActor in
                self.fireFinderActivation()
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let screenWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(screenWakeObserver)
        }
        screenWakeObserver = nil
        if let finderActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(finderActivationObserver)
        }
        finderActivationObserver = nil

        for instance in instances.values { instance.hide() }
        instances.removeAll()
    }

    /// Public hook bound to the menu-bar "Next Quote" command.
    func advanceAllQuotes() {
        advanceTrigger.fireAll()
    }

    // MARK: - Reconciliation

    private func reconcile() {
        let currentScreens = NSScreen.screens
        let currentKeys = Set(currentScreens.map(Self.key(for:)))

        for key in Array(instances.keys) where !currentKeys.contains(key) {
            instances[key]?.hide()
            instances.removeValue(forKey: key)
        }

        for (index, screen) in currentScreens.enumerated() {
            let key = Self.key(for: screen)
            if instances[key] == nil {
                let seed = Self.seed(for: screen, index: index)
                let rootView = AnyView(
                    WallpaperRootView(
                        screen: screen,
                        shuffleSeed: seed,
                        advanceTrigger: advanceTrigger
                    )
                    .environment(\.appTheme, theme)
                    .environment(state)
                    .modelContainer(modelContainer)
                )
                let instance = AmbientScreenInstance(
                    screen: screen,
                    reduceMotion: reduceMotion,
                    rootView: rootView
                )
                instance.show()
                instances[key] = instance
            } else {
                instances[key]?.relayout(to: screen)
            }
        }
    }

    /// Per-screen path for the Finder-activation 800ms delay. Because the
    /// rotation controller lives inside AmbientHostView, we route through the
    /// shared trigger using a dedicated callback list.
    private func fireFinderActivation() {
        // Spec §5.3: "Advance after 800ms (only if cursor not in safe zone)".
        // The controller already encodes both — we just need to ask it.
        advanceTrigger.fireAllFinderActivations()
    }

    private static func key(for screen: NSScreen) -> String {
        "\(screen.localizedName)|\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }

    /// Stable per-screen seed so multi-monitor setups get distinct shuffles
    /// without re-randomising on every reconcile.
    private static func seed(for screen: NSScreen, index: Int) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(screen.localizedName)
        hasher.combine(index)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
}
