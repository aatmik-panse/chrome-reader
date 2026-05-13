import Foundation

public struct OpenAIProvider: AIProvider {
    public let id: ProviderID = .openai
    public let defaultModel: String
    public let availableModels: [String]

    private let apiKey: String
    private let http: HTTPClient
    private let endpoint: URL

    public init(apiKey: String,
                defaultModel: String = "gpt-5.5",
                availableModels: [String] = ["gpt-5.5", "gpt-5.5-mini", "gpt-4o", "gpt-4o-mini"],
                endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
                http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.defaultModel = defaultModel
        self.availableModels = availableModels
        self.endpoint = endpoint
        self.http = http
    }

    /// Surface accessor used by the OpenRouter subclass-equivalent.
    var configuredEndpoint: URL { endpoint }
    var configuredHTTP: HTTPClient { http }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIChunk, Error> {
        let urlRequest = makeRequest(request, extraHeaders: [:])
        return Self.streamChatCompletions(urlRequest: urlRequest, http: http)
    }

    public func test() async throws {
        var minimal = makeRequest(.init(model: defaultModel,
                                        system: nil,
                                        messages: [.init(role: "user", content: "ping")],
                                        maxTokens: 1),
                                  extraHeaders: [:])
        // The 1-token cap is already encoded in the body; just exhaust the stream.
        _ = minimal
        var sawAny = false
        for try await chunk in stream(.init(model: defaultModel,
                                            system: nil,
                                            messages: [.init(role: "user", content: "ping")],
                                            maxTokens: 1)) {
            if case .textDelta = chunk { sawAny = true }
            if case .error(let m) = chunk { throw AIRouterError.http(status: 0, body: m) }
        }
        _ = sawAny
    }

    /// Build the URLRequest. Subclassed providers (OpenRouter) call this and
    /// then bolt on their own headers.
    func makeRequest(_ request: AIRequest, extraHeaders: [String: String]) -> URLRequest {
        var messages: [[String: String]] = []
        if let system = request.system, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        for m in request.messages {
            messages.append(["role": m.role, "content": m.content])
        }
        let body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "max_tokens": request.maxTokens,
            "messages": messages,
        ]
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return req
    }

    /// Shared OpenAI/OpenRouter chat-completions SSE consumer.
    static func streamChatCompletions(urlRequest: URLRequest,
                                      http: HTTPClient) -> AsyncThrowingStream<AIChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (response, bytes) = try await http.openStream(urlRequest)
                    guard (200..<300).contains(response.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines { body += line + "\n" }
                        continuation.finish(throwing:
                            AIRouterError.http(status: response.statusCode, body: body))
                        return
                    }
                    for try await event in SSEParser.events(fromBytes: bytes) {
                        if event.data == "[DONE]" {
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        }
                        guard let data = event.data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any] else {
                            continue
                        }
                        if let text = delta["content"] as? String, !text.isEmpty {
                            continuation.yield(.textDelta(text))
                        }
                    }
                    continuation.yield(.done)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
