import SwiftUI

enum SparkleChannel: String, CaseIterable, Identifiable {
    case stable, beta
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Advanced toggles. `sparkleChannel` is read by UpdateController when
/// constructing the feed URL; `diagnosticsEnabled` opts the user into
/// crash-log uploads (post-v1; the toggle exists but is wired to nothing
/// in v1.0).
struct AdvancedTab: View {
    @AppStorage("sparkleChannel") private var channel: SparkleChannel = .stable
    @AppStorage("diagnosticsEnabled") private var diagnostics: Bool = false

    var body: some View {
        Form {
            Section("Updates") {
                Picker("Update channel", selection: $channel) {
                    ForEach(SparkleChannel.allCases) { c in Text(c.label).tag(c) }
                }
                Text("Beta delivers releases before they go to the Stable channel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                Toggle("Send anonymous diagnostics", isOn: $diagnostics)
                Text("Wired to a no-op in v1.0; reserved for a future crash-reporter integration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
