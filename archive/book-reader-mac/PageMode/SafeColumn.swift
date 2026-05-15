import Foundation
import CoreGraphics
import SwiftUI

/// Placement of the safe column relative to the screen's horizontal axis.
public enum SafeColumnPlacement: String, CaseIterable, Sendable {
    case left
    case center
    case right
}

/// Geometry helper for page mode's centered text column. Spec §6.3:
/// 720pt wide by default, configurable. Right 200pt always reserved
/// for desktop icons regardless of placement.
public enum SafeColumn {

    /// Reserved horizontal strip on the right edge of every screen for
    /// user-arranged desktop icons. Spec §6.3.
    public static let reservedRightInsetForIcons: CGFloat = 200

    /// Default column width — spec §6.3.
    public static let defaultWidth: CGFloat = 720

    /// Storage key for `@AppStorage("pageModeColumnWidth")` consumers.
    public static let widthStorageKey = "pageModeColumnWidth"

    /// Storage key for `@AppStorage("pageModeColumnPlacement")` consumers.
    public static let placementStorageKey = "pageModeColumnPlacement"

    /// Compute the column's CGRect inside the given screen frame.
    /// - Parameters:
    ///   - screen: the screen frame in screen-local coordinates (origin (0,0)
    ///     is fine; only the size matters).
    ///   - placement: left / center / right preset.
    ///   - width: column width in points. Use `SafeColumn.defaultWidth` for
    ///     the spec default.
    public static func frame(
        for screen: CGRect,
        placement: SafeColumnPlacement,
        width: CGFloat = SafeColumn.defaultWidth
    ) -> CGRect {
        let usableRight = screen.width - reservedRightInsetForIcons
        let leftMargin: CGFloat = 96
        let clampedWidth = min(width, usableRight - leftMargin)

        let x: CGFloat
        switch placement {
        case .left:
            x = leftMargin
        case .center:
            // Center within full screen, but never overlap the reserved strip.
            let trueCenterX = (screen.width - clampedWidth) / 2
            let maxAllowedX = usableRight - clampedWidth
            x = max(leftMargin, min(trueCenterX, maxAllowedX))
        case .right:
            // Right-align inside the usable area.
            x = usableRight - clampedWidth
        }
        return CGRect(x: x, y: 0, width: clampedWidth, height: screen.height)
    }
}
