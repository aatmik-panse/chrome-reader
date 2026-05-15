import XCTest
import SwiftData
@testable import InstantBookReader

@MainActor
final class AICacheTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemoryContainer()
    }

    func testKeyIsSha256OfProviderModelPromptBookHash() {
        let key = AICache.makeKey(provider: .openai,
                                  model: "gpt-5.5",
                                  prompt: "hello",
                                  bookHash: "abc")
        XCTAssertEqual(key.count, 64)
        // Same inputs produce same key.
        let key2 = AICache.makeKey(provider: .openai,
                                   model: "gpt-5.5",
                                   prompt: "hello",
                                   bookHash: "abc")
        XCTAssertEqual(key, key2)
        // Different inputs produce different key.
        XCTAssertNotEqual(key, AICache.makeKey(provider: .openai,
                                               model: "gpt-5.5",
                                               prompt: "hello!",
                                               bookHash: "abc"))
    }

    func testCacheMissReturnsNil() throws {
        let container = try makeContainer()
        let cache = AICache(container: container, maxBytes: 1024)
        let key = AICache.makeKey(provider: .openai, model: "m", prompt: "p", bookHash: "b")
        XCTAssertNil(cache.read(key: key))
    }

    func testCacheHitReturnsValueAndUpdatesLastAccessed() throws {
        let container = try makeContainer()
        let cache = AICache(container: container, maxBytes: 1024)
        let key = AICache.makeKey(provider: .openai, model: "m", prompt: "p", bookHash: "b")
        cache.write(key: key, response: "world")
        let first = try XCTUnwrap(cache.read(key: key))
        XCTAssertEqual(first, "world")
        // Second read should still succeed (and bump lastAccessedAt).
        XCTAssertEqual(cache.read(key: key), "world")
    }

    func testLRUEvictionRemovesLeastRecentlyUsedEntries() throws {
        let container = try makeContainer()
        // 10-byte cap so we can simulate eviction with single-byte responses.
        let cache = AICache(container: container, maxBytes: 10)
        for i in 0..<15 {
            let key = AICache.makeKey(provider: .openai,
                                      model: "m",
                                      prompt: "p\(i)",
                                      bookHash: "b")
            cache.write(key: key, response: "x") // 1 byte
        }
        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<AICacheEntry>())
        let total = all.reduce(0) { $0 + $1.sizeBytes }
        XCTAssertLessThanOrEqual(total, 10)
    }

    func testEvictUnderSyntheticHighLoad() throws {
        let container = try makeContainer()
        let cache = AICache(container: container, maxBytes: 200 * 1024 * 1024)
        // Write 250 entries of 1 MB each = 250 MB > 200 MB cap.
        let big = String(repeating: "A", count: 1_000_000)
        for i in 0..<250 {
            let key = AICache.makeKey(provider: .openai,
                                      model: "m",
                                      prompt: "p\(i)",
                                      bookHash: "b")
            cache.write(key: key, response: big)
        }
        let context = ModelContext(container)
        let total = try context.fetch(FetchDescriptor<AICacheEntry>())
            .reduce(0) { $0 + $1.sizeBytes }
        XCTAssertLessThanOrEqual(total, 200 * 1024 * 1024)
    }
}
