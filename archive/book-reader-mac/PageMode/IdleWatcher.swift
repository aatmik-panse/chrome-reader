import Foundation
import AppKit
import CoreGraphics

/// Injectable provider of "seconds since last input event". Real
/// implementation wraps `CGEventSource.secondsSinceLastEventType`; tests
/// supply a stub.
public protocol IdleTimeProviding: AnyObject {
    func currentIdleSeconds() -> TimeInterval
}

/// Production provider — combined session-state, all event types.
public final class CombinedSessionIdleProvider: IdleTimeProviding {
    public init() {}
    public func currentIdleSeconds() -> TimeInterval {
        // `kCGAnyInputEventType` is conventionally represented as UInt32.max.
        let anyEvent = CGEventType(rawValue: ~0) ?? .mouseMoved
        return CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyEvent
        )
    }
}

/// Polls an `IdleTimeProviding` on a fixed cadence and emits `onIdle` /
/// `onWake` edge-transition callbacks.
///
/// Spec §6.6: 10 minutes idle → crossfade to ambient cover+quote. Mouse-move
/// → crossfade back. This class fires the edge events only; the caller
/// owns the animation.
@MainActor
public final class IdleWatcher {

    private let idleThreshold: TimeInterval
    private let tickInterval: TimeInterval
    private let idleProvider: IdleTimeProviding
    private let onIdle: () -> Void
    private let onWake: () -> Void

    private var timer: Timer?
    private var isIdle: Bool = false

    public init(
        idleThreshold: TimeInterval = 600,
        tickInterval: TimeInterval = 10,
        idleProvider: IdleTimeProviding = CombinedSessionIdleProvider(),
        onIdle: @escaping () -> Void,
        onWake: @escaping () -> Void
    ) {
        self.idleThreshold = idleThreshold
        self.tickInterval = tickInterval
        self.idleProvider = idleProvider
        self.onIdle = onIdle
        self.onWake = onWake
    }

    public func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = tickInterval * 0.1
        // Fire one tick immediately so tests don't have to wait for the
        // first scheduled fire.
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let idle = idleProvider.currentIdleSeconds()
        let shouldBeIdle = idle >= idleThreshold
        guard shouldBeIdle != isIdle else { return }
        isIdle = shouldBeIdle
        if shouldBeIdle { onIdle() } else { onWake() }
    }
}
