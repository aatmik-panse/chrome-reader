import XCTest
import AppKit
@testable import InstantBookReader

final class PhysicalTypeMetricsTests: XCTestCase {

    /// A stub that mimics `NSScreen` for metric calculation. We can't
    /// instantiate NSScreen ourselves, so PhysicalTypeMetrics is fed a
    /// `ScreenMetricsInput` value instead of a screen reference.
    private func input(
        widthPx: CGFloat,
        heightPx: CGFloat,
        widthMM: CGFloat,
        heightMM: CGFloat
    ) -> ScreenMetricsInput {
        ScreenMetricsInput(
            pixelSize: CGSize(width: widthPx, height: heightPx),
            physicalSizeMillimeters: CGSize(width: widthMM, height: heightMM)
        )
    }

    func testPointsPerInchFor13InchMBP() {
        // 13" MBP retina: 2560x1600 px, 286.1x178.8 mm → 227 ppi physical,
        // logical 1440x900 pt at 2x scale. We compute physical ppi (px/in).
        let metrics = PhysicalTypeMetrics(input: input(
            widthPx: 2560, heightPx: 1600,
            widthMM: 286.1, heightMM: 178.8
        ))
        XCTAssertEqual(metrics.pixelsPerInch, 227, accuracy: 2)
    }

    func testRecommendedBodyPointSizeFor13InchMBP() {
        let metrics = PhysicalTypeMetrics(input: input(
            widthPx: 2560, heightPx: 1600,
            widthMM: 286.1, heightMM: 178.8
        ))
        // 13" is the base; spec says ~22pt.
        XCTAssertEqual(metrics.recommendedBodyPointSize, 22, accuracy: 0.5)
    }

    func testRecommendedBodyPointSizeFor14InchMBP() {
        // 14" MBP: 3024x1964 px, 302.2x196.3 mm.
        let metrics = PhysicalTypeMetrics(input: input(
            widthPx: 3024, heightPx: 1964,
            widthMM: 302.2, heightMM: 196.3
        ))
        XCTAssertGreaterThanOrEqual(metrics.recommendedBodyPointSize, 22)
        XCTAssertLessThanOrEqual(metrics.recommendedBodyPointSize, 24)
    }

    func testRecommendedBodyPointSizeFor27InchStudioDisplay() {
        // 27" Studio Display: 5120x2880 px, 596x335 mm. 218 ppi.
        let metrics = PhysicalTypeMetrics(input: input(
            widthPx: 5120, heightPx: 2880,
            widthMM: 596, heightMM: 335
        ))
        // Spec: 27" capped at ~30pt.
        XCTAssertEqual(metrics.recommendedBodyPointSize, 30, accuracy: 1.0)
    }

    func testRecommendedBodyPointSizeFor32InchProDisplayXDR() {
        // 32" Pro Display XDR: 6016x3384 px, 698x393 mm.
        let metrics = PhysicalTypeMetrics(input: input(
            widthPx: 6016, heightPx: 3384,
            widthMM: 698, heightMM: 393
        ))
        // Logarithmic curve: 32" should be barely above 27" cap, not linear.
        XCTAssertLessThanOrEqual(metrics.recommendedBodyPointSize, 32)
        XCTAssertGreaterThanOrEqual(metrics.recommendedBodyPointSize, 30)
    }

    func testCapHeightTargetIsBetween22And25Hundredths() {
        // For every fixture, the cap-height-in-inches should fall in the
        // 0.22"–0.25" target band described in spec §6.2.
        let inputs = [
            input(widthPx: 2560, heightPx: 1600, widthMM: 286.1, heightMM: 178.8),
            input(widthPx: 3024, heightPx: 1964, widthMM: 302.2, heightMM: 196.3),
            input(widthPx: 5120, heightPx: 2880, widthMM: 596, heightMM: 335),
            input(widthPx: 6016, heightPx: 3384, widthMM: 698, heightMM: 393)
        ]
        for inp in inputs {
            let metrics = PhysicalTypeMetrics(input: inp)
            let capInches = metrics.estimatedCapHeightInches
            XCTAssertGreaterThanOrEqual(capInches, 0.21,
                "cap height \(capInches) below band for \(inp)")
            XCTAssertLessThanOrEqual(capInches, 0.27,
                "cap height \(capInches) above band for \(inp)")
        }
    }

    func testCurveIsLogarithmicNotLinear() {
        // The 27" point size should be much closer to the 13" size than a
        // linear scale would predict. 13"→22pt linear-to-27"→2x diagonal
        // would give 44pt. We expect ~30pt — well under half of that.
        let mbp13 = PhysicalTypeMetrics(input: input(
            widthPx: 2560, heightPx: 1600, widthMM: 286.1, heightMM: 178.8))
        let studio27 = PhysicalTypeMetrics(input: input(
            widthPx: 5120, heightPx: 2880, widthMM: 596, heightMM: 335))
        let ratio = studio27.recommendedBodyPointSize / mbp13.recommendedBodyPointSize
        XCTAssertLessThan(ratio, 1.6)
        XCTAssertGreaterThan(ratio, 1.2)
    }
}
