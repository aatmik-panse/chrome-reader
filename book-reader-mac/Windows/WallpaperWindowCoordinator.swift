import AppKit
import SwiftUI
import SwiftData

/// Owns one WallpaperWindow per NSScreen. Reconciles on screen-parameter
/// changes (hotplug, resolution, mirroring) and on display reconfiguration.
/// Windows are keyed by NSScreen `localizedName` + frame, not array index.
@MainActor
final class WallpaperWindowCoordinator {
    private var windows: [String: WallpaperWindow] = [:]
    private let state: ReadingState
    private let modelContainer: ModelContainer
    private let theme: AppTheme
    private var observer: NSObjectProtocol?

    init(state: ReadingState, modelContainer: ModelContainer, theme: AppTheme) {
        self.state = state
        self.modelContainer = modelContainer
        self.theme = theme
    }

    func start() {
        reconcile()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }

    private func reconcile() {
        let currentScreens = NSScreen.screens
        let currentKeys = Set(currentScreens.map(Self.key(for:)))

        // Tear down windows whose screens vanished.
        for key in Array(windows.keys) where !currentKeys.contains(key) {
            windows[key]?.orderOut(nil)
            windows.removeValue(forKey: key)
        }

        // Create windows for new screens.
        for screen in currentScreens {
            let key = Self.key(for: screen)
            if windows[key] == nil {
                let window = WallpaperWindow(screen: screen)
                let content = PlaceholderAmbientView(screenName: screen.localizedName)
                    .environment(\.appTheme, theme)
                    .environment(state)
                    .modelContainer(modelContainer)
                window.contentView = NSHostingView(rootView: content)
                window.setFrame(screen.frame, display: true)
                window.orderFront(nil)
                windows[key] = window
            } else if let window = windows[key] {
                window.setFrame(screen.frame, display: true)
            }
        }
    }

    private static func key(for screen: NSScreen) -> String {
        "\(screen.localizedName)|\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }
}
