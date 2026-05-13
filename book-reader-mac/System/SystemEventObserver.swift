import AppKit
import Foundation

/// Subscribes to OS events that the app cares about. Foundation wires up
/// the minimum set; later plans add finer-grained handlers (occlusion,
/// reachability) as they need them.
@MainActor
final class SystemEventObserver {
    private var observers: [NSObjectProtocol] = []
    private let onWillSleep: () -> Void
    private let onDidWake: () -> Void
    private let onLowPowerModeChange: (Bool) -> Void

    init(onWillSleep: @escaping () -> Void,
         onDidWake: @escaping () -> Void,
         onLowPowerModeChange: @escaping (Bool) -> Void) {
        self.onWillSleep = onWillSleep
        self.onDidWake = onDidWake
        self.onLowPowerModeChange = onLowPowerModeChange
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.onWillSleep() } })

        observers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.onDidWake() } })

        observers.append(NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onLowPowerModeChange(ProcessInfo.processInfo.isLowPowerModeEnabled)
            }
        })
    }

    func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
    }
}
