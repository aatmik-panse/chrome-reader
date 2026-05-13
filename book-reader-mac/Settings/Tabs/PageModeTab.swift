import SwiftUI

enum ColumnPlacement: String, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FontSizeOverride: String, CaseIterable, Identifiable {
    case none, sixteen, twenty, twentyFour, twentyEight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None (auto)"
        case .sixteen: return "16 pt"
        case .twenty: return "20 pt"
        case .twentyFour: return "24 pt"
        case .twentyEight: return "28 pt"
        }
    }
    var points: Double? {
        switch self {
        case .none: return nil
        case .sixteen: return 16
        case .twenty: return 20
        case .twentyFour: return 24
        case .twentyEight: return 28
        }
    }
}

/// Page-mode tunables. Bound to @AppStorage; PageModeController (Plan 6)
/// reads these keys.
struct PageModeTab: View {
    @AppStorage("pageModeColumnWidth") private var columnWidth: Double = 720
    @AppStorage("pageModeColumnPlacement") private var placement: ColumnPlacement = .center
    @AppStorage("pageModeFontOverride") private var fontOverride: FontSizeOverride = .none
    @AppStorage("pageModeIdleMinutes") private var idleMinutes: Double = 10

    var body: some View {
        Form {
            Section("Column") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Width")
                        Spacer()
                        Text("\(Int(columnWidth)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $columnWidth, in: 480...960, step: 10)
                }
                Picker("Placement", selection: $placement) {
                    ForEach(ColumnPlacement.allCases) { p in Text(p.label).tag(p) }
                }
            }

            Section("Typography") {
                Picker("Font size override", selection: $fontOverride) {
                    ForEach(FontSizeOverride.allCases) { f in Text(f.label).tag(f) }
                }
                Text("Auto picks size based on screen ppi. Override applies a fixed point size everywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Idle behavior") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Crossfade to ambient after")
                        Spacer()
                        Text("\(Int(idleMinutes)) min")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $idleMinutes, in: 5...30, step: 1)
                }
            }
        }
        .formStyle(.grouped)
    }
}
