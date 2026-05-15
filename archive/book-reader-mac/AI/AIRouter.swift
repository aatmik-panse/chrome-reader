import Foundation

/// Routes a feature → (provider, model). Reads per-feature preferences from
/// `UserDefaults`, fetches the BYOK key from Keychain, and constructs a
/// configured provider. Throws `.noKeyForProvider` if no key is configured.
public struct AIRouter {
    public struct Resolved {
        public let provider: any AIProvider
        public let model: String
    }

    public static let defaultProvider: ProviderID = .openai

    private let defaults: UserDefaults
    private let httpFactory: @Sendable () -> HTTPClient

    public init(defaults: UserDefaults = .standard,
                httpFactory: @escaping @Sendable () -> HTTPClient = { HTTPClient() }) {
        self.defaults = defaults
        self.httpFactory = httpFactory
    }

    public func providerID(for feature: AIFeature) -> ProviderID {
        if let raw = defaults.string(forKey: feature.providerDefaultsKey),
           let parsed = ProviderID(rawValue: raw) {
            return parsed
        }
        return Self.defaultProvider
    }

    public func modelOverride(for feature: AIFeature) -> String? {
        let v = defaults.string(forKey: feature.modelDefaultsKey)
        return (v?.isEmpty ?? true) ? nil : v
    }

    public func resolve(_ feature: AIFeature) throws -> Resolved {
        let id = providerID(for: feature)
        guard let key = KeychainStore.load(for: id), !key.isEmpty else {
            throw AIRouterError.noKeyForProvider(id)
        }
        let http = httpFactory()
        let provider: any AIProvider
        switch id {
        case .openai:     provider = OpenAIProvider(apiKey: key, http: http)
        case .anthropic:  provider = AnthropicProvider(apiKey: key, http: http)
        case .google:     provider = GoogleProvider(apiKey: key, http: http)
        case .openrouter: provider = OpenRouterProvider(apiKey: key, http: http)
        }
        let model = modelOverride(for: feature) ?? provider.defaultModel
        return Resolved(provider: provider, model: model)
    }

    /// Convenience: builds the AIRequest for a feature using its prompt template.
    public func request(for feature: AIFeature,
                        selection: String = "",
                        context: String = "",
                        chapterText: String = "",
                        question: String = "",
                        targetLang: String = "English",
                        maxTokens: Int = 1024) throws -> (AIRequest, Resolved) {
        let resolved = try resolve(feature)
        let request: AIRequest
        switch feature {
        case .summarize:
            request = AIRequest(model: resolved.model,
                                system: SummarizePrompt.system,
                                messages: [.init(role: "user", content: SummarizePrompt.user(chapterText: chapterText))],
                                maxTokens: maxTokens)
        case .ask:
            request = AIRequest(model: resolved.model,
                                system: AskPrompt.system,
                                messages: [.init(role: "user", content: AskPrompt.user(question: question, context: context))],
                                maxTokens: maxTokens)
        case .explain:
            request = AIRequest(model: resolved.model,
                                system: ExplainPrompt.system,
                                messages: [.init(role: "user", content: ExplainPrompt.user(selection: selection, context: context))],
                                maxTokens: maxTokens)
        case .translate:
            request = AIRequest(model: resolved.model,
                                system: TranslatePrompt.system,
                                messages: [.init(role: "user", content: TranslatePrompt.user(text: selection, targetLang: targetLang))],
                                maxTokens: maxTokens)
        case .extractHighlights:
            request = AIRequest(model: resolved.model,
                                system: ExtractHighlightsPrompt.system,
                                messages: [.init(role: "user", content: ExtractHighlightsPrompt.user(chapterText: chapterText))],
                                maxTokens: maxTokens)
        }
        return (request, resolved)
    }
}
