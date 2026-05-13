import XCTest
@testable import InstantBookReader

@MainActor
final class IdleWatcherTests: XCTestCase {

    final class StubIdleProvider: IdleTimeProviding {
        var idleSeconds: TimeInterval = 0
        func currentIdleSeconds() -> TimeInterval { idleSeconds }
    }

    func testEmitsIdleAfterTenMinutes() async {
        let stub = StubIdleProvider()
        var idleCount = 0
        var wakeCount = 0
        let watcher = IdleWatcher(
            idleThreshold: 600,
            tickInterval: 0.01,
            idleProvider: stub,
            onIdle: { idleCount += 1 },
            onWake: { wakeCount += 1 }
        )
        watcher.start()
        stub.idleSeconds = 599
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(idleCount, 0)

        stub.idleSeconds = 601
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(idleCount, 1)
        watcher.stop()
    }

    func testEmitsWakeWhenIdleDropsBelowThreshold() async {
        let stub = StubIdleProvider()
        var idleCount = 0
        var wakeCount = 0
        let watcher = IdleWatcher(
            idleThreshold: 600,
            tickInterval: 0.01,
            idleProvider: stub,
            onIdle: { idleCount += 1 },
            onWake: { wakeCount += 1 }
        )
        watcher.start()
        stub.idleSeconds = 601
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(idleCount, 1)
        XCTAssertEqual(wakeCount, 0)

        stub.idleSeconds = 0.1
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(wakeCount, 1)
        watcher.stop()
    }

    func testDoesNotEmitMultipleIdleEventsWhileStillIdle() async {
        let stub = StubIdleProvider()
        var idleCount = 0
        let watcher = IdleWatcher(
            idleThreshold: 600,
            tickInterval: 0.01,
            idleProvider: stub,
            onIdle: { idleCount += 1 },
            onWake: {}
        )
        watcher.start()
        stub.idleSeconds = 700
        try? await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(idleCount, 1)
        watcher.stop()
    }
}
