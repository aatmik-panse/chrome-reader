import XCTest
@testable import InstantBookReader

@MainActor
final class FakeAmbientClock: AmbientClock {
    struct Scheduled {
        let id: UUID
        let fireAt: TimeInterval
        let block: @MainActor () -> Void
    }

    private(set) var now: TimeInterval = 0
    private var pending: [Scheduled] = []

    func schedule(after seconds: TimeInterval,
                  _ block: @escaping @MainActor () -> Void) -> AmbientTimerHandle {
        let id = UUID()
        let entry = Scheduled(id: id, fireAt: now + seconds, block: block)
        pending.append(entry)
        return AmbientTimerHandle { [weak self] in
            self?.pending.removeAll { $0.id == id }
        }
    }

    /// Advances virtual time, firing every scheduled block whose deadline is
    /// reached. Removes fired blocks; remaining ones may have been rescheduled
    /// during their handler.
    func advance(by seconds: TimeInterval) {
        // Add a tiny epsilon to absorb floating-point drift so that callers
        // can advance the clock in fractional increments without missing fires.
        let epsilon: TimeInterval = 1e-9
        let target = now + seconds
        while let next = pending.filter({ $0.fireAt <= target + epsilon })
                .min(by: { $0.fireAt < $1.fireAt }) {
            pending.removeAll { $0.id == next.id }
            now = next.fireAt
            next.block()
        }
        now = target
    }

    var pendingCount: Int { pending.count }
}

@MainActor
final class AmbientRotationControllerTests: XCTestCase {
    private func makePool(_ count: Int) -> [Highlight] {
        (0..<count).map {
            Highlight(bookHash: "h",
                      text: "h\($0)",
                      surroundingText: "h\($0)",
                      offset: 0)
        }
    }

    func testTimerFireAdvancesQuote() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()

        XCTAssertEqual(observed.count, 1, "start() publishes the first quote immediately")
        clock.advance(by: 90)
        XCTAssertEqual(observed.count, 2)
        clock.advance(by: 90)
        XCTAssertEqual(observed.count, 3)
    }

    func testMenuCommandAdvancesImmediately() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()
        XCTAssertEqual(observed.count, 1)

        controller.advanceNow(reason: .menuCommand)
        XCTAssertEqual(observed.count, 2)
    }

    func testScreenWakeAdvancesImmediately() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()
        let before = observed.count

        controller.advanceNow(reason: .screenWake)
        XCTAssertEqual(observed.count, before + 1)
    }

    func testFinderActivationAdvancesAfter800ms() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()
        let before = observed.count

        controller.handleFinderActivation()
        clock.advance(by: 0.7)
        XCTAssertEqual(observed.count, before, "not yet — only 700ms elapsed")
        clock.advance(by: 0.1)
        XCTAssertEqual(observed.count, before + 1, "fires at 800ms")
    }

    func testFinderActivationSkippedWhileCursorInSafeZone() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()
        let before = observed.count

        controller.setSafeZoneOccupied(true)
        controller.handleFinderActivation()
        clock.advance(by: 1.0)
        XCTAssertEqual(observed.count, before, "no advance while in safe zone")
    }

    func testSafeZoneEntryPausesTimer() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()
        let before = observed.count

        controller.setSafeZoneOccupied(true)
        clock.advance(by: 200)
        XCTAssertEqual(observed.count, before, "timer paused while occupied")
    }

    func testSafeZoneExitResumesAfter5Seconds() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()
        controller.setSafeZoneOccupied(true)
        clock.advance(by: 30)
        let before = observed.count

        controller.setSafeZoneOccupied(false)
        clock.advance(by: 4.9)
        XCTAssertEqual(observed.count, before, "5s resume delay not elapsed")
        clock.advance(by: 0.2)
        XCTAssertEqual(observed.count, before + 1, "advance fires once resume delay completes")
    }

    func testEmptyPoolStillStartsButPublishesNil() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: [], seed: 1)
        var observed: [Highlight?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0) }
        )
        controller.start()
        XCTAssertEqual(observed.count, 1)
        XCTAssertNil(observed[0])
        clock.advance(by: 90)
        XCTAssertEqual(observed.count, 2)
        XCTAssertNil(observed[1])
    }

    func testStopCancelsPendingTimer() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [Highlight?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0) }
        )
        controller.start()
        let before = observed.count
        controller.stop()
        clock.advance(by: 1000)
        XCTAssertEqual(observed.count, before, "no advance after stop")
    }
}
