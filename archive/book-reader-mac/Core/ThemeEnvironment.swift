import SwiftUI

/// 24-bit RGB color value backed by Clay design system tokens.
/// Codable to hex string for persistence and inspection in tests.
struct AppColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        precondition(s.count == 6, "AppColor hex must be #RRGGBB")
        let value = UInt32(s, radix: 16) ?? 0
        self.red = Double((value >> 16) & 0xFF) / 255.0
        self.green = Double((value >> 8) & 0xFF) / 255.0
        self.blue = Double(value & 0xFF) / 255.0
    }

    var hexString: String {
        String(format: "#%02X%02X%02X",
               Int((red * 255).rounded()),
               Int((green * 255).rounded()),
               Int((blue * 255).rounded()))
    }

    var swiftUI: Color { Color(red: red, green: green, blue: blue) }
}

/// Themed token bundle. Active reader uses these via @Environment;
/// ambient layer derives ink + surface from the same source.
struct AppTheme: Equatable, Sendable {
    let id: String
    let ink: AppColor
    let surface: AppColor
    let border: AppColor

    static let clayDark = AppTheme(
        id: "clay-dark",
        ink:     AppColor(hex: "#F0EDE8"),
        surface: AppColor(hex: "#1A1815"),
        border:  AppColor(hex: "#3A362F")
    )

    static let clayLight = AppTheme(
        id: "clay-light",
        ink:     AppColor(hex: "#1A1815"),
        surface: AppColor(hex: "#FAF9F7"),
        border:  AppColor(hex: "#E8E2D6")
    )
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .clayDark
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}
