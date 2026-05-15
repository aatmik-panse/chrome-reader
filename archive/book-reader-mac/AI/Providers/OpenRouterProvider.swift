import Foundation

public struct OpenRouterProvider: AIProvider {
    public let id: ProviderID = .openrouter
    public let defaultModel: String
    public let availableModels: [String]

    /// Wraps `OpenAIProvider` with the OpenRouter base URL. We don't subclass
    /// (Swift structs can't) — instead we forward through a configured inner.
    private let inner: OpenAIProvider
    private let referer: String
    private let title: String

    public init(apiKey: String,
                defaultModel: String = "anthropic/claude-sonnet-4.6",
                availableModels: [String] = [
                    "anthropic/claude-sonnet-4.6",
                    "anthropic/claude-opus-4.6",
                    "openai/gpt-5.5",
                    "google/gemini-3.1-pro",
                ],
                endpoint: URL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                referer: String = "https://instant-book-reader.local",
                title: String = "Instant Book Reader",
                http: HTTPClient = HTTPClient()) {
        self.defaultModel = defaultModel
        self.availableModels = availableModels
        self.referer = referer
        self.title = title
        self.inner = OpenAIProvider(apiKey: apiKey,
                                    defaultModel: defaultModel,
                                    availableModels: availableModels,
                                    endpoint: endpoint,
                                    http: http)
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIChunk, Error> {
        let urlRequest = inner.makeRequest(request,
                                           extraHeaders: ["HTTP-Referer": referer,
                                                          "X-Title": title])
        return OpenAIProvider.streamChatCompletions(urlRequest: urlRequest,
                                                    http: inner.configuredHTTP)
    }

    public func test() async throws {
        for try await _ in stream(.init(model: defaultModel,
                                        system: nil,
                                        messages: [.init(role: "user", content: "ping")],
                                        maxTokens: 1)) {}
    }
}
