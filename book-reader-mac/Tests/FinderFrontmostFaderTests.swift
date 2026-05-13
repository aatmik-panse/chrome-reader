import XCTest
@testable import InstantBookReader

@MainActor
final class FinderFrontmostFaderTests: XCTestCase {
    func testActivatingFinderTriggersFadeOut() {
        var applied: [CGFloat] = []
        let fader = FinderFrontmostFader(
            isReducedMotion: { false },
            apply: { alpha, _ in applied.append(alpha) }
        )
        fader.handleActivation(bundleIdentifier: "com.apple.finder")
        XCTAssertEqual(applied.last, AmbientLayoutMetrics.finderFadeAlpha)
    }

    func testActivatingNonFinderDoesNothing() {
        var applied: [CGFloat] = []
        let fader = FinderFrontmostFader(
            isReducedMotion: { false },
            apply: { alpha, _ in applied.append(alpha) }
        )
        fader.handleActivation(bundleIdentifier: "com.google.Chrome")
        XCTAssertTrue(applied.isEmpty)
    }

    func testDeactivatingFinderRestoresAlpha() {
        var applied: [CGFloat] = []
        let fader = FinderFrontmostFader(
            isReducedMotion: { false },
            apply: { alpha, _ in applied.append(alpha) }
        )
        fader.handleActivation(bundleIdentifier: "com.apple.finder")
        fader.handleDeactivation(bundleIdentifier: "com.apple.finder")
        XCTAssertEqual(applied.last, AmbientLayoutMetrics.finderRestoreAlpha)
    }

    func testDeactivatingNonFinderDoesNothing() {
        var applied: [CGFloat] = []
        let fader = FinderFrontmostFader(
            isReducedMotion: { false },
            apply: { alpha, _ in applied.append(alpha) }
        )
        fader.handleDeactivation(bundleIdentifier: "com.google.Chrome")
        XCTAssertTrue(applied.isEmpty)
    }

    func testReducedMotionUsesShortDuration() {
        var applied: [(CGFloat, TimeInterval)] = []
        let fader = FinderFrontmostFader(
            isReducedMotion: { true },
            apply: { alpha, duration in applied.append((alpha, duration)) }
        )
        fader.handleActivation(bundleIdentifier: "com.apple.finder")
        XCTAssertEqual(applied.last?.1, AmbientLayoutMetrics.reducedMotionBlinkDuration)
    }

    func testNormalMotionUses400msDuration() {
        var applied: [(CGFloat, TimeInterval)] = []
        let fader = FinderFrontmostFader(
            isReducedMotion: { false },
            apply: { alpha, duration in applied.append((alpha, duration)) }
        )
        fader.handleActivation(bundleIdentifier: "com.apple.finder")
        XCTAssertEqual(applied.last?.1, AmbientLayoutMetrics.finderFadeDuration)
    }
}
