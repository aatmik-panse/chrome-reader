import AppKit

/// Policy object: when Finder activates, fade target alpha to 0.15; when it
/// deactivates, restore to 1.0. The actual animation is delegated to a closure
/// so tests can drive it without an NSWindow.
@MainActor
final class FinderFrontmostFader {
    private static let finderBundleID = "com.apple.finder"

    private let isReducedMotion: () -> Bool
    private let apply: (CGFloat, TimeInterval) -> Void
    private var workspaceObservers: [NSObjectProtocol] = []

    /// - Parameters:
    ///   - isReducedMotion: closure returning the current Reduce Motion state.
    ///   - apply: closure that animates content alpha → target over duration.
    init(isReducedMotion: @escaping () -> Bool,
         apply: @escaping (CGFloat, TimeInterval) -> Void) {
        self.isReducedMotion = isReducedMotion
        self.apply = apply
    }

    /// Subscribe to `NSWorkspace` activation events. Call once per fader.
    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        let activated = workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            Task { @MainActor in
                self.handleActivation(bundleIdentifier: app.bundleIdentifier)
            }
        }
        let deactivated = workspace.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            Task { @MainActor in
                self.handleDeactivation(bundleIdentifier: app.bundleIdentifier)
            }
        }
        workspaceObservers = [activated, deactivated]
    }

    /// Stop receiving events.
    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers { center.removeObserver(obs) }
        workspaceObservers.removeAll()
    }

    /// Internal entry point used by the notification handler and by tests.
    func handleActivation(bundleIdentifier: String?) {
        guard bundleIdentifier == Self.finderBundleID else { return }
        let duration = isReducedMotion()
            ? AmbientLayoutMetrics.reducedMotionBlinkDuration
            : AmbientLayoutMetrics.finderFadeDuration
        apply(AmbientLayoutMetrics.finderFadeAlpha, duration)
    }

    func handleDeactivation(bundleIdentifier: String?) {
        guard bundleIdentifier == Self.finderBundleID else { return }
        let duration = isReducedMotion()
            ? AmbientLayoutMetrics.reducedMotionBlinkDuration
            : AmbientLayoutMetrics.finderFadeDuration
        apply(AmbientLayoutMetrics.finderRestoreAlpha, duration)
    }
}
