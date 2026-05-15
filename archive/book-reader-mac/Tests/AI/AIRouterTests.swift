import XCTest
@testable import InstantBookReader

final class AIRouterTests: XCTestCase {
    override func setUp() async throws {
        for p in ProviderID.allCases { try? KeychainStore.delete(for: p) }
        let defaults = UserDefaults.standard
        for f in AIFeature.allCases {
            defaults.removeObject(forKey: f.providerDefaultsKey)
            defaults.removeObject(forKey: f.modelDefaultsKey)
        }
    }

    override func tearDown() async throws {
        for p in ProviderID.allCases { try? KeychainStore.delete(for: p) }
    }

    func testRouterThrowsWhenNoKeyConfigured() {
        UserDefaults.standard.set(ProviderID.openai.rawValue,
                                  forKey: AIFeature.explain.providerDefaultsKey)
        let router = AIRouter()
        XCTAssertThrowsError(try router.resolve(.explain)) { error in
            guard let e = error as? AIRouterError else { return XCTFail("wrong type") }
            XCTAssertEqual(e, .noKeyForProvider(.openai))
        }
    }

    func testRouterReturnsConfiguredProviderWhenKeyExists() throws {
        try KeychainStore.save(key: "sk-x", for: .openai)
        UserDefaults.standard.set(ProviderID.openai.rawValue,
                                  forKey: AIFeature.ask.providerDefaultsKey)
        UserDefaults.standard.set("gpt-5.5-mini", forKey: AIFeature.ask.modelDefaultsKey)
        let router = AIRouter()
        let resolved = try router.resolve(.ask)
        XCTAssertEqual(resolved.provider.id, .openai)
        XCTAssertEqual(resolved.model, "gpt-5.5-mini")
    }

    func testRouterUsesProviderDefaultModelWhenUnset() throws {
        try KeychainStore.save(key: "sk-x", for: .anthropic)
        UserDefaults.standard.set(ProviderID.anthropic.rawValue,
                                  forKey: AIFeature.summarize.providerDefaultsKey)
        let router = AIRouter()
        let resolved = try router.resolve(.summarize)
        XCTAssertEqual(resolved.provider.id, .anthropic)
        XCTAssertEqual(resolved.model, resolved.provider.defaultModel)
    }

    func testRouterDefaultsFeatureProviderToOpenAIWhenUnset() throws {
        try KeychainStore.save(key: "sk-x", for: .openai)
        let router = AIRouter()
        let resolved = try router.resolve(.translate)
        XCTAssertEqual(resolved.provider.id, .openai)
    }
}
