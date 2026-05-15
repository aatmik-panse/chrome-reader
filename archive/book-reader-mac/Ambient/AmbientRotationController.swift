import Foundation

/// Reasons the controller advances to the next quote. Used by tests + logs.
enum AmbientAdvanceReason {
    case startup
    case timer
    case screenWake
    case finderFrontmost
    case menuCommand
}

/// Owns a per-screen rotation loop. Triggers:
///   - timer fire (`rotationSeconds`)
///   - `advanceNow(reason: .screenWake)` from NSWorkspace screen-wake
///   - `handleFinderActivation()` from NSWorkspace activation events
///   - `advanceNow(reason: .menuCommand)` from the menu-bar command
///
/// Pauses while the cursor is in the safe zone (driven by `SafeZoneTracker`).
/// Resumes 5s after the cursor leaves.
///
/// All public methods are @MainActor.
@MainActor
final class AmbientRotationController {
    private let selector: AmbientHighlightSelector
    private let clock: AmbientClock
    private(set) var rotationSeconds: TimeInterval
    private let onAdvance: (Highlight?) -> Void

    private var timerHandle: AmbientTimerHandle?
    private var pendingFinderHandle: AmbientTimerHandle?
    private var safeZoneResumeHandle: AmbientTimerHandle?
    private var isRunning = false
    private var isPaused = false

    init(selector: AmbientHighlightSelector,
         clock: AmbientClock,
         rotationSeconds: TimeInterval,
         onAdvance: @escaping (Highlight?) -> Void) {
        self.selector = selector
        self.clock = clock
        self.rotationSeconds = max(AmbientLayoutMetrics.rotationMin,
                                    min(AmbientLayoutMetrics.rotationMax, rotationSeconds))
        self.onAdvance = onAdvance
    }

    /// Publishes the first quote immediately and starts the rotation timer.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        publishNext(reason: .startup)
        scheduleTimer()
    }

    /// Cancels every pending callback.
    func stop() {
        isRunning = false
        cancelTimer()
        pendingFinderHandle?.cancel()
        pendingFinderHandle = nil
        safeZoneResumeHandle?.cancel()
        safeZoneResumeHandle = nil
    }

    /// Updates the rotation cadence at runtime (e.g. from the Settings tab).
    /// Reschedules the running timer if active.
    func updateRotationSeconds(_ seconds: TimeInterval) {
        rotationSeconds = max(AmbientLayoutMetrics.rotationMin,
                              min(AmbientLayoutMetrics.rotationMax, seconds))
        if isRunning, !isPaused {
            scheduleTimer()
        }
    }

    /// Advance immediately for an explicit trigger (screen wake, menu command,
    /// or — internally — timer fire). Always publishes, even while paused, so
    /// a user-driven "Next quote" command works from a paused screen.
    func advanceNow(reason: AmbientAdvanceReason) {
        guard isRunning else { return }
        publishNext(reason: reason)
        if !isPaused { scheduleTimer() }
    }

    /// Schedule a Finder-activation-triggered advance. Per spec: 800ms delay,
    /// suppressed if cursor is in the safe zone at fire time.
    func handleFinderActivation() {
        guard isRunning else { return }
        pendingFinderHandle?.cancel()
        pendingFinderHandle = clock.schedule(
            after: AmbientLayoutMetrics.finderActivationDelay
        ) { [weak self] in
            guard let self else { return }
            self.pendingFinderHandle = nil
            guard !self.isPaused else { return }
            self.advanceNow(reason: .finderFrontmost)
        }
    }

    /// Pause (cursor entered safe zone) or resume (cursor left, after 5s grace).
    func setSafeZoneOccupied(_ occupied: Bool) {
        guard isRunning else { return }
        if occupied {
            isPaused = true
            cancelTimer()
            safeZoneResumeHandle?.cancel()
            safeZoneResumeHandle = nil
        } else {
            safeZoneResumeHandle?.cancel()
            safeZoneResumeHandle = clock.schedule(
                after: AmbientLayoutMetrics.safeZoneResumeDelay
            ) { [weak self] in
                guard let self else { return }
                self.safeZoneResumeHandle = nil
                self.isPaused = false
                self.advanceNow(reason: .timer)
            }
        }
    }

    private func scheduleTimer() {
        cancelTimer()
        timerHandle = clock.schedule(after: rotationSeconds) { [weak self] in
            guard let self else { return }
            self.timerHandle = nil
            self.advanceNow(reason: .timer)
        }
    }

    private func cancelTimer() {
        timerHandle?.cancel()
        timerHandle = nil
    }

    private func publishNext(reason: AmbientAdvanceReason) {
        _ = reason  // hook reserved for future logging; required by API for callers
        onAdvance(selector.next())
    }
}
