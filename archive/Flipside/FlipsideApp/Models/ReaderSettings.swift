import SwiftUI
import Combine

// MARK: - Setting Enums

enum AppThemeMode: String, Codable, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
}

enum PDFViewMode: String, Codable, CaseIterable, Identifiable {
    case single, continuous, spread
    var id: String { rawValue }
}

enum PDFColorMode: String, Codable, CaseIterable, Identifiable {
    case normal, dark, sepia
    var id: String { rawValue }
}

// MARK: - AppGroupDefault Property Wrapper

@propertyWrapper
struct AppGroupDefault<Value> {
    let key: String
    let defaultValue: Value
    let defaults: UserDefaults

    init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
        self.defaults = AppGroupManager.shared.defaults
    }

    var wrappedValue: Value {
        get { defaults.object(forKey: key) as? Value ?? defaultValue }
        set { defaults.set(newValue, forKey: key) }
    }
}

@propertyWrapper
struct AppGroupCodableDefault<Value: Codable> {
    let key: String
    let defaultValue: Value
    let defaults: UserDefaults

    init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
        self.defaults = AppGroupManager.shared.defaults
    }

    var wrappedValue: Value {
        get {
            guard let data = defaults.data(forKey: key),
                  let value = try? JSONDecoder().decode(Value.self, from: data) else {
                return defaultValue
            }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key)
            }
        }
    }
}

// MARK: - ReaderSettings

final class ReaderSettings: ObservableObject, @unchecked Sendable {
    static let shared = ReaderSettings()

    private let defaults: UserDefaults

    private enum Keys {
        static let theme = "settings_theme"
        static let fontSize = "settings_fontSize"
        static let lineHeight = "settings_lineHeight"
        static let fontFamily = "settings_fontFamily"
        static let pdfViewMode = "settings_pdfViewMode"
        static let pdfColorMode = "settings_pdfColorMode"
        static let widgetTextSize = "settings_widgetTextSize"
        static let widgetShowCover = "settings_widgetShowCover"
        static let pinToolbar = "settings_pinToolbar"
    }

    @Published var theme: AppThemeMode {
        didSet { saveCodable(theme, forKey: Keys.theme) }
    }

    @Published var fontSize: CGFloat {
        didSet { defaults.set(Double(fontSize), forKey: Keys.fontSize) }
    }

    @Published var lineHeight: CGFloat {
        didSet { defaults.set(Double(lineHeight), forKey: Keys.lineHeight) }
    }

    @Published var fontFamily: String {
        didSet { defaults.set(fontFamily, forKey: Keys.fontFamily) }
    }

    @Published var pdfViewMode: PDFViewMode {
        didSet { saveCodable(pdfViewMode, forKey: Keys.pdfViewMode) }
    }

    @Published var pdfColorMode: PDFColorMode {
        didSet { saveCodable(pdfColorMode, forKey: Keys.pdfColorMode) }
    }

    @Published var widgetTextSize: CGFloat {
        didSet { defaults.set(Double(widgetTextSize), forKey: Keys.widgetTextSize) }
    }

    @Published var widgetShowCover: Bool {
        didSet { defaults.set(widgetShowCover, forKey: Keys.widgetShowCover) }
    }

    @Published var pinToolbar: Bool {
        didSet { defaults.set(pinToolbar, forKey: Keys.pinToolbar) }
    }

    private init() {
        self.defaults = AppGroupManager.shared.defaults

        self.theme = Self.loadCodable(Keys.theme, from: defaults) ?? .system
        self.fontSize = CGFloat(defaults.double(forKey: Keys.fontSize).nonZeroOrDefault(18))
        self.lineHeight = CGFloat(defaults.double(forKey: Keys.lineHeight).nonZeroOrDefault(1.8))
        self.fontFamily = defaults.string(forKey: Keys.fontFamily) ?? "Georgia"
        self.pdfViewMode = Self.loadCodable(Keys.pdfViewMode, from: defaults) ?? .single
        self.pdfColorMode = Self.loadCodable(Keys.pdfColorMode, from: defaults) ?? .normal
        self.widgetTextSize = CGFloat(defaults.double(forKey: Keys.widgetTextSize).nonZeroOrDefault(16))
        self.widgetShowCover = defaults.object(forKey: Keys.widgetShowCover) as? Bool ?? true
        self.pinToolbar = defaults.bool(forKey: Keys.pinToolbar)
    }

    // MARK: - Resolved Theme

    func resolvedTheme(for colorScheme: ColorScheme) -> Theme {
        switch theme {
        case .light: return .light
        case .dark: return .dark
        case .system: return colorScheme == .dark ? .dark : .light
        }
    }

    // MARK: - Codable Persistence

    private func saveCodable<T: Codable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadCodable<T: Codable>(_ key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Reset

    func resetToDefaults() {
        theme = .system
        fontSize = 18
        lineHeight = 1.8
        fontFamily = "Georgia"
        pdfViewMode = .single
        pdfColorMode = .normal
        widgetTextSize = 16
        widgetShowCover = true
        pinToolbar = false
    }

    // MARK: - Font Helpers

    static let availableFonts = [
        "Georgia", "New York", "Palatino", "Charter", "Iowan Old Style", "System Serif"
    ]

    var resolvedFontName: String {
        fontFamily == "System Serif" ? ".AppleSystemUIFontSerif" : fontFamily
    }

    var cssFont: String {
        fontFamily == "System Serif"
            ? "-apple-system-ui-serif, ui-serif, Georgia, serif"
            : "'\(fontFamily)', Georgia, serif"
    }
}

// MARK: - Double Convenience

private extension Double {
    func nonZeroOrDefault(_ fallback: Double) -> Double {
        self == 0 ? fallback : self
    }
}
