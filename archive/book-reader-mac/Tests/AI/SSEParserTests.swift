import XCTest
@testable import InstantBookReader

final class SSEParserTests: XCTestCase {
    /// Wrap an array of strings as an `AsyncSequence<String>`.
    private func asyncLines(_ lines: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }
    }

    func testEmitsOneEventPerBlankLineSeparatedBlock() async throws {
        let stream = SSEParser.events(from: asyncLines([
            "data: hello",
            "",
            "data: world",
            "",
        ]))
        var seen: [SSEvent] = []
        for try await ev in stream { seen.append(ev) }
        XCTAssertEqual(seen, [SSEvent(data: "hello"), SSEvent(data: "world")])
    }

    func testCollapsesMultipleDataLinesWithNewlines() async throws {
        let stream = SSEParser.events(from: asyncLines([
            "data: line-1",
            "data: line-2",
            "",
        ]))
        var seen: [SSEvent] = []
        for try await ev in stream { seen.append(ev) }
        XCTAssertEqual(seen, [SSEvent(data: "line-1\nline-2")])
    }

    func testIgnoresCommentLines() async throws {
        let stream = SSEParser.events(from: asyncLines([
            ": keepalive",
            "data: a",
            "",
        ]))
        var seen: [SSEvent] = []
        for try await ev in stream { seen.append(ev) }
        XCTAssertEqual(seen, [SSEvent(data: "a")])
    }

    func testEventNameIsCaptured() async throws {
        let stream = SSEParser.events(from: asyncLines([
            "event: message_start",
            "data: payload",
            "",
        ]))
        var seen: [SSEvent] = []
        for try await ev in stream { seen.append(ev) }
        XCTAssertEqual(seen, [SSEvent(event: "message_start", data: "payload")])
    }

    func testFlushesTrailingBufferOnEOF() async throws {
        let stream = SSEParser.events(from: asyncLines([
            "data: trailing",
        ]))
        var seen: [SSEvent] = []
        for try await ev in stream { seen.append(ev) }
        XCTAssertEqual(seen, [SSEvent(data: "trailing")])
    }
}
