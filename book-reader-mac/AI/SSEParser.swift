import Foundation

/// One parsed Server-Sent Event. Per the SSE spec we accumulate `data:`
/// lines until a blank line dispatches the event. Comment lines (lines
/// that start with ":") and any unknown fields are ignored.
public struct SSEvent: Sendable, Equatable {
    public let event: String?
    public let data: String

    public init(event: String? = nil, data: String) {
        self.event = event
        self.data = data
    }
}

public enum SSEParser {
    /// Stream an `AsyncSequence<String>` of UTF-8 lines (the shape returned
    /// by `URLSession.bytes(for:).lines`) into discrete `SSEvent`s.
    public static func events<S: AsyncSequence>(
        from lines: S
    ) -> AsyncThrowingStream<SSEvent, Error> where S.Element == String {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var dataBuffer: [String] = []
                    var eventName: String?
                    for try await rawLine in lines {
                        // SSE field separator is colon. Treat a line starting
                        // with ":" as a comment and discard it.
                        let line = rawLine
                        if line.isEmpty {
                            if !dataBuffer.isEmpty {
                                continuation.yield(SSEvent(event: eventName,
                                                           data: dataBuffer.joined(separator: "\n")))
                            }
                            dataBuffer.removeAll(keepingCapacity: true)
                            eventName = nil
                            continue
                        }
                        if line.hasPrefix(":") { continue }
                        guard let colon = line.firstIndex(of: ":") else {
                            // Field with no value — ignore.
                            continue
                        }
                        let field = String(line[..<colon])
                        var value = String(line[line.index(after: colon)...])
                        if value.hasPrefix(" ") { value.removeFirst() }
                        switch field {
                        case "data":  dataBuffer.append(value)
                        case "event": eventName = value
                        default:      break
                        }
                    }
                    // EOF: flush any pending buffer.
                    if !dataBuffer.isEmpty {
                        continuation.yield(SSEvent(event: eventName,
                                                   data: dataBuffer.joined(separator: "\n")))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
