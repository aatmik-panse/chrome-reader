import Foundation
import SwiftUI
import SwiftData

@MainActor
@Observable
public final class AISettingsViewModel {
    public enum TestState: Equatable {
        case idle, running, ok, failed(String)
    }

    /// In-memory mirror of the SecureField values, one per provider.
    public var keyDrafts: [ProviderID: String] = [:]
    /// True when the saved key for that provider exists in Keychain.
    public var hasSavedKey: [ProviderID: Bool] = [:]
    /// Test outcome per provider.
    public var testState: [ProviderID: TestState] = [:]

    /// Routing — provider per feature.
    public var featureProvider: [AIFeature: ProviderID] = [:]
    /// Routing — model per feature ("" means "use provider default").
    public var featureModel: [AIFeature: String] = [:]

    public var syncToICloud: Bool = false
    public var totalCacheBytes: Int = 0

    private let router: AIRouter
    private let container: ModelContainer

    public init(router: AIRouter = AIRouter(),
                container: ModelContainer) {
        self.router = router
        self.container = container
        load()
    }

    public func load() {
        for p in ProviderID.allCases {
            hasSavedKey[p] = (KeychainStore.load(for: p) != nil)
            keyDrafts[p] = ""
            testState[p] = .idle
        }
        for f in AIFeature.allCases {
            featureProvider[f] = router.providerID(for: f)
            featureModel[f] = router.modelOverride(for: f) ?? ""
        }
        syncToICloud = KeychainStore.isSynchronizable
        totalCacheBytes = AICache(container: container).totalSizeBytes()
    }

    public func saveKey(for provider: ProviderID) {
        let raw = (keyDrafts[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        try? KeychainStore.save(key: raw, for: provider)
        hasSavedKey[provider] = true
        keyDrafts[provider] = ""
        testState[provider] = .idle
    }

    public func deleteKey(for provider: ProviderID) {
        try? KeychainStore.delete(for: provider)
        hasSavedKey[provider] = false
        testState[provider] = .idle
    }

    public func testKey(for provider: ProviderID) async {
        testState[provider] = .running
        guard let key = KeychainStore.load(for: provider), !key.isEmpty else {
            testState[provider] = .failed("No key saved")
            return
        }
        let p: any AIProvider
        switch provider {
        case .openai:     p = OpenAIProvider(apiKey: key)
        case .anthropic:  p = AnthropicProvider(apiKey: key)
        case .google:     p = GoogleProvider(apiKey: key)
        case .openrouter: p = OpenRouterProvider(apiKey: key)
        }
        do {
            try await p.test()
            testState[provider] = .ok
        } catch {
            testState[provider] = .failed(String(describing: error))
        }
    }

    public func setProvider(_ id: ProviderID, for feature: AIFeature) {
        featureProvider[feature] = id
        UserDefaults.standard.set(id.rawValue, forKey: feature.providerDefaultsKey)
    }

    public func setModel(_ model: String, for feature: AIFeature) {
        featureModel[feature] = model
        if model.isEmpty {
            UserDefaults.standard.removeObject(forKey: feature.modelDefaultsKey)
        } else {
            UserDefaults.standard.set(model, forKey: feature.modelDefaultsKey)
        }
    }

    public func availableModels(for provider: ProviderID) -> [String] {
        switch provider {
        case .openai:     return OpenAIProvider(apiKey: "").availableModels
        case .anthropic:  return AnthropicProvider(apiKey: "").availableModels
        case .google:     return GoogleProvider(apiKey: "").availableModels
        case .openrouter: return OpenRouterProvider(apiKey: "").availableModels
        }
    }

    public func setSync(_ enabled: Bool) {
        KeychainStore.setSynchronizable(enabled)
        syncToICloud = enabled
    }

    public func clearCache() {
        AICache(container: container).clear()
        totalCacheBytes = 0
    }

    public func refreshCacheSize() {
        totalCacheBytes = AICache(container: container).totalSizeBytes()
    }
}
