import Foundation
import CryptoKit
import SwiftData

/// SwiftData-backed AI response cache. 200 MB cap by default, LRU eviction.
/// Keys are sha256("provider|model|prompt|bookHash") so the byte layout
/// matches the extension's IndexedDB cache.
@MainActor
public final class AICache {
    public static let defaultMaxBytes = 200 * 1024 * 1024

    private let container: ModelContainer
    public let maxBytes: Int

    public init(container: ModelContainer, maxBytes: Int = defaultMaxBytes) {
        self.container = container
        self.maxBytes = maxBytes
    }

    public static func makeKey(provider: ProviderID,
                               model: String,
                               prompt: String,
                               bookHash: String) -> String {
        let raw = "\(provider.rawValue)|\(model)|\(prompt)|\(bookHash)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func read(key: String) -> String? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AICacheEntry>(
            predicate: #Predicate { $0.key == key }
        )
        guard let entry = (try? context.fetch(descriptor))?.first else { return nil }
        entry.lastAccessedAt = .now
        try? context.save()
        return entry.response
    }

    public func write(key: String, response: String) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AICacheEntry>(
            predicate: #Predicate { $0.key == key }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.response = response
            existing.sizeBytes = response.utf8.count
            existing.lastAccessedAt = .now
        } else {
            let entry = AICacheEntry(key: key,
                                     response: response,
                                     sizeBytes: response.utf8.count)
            context.insert(entry)
        }
        try? context.save()
        evict()
    }

    public func clear() {
        let context = ModelContext(container)
        if let all = try? context.fetch(FetchDescriptor<AICacheEntry>()) {
            for e in all { context.delete(e) }
            try? context.save()
        }
    }

    /// Deletes every cached AI response in the supplied ModelContext.
    /// Used by the Privacy & Data settings tab (Plan 7).
    public static func evictAll(in context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<AICacheEntry>())
        for e in all { context.delete(e) }
        try context.save()
    }

    public func totalSizeBytes() -> Int {
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<AICacheEntry>())) ?? []
        return all.reduce(0) { $0 + $1.sizeBytes }
    }

    /// LRU eviction: while total > maxBytes, delete the oldest-accessed.
    public func evict() {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<AICacheEntry>(
            sortBy: [SortDescriptor(\AICacheEntry.lastAccessedAt, order: .forward)]
        )
        descriptor.fetchLimit = 64
        var total = totalSizeBytes()
        while total > maxBytes {
            let batch = (try? context.fetch(descriptor)) ?? []
            if batch.isEmpty { break }
            for entry in batch {
                if total <= maxBytes { break }
                total -= entry.sizeBytes
                context.delete(entry)
            }
            try? context.save()
        }
    }
}
