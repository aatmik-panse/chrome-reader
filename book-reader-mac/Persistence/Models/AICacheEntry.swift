import Foundation
import SwiftData

/// Local AI response cache. Keyed by sha256("provider|model|prompt|bookHash").
/// 200 MB cap, LRU-evicted. Plan 4 wires the eviction.
@Model
final class AICacheEntry {
    @Attribute(.unique) var key: String
    var response: String
    var createdAt: Date
    var lastAccessedAt: Date
    var sizeBytes: Int

    init(key: String,
         response: String,
         createdAt: Date = .now,
         lastAccessedAt: Date = .now,
         sizeBytes: Int) {
        self.key = key
        self.response = response
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.sizeBytes = sizeBytes
    }
}
