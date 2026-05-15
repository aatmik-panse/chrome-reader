import Foundation
import SwiftData

/// Owns the app's SwiftData ModelContainer. All windows share one container
/// injected via SwiftUI environment so @Query observes changes process-wide.
enum PersistenceController {
    static let schema = Schema([
        Book.self,
        Position.self,
        Highlight.self,
        VocabEntry.self,
        AICacheEntry.self
    ])

    /// On-disk container at `<AppSupport>/Database/InstantBookReader.store`.
    static func makeContainer() throws -> ModelContainer {
        try AppSupportPaths.ensureCreated()
        let storeURL = AppSupportPaths.database
            .appendingPathComponent("InstantBookReader.store")
        let config = ModelConfiguration(schema: schema,
                                        url: storeURL,
                                        cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// For tests.
    static func makeInMemoryContainer() throws -> ModelContainer {
        let config = ModelConfiguration(schema: schema,
                                        isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
