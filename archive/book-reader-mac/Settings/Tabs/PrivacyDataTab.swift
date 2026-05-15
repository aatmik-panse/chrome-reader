import AppKit
import SwiftData
import SwiftUI
import ZIPFoundation

/// Destructive-action tab. All three buttons confirm before acting; the
/// reset-positions action uses an alert because the operation is silent
/// and not reversible.
struct PrivacyDataTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var statusMessage: String?
    @State private var showResetAlert: Bool = false

    var body: some View {
        Form {
            Section("AI cache") {
                Button("Clear AI cache") {
                    do {
                        try AICache.evictAll(in: modelContext)
                        statusMessage = "AI cache cleared."
                    } catch {
                        statusMessage = "Failed to clear cache: \(error.localizedDescription)"
                    }
                }
                Text("Removes all locally cached AI responses. Server-side cache is untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Library export") {
                Button("Export library to ZIP…") { exportLibrary() }
                Text("Bundles every imported book file into a single ZIP archive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Positions") {
                Button("Reset all reading positions…", role: .destructive) {
                    showResetAlert = true
                }
            }

            if let statusMessage {
                Section { Text(statusMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .alert("Reset all reading positions?",
               isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetAllPositions() }
        } message: {
            Text("Every book will lose its current position. Highlights and the library are preserved.")
        }
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "InstantBookReader-Library.zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.zipItem(at: AppSupportPaths.books, to: destination)
            statusMessage = "Exported library to \(destination.lastPathComponent)."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func resetAllPositions() {
        do {
            let positions = try modelContext.fetch(FetchDescriptor<Position>())
            for p in positions { modelContext.delete(p) }
            try modelContext.save()
            statusMessage = "Cleared \(positions.count) reading position(s)."
        } catch {
            statusMessage = "Reset failed: \(error.localizedDescription)"
        }
    }
}
