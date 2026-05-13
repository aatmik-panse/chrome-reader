import CoreGraphics
import Foundation

/// Single source of truth for the ambient corner card's measurements.
/// Every value here traces back to the design spec §5.2 / §11.1.
enum AmbientLayoutMetrics {
    /// Spec §5.2: ~360pt-wide card.
    static let cardWidth: CGFloat = 360

    /// Spec §5.2: 60×80 cover thumbnail.
    static let coverSize = CGSize(width: 60, height: 80)

    /// Spec §11.1 attribution: DM Sans 500, uppercase, 1.08px tracking.
    /// Reused for the chapter/progress label and the title/author footer.
    static let labelTracking: CGFloat = 1.08
    static let labelFontSize: CGFloat = 13        // chapter+progress
    static let footerFontSize: CGFloat = 11       // title+author
    static let footerOpacity: Double = 0.6        // "low opacity" per task brief

    /// Inner padding on the visual-effect plate; sized to the text block only.
    static let plateInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

    /// 16pt gap between cover and the text block.
    static let coverToTextGap: CGFloat = 16

    /// 8pt vertical spacing between chapter label, quote, and footer.
    static let blockSpacing: CGFloat = 8

    /// Padding from the screen edges (bottom-left corner anchor).
    static let screenPadding = NSEdgeInsets(top: 0, left: 56, bottom: 56, right: 0)

    /// Spec §11.1 motion timings.
    static let crossfadeOutDuration: TimeInterval = 0.8
    static let crossfadeInDuration: TimeInterval = 1.2
    static let reducedMotionBlinkDuration: TimeInterval = 0.1

    /// Spec §5.3 "Finder becomes frontmost" + §5.2 plate.
    static let finderFadeAlpha: CGFloat = 0.15
    static let finderFadeDuration: TimeInterval = 0.4
    static let finderRestoreAlpha: CGFloat = 1.0

    /// Spec §5.3 timer bounds.
    static let rotationMin: TimeInterval = 45
    static let rotationMax: TimeInterval = 600
    static let rotationDefault: TimeInterval = 90
    /// Spec §5.3 "Cursor enters safe zone … resume 5s after exit".
    static let safeZoneResumeDelay: TimeInterval = 5
    /// Spec §5.3 "Finder becomes frontmost … advance after 800ms".
    static let finderActivationDelay: TimeInterval = 0.8

    /// Truncated quote text + whether truncation happened.
    struct TruncatedQuote: Equatable {
        let text: String
        let wasTruncated: Bool
    }

    /// Spec §5.2: max 280 chars, "Read more…" affordance for longer.
    static func truncateForDisplay(_ raw: String) -> TruncatedQuote {
        if raw.count <= 280 {
            return TruncatedQuote(text: raw, wasTruncated: false)
        }
        let cut = raw.prefix(279)
        return TruncatedQuote(text: cut + "…", wasTruncated: true)
    }

    /// Spec §11.1: Medium 44pt for ≤120 chars, Regular 28pt for longer.
    static func quoteFontSize(for raw: String) -> CGFloat {
        raw.count <= 120 ? 44 : 28
    }

    /// Spec §11.1: 1.25 leading for short, 1.45 for long.
    static func quoteLeadingMultiple(for raw: String) -> CGFloat {
        raw.count <= 120 ? 1.25 : 1.45
    }
}
