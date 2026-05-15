import Foundation
import SwiftData

@Model
final class VocabEntry {
    @Attribute(.unique) var clientID: UUID
    var word: String
    var definition: String?
    var bookHash: String?
    /// Leitner box stage 0..4.
    var leitnerStage: Int
    var lastReviewedAt: Date?
    var nextReviewAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(clientID: UUID = UUID(),
         word: String,
         definition: String? = nil,
         bookHash: String? = nil,
         leitnerStage: Int = 0,
         lastReviewedAt: Date? = nil,
         nextReviewAt: Date? = nil,
         createdAt: Date = .now,
         updatedAt: Date = .now) {
        self.clientID = clientID
        self.word = word
        self.definition = definition
        self.bookHash = bookHash
        self.leitnerStage = leitnerStage
        self.lastReviewedAt = lastReviewedAt
        self.nextReviewAt = nextReviewAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
