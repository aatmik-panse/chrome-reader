import AppKit
import Observation

/// Observes `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`
/// and republishes the current `accessibilityDisplayShouldReduceMotion` value.
@MainActor
@Observable
final class AmbientReduceMotion {
    var isEnabled: Bool

    private var observer: NSObjectProtocol?

    init() {
        self.isEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }
}
