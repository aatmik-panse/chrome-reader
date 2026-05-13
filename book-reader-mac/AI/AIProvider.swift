import Foundation

/// Stable identifier for a BYOK provider. The raw value is used as
/// `kSecAttrAccount` in Keychain and as the persisted preference value.
public enum ProviderID: String, Codable, Sendable, CaseIterable {
    case openai
    case anthropic
    case google
    case openrouter

    public var displayName: String {
        switch self {
        case .openai:     return "OpenAI"
        case .anthropic:  return "Anthropic"
        case .google:     return "Google"
        case .openrouter: return "OpenRouter"
        }
    }
}

/// Single message in a chat-style request. `role` is "system" | "user" | "assistant".
public struct AIMessage: Sendable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// One unit of streamed model output.
public enum AIChunk: Sendable, Equatable {
    case textDelta(String)
    case done
    case error(String)
}

/// A normalized request shape. Providers map this to their wire format.
public struct AIRequest: Sendable, Equatable {
    public let model: String
    public let system: String?
    public let messages: [AIMessage]
    public let maxTokens: Int

    public init(model: String,
                system: String?,
                messages: [AIMessage],
                maxTokens: Int = 1024) {
        self.model = model
        self.system = system
        self.messages = messages
        self.maxTokens = maxTokens
    }
}

/// Errors that may surface from the router or providers.
public enum AIRouterError: Error, Equatable, Sendable {
    case noKeyForProvider(ProviderID)
    case unknownProvider(String)
    case http(status: Int, body: String)
    case decoding(String)
    case cancelled
}

/// Provider contract. One instance per `(provider, apiKey, model)` tuple.
public protocol AIProvider: Sendable {
    var id: ProviderID { get }
    var defaultModel: String { get }
    var availableModels: [String] { get }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIChunk, Error>
    /// 1-token request used by Settings → AI's "Test" button.
    func test() async throws
}
