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
    /// Stream raw UTF-8 bytes (the shape returned by `URLSession.bytes(for:)`)
    /// into discrete `SSEvent`s. Internally splits on `\n` (handling `\r\n`)
    /// while preserving empty lines, which mark event boundaries.
    public static func events<S: AsyncSequence>(
        fromBytes bytes: S
    ) -> AsyncThrowingStream<SSEvent, Error> where S.Element == UInt8 {
        events(from: byteLines(bytes))
    }

    /// Adapter: convert an `AsyncSequence<UInt8>` into an `AsyncStream<String>`
    /// of UTF-8 lines that preserves empty lines.
    public static func byteLines<S: AsyncSequence>(
        _ bytes: S
    ) -> AsyncThrowingStream<String, Error> where S.Element == UInt8 {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var buffer: [UInt8] = []
                    for try await byte in bytes {
                        if byte == 0x0A { // '\n'
                            // Strip trailing CR for CRLF line endings.
                            if buffer.last == 0x0D { buffer.removeLast() }
                            let line = String(decoding: buffer, as: UTF8.self)
                            continuation.yield(line)
                            buffer.removeAll(keepingCapacity: true)
                        } else {
                            buffer.append(byte)
                        }
                    }
                    // Trailing partial line at EOF (no terminating newline).
                    if !buffer.isEmpty {
                        if buffer.last == 0x0D { buffer.removeLast() }
                        let line = String(decoding: buffer, as: UTF8.self)
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Stream an `AsyncSequence<String>` of UTF-8 lines into `SSEvent`s.
    /// Callers feeding this from `URLSession.bytes(for:).lines` must verify
    /// their `AsyncLineSequence` preserves empty lines; otherwise prefer
    /// `events(fromBytes:)`.
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
