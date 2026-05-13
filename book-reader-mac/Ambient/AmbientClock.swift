import Foundation

/// Abstracts time for the rotation controller so tests can fire timers
/// without `Thread.sleep`. Production uses `SystemAmbientClock`; tests use
/// `FakeAmbientClock`.
protocol AmbientClock: AnyObject {
    /// Schedule `block` to run after `seconds`. Returns an opaque handle the
    /// caller can use to cancel. Implementations must execute `block` on the
    /// main actor.
    func schedule(after seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) -> AmbientTimerHandle
}

/// Opaque cancellation handle. Implementations decide what backs it.
final class AmbientTimerHandle {
    private let cancelBlock: () -> Void
    private var cancelled = false

    init(cancel: @escaping () -> Void) { self.cancelBlock = cancel }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        cancelBlock()
    }
}

/// Production clock backed by `DispatchSourceTimer` on the main queue.
final class SystemAmbientClock: AmbientClock {
    func schedule(after seconds: TimeInterval,
                  _ block: @escaping @MainActor () -> Void) -> AmbientTimerHandle {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + seconds,
                       leeway: .milliseconds(Int(seconds * 100))) // 10% tolerance
        timer.setEventHandler {
            Task { @MainActor in block() }
        }
        timer.resume()
        return AmbientTimerHandle { timer.cancel() }
    }
}
