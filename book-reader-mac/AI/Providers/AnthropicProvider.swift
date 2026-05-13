import Foundation

public struct AnthropicProvider: AIProvider {
    public let id: ProviderID = .anthropic
    public let defaultModel: String
    public let availableModels: [String]

    private let apiKey: String
    private let http: HTTPClient
    private let endpoint: URL

    public init(apiKey: String,
                defaultModel: String = "claude-sonnet-4-6",
                availableModels: [String] = ["claude-sonnet-4-6", "claude-opus-4-6", "claude-haiku-4-6"],
                endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
                http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.defaultModel = defaultModel
        self.availableModels = availableModels
        self.endpoint = endpoint
        self.http = http
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIChunk, Error> {
        let urlRequest = makeRequest(request)
        return AsyncThrowingStream { continuation in
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
                        guard let data = event.data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        let type = (json["type"] as? String) ?? event.event
                        switch type {
                        case "content_block_delta":
                            if let delta = json["delta"] as? [String: Any],
                               (delta["type"] as? String) == "text_delta",
                               let text = delta["text"] as? String, !text.isEmpty {
                                continuation.yield(.textDelta(text))
                            }
                        case "message_stop":
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        case "error":
                            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "error"
                            continuation.finish(throwing:
                                AIRouterError.http(status: response.statusCode, body: message))
                            return
                        default:
                            break
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

    public func test() async throws {
        for try await _ in stream(.init(model: defaultModel,
                                        system: nil,
                                        messages: [.init(role: "user", content: "ping")],
                                        maxTokens: 1)) {}
    }

    private func makeRequest(_ request: AIRequest) -> URLRequest {
        var body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "max_tokens": request.maxTokens,
            "messages": request.messages.map { ["role": $0.role, "content": $0.content] },
        ]
        if let system = request.system, !system.isEmpty {
            body["system"] = system
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return req
    }
}
