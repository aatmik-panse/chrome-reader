import XCTest
@testable import InstantBookReader

final class AnthropicProviderTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: type(of: self))
            .url(forResource: name, withExtension: "sse"))
        return try Data(contentsOf: url)
    }

    func testStreamYieldsTextDeltasInOrder() async throws {
        let body = try fixture("anthropic-hello")
        MockURLProtocol.handler = { _ in .init(chunks: [body]) }
        let session = MockURLProtocol.makeSession()
        let provider = AnthropicProvider(apiKey: "k",
                                         defaultModel: "claude-sonnet-4-6",
                                         http: HTTPClient(session: session))
        var deltas: [String] = []
        var sawDone = false
        for try await chunk in provider.stream(.init(model: "claude-sonnet-4-6",
                                                     system: "sys",
                                                     messages: [.init(role: "user", content: "hi")])) {
            switch chunk {
            case .textDelta(let s): deltas.append(s)
            case .done: sawDone = true
            case .error(let m): XCTFail("unexpected error \(m)")
            }
        }
        XCTAssertEqual(deltas.joined(), "Hello world.")
        XCTAssertTrue(sawDone)
    }

    func testRequestUsesMessagesEndpointAndHeaders() async throws {
        MockURLProtocol.handler = { _ in .init(chunks: [
            Data("event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n".utf8)
        ]) }
        let session = MockURLProtocol.makeSession()
        let provider = AnthropicProvider(apiKey: "ak",
                                         defaultModel: "claude-sonnet-4-6",
                                         http: HTTPClient(session: session))
        for try await _ in provider.stream(.init(model: "claude-sonnet-4-6",
                                                 system: nil,
                                                 messages: [.init(role: "user", content: "x")])) {}
        let req = try XCTUnwrap(MockURLProtocol.recordedRequests.first)
        XCTAssertEqual(req.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-api-key"), "ak")
        XCTAssertEqual(req.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func testBodyHasStreamTrueAndSystemField() async throws {
        MockURLProtocol.handler = { _ in .init(chunks: [Data("event: message_stop\ndata: {}\n\n".utf8)]) }
        let session = MockURLProtocol.makeSession()
        let provider = AnthropicProvider(apiKey: "k",
                                         defaultModel: "claude-sonnet-4-6",
                                         http: HTTPClient(session: session))
        for try await _ in provider.stream(.init(model: "claude-sonnet-4-6",
                                                 system: "S",
                                                 messages: [.init(role: "user", content: "U")])) {}
        let req = try XCTUnwrap(MockURLProtocol.recordedRequests.first)
        let body = try XCTUnwrap(req.httpBody ?? OpenAIProviderTests.readStream(req.httpBodyStream))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["stream"] as? Bool, true)
        XCTAssertEqual(json?["system"] as? String, "S")
        let messages = json?["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.first?["role"], "user")
        XCTAssertEqual(messages?.first?["content"], "U")
    }

    func testErrorEventThrows() async throws {
        let body = try fixture("anthropic-error")
        MockURLProtocol.handler = { _ in .init(chunks: [body]) }
        let session = MockURLProtocol.makeSession()
        let provider = AnthropicProvider(apiKey: "k",
                                         defaultModel: "claude-sonnet-4-6",
                                         http: HTTPClient(session: session))
        do {
            for try await _ in provider.stream(.init(model: "claude-sonnet-4-6",
                                                     system: nil,
                                                     messages: [.init(role: "user", content: "x")])) {}
            XCTFail("expected throw")
        } catch let AIRouterError.http(_, body) {
            XCTAssertTrue(body.contains("Overloaded"))
        }
    }
}
