import KeyboardShortcuts
import SwiftUI

/// All named global shortcuts, one Recorder row each. Defaults are seeded
/// where the spec calls for them; Summon Reader is ⌃⌥B (set in Plan 1),
/// page-turn keys are ⌃⌥← / ⌃⌥→.
struct ShortcutsTab: View {
    var body: some View {
        Form {
            Section("Global shortcuts") {
                LabeledContent("Summon Reader") {
                    KeyboardShortcuts.Recorder(for: .toggleReader)
                }
                LabeledContent("Next Quote") {
                    KeyboardShortcuts.Recorder(for: .nextQuote)
                }
                LabeledContent("Toggle Wallpaper Mode") {
                    KeyboardShortcuts.Recorder(for: .toggleWallpaperMode)
                }
                LabeledContent("Next Page") {
                    KeyboardShortcuts.Recorder(for: .nextPage)
                }
                LabeledContent("Previous Page") {
                    KeyboardShortcuts.Recorder(for: .previousPage)
                }
            }
            Section {
                Text("Shortcuts are global. Recording while another app holds the same combination silently replaces this app's binding only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
