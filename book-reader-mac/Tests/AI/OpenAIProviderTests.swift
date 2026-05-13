import XCTest
@testable import InstantBookReader

final class OpenAIProviderTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: type(of: self))
            .url(forResource: name, withExtension: "sse", subdirectory: "Fixtures/AI"))
        return try Data(contentsOf: url)
    }

    func testStreamYieldsTextDeltasInOrder() async throws {
        let body = try fixture("openai-hello")
        MockURLProtocol.handler = { _ in .init(chunks: [body]) }
        let session = MockURLProtocol.makeSession()
        let provider = OpenAIProvider(apiKey: "sk-test",
                                      defaultModel: "gpt-5.5",
                                      http: HTTPClient(session: session))
        var deltas: [String] = []
        var sawDone = false
        for try await chunk in provider.stream(.init(model: "gpt-5.5",
                                                     system: "sys",
                                                     messages: [.init(role: "user", content: "hi")])) {
            switch chunk {
            case .textDelta(let s): deltas.append(s)
            case .done: sawDone = true
            case .error: XCTFail("unexpected error chunk")
            }
        }
        XCTAssertEqual(deltas.joined(), "Hello world.")
        XCTAssertTrue(sawDone)
    }

    func testRequestUsesChatCompletionsEndpointAndAuthHeader() async throws {
        MockURLProtocol.handler = { _ in .init(chunks: [Data("data: [DONE]\n\n".utf8)]) }
        let session = MockURLProtocol.makeSession()
        let provider = OpenAIProvider(apiKey: "sk-key",
                                      defaultModel: "gpt-5.5",
                                      http: HTTPClient(session: session))
        for try await _ in provider.stream(.init(model: "gpt-5.5",
                                                 system: nil,
                                                 messages: [.init(role: "user", content: "x")])) {}
        let req = try XCTUnwrap(MockURLProtocol.recordedRequests.first)
        XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testBodyContainsStreamTrueAndMessages() async throws {
        MockURLProtocol.handler = { _ in .init(chunks: [Data("data: [DONE]\n\n".utf8)]) }
        let session = MockURLProtocol.makeSession()
        let provider = OpenAIProvider(apiKey: "k",
                                      defaultModel: "gpt-5.5",
                                      http: HTTPClient(session: session))
        for try await _ in provider.stream(.init(model: "gpt-5.5",
                                                 system: "sys",
                                                 messages: [.init(role: "user", content: "ask")])) {}
        let req = try XCTUnwrap(MockURLProtocol.recordedRequests.first)
        // bodyStreamData isn't exposed directly via URLProtocol; for these
        // tests URLProtocol delivers `httpBody`. If the test target sees
        // `httpBodyStream` instead, drain it.
        let body = try XCTUnwrap(req.httpBody ?? Self.readStream(req.httpBodyStream))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["stream"] as? Bool, true)
        XCTAssertEqual(json?["model"] as? String, "gpt-5.5")
        let messages = json?["messages"] as? [[String: String]]
        XCTAssertEqual(messages?.first?["role"], "system")
        XCTAssertEqual(messages?.first?["content"], "sys")
        XCTAssertEqual(messages?.last?["role"], "user")
        XCTAssertEqual(messages?.last?["content"], "ask")
    }

    func testNon200ThrowsHttpError() async throws {
        MockURLProtocol.handler = { _ in .init(status: 401,
                                               headers: ["Content-Type": "application/json"],
                                               chunks: [Data("{\"error\":\"bad key\"}".utf8)]) }
        let session = MockURLProtocol.makeSession()
        let provider = OpenAIProvider(apiKey: "k",
                                      defaultModel: "gpt-5.5",
                                      http: HTTPClient(session: session))
        do {
            for try await _ in provider.stream(.init(model: "gpt-5.5",
                                                     system: nil,
                                                     messages: [.init(role: "user", content: "x")])) {}
            XCTFail("expected throw")
        } catch let AIRouterError.http(status, _) {
            XCTAssertEqual(status, 401)
        }
    }

    func testTestUsesOneTokenRequest() async throws {
        MockURLProtocol.handler = { _ in .init(chunks: [Data("data: [DONE]\n\n".utf8)]) }
        let session = MockURLProtocol.makeSession()
        let provider = OpenAIProvider(apiKey: "k",
                                      defaultModel: "gpt-5.5",
                                      http: HTTPClient(session: session))
        try await provider.test()
        let req = try XCTUnwrap(MockURLProtocol.recordedRequests.first)
        let body = try XCTUnwrap(req.httpBody ?? Self.readStream(req.httpBodyStream))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["max_tokens"] as? Int, 1)
    }

    /// URLProtocol-backed requests can deliver bodies as streams. Drain.
    static func readStream(_ stream: InputStream?) -> Data? {
        guard let stream = stream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufSize = 4096
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buf, maxLength: bufSize)
            if read <= 0 { break }
            data.append(buf, count: read)
        }
        return data
    }
}
