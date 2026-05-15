import SwiftUI
import SwiftData

@main
struct FlipsideApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear { processPendingImports() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        processPendingImports()
                    }
                }
        }
        .modelContainer(for: [Book.self, ReadingPosition.self])
    }

    private func processPendingImports() {
        let defaults = UserDefaults(suiteName: AppGroupManager.appGroupID)
        guard var pending = defaults?.stringArray(forKey: "pendingImports"), !pending.isEmpty else { return }

        let containerURL = AppGroupManager.shared.containerURL
        let importsDir = containerURL.appendingPathComponent("SharedImports", isDirectory: true)

        Task {
            let importer = BookImporter()
            for fileName in pending {
                let fileURL = importsDir.appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

                _ = try? await importer.importBook(from: fileURL)
                try? FileManager.default.removeItem(at: fileURL)
            }

            pending.removeAll()
            defaults?.set(pending, forKey: "pendingImports")
        }
    }
}
