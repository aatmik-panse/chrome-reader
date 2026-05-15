import SwiftUI

enum ReadingFontFamily: String, CaseIterable, Identifiable {
    case newYork = "new-york"
    case sfPro   = "sf-pro"
    case georgia = "georgia"
    case iowan   = "iowan-old-style"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newYork: return "New York (default)"
        case .sfPro:   return "SF Pro"
        case .georgia: return "Georgia"
        case .iowan:   return "Iowan Old Style"
        }
    }
}

/// Active-reader typography. Plan 3's reader views read these keys.
struct ReadingTab: View {
    @AppStorage("readingLineHeight") private var lineHeight: Double = 1.5
    @AppStorage("readingJustify") private var justify: Bool = false
    @AppStorage("readingHyphenate") private var hyphenate: Bool = true
    @AppStorage("readingFontFamily") private var fontFamily: ReadingFontFamily = .newYork

    var body: some View {
        Form {
            Section("Typography") {
                Picker("Font family", selection: $fontFamily) {
                    ForEach(ReadingFontFamily.allCases) { f in Text(f.label).tag(f) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Line height")
                        Spacer()
                        Text(String(format: "%.2f", lineHeight))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $lineHeight, in: 1.2...2.0, step: 0.05)
                }
            }
            Section("Layout") {
                Toggle("Justify text", isOn: $justify)
                Toggle("Hyphenation", isOn: $hyphenate)
            }
        }
        .formStyle(.grouped)
    }
}
