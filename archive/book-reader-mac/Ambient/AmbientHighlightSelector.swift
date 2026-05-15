import Foundation

/// A seeded PRNG so the per-session shuffle is reproducible in tests.
/// Splitmix64 — small, fast, no Foundation dependency, deterministic.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Produces a session-stable shuffled stream over the user's highlights for
/// the current book. Empty pool ⇒ nil forever. Single-element pool ⇒ repeat.
/// Blank-text highlights (where the user only attached a note) are filtered
/// out before shuffling.
final class AmbientHighlightSelector {
    private let pool: [Highlight]
    private var rng: SeededRandomNumberGenerator
    private var deck: [Highlight] = []

    init(highlights: [Highlight], seed: UInt64) {
        self.pool = highlights.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.rng = SeededRandomNumberGenerator(seed: seed)
    }

    /// Returns the next highlight in the shuffle. When the deck is exhausted,
    /// reshuffles the pool and starts again. Returns nil iff the pool is empty.
    func next() -> Highlight? {
        guard !pool.isEmpty else { return nil }
        if deck.isEmpty {
            deck = pool.shuffled(using: &rng)
        }
        return deck.removeFirst()
    }
}
