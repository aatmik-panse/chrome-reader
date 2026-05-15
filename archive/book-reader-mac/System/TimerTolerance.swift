import Foundation

/// Energy discipline helper. Every recurring Timer in the app should
/// pass through `Timer.applyDefaultTolerance(_:)` to allow the system
/// to coalesce wakeups with other timers.
extension Timer {
    /// 10% tolerance per §12.1 of the spec.
    static func applyDefaultTolerance(_ timer: Timer) {
        timer.tolerance = timer.timeInterval * 0.1
    }
}
