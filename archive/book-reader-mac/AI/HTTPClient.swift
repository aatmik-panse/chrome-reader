import Foundation

/// Thin seam around URLSession. Providers depend on this struct so tests
/// can inject `MockURLProtocol.makeSession()`.
public struct HTTPClient: Sendable {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Open a streaming connection. Returns the HTTPURLResponse plus an
    /// `AsyncSequence<String>` of UTF-8 lines.
    public func openStream(_ request: URLRequest) async throws -> (HTTPURLResponse, URLSession.AsyncBytes) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIRouterError.http(status: -1, body: "non-http response")
        }
        return (http, bytes)
    }
}
