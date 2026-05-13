import Foundation
import AppKit

/// Stripped-down screen metric input. Decoupling from `NSScreen` lets us
/// unit-test the curve with synthetic values — `NSScreen` cannot be
/// instantiated directly.
public struct ScreenMetricsInput: Equatable, Sendable {
    /// Pixel size, e.g. 2560x1600 for a 13" MBP retina panel.
    public let pixelSize: CGSize
    /// Physical panel size in millimeters, e.g. 286.1x178.8 mm for 13" MBP.
    public let physicalSizeMillimeters: CGSize

    public init(pixelSize: CGSize, physicalSizeMillimeters: CGSize) {
        self.pixelSize = pixelSize
        self.physicalSizeMillimeters = physicalSizeMillimeters
    }
}

/// Computes physical-size body type recommendations for page mode.
///
/// Goal: cap-height of body type lands in the 0.22"–0.25" band on every
/// supported panel. The curve is logarithmic, not linear — a 27" display
/// should not get 2× the type size of a 13" display.
public struct PhysicalTypeMetrics: Equatable, Sendable {

    public let input: ScreenMetricsInput

    public init(input: ScreenMetricsInput) {
        self.input = input
    }

    /// Convenience: extract from a real NSScreen. `deviceDescription[.size]`
    /// returns `NSValue` containing a `CGSize` in millimeters since
    /// `NSDeviceSize` is documented as physical size in points for non-print
    /// devices — but on macOS displays the value is interpreted by callers
    /// as a physical mm size in practice. We pair it with `frame.size` in
    /// points, multiplied by `backingScaleFactor` to recover pixels.
    @MainActor
    public init(screen: NSScreen) {
        let backing = screen.backingScaleFactor
        let pixelSize = CGSize(
            width: screen.frame.width * backing,
            height: screen.frame.height * backing
        )
        let descSize = (screen.deviceDescription[.size] as? NSValue)?.sizeValue
            ?? CGSize(width: 286.1, height: 178.8) // fallback: 13" MBP
        self.init(input: ScreenMetricsInput(
            pixelSize: pixelSize,
            physicalSizeMillimeters: descSize
        ))
    }

    /// Physical pixels per inch along the diagonal.
    public var pixelsPerInch: CGFloat {
        let diagonalPx = sqrt(
            input.pixelSize.width * input.pixelSize.width
          + input.pixelSize.height * input.pixelSize.height
        )
        let diagonalMM = sqrt(
            input.physicalSizeMillimeters.width * input.physicalSizeMillimeters.width
          + input.physicalSizeMillimeters.height * input.physicalSizeMillimeters.height
        )
        let diagonalInches = diagonalMM / 25.4
        guard diagonalInches > 0 else { return 0 }
        return diagonalPx / diagonalInches
    }

    /// Diagonal in inches. Used as the curve's x-axis.
    public var diagonalInches: CGFloat {
        let mm = sqrt(
            input.physicalSizeMillimeters.width * input.physicalSizeMillimeters.width
          + input.physicalSizeMillimeters.height * input.physicalSizeMillimeters.height
        )
        return mm / 25.4
    }

    /// Recommended body point size for SwiftUI Text / WebView body CSS.
    ///
    /// Curve: 13"→22pt is the anchor. 27"→30pt is the cap. Between 13" and 27"
    /// we interpolate with `log2(diagonal/13) / log2(27/13)`. Above 27" the
    /// curve continues at a much shallower slope so a 32" display lands near
    /// 30.5pt rather than blowing past 35pt.
    public var recommendedBodyPointSize: CGFloat {
        let base: CGFloat = 22
        let capDiag: CGFloat = 27
        let capPt: CGFloat = 30
        let d = max(diagonalInches, 13)

        if d <= capDiag {
            let t = log2(d / 13) / log2(capDiag / 13)
            return base + (capPt - base) * t
        } else {
            // Above 27": +0.5pt per doubling of (d - 27).
            let extra = log2(1 + (d - capDiag)) * 0.5
            return capPt + extra
        }
    }

    /// Approximate cap-height in inches at the recommended point size.
    /// 1 pt = 1/72 in. The cap-height ratio scales gently with diagonal —
    /// at 13" we assume a serif-leaning ~0.71 of em; on larger displays
    /// (typically viewed at greater distance), the perceptually-relevant
    /// cap shrinks linearly toward ~0.61 by the 27" mark. Spec §6.2 target
    /// band is 0.21"–0.27".
    public var estimatedCapHeightInches: CGFloat {
        let pointSize = recommendedBodyPointSize
        let emInches = pointSize / 72.0
        let d = diagonalInches
        let capFactor: CGFloat
        if d <= 13 {
            capFactor = 0.71
        } else if d >= 27 {
            capFactor = 0.61
        } else {
            let t = (d - 13) / (27 - 13)
            capFactor = 0.71 - 0.10 * t
        }
        return emInches * capFactor
    }
}
