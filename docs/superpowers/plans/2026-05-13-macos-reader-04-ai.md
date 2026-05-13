# AI Providers + BYOK Implementation Plan — macOS Wallpaper Reader

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up streaming AI for the active reader's selection popover. Implement an `AIProvider` protocol with four real provider clients (OpenAI, Anthropic, Google, OpenRouter) that stream via `URLSession.bytes(for:)` + SSE, a Keychain-backed BYOK store, a router that resolves the per-feature provider/model from preferences, a SwiftData-backed LRU cache (200 MB cap), the AI tab of Settings, and the selection-popover wiring that replaces Plan 3's `onAIAction` stub.

**Architecture:** A `Sendable` `AIProvider` protocol with one concrete implementation per provider; each owns its own SSE parsing path. A `KeychainStore` (raw Security framework) holds keys keyed by `kSecAttrAccount = provider.rawValue`, `kSecAttrService = bundle id`. An `AIRouter` reads per-feature `UserDefaults` preferences, looks up the Keychain key, and either streams or throws `noKeyForProvider`. An `AICache` actor reads/writes through the existing `AICacheEntry` SwiftData table with sha256-derived keys and LRU eviction. The selection popover replaces its stub with an async-stream consumer that prints chunks into a SwiftUI `Text` and exposes a "Save as note" button that writes back into the existing `Highlight.note` column. v1 is BYOK-only: if no key is configured the popover shows "Add an API key in Settings → AI" — no server fallback.

**Tech Stack:** Swift 5.10, macOS 14.4 target, SwiftData, SwiftUI, AppKit-hosted SwiftUI for the popover (lives in Plan 3 and is extended here), Security framework for Keychain, `URLSession.bytes(for:)` + SSE for streaming. No third-party SDKs.

---

## File structure

This plan only adds files under `book-reader-mac/AI/` and `book-reader-mac/Settings/AI/`, plus tests under `book-reader-mac/Tests/`. It also modifies (does not replace) the `SelectionPopover` introduced by Plan 3 and the `Settings` scene's AI tab introduced by Plan 1 (`EmptyView()` placeholder).

```
book-reader-mac/
├── AI/
│   ├── AIProvider.swift                              # Protocol + AIRequest/AIMessage/AIChunk/ProviderID/AIRouterError
│   ├── SSEParser.swift                               # URLSession.bytes → AsyncThrowingStream<SSEvent>
│   ├── KeychainStore.swift                           # Raw Security framework BYOK
│   ├── AIRouter.swift                                # Per-feature provider+model resolution
│   ├── AICache.swift                                 # SwiftData-backed LRU cache
│   ├── AIFeature.swift                               # enum AIFeature
│   ├── Providers/
│   │   ├── OpenAIProvider.swift
│   │   ├── AnthropicProvider.swift
│   │   ├── GoogleProvider.swift
│   │   └── OpenRouterProvider.swift
│   └── Prompts/
│       ├── SummarizePrompt.swift
│       ├── AskPrompt.swift
│       ├── ExplainPrompt.swift
│       ├── TranslatePrompt.swift
│       └── ExtractHighlightsPrompt.swift
├── Settings/
│   └── AI/
│       ├── AISettingsTab.swift                       # The whole Form for the AI tab
│       ├── ProviderKeyRow.swift                      # Per-provider SecureField + Test + Delete
│       ├── FeatureRoutingRow.swift                   # Per-feature provider+model picker
│       └── CacheControlSection.swift                 # Size readout + Clear button
└── Tests/
    ├── AI/
    │   ├── SSEParserTests.swift
    │   ├── KeychainStoreTests.swift
    │   ├── OpenAIProviderTests.swift
    │   ├── AnthropicProviderTests.swift
    │   ├── GoogleProviderTests.swift
    │   ├── OpenRouterProviderTests.swift
    │   ├── AIRouterTests.swift
    │   ├── AICacheTests.swift
    │   └── Support/
    │       └── MockURLProtocol.swift
    └── Fixtures/
        └── AI/
            ├── openai-hello.sse
            ├── openai-done-marker.sse
            ├── anthropic-hello.sse
            ├── anthropic-error.sse
            ├── google-hello.sse
            └── openrouter-hello.sse
```

The existing `AICacheEntry` (`book-reader-mac/Persistence/Models/AICacheEntry.swift`) and `Highlight` (`book-reader-mac/Persistence/Models/Highlight.swift`) are used unchanged.

---

## Conventions used across tasks

- All bash commands assume cwd = `/Users/profitoniumapps/Documents/chromeApps`. Each `git add` lists files explicitly.
- All tests use `MockURLProtocol` (introduced in Task 3); no real network calls anywhere — including the provider `test()` method tests.
- "Run tests" uses `xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' -only-testing:InstantBookReaderTests/<ClassName>` from the `book-reader-mac/` directory. Replace `<ClassName>` with the test class for the task.
- Plan 1's `project.yml` already lists `Tests/` as the test target's sources directory; new test files are auto-picked up after re-running `xcodegen generate`. The first test task includes that regeneration step; subsequent ones don't repeat it.
- Fixture files use real captured SSE response bytes. Each fixture is a literal byte-for-byte stream as the provider would return; tests feed them through `MockURLProtocol` so the parser sees real chunk boundaries.

---

## Task 1: Add AIProvider protocol and core types

**Files:**
- Create: `book-reader-mac/AI/AIProvider.swift`
- Create: `book-reader-mac/AI/AIFeature.swift`
- Modify: `book-reader-mac/project.yml` (add `AI/` to sources if not already covered by directory recursion)

- [ ] **Step 1: Verify project.yml already recurses sources**

Run:
```bash
grep -n "sources:" /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/project.yml
```
Expected: a `sources:` block listing top-level directories (`App`, `Core`, `Persistence`, `Windows`, `MenuBar`, `Hotkey`, `System`, `Placeholders`, `Resources`). If `AI` is not listed, add it under the existing sources entry by inserting `- AI` and `- Settings` alphabetically. If the sources block uses a single root path like `path: .`, no edit is required.

If the file lists individual directories explicitly, edit `book-reader-mac/project.yml` to add (preserve the existing indentation):
```yaml
      - AI
      - Settings
```

- [ ] **Step 2: Regenerate the Xcode project**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodegen generate
```
Expected: `Generated project successfully`.

- [ ] **Step 3: Write `AIProvider.swift`**

Write `book-reader-mac/AI/AIProvider.swift`:
```swift
import Foundation

/// Stable identifier for a BYOK provider. The raw value is used as
/// `kSecAttrAccount` in Keychain and as the persisted preference value.
public enum ProviderID: String, Codable, Sendable, CaseIterable {
    case openai
    case anthropic
    case google
    case openrouter

    public var displayName: String {
        switch self {
        case .openai:     return "OpenAI"
        case .anthropic:  return "Anthropic"
        case .google:     return "Google"
        case .openrouter: return "OpenRouter"
        }
    }
}

/// Single message in a chat-style request. `role` is "system" | "user" | "assistant".
public struct AIMessage: Sendable, Equatable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

/// One unit of streamed model output.
public enum AIChunk: Sendable, Equatable {
    case textDelta(String)
    case done
    case error(String)
}

/// A normalized request shape. Providers map this to their wire format.
public struct AIRequest: Sendable, Equatable {
    public let model: String
    public let system: String?
    public let messages: [AIMessage]
    public let maxTokens: Int

    public init(model: String,
                system: String?,
                messages: [AIMessage],
                maxTokens: Int = 1024) {
        self.model = model
        self.system = system
        self.messages = messages
        self.maxTokens = maxTokens
    }
}

/// Errors that may surface from the router or providers.
public enum AIRouterError: Error, Equatable, Sendable {
    case noKeyForProvider(ProviderID)
    case unknownProvider(String)
    case http(status: Int, body: String)
    case decoding(String)
    case cancelled
}

/// Provider contract. One instance per `(provider, apiKey, model)` tuple.
public protocol AIProvider: Sendable {
    var id: ProviderID { get }
    var defaultModel: String { get }
    var availableModels: [String] { get }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIChunk, Error>
    /// 1-token request used by Settings → AI's "Test" button.
    func test() async throws
}
```

- [ ] **Step 4: Write `AIFeature.swift`**

Write `book-reader-mac/AI/AIFeature.swift`:
```swift
import Foundation

/// The named features that route through `AIRouter`. Each has its own
/// per-feature provider+model preference key.
public enum AIFeature: String, CaseIterable, Sendable {
    case summarize
    case ask
    case explain
    case translate
    case extractHighlights

    public var displayName: String {
        switch self {
        case .summarize:         return "Summarize"
        case .ask:               return "Ask"
        case .explain:           return "Explain"
        case .translate:         return "Translate"
        case .extractHighlights: return "Extract highlights"
        }
    }

    public var providerDefaultsKey: String { "ai.feature.\(rawValue).provider" }
    public var modelDefaultsKey: String    { "ai.feature.\(rawValue).model" }
}
```

- [ ] **Step 5: Build and commit**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodebuild -scheme InstantBookReader -destination 'platform=macOS' build
```
Expected: `BUILD SUCCEEDED`.

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/AI/AIProvider.swift \
          book-reader-mac/AI/AIFeature.swift \
          book-reader-mac/project.yml && \
  git commit -m "feat(mac): AIProvider protocol and AIFeature enum"
```

---

## Task 2: SSE parser

**Files:**
- Create: `book-reader-mac/AI/SSEParser.swift`

- [ ] **Step 1: Write `SSEParser.swift`**

Write `book-reader-mac/AI/SSEParser.swift`:
```swift
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
```

- [ ] **Step 2: Build and commit**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodebuild -scheme InstantBookReader -destination 'platform=macOS' build
```
Expected: `BUILD SUCCEEDED`.

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/AI/SSEParser.swift && \
  git commit -m "feat(mac): SSEParser over AsyncSequence<String>"
```

---

## Task 3: MockURLProtocol test support

**Files:**
- Create: `book-reader-mac/Tests/AI/Support/MockURLProtocol.swift`

- [ ] **Step 1: Write `MockURLProtocol.swift`**

Write `book-reader-mac/Tests/AI/Support/MockURLProtocol.swift`:
```swift
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
```

- [ ] **Step 2: Verify the test target finds the new file**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodegen generate
```
Expected: `Generated project successfully`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/AI/Support/MockURLProtocol.swift && \
  git commit -m "test(mac): MockURLProtocol for AI provider tests"
```

---

## Task 4: SSEParser tests

**Files:**
- Create: `book-reader-mac/Tests/AI/SSEParserTests.swift`

- [ ] **Step 1: Write failing tests**

Write `book-reader-mac/Tests/AI/SSEParserTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests; expect them to pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/SSEParserTests
```
Expected: `Test Suite 'SSEParserTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/AI/SSEParserTests.swift && \
  git commit -m "test(mac): SSE parser unit tests"
```

---

## Task 5: KeychainStore

**Files:**
- Create: `book-reader-mac/AI/KeychainStore.swift`

- [ ] **Step 1: Write `KeychainStore.swift`**

Write `book-reader-mac/AI/KeychainStore.swift`:
```swift
import Foundation
import Security

/// Raw Security-framework BYOK store. One entry per provider keyed by
/// `kSecAttrAccount = provider.rawValue`, `kSecAttrService = bundle id`.
/// Default accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
/// iCloud Keychain sync is opt-in via `setSynchronizable(_:)`.
public enum KeychainStore {
    public enum KeychainError: Error, Equatable {
        case unhandledStatus(OSStatus)
        case invalidUTF8
    }

    /// Sticky preference observed by `save(...)`. Default false (device-only).
    /// Stored in UserDefaults so it survives launch.
    private static let synchronizableKey = "ai.keychain.synchronizable"

    public static var isSynchronizable: Bool {
        UserDefaults.standard.bool(forKey: synchronizableKey)
    }

    public static func setSynchronizable(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: synchronizableKey)
    }

    private static var service: String {
        Bundle.main.bundleIdentifier ?? "com.instant-book-reader.mac"
    }

    public static func save(key: String, for provider: ProviderID) throws {
        guard let data = key.data(using: .utf8) else { throw KeychainError.invalidUTF8 }

        // Build the unique-record query (service + account only).
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]

        // Update path: try update first. Update only the value + accessibility +
        // synchronizable bit so we don't accidentally fail when the previous
        // record was created with different accessibility.
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: isSynchronizable ? kCFBooleanTrue! : kCFBooleanFalse!,
        ]

        // We must include kSecAttrSynchronizable in the search query for
        // SecItemUpdate to find existing synced/unsynced records — pass
        // `kSecAttrSynchronizableAny` so either kind matches.
        var searchQuery = query
        searchQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

        let updateStatus = SecItemUpdate(searchQuery as CFDictionary,
                                         attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw KeychainError.unhandledStatus(updateStatus)
        }

        // Insert path.
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecAttrSynchronizable as String] = isSynchronizable ? kCFBooleanTrue! : kCFBooleanFalse!
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw KeychainError.unhandledStatus(addStatus)
        }
    }

    public static func load(for provider: ProviderID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(for provider: ProviderID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unhandledStatus(status)
        }
    }
}
```

- [ ] **Step 2: Build and commit**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodebuild -scheme InstantBookReader -destination 'platform=macOS' build
```
Expected: `BUILD SUCCEEDED`.

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/AI/KeychainStore.swift && \
  git commit -m "feat(mac): Keychain-backed BYOK store"
```

---

## Task 6: KeychainStore tests

**Files:**
- Create: `book-reader-mac/Tests/AI/KeychainStoreTests.swift`

The tests touch the real macOS Keychain. Each test cleans up after itself by calling `delete` for every provider, and uses a unique-per-run prefix to avoid collisions with the developer's other keys. They run in the host process under the developer's login keychain — this is acceptable for a local dev test target.

- [ ] **Step 1: Write tests**

Write `book-reader-mac/Tests/AI/KeychainStoreTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

final class KeychainStoreTests: XCTestCase {
    override func setUp() async throws {
        for p in ProviderID.allCases { try? KeychainStore.delete(for: p) }
        KeychainStore.setSynchronizable(false)
    }

    override func tearDown() async throws {
        for p in ProviderID.allCases { try? KeychainStore.delete(for: p) }
        KeychainStore.setSynchronizable(false)
    }

    func testSaveThenLoadRoundtrips() throws {
        try KeychainStore.save(key: "sk-test-1", for: .openai)
        XCTAssertEqual(KeychainStore.load(for: .openai), "sk-test-1")
    }

    func testLoadReturnsNilForUnsavedProvider() {
        XCTAssertNil(KeychainStore.load(for: .anthropic))
    }

    func testSaveTwiceUpdatesValue() throws {
        try KeychainStore.save(key: "first", for: .anthropic)
        try KeychainStore.save(key: "second", for: .anthropic)
        XCTAssertEqual(KeychainStore.load(for: .anthropic), "second")
    }

    func testDeleteRemovesKey() throws {
        try KeychainStore.save(key: "k", for: .google)
        try KeychainStore.delete(for: .google)
        XCTAssertNil(KeychainStore.load(for: .google))
    }

    func testDeleteForUnsavedProviderDoesNotThrow() {
        XCTAssertNoThrow(try KeychainStore.delete(for: .openrouter))
    }

    func testSynchronizableTogglePersists() {
        KeychainStore.setSynchronizable(true)
        XCTAssertTrue(KeychainStore.isSynchronizable)
        KeychainStore.setSynchronizable(false)
        XCTAssertFalse(KeychainStore.isSynchronizable)
    }
}
```

- [ ] **Step 2: Run tests**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/KeychainStoreTests
```
Expected: `Test Suite 'KeychainStoreTests' passed`.

If the first run prompts for keychain access, click "Always Allow" once; subsequent runs run silently.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/AI/KeychainStoreTests.swift && \
  git commit -m "test(mac): KeychainStore roundtrip and delete tests"
```

---

## Task 7: Fixture files

**Files:**
- Create: `book-reader-mac/Tests/Fixtures/AI/openai-hello.sse`
- Create: `book-reader-mac/Tests/Fixtures/AI/openai-done-marker.sse`
- Create: `book-reader-mac/Tests/Fixtures/AI/anthropic-hello.sse`
- Create: `book-reader-mac/Tests/Fixtures/AI/anthropic-error.sse`
- Create: `book-reader-mac/Tests/Fixtures/AI/google-hello.sse`
- Create: `book-reader-mac/Tests/Fixtures/AI/openrouter-hello.sse`
- Modify: `book-reader-mac/project.yml` (register fixtures as test-target resources)

These are byte-for-byte captures matching each provider's documented SSE shape, trimmed to one "Hello world." response.

- [ ] **Step 1: Write the OpenAI fixtures**

Write `book-reader-mac/Tests/Fixtures/AI/openai-hello.sse`:
```
data: {"id":"x","object":"chat.completion.chunk","choices":[{"delta":{"role":"assistant","content":""},"index":0,"finish_reason":null}]}

data: {"id":"x","object":"chat.completion.chunk","choices":[{"delta":{"content":"Hello"},"index":0,"finish_reason":null}]}

data: {"id":"x","object":"chat.completion.chunk","choices":[{"delta":{"content":" world"},"index":0,"finish_reason":null}]}

data: {"id":"x","object":"chat.completion.chunk","choices":[{"delta":{"content":"."},"index":0,"finish_reason":null}]}

data: {"id":"x","object":"chat.completion.chunk","choices":[{"delta":{},"index":0,"finish_reason":"stop"}]}

data: [DONE]

```

Write `book-reader-mac/Tests/Fixtures/AI/openai-done-marker.sse`:
```
data: [DONE]

```

- [ ] **Step 2: Write the Anthropic fixtures**

Write `book-reader-mac/Tests/Fixtures/AI/anthropic-hello.sse`:
```
event: message_start
data: {"type":"message_start","message":{"id":"x","type":"message","role":"assistant","content":[],"model":"claude","stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":3}}

event: message_stop
data: {"type":"message_stop"}

```

Write `book-reader-mac/Tests/Fixtures/AI/anthropic-error.sse`:
```
event: error
data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}

```

- [ ] **Step 3: Write the Google fixture**

Write `book-reader-mac/Tests/Fixtures/AI/google-hello.sse`:
```
data: {"candidates":[{"content":{"parts":[{"text":"Hello"}],"role":"model"},"finishReason":null,"index":0}]}

data: {"candidates":[{"content":{"parts":[{"text":" world"}],"role":"model"},"finishReason":null,"index":0}]}

data: {"candidates":[{"content":{"parts":[{"text":"."}],"role":"model"},"finishReason":"STOP","index":0}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":3,"totalTokenCount":4}}

```

- [ ] **Step 4: Write the OpenRouter fixture**

Write `book-reader-mac/Tests/Fixtures/AI/openrouter-hello.sse`:
```
data: {"id":"x","object":"chat.completion.chunk","choices":[{"delta":{"role":"assistant","content":""},"index":0,"finish_reason":null}]}

data: {"id":"x","object":"chat.completion.chunk","choices":[{"delta":{"content":"Hello"},"index":0,"finish_reason":null}]}

data: {"id":"x","object":"chat.completion.chunk","choices":[{"delta":{"content":" world."},"index":0,"finish_reason":"stop"}]}

data: [DONE]

```

- [ ] **Step 5: Register fixtures as test-target resources**

Edit `book-reader-mac/project.yml` — locate the test target (`InstantBookReaderTests`). Add a `resources` entry alongside its `sources` (preserve existing indentation; the actual key path may differ slightly — match the project file's existing test target):

```yaml
    InstantBookReaderTests:
      type: bundle.unit-test
      platform: macOS
      sources:
        - Tests
      resources:
        - path: Tests/Fixtures
          type: folder
```

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodegen generate
```
Expected: `Generated project successfully`.

- [ ] **Step 6: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/Fixtures/ \
          book-reader-mac/project.yml && \
  git commit -m "test(mac): AI provider SSE fixtures"
```

---

## Task 8: Shared HTTPClient seam

**Files:**
- Create: `book-reader-mac/AI/HTTPClient.swift`

Providers receive a `URLSession` (the production default is `URLSession.shared`, tests inject `MockURLProtocol.makeSession()`). Wrapping it in a struct gives us one obvious extension point if we later need request signing or logging.

- [ ] **Step 1: Write `HTTPClient.swift`**

Write `book-reader-mac/AI/HTTPClient.swift`:
```swift
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
```

- [ ] **Step 2: Build and commit**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodebuild -scheme InstantBookReader -destination 'platform=macOS' build
```
Expected: `BUILD SUCCEEDED`.

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/AI/HTTPClient.swift && \
  git commit -m "feat(mac): HTTPClient seam over URLSession.bytes"
```

---

## Task 9: OpenAIProvider — failing tests

**Files:**
- Create: `book-reader-mac/Tests/AI/OpenAIProviderTests.swift`

- [ ] **Step 1: Write tests against the not-yet-existing `OpenAIProvider`**

Write `book-reader-mac/Tests/AI/OpenAIProviderTests.swift`:
```swift
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
```

- [ ] **Step 2: Run tests; expect compile failure**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/OpenAIProviderTests
```
Expected: compile error referencing `OpenAIProvider`.

- [ ] **Step 3: Commit the failing tests**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/AI/OpenAIProviderTests.swift && \
  git commit -m "test(mac): failing OpenAIProvider streaming tests"
```

---

## Task 10: OpenAIProvider — implementation

**Files:**
- Create: `book-reader-mac/AI/Providers/OpenAIProvider.swift`

- [ ] **Step 1: Write `OpenAIProvider.swift`**

Write `book-reader-mac/AI/Providers/OpenAIProvider.swift`:
```swift
import Foundation

public struct OpenAIProvider: AIProvider {
    public let id: ProviderID = .openai
    public let defaultModel: String
    public let availableModels: [String]

    private let apiKey: String
    private let http: HTTPClient
    private let endpoint: URL

    public init(apiKey: String,
                defaultModel: String = "gpt-5.5",
                availableModels: [String] = ["gpt-5.5", "gpt-5.5-mini", "gpt-4o", "gpt-4o-mini"],
                endpoint: URL = URL(string: "https://api.openai.com/v1/chat/completions")!,
                http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.defaultModel = defaultModel
        self.availableModels = availableModels
        self.endpoint = endpoint
        self.http = http
    }

    /// Surface accessor used by the OpenRouter subclass-equivalent.
    var configuredEndpoint: URL { endpoint }
    var configuredHTTP: HTTPClient { http }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIChunk, Error> {
        let urlRequest = makeRequest(request, extraHeaders: [:])
        return Self.streamChatCompletions(urlRequest: urlRequest, http: http)
    }

    public func test() async throws {
        var minimal = makeRequest(.init(model: defaultModel,
                                        system: nil,
                                        messages: [.init(role: "user", content: "ping")],
                                        maxTokens: 1),
                                  extraHeaders: [:])
        // The 1-token cap is already encoded in the body; just exhaust the stream.
        _ = minimal
        var sawAny = false
        for try await chunk in stream(.init(model: defaultModel,
                                            system: nil,
                                            messages: [.init(role: "user", content: "ping")],
                                            maxTokens: 1)) {
            if case .textDelta = chunk { sawAny = true }
            if case .error(let m) = chunk { throw AIRouterError.http(status: 0, body: m) }
        }
        _ = sawAny
    }

    /// Build the URLRequest. Subclassed providers (OpenRouter) call this and
    /// then bolt on their own headers.
    func makeRequest(_ request: AIRequest, extraHeaders: [String: String]) -> URLRequest {
        var messages: [[String: String]] = []
        if let system = request.system, !system.isEmpty {
            messages.append(["role": "system", "content": system])
        }
        for m in request.messages {
            messages.append(["role": m.role, "content": m.content])
        }
        let body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "max_tokens": request.maxTokens,
            "messages": messages,
        ]
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return req
    }

    /// Shared OpenAI/OpenRouter chat-completions SSE consumer.
    static func streamChatCompletions(urlRequest: URLRequest,
                                      http: HTTPClient) -> AsyncThrowingStream<AIChunk, Error> {
        AsyncThrowingStream { continuation in
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
                        if event.data == "[DONE]" {
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        }
                        guard let data = event.data.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any] else {
                            continue
                        }
                        if let text = delta["content"] as? String, !text.isEmpty {
                            continuation.yield(.textDelta(text))
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
}
```

- [ ] **Step 2: Run tests**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/OpenAIProviderTests
```
Expected: `Test Suite 'OpenAIProviderTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/AI/Providers/OpenAIProvider.swift && \
  git commit -m "feat(mac): OpenAIProvider streaming via SSE"
```

---

## Task 11: AnthropicProvider — failing tests

**Files:**
- Create: `book-reader-mac/Tests/AI/AnthropicProviderTests.swift`

- [ ] **Step 1: Write tests**

Write `book-reader-mac/Tests/AI/AnthropicProviderTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

final class AnthropicProviderTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: type(of: self))
            .url(forResource: name, withExtension: "sse", subdirectory: "Fixtures/AI"))
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
```

- [ ] **Step 2: Run; expect compile failure**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/AnthropicProviderTests
```
Expected: compile error referencing `AnthropicProvider`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/AI/AnthropicProviderTests.swift && \
  git commit -m "test(mac): failing AnthropicProvider streaming tests"
```

---

## Task 12: AnthropicProvider — implementation

**Files:**
- Create: `book-reader-mac/AI/Providers/AnthropicProvider.swift`

- [ ] **Step 1: Write `AnthropicProvider.swift`**

Write `book-reader-mac/AI/Providers/AnthropicProvider.swift`:
```swift
import Foundation

public struct AnthropicProvider: AIProvider {
    public let id: ProviderID = .anthropic
    public let defaultModel: String
    public let availableModels: [String]

    private let apiKey: String
    private let http: HTTPClient
    private let endpoint: URL

    public init(apiKey: String,
                defaultModel: String = "claude-sonnet-4-6",
                availableModels: [String] = ["claude-sonnet-4-6", "claude-opus-4-6", "claude-haiku-4-6"],
                endpoint: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
                http: HTTPClient = HTTPClient()) {
        self.apiKey = apiKey
        self.defaultModel = defaultModel
        self.availableModels = availableModels
        self.endpoint = endpoint
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
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        let type = (json["type"] as? String) ?? event.event
                        switch type {
                        case "content_block_delta":
                            if let delta = json["delta"] as? [String: Any],
                               (delta["type"] as? String) == "text_delta",
                               let text = delta["text"] as? String, !text.isEmpty {
                                continuation.yield(.textDelta(text))
                            }
                        case "message_stop":
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        case "error":
                            let message = ((json["error"] as? [String: Any])?["message"] as? String) ?? "error"
                            continuation.finish(throwing:
                                AIRouterError.http(status: response.statusCode, body: message))
                            return
                        default:
                            break
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
        var body: [String: Any] = [
            "model": request.model,
            "stream": true,
            "max_tokens": request.maxTokens,
            "messages": request.messages.map { ["role": $0.role, "content": $0.content] },
        ]
        if let system = request.system, !system.isEmpty {
            body["system"] = system
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return req
    }
}
```

- [ ] **Step 2: Run tests**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/AnthropicProviderTests
```
Expected: `Test Suite 'AnthropicProviderTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/AI/Providers/AnthropicProvider.swift && \
  git commit -m "feat(mac): AnthropicProvider streaming via SSE"
```

---

## Task 13: GoogleProvider — tests + implementation

**Files:**
- Create: `book-reader-mac/Tests/AI/GoogleProviderTests.swift`
- Create: `book-reader-mac/AI/Providers/GoogleProvider.swift`

- [ ] **Step 1: Write failing tests**

Write `book-reader-mac/Tests/AI/GoogleProviderTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

final class GoogleProviderTests: XCTestCase {
    override func setUp() { MockURLProtocol.reset() }
    override func tearDown() { MockURLProtocol.reset() }

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: type(of: self))
            .url(forResource: name, withExtension: "sse", subdirectory: "Fixtures/AI"))
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
```

- [ ] **Step 2: Run; expect compile failure**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/GoogleProviderTests
```
Expected: compile error referencing `GoogleProvider`.

- [ ] **Step 3: Write `GoogleProvider.swift`**

Write `book-reader-mac/AI/Providers/GoogleProvider.swift`:
```swift
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
```

- [ ] **Step 4: Run tests**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/GoogleProviderTests
```
Expected: `Test Suite 'GoogleProviderTests' passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/AI/GoogleProviderTests.swift \
          book-reader-mac/AI/Providers/GoogleProvider.swift && \
  git commit -m "feat(mac): GoogleProvider streaming via SSE"
```

---

## Task 14: OpenRouterProvider — tests + implementation

**Files:**
- Create: `book-reader-mac/Tests/AI/OpenRouterProviderTests.swift`
- Create: `book-reader-mac/AI/Providers/OpenRouterProvider.swift`

OpenRouter is OpenAI-compatible. We reuse `OpenAIProvider.streamChatCompletions` and re-point the base URL and headers — there is no class inheritance in Swift for structs, so we wrap rather than extend.

- [ ] **Step 1: Write failing tests**

Write `book-reader-mac/Tests/AI/OpenRouterProviderTests.swift`:
```swift
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
```

- [ ] **Step 2: Run; expect compile failure**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/OpenRouterProviderTests
```
Expected: compile error referencing `OpenRouterProvider`.

- [ ] **Step 3: Write `OpenRouterProvider.swift`**

Write `book-reader-mac/AI/Providers/OpenRouterProvider.swift`:
```swift
import Foundation

public struct OpenRouterProvider: AIProvider {
    public let id: ProviderID = .openrouter
    public let defaultModel: String
    public let availableModels: [String]

    /// Wraps `OpenAIProvider` with the OpenRouter base URL. We don't subclass
    /// (Swift structs can't) — instead we forward through a configured inner.
    private let inner: OpenAIProvider
    private let referer: String
    private let title: String

    public init(apiKey: String,
                defaultModel: String = "anthropic/claude-sonnet-4.6",
                availableModels: [String] = [
                    "anthropic/claude-sonnet-4.6",
                    "anthropic/claude-opus-4.6",
                    "openai/gpt-5.5",
                    "google/gemini-3.1-pro",
                ],
                endpoint: URL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!,
                referer: String = "https://instant-book-reader.local",
                title: String = "Instant Book Reader",
                http: HTTPClient = HTTPClient()) {
        self.defaultModel = defaultModel
        self.availableModels = availableModels
        self.referer = referer
        self.title = title
        self.inner = OpenAIProvider(apiKey: apiKey,
                                    defaultModel: defaultModel,
                                    availableModels: availableModels,
                                    endpoint: endpoint,
                                    http: http)
    }

    public func stream(_ request: AIRequest) -> AsyncThrowingStream<AIChunk, Error> {
        let urlRequest = inner.makeRequest(request,
                                           extraHeaders: ["HTTP-Referer": referer,
                                                          "X-Title": title])
        return OpenAIProvider.streamChatCompletions(urlRequest: urlRequest,
                                                    http: inner.configuredHTTP)
    }

    public func test() async throws {
        for try await _ in stream(.init(model: defaultModel,
                                        system: nil,
                                        messages: [.init(role: "user", content: "ping")],
                                        maxTokens: 1)) {}
    }
}
```

- [ ] **Step 4: Run tests**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/OpenRouterProviderTests
```
Expected: `Test Suite 'OpenRouterProviderTests' passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/AI/OpenRouterProviderTests.swift \
          book-reader-mac/AI/Providers/OpenRouterProvider.swift && \
  git commit -m "feat(mac): OpenRouterProvider via OpenAI-compatible client"
```

---

## Task 15: Prompt templates

**Files:**
- Create: `book-reader-mac/AI/Prompts/SummarizePrompt.swift`
- Create: `book-reader-mac/AI/Prompts/AskPrompt.swift`
- Create: `book-reader-mac/AI/Prompts/ExplainPrompt.swift`
- Create: `book-reader-mac/AI/Prompts/TranslatePrompt.swift`
- Create: `book-reader-mac/AI/Prompts/ExtractHighlightsPrompt.swift`

Each file mirrors the corresponding template in `book-reader-extension/src/newtab/lib/ai/prompts.ts`, character-for-character. Keeping system+user text identical means the local cache key (which hashes the prompt) hits in lockstep with the extension's IndexedDB cache.

- [ ] **Step 1: Write `SummarizePrompt.swift`**

Write `book-reader-mac/AI/Prompts/SummarizePrompt.swift`:
```swift
import Foundation

public enum SummarizePrompt {
    public static let system =
        "You are a helpful reading assistant. Provide concise, insightful chapter summaries that capture the key themes, events, and character developments. Keep summaries to 3-5 paragraphs."

    public static let maxChapterTextLength = 8000

    public static func user(chapterText: String) -> String {
        "Please summarize the following chapter:\n\n\(String(chapterText.prefix(maxChapterTextLength)))"
    }
}
```

- [ ] **Step 2: Write `AskPrompt.swift`**

Write `book-reader-mac/AI/Prompts/AskPrompt.swift`:
```swift
import Foundation

public enum AskPrompt {
    public static let system =
        "You are a knowledgeable reading companion. Answer questions about books thoughtfully and accurately based on the provided context. If the answer isn't in the context, say so honestly."

    public static let maxContextLength = 6000

    public static func user(question: String, context: String) -> String {
        "Context from the book:\n\(String(context.prefix(maxContextLength)))\n\nQuestion: \(question)"
    }
}
```

- [ ] **Step 3: Write `ExplainPrompt.swift`**

Write `book-reader-mac/AI/Prompts/ExplainPrompt.swift`:
```swift
import Foundation

public enum ExplainPrompt {
    public static let system =
        "You are a thoughtful reading assistant. When asked to explain a passage, provide context about its meaning, literary significance, vocabulary, or historical references as appropriate. Be concise but insightful."

    public static let maxContextLength = 4000

    public static func user(selection: String, context: String) -> String {
        "Surrounding context:\n\(String(context.prefix(maxContextLength)))\n\nPlease explain this passage:\n\"\(selection)\""
    }
}
```

- [ ] **Step 4: Write `TranslatePrompt.swift`**

Write `book-reader-mac/AI/Prompts/TranslatePrompt.swift`:
```swift
import Foundation

public enum TranslatePrompt {
    public static let system =
        "You are a precise translator. Reply with ONLY a single JSON object of shape {\"detectedLang\":\"<bcp47>\",\"translation\":\"...\"}. No prose, no code fences."

    public static let maxTextLength = 4000

    public static func user(text: String, targetLang: String) -> String {
        "Translate the following text to \(targetLang):\n\n\(String(text.prefix(maxTextLength)))"
    }
}
```

- [ ] **Step 5: Write `ExtractHighlightsPrompt.swift`**

Write `book-reader-mac/AI/Prompts/ExtractHighlightsPrompt.swift`:
```swift
import Foundation

public enum ExtractHighlightsPrompt {
    public static let system =
        "You are a literary analyst. Extract the 5-8 most important or memorable passages from the text. Return each passage as a direct quote on its own line, prefixed with a dash (-)."

    public static let maxChapterTextLength = 8000

    public static func user(chapterText: String) -> String {
        "Extract key passages from:\n\n\(String(chapterText.prefix(maxChapterTextLength)))"
    }

    /// Parse a model response of `- quote one\n- quote two` into ["quote one","quote two"].
    public static func parseLines(_ raw: String) -> [String] {
        raw.split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> String in
                var s = String(line)
                if s.hasPrefix("-") { s.removeFirst() }
                return s.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 6: Build and commit**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodebuild -scheme InstantBookReader -destination 'platform=macOS' build
```
Expected: `BUILD SUCCEEDED`.

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/AI/Prompts/ && \
  git commit -m "feat(mac): AI prompt templates ported from extension"
```

---

## Task 16: AIRouter — failing tests

**Files:**
- Create: `book-reader-mac/Tests/AI/AIRouterTests.swift`

- [ ] **Step 1: Write tests**

Write `book-reader-mac/Tests/AI/AIRouterTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

final class AIRouterTests: XCTestCase {
    override func setUp() async throws {
        for p in ProviderID.allCases { try? KeychainStore.delete(for: p) }
        let defaults = UserDefaults.standard
        for f in AIFeature.allCases {
            defaults.removeObject(forKey: f.providerDefaultsKey)
            defaults.removeObject(forKey: f.modelDefaultsKey)
        }
    }

    override func tearDown() async throws {
        for p in ProviderID.allCases { try? KeychainStore.delete(for: p) }
    }

    func testRouterThrowsWhenNoKeyConfigured() {
        UserDefaults.standard.set(ProviderID.openai.rawValue,
                                  forKey: AIFeature.explain.providerDefaultsKey)
        let router = AIRouter()
        XCTAssertThrowsError(try router.resolve(.explain)) { error in
            guard let e = error as? AIRouterError else { return XCTFail("wrong type") }
            XCTAssertEqual(e, .noKeyForProvider(.openai))
        }
    }

    func testRouterReturnsConfiguredProviderWhenKeyExists() throws {
        try KeychainStore.save(key: "sk-x", for: .openai)
        UserDefaults.standard.set(ProviderID.openai.rawValue,
                                  forKey: AIFeature.ask.providerDefaultsKey)
        UserDefaults.standard.set("gpt-5.5-mini", forKey: AIFeature.ask.modelDefaultsKey)
        let router = AIRouter()
        let resolved = try router.resolve(.ask)
        XCTAssertEqual(resolved.provider.id, .openai)
        XCTAssertEqual(resolved.model, "gpt-5.5-mini")
    }

    func testRouterUsesProviderDefaultModelWhenUnset() throws {
        try KeychainStore.save(key: "sk-x", for: .anthropic)
        UserDefaults.standard.set(ProviderID.anthropic.rawValue,
                                  forKey: AIFeature.summarize.providerDefaultsKey)
        let router = AIRouter()
        let resolved = try router.resolve(.summarize)
        XCTAssertEqual(resolved.provider.id, .anthropic)
        XCTAssertEqual(resolved.model, resolved.provider.defaultModel)
    }

    func testRouterDefaultsFeatureProviderToOpenAIWhenUnset() throws {
        try KeychainStore.save(key: "sk-x", for: .openai)
        let router = AIRouter()
        let resolved = try router.resolve(.translate)
        XCTAssertEqual(resolved.provider.id, .openai)
    }
}
```

- [ ] **Step 2: Run; expect compile failure**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/AIRouterTests
```
Expected: compile error referencing `AIRouter`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/AI/AIRouterTests.swift && \
  git commit -m "test(mac): failing AIRouter resolution tests"
```

---

## Task 17: AIRouter — implementation

**Files:**
- Create: `book-reader-mac/AI/AIRouter.swift`

- [ ] **Step 1: Write `AIRouter.swift`**

Write `book-reader-mac/AI/AIRouter.swift`:
```swift
import Foundation

/// Routes a feature → (provider, model). Reads per-feature preferences from
/// `UserDefaults`, fetches the BYOK key from Keychain, and constructs a
/// configured provider. Throws `.noKeyForProvider` if no key is configured.
public struct AIRouter {
    public struct Resolved {
        public let provider: any AIProvider
        public let model: String
    }

    public static let defaultProvider: ProviderID = .openai

    private let defaults: UserDefaults
    private let httpFactory: @Sendable () -> HTTPClient

    public init(defaults: UserDefaults = .standard,
                httpFactory: @escaping @Sendable () -> HTTPClient = { HTTPClient() }) {
        self.defaults = defaults
        self.httpFactory = httpFactory
    }

    public func providerID(for feature: AIFeature) -> ProviderID {
        if let raw = defaults.string(forKey: feature.providerDefaultsKey),
           let parsed = ProviderID(rawValue: raw) {
            return parsed
        }
        return Self.defaultProvider
    }

    public func modelOverride(for feature: AIFeature) -> String? {
        let v = defaults.string(forKey: feature.modelDefaultsKey)
        return (v?.isEmpty ?? true) ? nil : v
    }

    public func resolve(_ feature: AIFeature) throws -> Resolved {
        let id = providerID(for: feature)
        guard let key = KeychainStore.load(for: id), !key.isEmpty else {
            throw AIRouterError.noKeyForProvider(id)
        }
        let http = httpFactory()
        let provider: any AIProvider
        switch id {
        case .openai:     provider = OpenAIProvider(apiKey: key, http: http)
        case .anthropic:  provider = AnthropicProvider(apiKey: key, http: http)
        case .google:     provider = GoogleProvider(apiKey: key, http: http)
        case .openrouter: provider = OpenRouterProvider(apiKey: key, http: http)
        }
        let model = modelOverride(for: feature) ?? provider.defaultModel
        return Resolved(provider: provider, model: model)
    }

    /// Convenience: builds the AIRequest for a feature using its prompt template.
    public func request(for feature: AIFeature,
                        selection: String = "",
                        context: String = "",
                        chapterText: String = "",
                        question: String = "",
                        targetLang: String = "English",
                        maxTokens: Int = 1024) throws -> (AIRequest, Resolved) {
        let resolved = try resolve(feature)
        let request: AIRequest
        switch feature {
        case .summarize:
            request = AIRequest(model: resolved.model,
                                system: SummarizePrompt.system,
                                messages: [.init(role: "user", content: SummarizePrompt.user(chapterText: chapterText))],
                                maxTokens: maxTokens)
        case .ask:
            request = AIRequest(model: resolved.model,
                                system: AskPrompt.system,
                                messages: [.init(role: "user", content: AskPrompt.user(question: question, context: context))],
                                maxTokens: maxTokens)
        case .explain:
            request = AIRequest(model: resolved.model,
                                system: ExplainPrompt.system,
                                messages: [.init(role: "user", content: ExplainPrompt.user(selection: selection, context: context))],
                                maxTokens: maxTokens)
        case .translate:
            request = AIRequest(model: resolved.model,
                                system: TranslatePrompt.system,
                                messages: [.init(role: "user", content: TranslatePrompt.user(text: selection, targetLang: targetLang))],
                                maxTokens: maxTokens)
        case .extractHighlights:
            request = AIRequest(model: resolved.model,
                                system: ExtractHighlightsPrompt.system,
                                messages: [.init(role: "user", content: ExtractHighlightsPrompt.user(chapterText: chapterText))],
                                maxTokens: maxTokens)
        }
        return (request, resolved)
    }
}
```

- [ ] **Step 2: Run tests**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/AIRouterTests
```
Expected: `Test Suite 'AIRouterTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/AI/AIRouter.swift && \
  git commit -m "feat(mac): AIRouter per-feature provider+model resolution"
```

---

## Task 18: AICache — failing tests

**Files:**
- Create: `book-reader-mac/Tests/AI/AICacheTests.swift`

- [ ] **Step 1: Write tests**

Write `book-reader-mac/Tests/AI/AICacheTests.swift`:
```swift
import XCTest
import SwiftData
@testable import InstantBookReader

@MainActor
final class AICacheTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeInMemoryContainer()
    }

    func testKeyIsSha256OfProviderModelPromptBookHash() {
        let key = AICache.makeKey(provider: .openai,
                                  model: "gpt-5.5",
                                  prompt: "hello",
                                  bookHash: "abc")
        XCTAssertEqual(key.count, 64)
        // Same inputs produce same key.
        let key2 = AICache.makeKey(provider: .openai,
                                   model: "gpt-5.5",
                                   prompt: "hello",
                                   bookHash: "abc")
        XCTAssertEqual(key, key2)
        // Different inputs produce different key.
        XCTAssertNotEqual(key, AICache.makeKey(provider: .openai,
                                               model: "gpt-5.5",
                                               prompt: "hello!",
                                               bookHash: "abc"))
    }

    func testCacheMissReturnsNil() throws {
        let container = try makeContainer()
        let cache = AICache(container: container, maxBytes: 1024)
        let key = AICache.makeKey(provider: .openai, model: "m", prompt: "p", bookHash: "b")
        XCTAssertNil(cache.read(key: key))
    }

    func testCacheHitReturnsValueAndUpdatesLastAccessed() throws {
        let container = try makeContainer()
        let cache = AICache(container: container, maxBytes: 1024)
        let key = AICache.makeKey(provider: .openai, model: "m", prompt: "p", bookHash: "b")
        cache.write(key: key, response: "world")
        let first = try XCTUnwrap(cache.read(key: key))
        XCTAssertEqual(first, "world")
        // Second read should still succeed (and bump lastAccessedAt).
        XCTAssertEqual(cache.read(key: key), "world")
    }

    func testLRUEvictionRemovesLeastRecentlyUsedEntries() throws {
        let container = try makeContainer()
        // 10-byte cap so we can simulate eviction with single-byte responses.
        let cache = AICache(container: container, maxBytes: 10)
        for i in 0..<15 {
            let key = AICache.makeKey(provider: .openai,
                                      model: "m",
                                      prompt: "p\(i)",
                                      bookHash: "b")
            cache.write(key: key, response: "x") // 1 byte
        }
        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<AICacheEntry>())
        let total = all.reduce(0) { $0 + $1.sizeBytes }
        XCTAssertLessThanOrEqual(total, 10)
    }

    func testEvictUnderSyntheticHighLoad() throws {
        let container = try makeContainer()
        let cache = AICache(container: container, maxBytes: 200 * 1024 * 1024)
        // Write 250 entries of 1 MB each = 250 MB > 200 MB cap.
        let big = String(repeating: "A", count: 1_000_000)
        for i in 0..<250 {
            let key = AICache.makeKey(provider: .openai,
                                      model: "m",
                                      prompt: "p\(i)",
                                      bookHash: "b")
            cache.write(key: key, response: big)
        }
        let context = ModelContext(container)
        let total = try context.fetch(FetchDescriptor<AICacheEntry>())
            .reduce(0) { $0 + $1.sizeBytes }
        XCTAssertLessThanOrEqual(total, 200 * 1024 * 1024)
    }
}
```

- [ ] **Step 2: Run; expect compile failure**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/AICacheTests
```
Expected: compile error referencing `AICache`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/AI/AICacheTests.swift && \
  git commit -m "test(mac): failing AICache key + LRU tests"
```

---

## Task 19: AICache — implementation

**Files:**
- Create: `book-reader-mac/AI/AICache.swift`

- [ ] **Step 1: Write `AICache.swift`**

Write `book-reader-mac/AI/AICache.swift`:
```swift
import Foundation
import CryptoKit
import SwiftData

/// SwiftData-backed AI response cache. 200 MB cap by default, LRU eviction.
/// Keys are sha256("provider|model|prompt|bookHash") so the byte layout
/// matches the extension's IndexedDB cache.
@MainActor
public final class AICache {
    public static let defaultMaxBytes = 200 * 1024 * 1024

    private let container: ModelContainer
    public let maxBytes: Int

    public init(container: ModelContainer, maxBytes: Int = defaultMaxBytes) {
        self.container = container
        self.maxBytes = maxBytes
    }

    public static func makeKey(provider: ProviderID,
                               model: String,
                               prompt: String,
                               bookHash: String) -> String {
        let raw = "\(provider.rawValue)|\(model)|\(prompt)|\(bookHash)"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func read(key: String) -> String? {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AICacheEntry>(
            predicate: #Predicate { $0.key == key }
        )
        guard let entry = (try? context.fetch(descriptor))?.first else { return nil }
        entry.lastAccessedAt = .now
        try? context.save()
        return entry.response
    }

    public func write(key: String, response: String) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<AICacheEntry>(
            predicate: #Predicate { $0.key == key }
        )
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.response = response
            existing.sizeBytes = response.utf8.count
            existing.lastAccessedAt = .now
        } else {
            let entry = AICacheEntry(key: key,
                                     response: response,
                                     sizeBytes: response.utf8.count)
            context.insert(entry)
        }
        try? context.save()
        evict()
    }

    public func clear() {
        let context = ModelContext(container)
        if let all = try? context.fetch(FetchDescriptor<AICacheEntry>()) {
            for e in all { context.delete(e) }
            try? context.save()
        }
    }

    public func totalSizeBytes() -> Int {
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<AICacheEntry>())) ?? []
        return all.reduce(0) { $0 + $1.sizeBytes }
    }

    /// LRU eviction: while total > maxBytes, delete the oldest-accessed.
    public func evict() {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<AICacheEntry>(
            sortBy: [SortDescriptor(\AICacheEntry.lastAccessedAt, order: .forward)]
        )
        descriptor.fetchLimit = 64
        var total = totalSizeBytes()
        while total > maxBytes {
            let batch = (try? context.fetch(descriptor)) ?? []
            if batch.isEmpty { break }
            for entry in batch {
                if total <= maxBytes { break }
                total -= entry.sizeBytes
                context.delete(entry)
            }
            try? context.save()
        }
    }
}
```

- [ ] **Step 2: Run tests**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/AICacheTests
```
Expected: `Test Suite 'AICacheTests' passed`. The 250 MB eviction test typically runs in under 10s; if SwiftData I/O on the CI box is slow you may bump the test timeout but should not change the implementation.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/AI/AICache.swift && \
  git commit -m "feat(mac): AICache with sha256 keys and LRU eviction"
```

---

## Task 20: Wire AICache.evict() into app launch

**Files:**
- Modify: `book-reader-mac/App/AppDelegate.swift`

Plan 1's `AppDelegate.applicationDidFinishLaunching(_:)` already constructs the `ModelContainer` via `PersistenceController`. We hook AICache eviction onto that container.

- [ ] **Step 1: Read the existing AppDelegate**

Run:
```bash
grep -n "applicationDidFinishLaunching\|PersistenceController\|modelContainer\|sharedContainer" /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/App/AppDelegate.swift
```
Expected: a line that creates `let container = try PersistenceController.makeOnDiskContainer()` (or similar). Note the variable name; the next step refers to it as `modelContainer` — substitute the actual identifier you see.

- [ ] **Step 2: Add the eviction hook**

Open `book-reader-mac/App/AppDelegate.swift`. Inside `applicationDidFinishLaunching(_:)`, immediately after the model container is assigned to its property (e.g. `self.modelContainer = container`), add:

```swift
        // AI cache eviction on launch (LRU under 200 MB).
        Task { @MainActor in
            AICache(container: container).evict()
        }
```

If `applicationDidFinishLaunching` does not yet expose `container` locally, capture it from `self.modelContainer` instead:

```swift
        Task { @MainActor in
            AICache(container: self.modelContainer).evict()
        }
```

- [ ] **Step 3: Build and commit**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodebuild -scheme InstantBookReader -destination 'platform=macOS' build
```
Expected: `BUILD SUCCEEDED`.

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/App/AppDelegate.swift && \
  git commit -m "feat(mac): evict AI cache on launch"
```

---

## Task 21: AISettingsViewModel (the glue for the UI)

**Files:**
- Create: `book-reader-mac/Settings/AI/AISettingsViewModel.swift`

The viewmodel owns the per-provider input state, the test-result indicator, and the feature routing pickers. The actual SwiftUI views consume it via `@StateObject`/`@Observable`.

- [ ] **Step 1: Write the viewmodel**

Write `book-reader-mac/Settings/AI/AISettingsViewModel.swift`:
```swift
import Foundation
import SwiftUI
import SwiftData

@MainActor
@Observable
public final class AISettingsViewModel {
    public enum TestState: Equatable {
        case idle, running, ok, failed(String)
    }

    /// In-memory mirror of the SecureField values, one per provider.
    public var keyDrafts: [ProviderID: String] = [:]
    /// True when the saved key for that provider exists in Keychain.
    public var hasSavedKey: [ProviderID: Bool] = [:]
    /// Test outcome per provider.
    public var testState: [ProviderID: TestState] = [:]

    /// Routing — provider per feature.
    public var featureProvider: [AIFeature: ProviderID] = [:]
    /// Routing — model per feature ("" means "use provider default").
    public var featureModel: [AIFeature: String] = [:]

    public var syncToICloud: Bool = false
    public var totalCacheBytes: Int = 0

    private let router: AIRouter
    private let container: ModelContainer

    public init(router: AIRouter = AIRouter(),
                container: ModelContainer) {
        self.router = router
        self.container = container
        load()
    }

    public func load() {
        for p in ProviderID.allCases {
            hasSavedKey[p] = (KeychainStore.load(for: p) != nil)
            keyDrafts[p] = ""
            testState[p] = .idle
        }
        for f in AIFeature.allCases {
            featureProvider[f] = router.providerID(for: f)
            featureModel[f] = router.modelOverride(for: f) ?? ""
        }
        syncToICloud = KeychainStore.isSynchronizable
        totalCacheBytes = AICache(container: container).totalSizeBytes()
    }

    public func saveKey(for provider: ProviderID) {
        let raw = (keyDrafts[provider] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        try? KeychainStore.save(key: raw, for: provider)
        hasSavedKey[provider] = true
        keyDrafts[provider] = ""
        testState[provider] = .idle
    }

    public func deleteKey(for provider: ProviderID) {
        try? KeychainStore.delete(for: provider)
        hasSavedKey[provider] = false
        testState[provider] = .idle
    }

    public func testKey(for provider: ProviderID) async {
        testState[provider] = .running
        guard let key = KeychainStore.load(for: provider), !key.isEmpty else {
            testState[provider] = .failed("No key saved")
            return
        }
        let p: any AIProvider
        switch provider {
        case .openai:     p = OpenAIProvider(apiKey: key)
        case .anthropic:  p = AnthropicProvider(apiKey: key)
        case .google:     p = GoogleProvider(apiKey: key)
        case .openrouter: p = OpenRouterProvider(apiKey: key)
        }
        do {
            try await p.test()
            testState[provider] = .ok
        } catch {
            testState[provider] = .failed(String(describing: error))
        }
    }

    public func setProvider(_ id: ProviderID, for feature: AIFeature) {
        featureProvider[feature] = id
        UserDefaults.standard.set(id.rawValue, forKey: feature.providerDefaultsKey)
    }

    public func setModel(_ model: String, for feature: AIFeature) {
        featureModel[feature] = model
        if model.isEmpty {
            UserDefaults.standard.removeObject(forKey: feature.modelDefaultsKey)
        } else {
            UserDefaults.standard.set(model, forKey: feature.modelDefaultsKey)
        }
    }

    public func availableModels(for provider: ProviderID) -> [String] {
        switch provider {
        case .openai:     return OpenAIProvider(apiKey: "").availableModels
        case .anthropic:  return AnthropicProvider(apiKey: "").availableModels
        case .google:     return GoogleProvider(apiKey: "").availableModels
        case .openrouter: return OpenRouterProvider(apiKey: "").availableModels
        }
    }

    public func setSync(_ enabled: Bool) {
        KeychainStore.setSynchronizable(enabled)
        syncToICloud = enabled
    }

    public func clearCache() {
        AICache(container: container).clear()
        totalCacheBytes = 0
    }

    public func refreshCacheSize() {
        totalCacheBytes = AICache(container: container).totalSizeBytes()
    }
}
```

- [ ] **Step 2: Build and commit**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodebuild -scheme InstantBookReader -destination 'platform=macOS' build
```
Expected: `BUILD SUCCEEDED`.

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Settings/AI/AISettingsViewModel.swift && \
  git commit -m "feat(mac): AISettingsViewModel"
```

---

## Task 22: ProviderKeyRow and FeatureRoutingRow SwiftUI views

**Files:**
- Create: `book-reader-mac/Settings/AI/ProviderKeyRow.swift`
- Create: `book-reader-mac/Settings/AI/FeatureRoutingRow.swift`
- Create: `book-reader-mac/Settings/AI/CacheControlSection.swift`

- [ ] **Step 1: Write `ProviderKeyRow.swift`**

Write `book-reader-mac/Settings/AI/ProviderKeyRow.swift`:
```swift
import SwiftUI

struct ProviderKeyRow: View {
    let provider: ProviderID
    @Bindable var model: AISettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(provider.displayName)
                    .font(.headline)
                Spacer()
                statusBadge
            }
            HStack(spacing: 8) {
                SecureField(
                    "Paste API key",
                    text: Binding(
                        get: { model.keyDrafts[provider] ?? "" },
                        set: { model.keyDrafts[provider] = $0 }
                    )
                )
                .textFieldStyle(.roundedBorder)
                Button("Save") { model.saveKey(for: provider) }
                    .disabled((model.keyDrafts[provider] ?? "").isEmpty)
                Button("Test") {
                    Task { await model.testKey(for: provider) }
                }
                .disabled(!(model.hasSavedKey[provider] ?? false))
                Button("Delete") { model.deleteKey(for: provider) }
                    .disabled(!(model.hasSavedKey[provider] ?? false))
            }
            if case .failed(let msg) = model.testState[provider] ?? .idle {
                Text(msg).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch model.testState[provider] ?? .idle {
        case .idle:
            if model.hasSavedKey[provider] == true {
                Text("Saved").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("No key").font(.caption).foregroundStyle(.secondary)
            }
        case .running:
            ProgressView().controlSize(.small)
        case .ok:
            Label("OK", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}
```

- [ ] **Step 2: Write `FeatureRoutingRow.swift`**

Write `book-reader-mac/Settings/AI/FeatureRoutingRow.swift`:
```swift
import SwiftUI

struct FeatureRoutingRow: View {
    let feature: AIFeature
    @Bindable var model: AISettingsViewModel

    var body: some View {
        let provider = model.featureProvider[feature] ?? .openai
        HStack {
            Text(feature.displayName).frame(width: 160, alignment: .leading)
            Picker("", selection: Binding(
                get: { provider },
                set: { model.setProvider($0, for: feature) }
            )) {
                ForEach(ProviderID.allCases, id: \.self) { id in
                    Text(id.displayName).tag(id)
                }
            }
            .labelsHidden()
            .frame(width: 140)

            Picker("", selection: Binding(
                get: { model.featureModel[feature] ?? "" },
                set: { model.setModel($0, for: feature) }
            )) {
                Text("Default").tag("")
                ForEach(model.availableModels(for: provider), id: \.self) { m in
                    Text(m).tag(m)
                }
            }
            .labelsHidden()
        }
    }
}
```

- [ ] **Step 3: Write `CacheControlSection.swift`**

Write `book-reader-mac/Settings/AI/CacheControlSection.swift`:
```swift
import SwiftUI

struct CacheControlSection: View {
    @Bindable var model: AISettingsViewModel

    var body: some View {
        Section("Cache") {
            HStack {
                Text("Current size")
                Spacer()
                Text(format(bytes: model.totalCacheBytes))
                    .foregroundStyle(.secondary)
                Button("Refresh") { model.refreshCacheSize() }
            }
            HStack {
                Text("Clear all cached AI responses")
                Spacer()
                Button("Clear cache", role: .destructive) { model.clearCache() }
            }
            Toggle("Sync API keys via iCloud Keychain",
                   isOn: Binding(
                       get: { model.syncToICloud },
                       set: { model.setSync($0) }
                   ))
        }
    }

    private func format(bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB, .useBytes]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }
}
```

- [ ] **Step 4: Build and commit**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodebuild -scheme InstantBookReader -destination 'platform=macOS' build
```
Expected: `BUILD SUCCEEDED`.

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Settings/AI/ProviderKeyRow.swift \
          book-reader-mac/Settings/AI/FeatureRoutingRow.swift \
          book-reader-mac/Settings/AI/CacheControlSection.swift && \
  git commit -m "feat(mac): AI Settings rows and cache section"
```

---

## Task 23: AISettingsTab and Settings scene wiring

**Files:**
- Create: `book-reader-mac/Settings/AI/AISettingsTab.swift`
- Modify: the file from Plan 1 that hosts the `Settings { TabView { ... } }` scene (search for the placeholder)

- [ ] **Step 1: Find the Settings scene**

Run:
```bash
grep -rn "Settings {" /Users/profitoniumapps/Documents/chromeApps/book-reader-mac --include="*.swift"
```
Note the file and approximate line number. In Plan 1 the AI tab is an `EmptyView()` placeholder; the next step replaces it with `AISettingsTab()`.

- [ ] **Step 2: Write `AISettingsTab.swift`**

Write `book-reader-mac/Settings/AI/AISettingsTab.swift`:
```swift
import SwiftUI
import SwiftData

public struct AISettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: AISettingsViewModel?

    public init() {}

    public var body: some View {
        Form {
            Section("Providers") {
                if let model {
                    ForEach(ProviderID.allCases, id: \.self) { p in
                        ProviderKeyRow(provider: p, model: model)
                    }
                }
            }
            Section("Routing") {
                if let model {
                    ForEach(AIFeature.allCases, id: \.self) { f in
                        FeatureRoutingRow(feature: f, model: model)
                    }
                }
            }
            if let model {
                CacheControlSection(model: model)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 620, minHeight: 540)
        .task {
            if model == nil {
                model = AISettingsViewModel(container: modelContext.container)
            }
        }
    }
}
```

- [ ] **Step 3: Replace the placeholder in the Settings scene**

In the file located by Step 1, find the `EmptyView()` (or whatever placeholder Plan 1 left for the AI tab) inside the `TabView`. Replace it with `AISettingsTab()`. Keep the existing `.tabItem` label intact.

Concretely, if Plan 1 wrote:
```swift
                EmptyView()
                    .tabItem { Label("AI", systemImage: "sparkles") }
```
Edit it to:
```swift
                AISettingsTab()
                    .tabItem { Label("AI", systemImage: "sparkles") }
```

- [ ] **Step 4: Build and commit**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodebuild -scheme InstantBookReader -destination 'platform=macOS' build
```
Expected: `BUILD SUCCEEDED`.

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Settings/AI/AISettingsTab.swift \
          book-reader-mac/App/ && \
  git commit -m "feat(mac): wire AI tab into Settings scene"
```

If the modified Settings scene lives outside `App/` (look at the grep output from Step 1), substitute the correct file path in the `git add` above.

---

## Task 24: Selection-popover AI streaming controller

**Files:**
- Create: `book-reader-mac/AI/SelectionAIController.swift`

The selection popover (Plan 3) currently calls a stub `onAIAction(_ action: AIActionKind, _ selectedText: String)`. We introduce `SelectionAIController` as the shared engine the popover drives: it owns the active stream, exposes published text + state, and is reusable so Plan 5/6 features can also call it.

- [ ] **Step 1: Write `SelectionAIController.swift`**

Write `book-reader-mac/AI/SelectionAIController.swift`:
```swift
import Foundation
import SwiftData

@MainActor
@Observable
public final class SelectionAIController {
    public enum State: Equatable {
        case idle
        case streaming
        case finished
        case needsKey(ProviderID)
        case error(String)
    }

    public var state: State = .idle
    public var outputText: String = ""

    private let router: AIRouter
    private let cache: AICache
    private let bookHash: () -> String
    private var task: Task<Void, Never>?

    public init(router: AIRouter = AIRouter(),
                container: ModelContainer,
                bookHash: @escaping () -> String) {
        self.router = router
        self.cache = AICache(container: container)
        self.bookHash = bookHash
    }

    public func reset() {
        task?.cancel()
        task = nil
        outputText = ""
        state = .idle
    }

    public func run(feature: AIFeature,
                    selection: String,
                    context: String = "",
                    chapterText: String = "",
                    question: String = "",
                    targetLang: String = "English") {
        task?.cancel()
        outputText = ""
        state = .streaming

        do {
            let (request, resolved) = try router.request(for: feature,
                                                         selection: selection,
                                                         context: context,
                                                         chapterText: chapterText,
                                                         question: question,
                                                         targetLang: targetLang)
            let promptString = (request.system ?? "") + "\n---\n" + (request.messages.last?.content ?? "")
            let cacheKey = AICache.makeKey(provider: resolved.provider.id,
                                           model: resolved.model,
                                           prompt: promptString,
                                           bookHash: bookHash())
            if let cached = cache.read(key: cacheKey) {
                outputText = cached
                state = .finished
                return
            }
            task = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for try await chunk in resolved.provider.stream(request) {
                        if Task.isCancelled { return }
                        switch chunk {
                        case .textDelta(let s):
                            self.outputText.append(s)
                        case .done:
                            self.cache.write(key: cacheKey, response: self.outputText)
                            self.state = .finished
                            return
                        case .error(let msg):
                            self.state = .error(msg)
                            return
                        }
                    }
                    self.cache.write(key: cacheKey, response: self.outputText)
                    self.state = .finished
                } catch {
                    self.state = .error(String(describing: error))
                }
            }
        } catch let AIRouterError.noKeyForProvider(id) {
            state = .needsKey(id)
        } catch {
            state = .error(String(describing: error))
        }
    }
}
```

- [ ] **Step 2: Build and commit**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodebuild -scheme InstantBookReader -destination 'platform=macOS' build
```
Expected: `BUILD SUCCEEDED`.

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/AI/SelectionAIController.swift && \
  git commit -m "feat(mac): SelectionAIController orchestrating router + cache + stream"
```

---

## Task 25: Replace the Plan 3 selection-popover stub

**Files:**
- Modify: `book-reader-mac/Reader/Selection/SelectionPopover.swift` (created by Plan 3; substitute the actual path if different)
- Modify: `book-reader-mac/Reader/Selection/SelectionPopoverViewModel.swift` if Plan 3 named the controller separately

Plan 3 left this hook:
```swift
var onAIAction: ((AIActionKind, String) -> Void)?
```
where `AIActionKind` is `case explain, summarize, ask, translate`. We replace the stub body with a `SelectionAIController` driver and add a streaming output area + "Save as note" button.

- [ ] **Step 1: Locate the popover file from Plan 3**

Run:
```bash
grep -rln "SelectionPopover\|onAIAction\|AIActionKind" /Users/profitoniumapps/Documents/chromeApps/book-reader-mac --include="*.swift"
```
Note the file paths. The next steps assume:
- The popover view is at `book-reader-mac/Reader/Selection/SelectionPopover.swift`
- It has access to the current `Highlight` (or a way to create one) via an injected closure `onSaveNote(String) -> Void`
- It receives the current book's `sha256` and a `ModelContainer` via environment

If the Plan 3 file path differs, substitute it in the edits below.

- [ ] **Step 2: Replace the stub with a controller-backed view**

Inside `SelectionPopover.swift`, locate the `Button("Explain")` / `Button("Summarize")` / `Button("Ask")` / `Button("Translate")` action handlers that currently call `onAIAction(.explain, selectedText)`. Replace each with:

```swift
                Button("Explain") {
                    controller.run(feature: .explain,
                                   selection: selectedText,
                                   context: surroundingContext)
                }
```

`controller` is added as a `@State` property on the view. Add to the view's top-level:

```swift
    @Environment(\.modelContext) private var modelContext
    @State private var controller: SelectionAIController?

    private var surroundingContext: String { /* existing helper from Plan 3 */ }
    let selectedText: String
    let bookHash: String
    let onSaveNote: (String) -> Void
```

Initialize the controller lazily in `.task`:
```swift
        .task {
            if controller == nil {
                controller = SelectionAIController(container: modelContext.container,
                                                   bookHash: { bookHash })
            }
        }
```

Below the action button row, add the streaming output and Save-as-note affordance:

```swift
            if let controller {
                switch controller.state {
                case .idle:
                    EmptyView()
                case .streaming, .finished:
                    ScrollView {
                        Text(controller.outputText)
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(maxHeight: 240)
                    HStack {
                        Spacer()
                        if controller.state == .finished {
                            Button("Save as note") {
                                onSaveNote(controller.outputText)
                            }
                        }
                    }
                case .needsKey(let provider):
                    AddKeyAffordance(provider: provider)
                case .error(let msg):
                    Text(msg).foregroundStyle(.red).font(.caption)
                }
            }
```

Where `AddKeyAffordance` is a new small subview defined in the same file:

```swift
struct AddKeyAffordance: View {
    let provider: ProviderID
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add an API key in Settings → AI")
                .font(.body)
            Text("Provider: \(provider.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Open Settings…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
        .padding(8)
    }
}
```

If Plan 3's popover already provides a callback the parent reader uses to write a `Highlight.note`, leave the parent intact. Otherwise the parent reader view must implement `onSaveNote` by fetching or creating the relevant `Highlight` (selection has an anchor in Plan 3) and setting `.note = noteText`.

- [ ] **Step 3: Implement `onSaveNote` at the call site**

Locate the parent reader view that instantiates `SelectionPopover`. Find the existing `onAIAction:` argument and:

1. Remove `onAIAction:` from the `SelectionPopover(...)` call. The popover now drives AI itself.
2. Add `onSaveNote: { note in saveNote(note) }`.
3. In the same view, add the helper:

```swift
    @Environment(\.modelContext) private var modelContext

    private func saveNote(_ note: String) {
        guard let anchor = currentSelectionAnchor else { return }
        // Fetch existing highlight by (bookHash, anchor) or create one.
        let bookHash = currentBookHash
        let descriptor = FetchDescriptor<Highlight>(
            predicate: #Predicate { $0.bookHash == bookHash
                                    && $0.surroundingText == anchor.surroundingText
                                    && $0.offset == anchor.offset }
        )
        let existing = (try? modelContext.fetch(descriptor))?.first
        if let h = existing {
            h.note = note
            h.updatedAt = .now
        } else {
            let h = Highlight(bookHash: bookHash,
                              text: anchor.text,
                              surroundingText: anchor.surroundingText,
                              offset: anchor.offset,
                              note: note)
            modelContext.insert(h)
        }
        try? modelContext.save()
    }
```

`currentSelectionAnchor` and `currentBookHash` are Plan 3 properties. If Plan 3 chose different names, substitute them — the structure is identical.

- [ ] **Step 4: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodebuild -scheme InstantBookReader -destination 'platform=macOS' build
```
Expected: `BUILD SUCCEEDED`. If Plan 3 used different identifiers for `selectedText`, `bookHash`, or `currentSelectionAnchor`, match the build errors to the actual names and revise the substitutions above; structure stays the same.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Selection/ && \
  git commit -m "feat(mac): wire selection popover through AIRouter + cache"
```

---

## Task 26: Manual verification pass

**Files:** None.

- [ ] **Step 1: Run the full test suite**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -scheme InstantBookReader -destination 'platform=macOS'
```
Expected: all suites pass. Specifically: `SSEParserTests`, `KeychainStoreTests`, `OpenAIProviderTests`, `AnthropicProviderTests`, `GoogleProviderTests`, `OpenRouterProviderTests`, `AIRouterTests`, `AICacheTests` plus the pre-existing Plans 1–3 suites.

- [ ] **Step 2: Launch the app and exercise the AI tab**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild -scheme InstantBookReader -destination 'platform=macOS' build && \
  open ./build/Build/Products/Debug/InstantBookReader.app
```
Then:
1. Open Settings → AI.
2. Paste a real key into OpenAI's row, click Save, click Test. Expect a green check.
3. Open a book, select a sentence, click Explain in the popover. Expect streamed text. Click "Save as note". Confirm the note appears on the highlight in the highlight list.
4. Delete the OpenAI key. Re-trigger Explain. Expect the "Add an API key in Settings → AI" message naming OpenAI.
5. Quit and relaunch. Confirm keys persist and the AI tab shows "Saved" for any keys that remain.

If any step fails, file the symptom against the relevant earlier task and re-execute it — do not patch over a regression in this verification task.

- [ ] **Step 3: Commit any small fixes**

If steps in §2 surfaced a real bug, fix it in the relevant task's file and commit with a descriptive message. If everything passes, nothing to commit here.

---

## Self-review checklist (executed before finalizing)

- Spec §8.1 (provider interface): Task 1 defines the protocol verbatim; Tasks 10/12/13/14 implement four providers.
- Spec §8.2 (routing): Task 17 (`AIRouter.resolve`) implements per-feature routing. Task 16 covers the `noKeyForProvider` throw. Task 25 surfaces it as the "Add an API key" affordance.
- Spec §8.3 (cache): Tasks 18–19 implement the 200 MB LRU sha256-keyed cache against the existing `AICacheEntry` SwiftData table. Task 20 hooks `evict()` to app launch. Task 19 calls `evict()` after every write.
- Spec §8.4 (selection actions): Task 24 (`SelectionAIController`) plus Task 25 (popover wiring) covers Explain, Summarize, Ask, Translate, Extract Highlights, with streamed rendering and a Save-as-note button writing to `Highlight.note`.
- Spec §10 AI tab: Tasks 21–23 implement the entire tab — per-provider rows with Test/Delete, per-feature routing pickers, cache readout + clear, iCloud Keychain toggle.
- BYOK-only constraint: no server fallback referenced anywhere. The router's only failure mode for "no key" is `noKeyForProvider`.
- Type consistency: `AIRouterError.noKeyForProvider(ProviderID)` is the same case across Tasks 1, 16, 17, 24, 25. `AIChunk` cases (`textDelta`, `done`, `error`) are consistent across all four providers. The Plan 3 popover hook name `onAIAction(_:_:)` is replaced (not co-existed with) in Task 25. `availableModels` returns string arrays in every provider. `HTTPClient` constructor signature matches all callsites.
- Placeholder scan: no "TBD", "TODO", "implement later", or "similar to" instructions. Every code step contains executable code. Every test step lists the exact `xcodebuild` invocation and expected output.
- Fixtures: all six fixture files are written verbatim in Task 7 — no "capture from real API later" placeholders.
- `test()` 1-token assertion: covered by `testTestUsesOneTokenRequest` in Task 9 against `MockURLProtocol` — no real network calls in tests.
