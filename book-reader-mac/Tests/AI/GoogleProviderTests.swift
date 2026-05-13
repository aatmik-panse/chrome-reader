import XCTest
@testable import InstantBookReader

final class GoogleProviderTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: type(of: self))
            .url(forResource: name, withExtension: "sse"))
        return try Data(contentsOf: url)
    }

    func testStreamYieldsTextDeltasInOrder() async throws {
        let body = try fixture("google-hello")
        MockURLProtocol.handler = { _ in .init(chunks: [body]) }
        let session = MockURLProtocol.makeSession()
        let provider = GoogleProvider(apiKey: "k",
                                      defaultModel: "gemini-3.1-pro-preview",
                                      http: HTTPClient(session: session))
        var deltas: [String] = []
        for try await chunk in provider.stream(.init(model: "gemini-3.1-pro-preview",
                                                     system: "sys",
                                                     messages: [.init(role: "user", content: "hi")])) {
            if case .textDelta(let s) = chunk { deltas.append(s) }
        }
        XCTAssertEqual(deltas.joined(), "Hello world.")
    }

    func testUrlIncludesStreamGenerateContentAndAltSse() async throws {
        MockURLProtocol.handler = { _ in .init(chunks: [Data("data: {}\n\n".utf8)]) }
        let session = MockURLProtocol.makeSession()
        let provider = GoogleProvider(apiKey: "g-key",
                                      defaultModel: "gemini-3.1-pro-preview",
                                      http: HTTPClient(session: session))
        for try await _ in provider.stream(.init(model: "gemini-3.1-pro-preview",
                                                 system: nil,
                                                 messages: [.init(role: "user", content: "x")])) {}
        let req = try XCTUnwrap(MockURLProtocol.recordedRequests.first)
        let url = try XCTUnwrap(req.url?.absoluteString)
        XCTAssertTrue(url.contains(":streamGenerateContent"))
        XCTAssertTrue(url.contains("alt=sse"))
        XCTAssertTrue(url.contains("key=g-key"))
    }

    func testBodyHasSystemInstructionAndContents() async throws {
        MockURLProtocol.handler = { _ in .init(chunks: [Data("data: {}\n\n".utf8)]) }
        let session = MockURLProtocol.makeSession()
        let provider = GoogleProvider(apiKey: "k",
                                      defaultModel: "gemini-3.1-pro-preview",
                                      http: HTTPClient(session: session))
        for try await _ in provider.stream(.init(model: "gemini-3.1-pro-preview",
                                                 system: "S",
                                                 messages: [.init(role: "user", content: "U")])) {}
        let req = try XCTUnwrap(MockURLProtocol.recordedRequests.first)
        let body = try XCTUnwrap(req.httpBody ?? OpenAIProviderTests.readStream(req.httpBodyStream))
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let sysParts = ((json?["systemInstruction"] as? [String: Any])?["parts"] as? [[String: String]])
        XCTAssertEqual(sysParts?.first?["text"], "S")
        let contents = json?["contents"] as? [[String: Any]]
        let firstPart = ((contents?.first?["parts"] as? [[String: String]])?.first)
        XCTAssertEqual(firstPart?["text"], "U")
        let gen = json?["generationConfig"] as? [String: Any]
        XCTAssertEqual(gen?["maxOutputTokens"] as? Int, 1024)
    }
}
