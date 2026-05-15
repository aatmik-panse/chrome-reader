import AppKit
import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Follow macOS"
        case .light:  return "Always light"
        case .dark:   return "Always dark"
        }
    }
}

enum ReaderThemePreset: String, CaseIterable, Identifiable {
    case clayLight = "clay-light"
    case clayDark  = "clay-dark"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clayLight: return "Clay Light"
        case .clayDark:  return "Clay Dark"
        }
    }
}

/// macOS-appearance preference + active reader theme preset.
/// Applies NSApp.appearance live when the user changes the dropdown.
struct AppearanceTab: View {
    @AppStorage("appearancePreference") private var appearance: AppearancePreference = .system
    @AppStorage("readerThemePreset") private var themePreset: ReaderThemePreset = .clayDark

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Window appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
            }
            Section("Active reader") {
                Picker("Theme preset", selection: $themePreset) {
                    ForEach(ReaderThemePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                Text("Themes follow the Clay design system from the Chrome extension.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { _, newValue in apply(newValue) }
        .onAppear { apply(appearance) }
    }

    private func apply(_ preference: AppearancePreference) {
        switch preference {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
