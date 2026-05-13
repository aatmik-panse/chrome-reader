import XCTest
@testable import InstantBookReader

final class OpenRouterProviderTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: type(of: self))
            .url(forResource: name, withExtension: "sse", subdirectory: "Fixtures/AI"))
        return try Data(contentsOf: url)
    }

    func testStreamYieldsTextDeltas() async throws {
        let body = try fixture("openrouter-hello")
        MockURLProtocol.handler = { _ in .init(chunks: [body]) }
        let session = MockURLProtocol.makeSession()
        let provider = OpenRouterProvider(apiKey: "or-k",
                                          defaultModel: "anthropic/claude-sonnet-4.6",
                                          http: HTTPClient(session: session))
        var deltas: [String] = []
        for try await chunk in provider.stream(.init(model: "anthropic/claude-sonnet-4.6",
                                                     system: nil,
                                                     messages: [.init(role: "user", content: "hi")])) {
            if case .textDelta(let s) = chunk { deltas.append(s) }
        }
        XCTAssertEqual(deltas.joined(), "Hello world.")
    }

    func testRequestUsesOpenRouterEndpointAndHeaders() async throws {
        MockURLProtocol.handler = { _ in .init(chunks: [Data("data: [DONE]\n\n".utf8)]) }
        let session = MockURLProtocol.makeSession()
        let provider = OpenRouterProvider(apiKey: "or-k",
                                          defaultModel: "anthropic/claude-sonnet-4.6",
                                          http: HTTPClient(session: session))
        for try await _ in provider.stream(.init(model: "anthropic/claude-sonnet-4.6",
                                                 system: nil,
                                                 messages: [.init(role: "user", content: "x")])) {}
        let req = try XCTUnwrap(MockURLProtocol.recordedRequests.first)
        XCTAssertEqual(req.url?.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer or-k")
        XCTAssertEqual(req.value(forHTTPHeaderField: "HTTP-Referer"), "https://instant-book-reader.local")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-Title"), "Instant Book Reader")
    }
}
