import AppKit
import SwiftData
import SwiftUI

/// Library tab: storage location readout, current book selector,
/// "Import folder…" entry point. Plan 2 owns the import pipeline;
/// this tab calls `BookImporter.importFolder(at:into:)` for recursion.
struct LibraryTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.title) private var books: [Book]
    @AppStorage("currentBookHash") private var currentBookHash: String = ""
    @State private var importErrors: [String] = []
    @State private var isImporting: Bool = false

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Location", value: AppSupportPaths.root.path)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppSupportPaths.root])
                }
            }

            Section("Current book") {
                Picker("Currently reading", selection: $currentBookHash) {
                    Text("None").tag("")
                    ForEach(books, id: \.sha256) { book in
                        Text("\(book.title) — \(book.author ?? "Unknown")")
                            .tag(book.sha256)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Import") {
                Button(isImporting ? "Importing…" : "Import folder…") {
                    importFolder()
                }
                .disabled(isImporting)
                if !importErrors.isEmpty {
                    DisclosureGroup("Skipped \(importErrors.count) file(s)") {
                        ForEach(importErrors, id: \.self) { line in
                            Text(line).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        isImporting = true
        importErrors.removeAll()
        Task { @MainActor in
            defer { isImporting = false }
            do {
                let report = try await BookImporter.importFolder(at: folder, into: modelContext)
                importErrors = report.skipped.map { "\($0.url.lastPathComponent): \($0.reason)" }
            } catch {
                importErrors = ["Folder import failed: \(error.localizedDescription)"]
            }
        }
    }
}
