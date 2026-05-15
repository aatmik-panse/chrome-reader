import SwiftUI

struct SettingsView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: ReaderSettings

    private var theme: Theme {
        settings.resolvedTheme(for: colorScheme)
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - iPhone Layout

    private var iPhoneLayout: some View {
        List {
            previewSection
            appearanceSection
            readerSection
            widgetSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(theme.backgroundColor)
    }

    // MARK: - iPad Layout

    @State private var selectedSection: SettingsSection = .appearance

    private var iPadLayout: some View {
        HStack(spacing: 0) {
            sidebarList
                .frame(width: 280)

            Divider()

            detailForSection(selectedSection)
                .frame(maxWidth: .infinity)
        }
        .background(theme.backgroundColor)
    }

    private var sidebarList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.title, systemImage: section.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(selectedSection == section ? Color.matcha600 : theme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                selectedSection == section
                                    ? Color.matcha600.opacity(0.1)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .background(theme.surfaceColor)
    }

    @ViewBuilder
    private func detailForSection(_ section: SettingsSection) -> some View {
        List {
            switch section {
            case .appearance:
                previewSection
                appearanceSection
            case .reader:
                readerSection
            case .widget:
                widgetSection
            case .about:
                aboutSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.backgroundColor)
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reading Preview")
                    .clayLabel()
                    .foregroundStyle(theme.secondaryText)

                VStack(alignment: .leading, spacing: 8) {
                    Text("The Art of Reading")
                        .font(.custom(settings.resolvedFontName, size: settings.fontSize + 4))
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.primaryText)

                    Text("In a hole in the ground there lived a hobbit. Not a nasty, dirty, wet hole — it was a hobbit-hole, and that means comfort.")
                        .font(.custom(settings.resolvedFontName, size: settings.fontSize))
                        .lineSpacing(settings.fontSize * (settings.lineHeight - 1))
                        .foregroundStyle(theme.primaryText)
                }
                .padding(ClayConstants.spacingMD)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: ClayConstants.cornerRadiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: ClayConstants.cornerRadiusSmall)
                        .strokeBorder(theme.divider, lineWidth: 1)
                )
            }
        }
        .listRowBackground(theme.surfaceColor)
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        Section("Appearance") {
            themeRow
            fontRow
            fontSizeRow
            lineSpacingRow
        }
        .listRowBackground(theme.surfaceColor)
    }

    private var themeRow: some View {
        VStack(alignment: .leading, spacing: ClayConstants.spacingSM) {
            Text("Theme")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.primaryText)

            HStack(spacing: ClayConstants.spacingSM) {
                ForEach(AppThemeMode.allCases) { mode in
                    let modeTheme = previewTheme(for: mode)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            settings.theme = mode
                        }
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: ClayConstants.cornerRadiusSmall)
                                .fill(modeTheme.backgroundColor)
                                .frame(height: 48)
                                .overlay(
                                    RoundedRectangle(cornerRadius: ClayConstants.cornerRadiusSmall)
                                        .strokeBorder(
                                            settings.theme == mode
                                                ? Color.matcha600
                                                : modeTheme.divider,
                                            lineWidth: settings.theme == mode ? 2 : 1
                                        )
                                )
                                .overlay {
                                    VStack(spacing: 3) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(modeTheme.primaryText)
                                            .frame(width: 28, height: 3)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(modeTheme.secondaryText)
                                            .frame(width: 20, height: 3)
                                    }
                                }

                            Text(mode.rawValue.capitalized)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(
                                    settings.theme == mode
                                        ? Color.matcha600
                                        : theme.secondaryText
                                )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func previewTheme(for mode: AppThemeMode) -> Theme {
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .system: return colorScheme == .dark ? .dark : .light
        }
    }

    private var fontRow: some View {
        Picker("Font", selection: $settings.fontFamily) {
            ForEach(ReaderSettings.availableFonts, id: \.self) { fontName in
                Text(fontName)
                    .font(.custom(
                        fontName == "System Serif" ? ".AppleSystemUIFontSerif" : fontName,
                        size: 15
                    ))
                    .tag(fontName)
            }
        }
        .foregroundStyle(theme.primaryText)
    }

    private var fontSizeRow: some View {
        HStack {
            Text("Font Size")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.primaryText)

            Spacer()

            HStack(spacing: ClayConstants.spacingSM) {
                Button {
                    settings.fontSize = max(12, settings.fontSize - 1)
                } label: {
                    Text("A")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .frame(width: 32, height: 32)
                        .background(theme.backgroundColor)
                        .clipShape(Circle())
                }

                Text("\(Int(settings.fontSize))")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.primaryText)
                    .frame(width: 32)

                Button {
                    settings.fontSize = min(32, settings.fontSize + 1)
                } label: {
                    Text("A")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(theme.primaryText)
                        .frame(width: 32, height: 32)
                        .background(theme.backgroundColor)
                        .clipShape(Circle())
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var lineSpacingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Line Spacing")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.primaryText)

                Spacer()

                Text("\(String(format: "%.1f", settings.lineHeight))×")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
            }

            Slider(value: $settings.lineHeight, in: 1.0...2.5, step: 0.1)
                .tint(.matcha600)
        }
    }

    // MARK: - Reader Section

    private var readerSection: some View {
        Section("Reader") {
            Toggle(isOn: $settings.pinToolbar) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pin Toolbar")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.primaryText)

                    Text("Keep the toolbar visible while reading")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .tint(.matcha600)
        }
        .listRowBackground(theme.surfaceColor)
    }

    // MARK: - Widget Section

    private var widgetSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Widget Text Size")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.primaryText)

                    Spacer()

                    Text("\(Int(settings.widgetTextSize))pt")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.secondaryText)
                }

                Slider(value: $settings.widgetTextSize, in: 10...20, step: 1)
                    .tint(.matcha600)
            }

            Toggle(isOn: $settings.widgetShowCover) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Book Cover")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.primaryText)

                    Text("Display the cover image in the widget")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }
            }
            .tint(.matcha600)
        } header: {
            Text("Widget")
        } footer: {
            Text("Changes will appear the next time the widget refreshes.")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)
        }
        .listRowBackground(theme.surfaceColor)
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("1.0.0")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.secondaryText)
            }

            HStack {
                Text("Built with")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.primaryText)
                Spacer()
                Text("SwiftUI + SwiftData")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.secondaryText)
            }

            Button {
                settings.resetToDefaults()
            } label: {
                Text("Reset to Defaults")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.pomegranate400)
            }
        }
        .listRowBackground(theme.surfaceColor)
    }
}

// MARK: - Settings Section Enum

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case appearance
    case reader
    case widget
    case about

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .appearance: return "paintpalette"
        case .reader: return "book"
        case .widget: return "square.text.square"
        case .about: return "info.circle"
        }
    }
}
