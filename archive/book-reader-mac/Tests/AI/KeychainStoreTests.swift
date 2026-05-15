import XCTest
@testable import InstantBookReader

final class KeychainStoreTests: XCTestCase {
    override func setUp() async throws {
        for p in ProviderID.allCases { try? KeychainStore.delete(for: p) }
        KeychainStore.setSynchronizable(false)
    }

    override func tearDown() async throws {
        for p in ProviderID.allCases { try? KeychainStore.delete(for: p) }
        KeychainStore.setSynchronizable(false)
    }

    func testSaveThenLoadRoundtrips() throws {
        try KeychainStore.save(key: "sk-test-1", for: .openai)
        XCTAssertEqual(KeychainStore.load(for: .openai), "sk-test-1")
    }

    func testLoadReturnsNilForUnsavedProvider() {
        XCTAssertNil(KeychainStore.load(for: .anthropic))
    }

    func testSaveTwiceUpdatesValue() throws {
        try KeychainStore.save(key: "first", for: .anthropic)
        try KeychainStore.save(key: "second", for: .anthropic)
        XCTAssertEqual(KeychainStore.load(for: .anthropic), "second")
    }

    func testDeleteRemovesKey() throws {
        try KeychainStore.save(key: "k", for: .google)
        try KeychainStore.delete(for: .google)
        XCTAssertNil(KeychainStore.load(for: .google))
    }

    func testDeleteForUnsavedProviderDoesNotThrow() {
        XCTAssertNoThrow(try KeychainStore.delete(for: .openrouter))
    }

    func testSynchronizableTogglePersists() {
        KeychainStore.setSynchronizable(true)
        XCTAssertTrue(KeychainStore.isSynchronizable)
        KeychainStore.setSynchronizable(false)
        XCTAssertFalse(KeychainStore.isSynchronizable)
    }
}
