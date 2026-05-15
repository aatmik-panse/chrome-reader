import SwiftUI

// MARK: - Clay Color Palette

extension Color {
    // Neutrals
    static let cream      = Color(red: 0.98, green: 0.96, blue: 0.93)
    static let oat        = Color(red: 0.93, green: 0.90, blue: 0.85)
    static let silver     = Color(red: 0.75, green: 0.73, blue: 0.71)
    static let charcoal   = Color(red: 0.25, green: 0.24, blue: 0.23)
    static let clayBlack  = Color(red: 0.09, green: 0.09, blue: 0.08)
    static let clayWhite  = Color(red: 1.00, green: 1.00, blue: 0.99)

    // Matcha scale
    static let matcha100 = Color(red: 0.91, green: 0.95, blue: 0.88)
    static let matcha200 = Color(red: 0.82, green: 0.90, blue: 0.76)
    static let matcha300 = Color(red: 0.70, green: 0.83, blue: 0.62)
    static let matcha400 = Color(red: 0.58, green: 0.75, blue: 0.48)
    static let matcha500 = Color(red: 0.45, green: 0.64, blue: 0.35)
    static let matcha600 = Color(red: 0.36, green: 0.53, blue: 0.28)
    static let matcha700 = Color(red: 0.28, green: 0.42, blue: 0.22)
    static let matcha800 = Color(red: 0.20, green: 0.31, blue: 0.16)
    static let matcha900 = Color(red: 0.13, green: 0.21, blue: 0.11)

    // Pomegranate scale
    static let pomegranate100 = Color(red: 0.98, green: 0.89, blue: 0.88)
    static let pomegranate200 = Color(red: 0.95, green: 0.78, blue: 0.76)
    static let pomegranate300 = Color(red: 0.91, green: 0.63, blue: 0.60)
    static let pomegranate400 = Color(red: 0.86, green: 0.48, blue: 0.44)
    static let pomegranate500 = Color(red: 0.78, green: 0.33, blue: 0.29)
    static let pomegranate600 = Color(red: 0.65, green: 0.25, blue: 0.22)
    static let pomegranate700 = Color(red: 0.52, green: 0.19, blue: 0.17)
    static let pomegranate800 = Color(red: 0.40, green: 0.14, blue: 0.13)
    static let pomegranate900 = Color(red: 0.29, green: 0.10, blue: 0.09)
}

// MARK: - Clay Typography

struct ClayTitle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 28, weight: .bold, design: .serif))
            .tracking(0.3)
    }
}

struct ClayHeading: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 22, weight: .semibold, design: .serif))
            .tracking(0.2)
    }
}

struct ClayBody: ViewModifier {
    var size: CGFloat = 17

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .regular, design: .serif))
            .lineSpacing(size * 0.6)
    }
}

struct ClayCaption: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .regular, design: .default))
            .tracking(0.2)
    }
}

struct ClayLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .semibold, design: .default))
            .textCase(.uppercase)
            .tracking(0.8)
    }
}

extension View {
    func clayTitle() -> some View { modifier(ClayTitle()) }
    func clayHeading() -> some View { modifier(ClayHeading()) }
    func clayBody(size: CGFloat = 17) -> some View { modifier(ClayBody(size: size)) }
    func clayCaption() -> some View { modifier(ClayCaption()) }
    func clayLabel() -> some View { modifier(ClayLabel()) }
}

// MARK: - Clay Design Constants

enum ClayConstants {
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 20

    static let spacingXS: CGFloat = 4
    static let spacingSM: CGFloat = 8
    static let spacingMD: CGFloat = 16
    static let spacingLG: CGFloat = 24
    static let spacingXL: CGFloat = 32
    static let spacingXXL: CGFloat = 48

    static let shadowRadius: CGFloat = 8
    static let shadowX: CGFloat = 0
    static let shadowY: CGFloat = 4
}

struct ClayShadow: ViewModifier {
    var theme: Theme = .light

    func body(content: Content) -> some View {
        content
            .shadow(
                color: theme == .light
                    ? Color.black.opacity(0.08)
                    : Color.black.opacity(0.25),
                radius: ClayConstants.shadowRadius,
                x: ClayConstants.shadowX,
                y: ClayConstants.shadowY
            )
    }
}

extension View {
    func clayShadow(theme: Theme = .light) -> some View {
        modifier(ClayShadow(theme: theme))
    }
}

// MARK: - Theme

enum Theme: String, Codable, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var backgroundColor: Color {
        switch self {
        case .light: return .cream
        case .dark: return .clayBlack
        }
    }

    var surfaceColor: Color {
        switch self {
        case .light: return .clayWhite
        case .dark: return Color(red: 0.14, green: 0.14, blue: 0.13)
        }
    }

    var primaryText: Color {
        switch self {
        case .light: return .charcoal
        case .dark: return .oat
        }
    }

    var secondaryText: Color {
        switch self {
        case .light: return .silver
        case .dark: return Color(red: 0.55, green: 0.53, blue: 0.51)
        }
    }

    var accent: Color {
        switch self {
        case .light: return .matcha600
        case .dark: return .matcha400
        }
    }

    var destructive: Color {
        switch self {
        case .light: return .pomegranate600
        case .dark: return .pomegranate400
        }
    }

    var divider: Color {
        switch self {
        case .light: return .oat
        case .dark: return Color(red: 0.22, green: 0.21, blue: 0.20)
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        }
    }
}
