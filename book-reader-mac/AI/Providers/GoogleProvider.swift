import Foundation

public struct GoogleProvider: AIProvider {
    public let id: ProviderID = .google
    public let defaultModel: String
    public let availableModels: [String]

    private let apiKey: String
    private let http: HTTPClient
    private let baseURL: URL

    public init(apiKey: String,
                defaultModel: String = "gemini-3.1-pro-preview",
                availableModels: [String] = ["gemini-3.1-pro-preview", "gemini-2.5-flash"],
                baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!,
                http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.defaultModel = defaultModel
        self.availableModels = availableModels
        self.baseURL = baseURL
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
                    for try await event in SSEParser.events(from: bytes.lines) {
                        guard let data = event.data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let candidates = json["candidates"] as? [[String: Any]],
                              let content = candidates.first?["content"] as? [String: Any],
                              let parts = content["parts"] as? [[String: Any]] else {
                            continue
                        }
                        for part in parts {
                            if let text = part["text"] as? String, !text.isEmpty {
                                continuation.yield(.textDelta(text))
                            }
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
        let encodedModel = request.model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? request.model
        let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        let url = URL(string: "\(baseURL.absoluteString)/\(encodedModel):streamGenerateContent?alt=sse&key=\(encodedKey)")!

        var body: [String: Any] = [
            "contents": request.messages.map { msg -> [String: Any] in
                ["role": msg.role == "assistant" ? "model" : "user",
                 "parts": [["text": msg.content]]]
            },
            "generationConfig": ["maxOutputTokens": request.maxTokens],
        ]
        if let system = request.system, !system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return req
    }
}
