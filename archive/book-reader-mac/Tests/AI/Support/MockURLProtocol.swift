import Foundation

/// `URLProtocol` subclass that lets tests stub `URLSession` responses,
/// including streaming bodies. Register with a `URLSessionConfiguration`
/// and supply a handler via `MockURLProtocol.handler`.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let status: Int
        let headers: [String: String]
        /// Body chunks; each is delivered separately so streaming tests can
        /// observe partial reads. For non-streaming tests, pass a single chunk.
        let chunks: [Data]
        let error: Error?
        let interChunkDelay: TimeInterval

        init(status: Int = 200,
             headers: [String: String] = ["Content-Type": "text/event-stream"],
             chunks: [Data],
             error: Error? = nil,
             interChunkDelay: TimeInterval = 0) {
            self.status = status
            self.headers = headers
            self.chunks = chunks
            self.error = error
            self.interChunkDelay = interChunkDelay
        }

        static func text(_ body: String, status: Int = 200,
                         headers: [String: String] = ["Content-Type": "application/json"]) -> Stub {
            Stub(status: status, headers: headers, chunks: [Data(body.utf8)])
        }
    }

    /// Test sets this before exercising URLSession. Returns the stub to apply
    /// for the inbound request. Throws to fail the request with a URLError.
    static var handler: ((URLRequest) throws -> Stub)?

    /// Records every URLRequest the system has issued during the test, in
    /// FIFO order. Tests inspect this to assert request bodies/headers.
    static private(set) var recordedRequests: [URLRequest] = []

    static func reset() {
        handler = nil
        recordedRequests.removeAll()
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.recordedRequests.append(request)

        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let stub = try handler(request)
            if let error = stub.error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let url = request.url ?? URL(string: "http://mock.local/")!
            let response = HTTPURLResponse(url: url,
                                           statusCode: stub.status,
                                           httpVersion: "HTTP/1.1",
                                           headerFields: stub.headers)!
            client?.urlProtocol(self,
                                didReceive: response,
                                cacheStoragePolicy: .notAllowed)
            for chunk in stub.chunks {
                if stub.interChunkDelay > 0 {
                    Thread.sleep(forTimeInterval: stub.interChunkDelay)
                }
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
