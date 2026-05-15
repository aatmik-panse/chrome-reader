import SwiftUI
import WidgetKit

// MARK: - StandBy Layout Configuration

/// Provides adaptive layout values for Home Screen vs StandBy rendering.
/// StandBy is detected when `showsWidgetContainerBackground` is `false`
/// for `systemLarge` / `systemExtraLarge` families.
struct StandByLayout {
    let isStandBy: Bool
    let bodyFont: Font
    let headerFont: Font
    let captionFont: Font
    let lineSpacing: CGFloat
    let textColor: Color
    let secondaryTextColor: Color
    let accentColor: Color
    let separatorColor: Color
    let buttonBackgroundColor: Color

    static func resolve(
        showsBackground: Bool,
        family: WidgetFamily
    ) -> StandByLayout {
        let standBy = !showsBackground
            && (family == .systemLarge || family == .systemExtraLarge)

        if standBy {
            return StandByLayout(
                isStandBy: true,
                bodyFont: .system(size: 22, design: .serif),
                headerFont: .system(size: 15, weight: .medium),
                captionFont: .system(size: 14, weight: .semibold),
                lineSpacing: 7,
                textColor: .white,
                secondaryTextColor: .white.opacity(0.55),
                accentColor: Color(red: 100 / 255, green: 220 / 255, blue: 150 / 255),
                separatorColor: .white.opacity(0.15),
                buttonBackgroundColor: .white.opacity(0.12)
            )
        } else {
            return StandByLayout(
                isStandBy: false,
                bodyFont: .system(size: 16, design: .serif),
                headerFont: .system(size: 12, weight: .medium),
                captionFont: .system(size: 13, weight: .semibold),
                lineSpacing: 4,
                textColor: ClayColors.clayBlack,
                secondaryTextColor: ClayColors.clayBlack.opacity(0.5),
                accentColor: ClayColors.matcha600,
                separatorColor: ClayColors.oat,
                buttonBackgroundColor: ClayColors.matcha600.opacity(0.12)
            )
        }
    }
}

// MARK: - StandBy-Aware View Modifier

/// Marks accent-colored content so iOS renders it correctly in StandBy
/// night mode (red-tinted / accented rendering mode).
struct StandByAccentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.widgetAccentable()
    }
}

extension View {
    func standByAccent() -> some View {
        modifier(StandByAccentModifier())
    }
}
