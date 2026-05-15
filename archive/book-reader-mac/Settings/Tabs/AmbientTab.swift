import SwiftUI

enum AmbientLayout: String, CaseIterable, Identifiable {
    case cornerCard = "corner-card"
    case leftRail   = "left-rail"
    case dockFlank  = "dock-flank"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cornerCard: return "Corner card (default)"
        case .leftRail:   return "Left rail"
        case .dockFlank:  return "Dock flank"
        }
    }
}

enum AmbientCadence: Int, CaseIterable, Identifiable {
    case fast = 45, normal = 90, slow = 300, slowest = 600
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .fast: return "45 seconds"
        case .normal: return "90 seconds (default)"
        case .slow: return "5 minutes"
        case .slowest: return "10 minutes"
        }
    }
}

/// Ambient mode tunables. Bound to @AppStorage; the runtime layer
/// (Plan 5 — AmbientRotationController) reads these via the same keys.
struct AmbientTab: View {
    @AppStorage("ambientLayout") private var layout: AmbientLayout = .cornerCard
    @AppStorage("ambientCadenceSeconds") private var cadence: AmbientCadence = .normal
    @AppStorage("ambientScrimEnabled") private var scrim: Bool = true
    @AppStorage("ambientShowCover") private var showCover: Bool = true
    @AppStorage("ambientShowProgress") private var showProgress: Bool = true
    @AppStorage("ambientShowHighlight") private var showHighlight: Bool = true
    @AppStorage("ambientFinderFade") private var finderFade: Bool = true

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Layout", selection: $layout) {
                    ForEach(AmbientLayout.allCases) { l in Text(l.label).tag(l) }
                }
            }

            Section("Rotation") {
                Picker("Quote cadence", selection: $cadence) {
                    ForEach(AmbientCadence.allCases) { c in Text(c.label).tag(c) }
                }
                Text("Rotation also advances on screen wake, Finder activation, and the menu-bar Next quote command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Toggle("Show scrim behind quote", isOn: $scrim)
                Toggle("Fade when Finder is frontmost", isOn: $finderFade)
            }

            Section("Content units") {
                Toggle("Cover image", isOn: $showCover)
                Toggle("Chapter title + progress", isOn: $showProgress)
                Toggle("Rotating highlight", isOn: $showHighlight)
            }
        }
        .formStyle(.grouped)
    }
}
