# Active Reader Implementation Plan — macOS

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `PlaceholderReaderView` with a fully functional active reader that renders EPUB and TXT via a WKWebView hosting the existing Chrome extension's built React app, and renders PDF via PDFKit. Selection toolbar, highlights, position persistence, and theme handoff all work end to end. AI calls are stubbed for Plan 4.

**Architecture:** A `ReaderRouter` SwiftUI view dispatches on `Book.format`. EPUB and TXT route to `WKWebViewReader`, which loads `WebReader.bundle/index.html` (the extension's `dist/` bundled in via a pre-build script) and bridges a minimal set of `chrome.*` shims via `WKScriptMessageHandler`. The book's bytes are streamed into the web app over a custom URL scheme (`bookreader://current`) handled by `BookContentLoader`/`BookURLSchemeHandler`. PDF routes to `PDFReaderView`, an `NSViewRepresentable<PDFView>` subclass with mode/outline/thumbnail support. Highlights and positions use a shared content-addressed anchor scheme (`HighlightAnchor`) ported from the extension. A `PositionRecorder` debounces 500 ms before writing `Position` to SwiftData. A `SelectionPopover` (`NSPopover`) renders the selection toolbar over both reader paths.

**Tech Stack:** Swift 5.10, SwiftUI + AppKit, WebKit (`WKWebView`, `WKWebViewConfiguration`, `WKScriptMessageHandler`, `WKURLSchemeHandler`), PDFKit (`PDFView`, `PDFDocument`, `PDFAnnotation`, `PDFSelection`), SwiftData, XCTest, Node 20+ for the extension build, `xcodegen`.

---

## Assumptions about Plan 2 deliverables

Plan 3 assumes that Plan 2 has already produced the following — referenced freely in tasks below:

- `book-reader-mac/Library/BookImporter.swift` — `BookImporter.import(file:into:)` copies a file to `AppSupportPaths.books/<sha256>.<ext>`, inserts a `Book`, and returns it.
- `book-reader-mac/Tests/Fixtures/` — directory containing `sample.epub`, `sample.pdf`, and `sample.txt` plus a `Fixtures.swift` helper exposing `Fixtures.epubURL`, `Fixtures.pdfURL`, `Fixtures.txtURL`. `project.yml` lists `Tests/Fixtures` under the test target's `resources`.
- A library window that, on double-clicking a book, sets `ReadingState.currentBookHash` and calls `ReaderWindowController.summon()`.

If any of these are missing, file an issue and unblock with the minimum stub before continuing — do not silently work around.

---

## File structure

New files this plan creates (existing foundation paths are not relisted):

```
book-reader-mac/
├── project.yml                                       # MODIFIED: pre-build script, WebReader.bundle resource
├── .gitignore                                        # MODIFIED: ignore generated WebReader.bundle/
├── Resources/
│   └── WebReader.bundle/                             # generated; gitignored
├── Reader/
│   ├── ReaderRouter.swift                            # Dispatches on Book.format
│   ├── Web/
│   │   ├── WKWebViewReader.swift                     # NSViewRepresentable<WKWebView>
│   │   ├── WebReaderBridge.swift                     # WKScriptMessageHandler
│   │   ├── BookURLSchemeHandler.swift                # bookreader:// scheme
│   │   ├── BookContentLoader.swift                   # Reads bytes from AppSupportPaths.books
│   │   ├── WebThemeInjector.swift                    # Clay CSS variables → WKWebView
│   │   └── WebHighlightBridge.swift                  # Apply/remove highlights via JS
│   ├── PDF/
│   │   ├── PDFReaderView.swift                       # NSViewRepresentable<PDFView>
│   │   ├── PDFReaderCoordinator.swift                # Page-change, selection callbacks
│   │   ├── HighlightedPDFView.swift                  # PDFView subclass drawing PDFAnnotations
│   │   ├── PDFOutlinePanel.swift                     # SwiftUI TOC from outlineRoot
│   │   ├── PDFThumbnailStripView.swift               # NSViewRepresentable<PDFThumbnailView>
│   │   └── PDFDisplayMode.swift                      # enum + mapping to PDFKit modes
│   ├── TXT/
│   │   └── TXTReaderView.swift                       # Chunked ScrollView
│   ├── Anchors/
│   │   ├── HighlightAnchor.swift                     # Surrounding-text + offset scheme
│   │   ├── PDFAnchorResolver.swift                   # PDFSelection ↔ anchor
│   │   └── TXTAnchorResolver.swift                   # Text ↔ anchor (shared by EPUB JS)
│   ├── Position/
│   │   └── PositionRecorder.swift                    # 500 ms debounce → SwiftData
│   └── Selection/
│       ├── SelectionPopover.swift                    # NSPopover host
│       └── SelectionToolbarView.swift                # SwiftUI toolbar (Highlight/Copy/Explain)
└── Tests/
    ├── HighlightAnchorTests.swift
    ├── PDFAnchorResolverTests.swift
    ├── TXTAnchorResolverTests.swift
    ├── WebReaderBridgeTests.swift
    ├── BookContentLoaderTests.swift
    ├── PositionRecorderTests.swift
    └── PDFDisplayModeTests.swift
```

---

## Task 1: Pre-build script that builds and copies the WebReader bundle

**Files:**
- Modify: `book-reader-mac/project.yml`
- Modify: `book-reader-mac/.gitignore`

- [ ] **Step 1: Add WebReader.bundle to .gitignore**

Append to `book-reader-mac/.gitignore`:
```
# Built JS bundle copied from book-reader-extension/dist at build time.
Resources/WebReader.bundle/
```

- [ ] **Step 2: Add a pre-build script and resource entry to the app target in `project.yml`**

In `book-reader-mac/project.yml`, locate the `InstantBookReader` target's `sources:` block and add a sibling `preBuildScripts:` entry plus add `Resources/WebReader.bundle` as a resource. Replace the `InstantBookReader:` target block with:

```yaml
  InstantBookReader:
    type: application
    platform: macOS
    sources:
      - path: App
      - path: Core
      - path: Persistence
      - path: Windows
      - path: MenuBar
      - path: Hotkey
      - path: System
      - path: Placeholders
      - path: Library
      - path: Reader
      - path: Resources
    resources:
      - path: Resources/WebReader.bundle
        optional: true
    preBuildScripts:
      - name: Build WebReader bundle from extension dist
        script: |
          set -euo pipefail
          EXT_DIR="${SRCROOT}/../book-reader-extension"
          DEST="${SRCROOT}/Resources/WebReader.bundle"
          if [ ! -d "$EXT_DIR" ]; then
            echo "error: book-reader-extension directory not found at $EXT_DIR"
            exit 1
          fi
          pushd "$EXT_DIR" >/dev/null
          if [ ! -d node_modules ]; then
            npm install --no-audit --no-fund
          fi
          npm run build
          popd >/dev/null
          rm -rf "$DEST"
          mkdir -p "$DEST"
          cp -R "$EXT_DIR/dist/." "$DEST/"
        inputFiles:
          - $(SRCROOT)/../book-reader-extension/src
          - $(SRCROOT)/../book-reader-extension/package.json
        outputFiles:
          - $(SRCROOT)/Resources/WebReader.bundle/index.html
        basedOnDependencyAnalysis: false
    dependencies:
      - package: KeyboardShortcuts
    info:
      path: App/Info.plist
      properties:
        LSUIElement: true
        LSApplicationCategoryType: public.app-category.productivity
        NSHumanReadableCopyright: "© 2026 Profitonium Apps"
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        NSSupportsAutomaticTermination: false
        NSSupportsSuddenTermination: false
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.profitoniumapps.instantbookreader
        INFOPLIST_FILE: App/Info.plist
        ENABLE_PREVIEWS: YES
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
```

Note: the `Reader/` and `Library/` source paths are added even though Plan 2 may have added `Library/` already — listing the same path twice is harmless in XcodeGen and the merge is idempotent.

- [ ] **Step 3: Pre-create an empty `Resources/WebReader.bundle/` so XcodeGen can resolve the resource entry on the first generate**

Run:
```bash
mkdir -p /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Resources/WebReader.bundle && \
  touch /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Resources/WebReader.bundle/.placeholder
```

- [ ] **Step 4: Regenerate and run a build to confirm the pre-build script runs**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -configuration Debug \
    -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`. Confirm `Resources/WebReader.bundle/index.html` now exists:
```bash
test -f /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Resources/WebReader.bundle/index.html && echo OK
```
Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/.gitignore book-reader-mac/project.yml && \
  git commit -m "build(mac): pre-build extension dist into WebReader.bundle resource"
```

---

## Task 2: Source the chrome.* surface the extension actually uses

This task produces a short reference file we'll consult while writing the bridge in Task 5. No build output.

**Files:**
- Create: `book-reader-mac/Reader/Web/CHROME_SURFACE.md`

- [ ] **Step 1: Write the surface inventory**

Write `book-reader-mac/Reader/Web/CHROME_SURFACE.md`:
```markdown
# chrome.* APIs the extension calls

Sourced from a grep over `book-reader-extension/src/newtab/`. The WKWebView
bridge in `WebReaderBridge.swift` must support the read paths; write paths
delegate to UserDefaults keyed by `wk_<name>`. Anything not listed here is a
no-op stub that logs to `os_log` and returns `undefined`.

## chrome.storage.local

- `chrome.storage.local.get(keys)` — keys is string | string[] | Record<string, unknown>.
  Returns `{ [key]: value }`. Bridge to UserDefaults keys prefixed `wk_`.
- `chrome.storage.local.set(items)` — items is `Record<string, unknown>`.
  Bridge to UserDefaults; emit synthetic onChanged events.
- `chrome.storage.local.remove(keys)` — keys is string | string[].
- `chrome.storage.onChanged.addListener(cb)` — cb receives
  `(changes: Record<string, {oldValue?: any, newValue?: any}>, areaName: 'local')`.

## chrome.runtime

- `chrome.runtime.getURL(path)` — returns `bookreader://app/<path>` so the web
  app can load assets via the same WKURLSchemeHandler that serves the book file.
- `chrome.runtime.openOptionsPage()` — stub. Opens the macOS Settings scene
  (Plan 7); for v1 of Plan 3 logs `os_log` and posts a Notification.

## chrome.identity (unused in offline reader path)

- `chrome.identity.getAuthToken(opts, cb)` — stub: returns
  `cb(undefined, chrome.runtime.lastError = { message: "not signed in" })`.
- `chrome.identity.clearAllCachedAuthTokens(cb)` — stub: `cb()`.

The Mac app does not call `book-reader-api` (spec §14). The extension's hooks
that depend on identity short-circuit when no token is returned, which is the
desired path here.

## chrome.alarms (background-only)

The new-tab page never registers chrome.alarms — only the service worker does.
The Mac shell never executes the service worker. No bridge needed.

## chrome.tabs

Not referenced in `src/newtab/`. Confirm with:

    grep -r "chrome.tabs" book-reader-extension/src/newtab

Expected: no matches. If matches appear, extend this file before changing the bridge.
```

- [ ] **Step 2: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Web/CHROME_SURFACE.md && \
  git commit -m "docs(mac): chrome.* surface inventory for WebReader bridge"
```

---

## Task 3: HighlightAnchor — port of the extension's anchor scheme

**Files:**
- Create: `book-reader-mac/Reader/Anchors/HighlightAnchor.swift`
- Create: `book-reader-mac/Tests/HighlightAnchorTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/HighlightAnchorTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

final class HighlightAnchorTests: XCTestCase {
    private let text = """
    The quick brown fox jumps over the lazy dog. The river ran deep \
    and dark beside the rocky path. Somewhere far off a wolf began to \
    howl beneath the silver moon, low and lonely. The brown fox stopped \
    and listened, then trotted on.
    """

    func testBuildAnchorCapturesSurroundingText() {
        let anchor = HighlightAnchor.build(plainText: text, startOffset: 16, length: 3) // "fox"
        XCTAssertEqual(anchor.startOffset, 16)
        XCTAssertEqual(anchor.length, 3)
        XCTAssertEqual(anchor.contextBefore.suffix(10), "ck brown ")
        XCTAssertEqual(anchor.contextAfter.prefix(10), " jumps ove")
    }

    func testResolveAnchorRecoversTextAtSameOffset() {
        let anchor = HighlightAnchor.build(plainText: text, startOffset: 16, length: 3)
        let resolved = HighlightAnchor.resolve(plainText: text, anchor: anchor)
        XCTAssertEqual(resolved?.startOffset, 16)
        XCTAssertEqual(resolved?.length, 3)
        let nsText = text as NSString
        XCTAssertEqual(nsText.substring(with: NSRange(location: 16, length: 3)), "fox")
    }

    func testResolveAnchorRecoversAfterPrefixShift() {
        let anchor = HighlightAnchor.build(plainText: text, startOffset: 16, length: 3)
        let shifted = "PREFIX_INSERTED. " + text
        let resolved = HighlightAnchor.resolve(plainText: shifted, anchor: anchor)
        XCTAssertNotNil(resolved)
        let nsShifted = shifted as NSString
        XCTAssertEqual(
            nsShifted.substring(with: NSRange(location: resolved!.startOffset, length: resolved!.length)),
            "fox"
        )
    }

    func testResolveAnchorPrefersFirstUniqueMatch() {
        // "brown fox" appears twice in `text`. Anchor built around the first
        // occurrence must resolve to the first occurrence, not the second.
        let firstStart = (text as NSString).range(of: "brown fox").location
        let anchor = HighlightAnchor.build(plainText: text, startOffset: firstStart, length: 9)
        let resolved = HighlightAnchor.resolve(plainText: text, anchor: anchor)
        XCTAssertEqual(resolved?.startOffset, firstStart)
    }

    func testResolveAnchorReturnsNilWhenContextDestroyed() {
        let anchor = HighlightAnchor.build(plainText: text, startOffset: 16, length: 3)
        let resolved = HighlightAnchor.resolve(plainText: "completely unrelated content", anchor: anchor)
        XCTAssertNil(resolved)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: compile error referencing `HighlightAnchor`.

- [ ] **Step 3: Implement**

Write `book-reader-mac/Reader/Anchors/HighlightAnchor.swift`:
```swift
import Foundation

/// Content-addressed highlight anchor. Mirrors the extension's
/// `lib/highlights/anchor.ts`: stores surrounding text + offset rather than
/// DOM ranges, so highlights survive re-renders and reflow.
///
/// The Swift port treats `plainText` as a Swift String (Unicode-scalar safe)
/// but exposes offsets as `Int` measured in UTF-16 code units to match the
/// JS-side semantics used by the WKWebView reader. PDFKit clients convert
/// `String.utf16` offsets when going through `PDFPage.characterBounds(at:)`.
struct HighlightAnchor: Equatable, Sendable {
    var startOffset: Int
    var length: Int
    var contextBefore: String
    var contextAfter: String

    static let contextWindow = 50

    static func build(plainText: String, startOffset: Int, length: Int) -> HighlightAnchor {
        let utf16 = plainText.utf16
        let total = utf16.count
        let clampedStart = max(0, min(startOffset, total))
        let clampedEnd = max(clampedStart, min(startOffset + length, total))
        let beforeStart = max(0, clampedStart - contextWindow)
        let afterEnd = min(total, clampedEnd + contextWindow)
        return HighlightAnchor(
            startOffset: clampedStart,
            length: clampedEnd - clampedStart,
            contextBefore: substring(utf16: utf16, from: beforeStart, to: clampedStart),
            contextAfter: substring(utf16: utf16, from: clampedEnd, to: afterEnd)
        )
    }

    /// Returns the resolved range in `plainText`, or nil if the anchor cannot
    /// be located. Tries the literal offset first; then walks the text looking
    /// for `contextBefore` + (length-wide gap) + `contextAfter`.
    static func resolve(plainText: String, anchor: HighlightAnchor) -> (startOffset: Int, length: Int)? {
        let utf16 = plainText.utf16
        let total = utf16.count

        // Literal offset attempt.
        if anchor.startOffset + anchor.length <= total {
            let beforeStart = max(0, anchor.startOffset - contextWindow)
            let beforeSlice = substring(utf16: utf16, from: beforeStart, to: anchor.startOffset)
            let neededSuffixLen = min(contextWindow, anchor.contextBefore.utf16.count)
            let neededSuffix = String(anchor.contextBefore.utf16.suffix(neededSuffixLen)) ?? ""
            if beforeSlice.hasSuffix(neededSuffix) || anchor.contextBefore.isEmpty {
                return (anchor.startOffset, anchor.length)
            }
        }

        // Both contexts empty → cannot disambiguate.
        if anchor.contextBefore.isEmpty && anchor.contextAfter.isEmpty {
            return nil
        }

        let probe = anchor.contextBefore
        let probeLen = probe.utf16.count
        let afterLen = anchor.contextAfter.utf16.count

        var from = 0
        while from <= total {
            let idx: Int
            if probeLen > 0 {
                guard let found = indexOf(needle: probe, in: utf16, from: from) else { return nil }
                idx = found
            } else {
                idx = 0
            }
            let candidateStart = idx + probeLen
            let candidateEnd = candidateStart + anchor.length
            if candidateEnd > total { return nil }
            let afterEnd = min(total, candidateEnd + afterLen)
            let afterSlice = substring(utf16: utf16, from: candidateEnd, to: afterEnd)
            if afterSlice == anchor.contextAfter || (afterLen == 0 && candidateEnd <= total) {
                return (candidateStart, anchor.length)
            }
            if probeLen == 0 { return nil }
            from = idx + 1
        }
        return nil
    }

    // MARK: - UTF-16 helpers

    private static func substring(utf16: String.UTF16View, from: Int, to: Int) -> String {
        guard from < to else { return "" }
        let start = utf16.index(utf16.startIndex, offsetBy: from)
        let end = utf16.index(utf16.startIndex, offsetBy: to)
        return String(String.UnicodeScalarView(utf16[start..<end].compactMap { Unicode.Scalar($0) }))
    }

    private static func indexOf(needle: String, in haystack: String.UTF16View, from: Int) -> Int? {
        let needleUnits = Array(needle.utf16)
        if needleUnits.isEmpty { return from }
        let haystackUnits = Array(haystack)
        let n = haystackUnits.count
        let m = needleUnits.count
        if from + m > n { return nil }
        var i = from
        while i + m <= n {
            var k = 0
            while k < m && haystackUnits[i + k] == needleUnits[k] { k += 1 }
            if k == m { return i }
            i += 1
        }
        return nil
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/HighlightAnchorTests 2>&1 | tail -10
```
Expected: `Test Suite 'HighlightAnchorTests' passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Anchors/HighlightAnchor.swift \
          book-reader-mac/Tests/HighlightAnchorTests.swift && \
  git commit -m "feat(mac): HighlightAnchor ported from extension"
```

---

## Task 4: BookContentLoader and the bookreader:// URL scheme

**Files:**
- Create: `book-reader-mac/Reader/Web/BookContentLoader.swift`
- Create: `book-reader-mac/Reader/Web/BookURLSchemeHandler.swift`
- Create: `book-reader-mac/Tests/BookContentLoaderTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/BookContentLoaderTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

final class BookContentLoaderTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("bcl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func testReadsBytesByHash() throws {
        let payload = Data([0x42, 0x4F, 0x4F, 0x4B]) // "BOOK"
        let file = tmp.appendingPathComponent("abc123.epub")
        try payload.write(to: file)
        let loader = BookContentLoader(booksDirectory: tmp)
        let data = try loader.read(hash: "abc123", ext: "epub")
        XCTAssertEqual(data, payload)
    }

    func testMimeTypeForEachFormat() {
        XCTAssertEqual(BookContentLoader.mimeType(forExtension: "epub"), "application/epub+zip")
        XCTAssertEqual(BookContentLoader.mimeType(forExtension: "pdf"), "application/pdf")
        XCTAssertEqual(BookContentLoader.mimeType(forExtension: "txt"), "text/plain; charset=utf-8")
        XCTAssertEqual(BookContentLoader.mimeType(forExtension: "unknown"), "application/octet-stream")
    }

    func testReadThrowsWhenMissing() {
        let loader = BookContentLoader(booksDirectory: tmp)
        XCTAssertThrowsError(try loader.read(hash: "nope", ext: "epub")) { error in
            XCTAssertTrue("\(error)".contains("nope"))
        }
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/BookContentLoaderTests 2>&1 | tail -10
```
Expected: compile error referencing `BookContentLoader`.

- [ ] **Step 3: Implement `BookContentLoader`**

Write `book-reader-mac/Reader/Web/BookContentLoader.swift`:
```swift
import Foundation

/// Reads book bytes by SHA-256 hash from the on-disk Books directory.
/// Returned through the bookreader:// URL scheme so the WKWebView reader can
/// `fetch('bookreader://current')` instead of going through IndexedDB.
struct BookContentLoader {
    let booksDirectory: URL

    init(booksDirectory: URL = AppSupportPaths.books) {
        self.booksDirectory = booksDirectory
    }

    enum LoaderError: Error, CustomStringConvertible {
        case notFound(hash: String)
        var description: String {
            switch self {
            case .notFound(let hash): return "book not found: \(hash)"
            }
        }
    }

    func read(hash: String, ext: String) throws -> Data {
        let url = booksDirectory.appendingPathComponent("\(hash).\(ext)")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoaderError.notFound(hash: hash)
        }
        return try Data(contentsOf: url)
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "epub": return "application/epub+zip"
        case "pdf":  return "application/pdf"
        case "txt":  return "text/plain; charset=utf-8"
        default:     return "application/octet-stream"
        }
    }
}
```

- [ ] **Step 4: Implement the URL scheme handler**

Write `book-reader-mac/Reader/Web/BookURLSchemeHandler.swift`:
```swift
import Foundation
import WebKit

/// Serves the bookreader:// scheme. Two URL shapes:
///
///   bookreader://current
///       → returns bytes of the currently active book.
///   bookreader://app/<relative-path>
///       → returns a file from the WebReader.bundle resource. Used by the
///         extension's chrome.runtime.getURL() stub for asset loads.
@MainActor
final class BookURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private let loader: BookContentLoader
    private let bundleURL: URL
    private let getCurrent: () -> (hash: String, ext: String)?

    init(loader: BookContentLoader,
         bundleURL: URL,
         getCurrent: @escaping () -> (hash: String, ext: String)?) {
        self.loader = loader
        self.bundleURL = bundleURL
        self.getCurrent = getCurrent
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        switch url.host {
        case "current":
            handleCurrent(task: urlSchemeTask)
        case "app":
            handleApp(url: url, task: urlSchemeTask)
        default:
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // No-op: synchronous handlers.
    }

    private func handleCurrent(task: any WKURLSchemeTask) {
        guard let current = getCurrent() else {
            task.didFailWithError(URLError(.resourceUnavailable))
            return
        }
        do {
            let data = try loader.read(hash: current.hash, ext: current.ext)
            respond(task: task,
                    url: task.request.url!,
                    data: data,
                    mime: BookContentLoader.mimeType(forExtension: current.ext))
        } catch {
            task.didFailWithError(error)
        }
    }

    private func handleApp(url: URL, task: any WKURLSchemeTask) {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fileURL = bundleURL.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = BookContentLoader.mimeType(forExtension: fileURL.pathExtension)
        respond(task: task, url: url, data: data, mime: mime)
    }

    private func respond(task: any WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let headers = [
            "Content-Type": mime,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*"
        ]
        let response = HTTPURLResponse(url: url,
                                       statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/BookContentLoaderTests 2>&1 | tail -10
```
Expected: `Test Suite 'BookContentLoaderTests' passed`.

- [ ] **Step 6: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Web/BookContentLoader.swift \
          book-reader-mac/Reader/Web/BookURLSchemeHandler.swift \
          book-reader-mac/Tests/BookContentLoaderTests.swift && \
  git commit -m "feat(mac): BookContentLoader and bookreader:// scheme handler"
```

---

## Task 5: WebReaderBridge — chrome.storage.local / chrome.runtime shim

**Files:**
- Create: `book-reader-mac/Reader/Web/WebReaderBridge.swift`
- Create: `book-reader-mac/Tests/WebReaderBridgeTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/WebReaderBridgeTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

final class WebReaderBridgeTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = UserDefaults(suiteName: "WebReaderBridgeTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: defaults.dictionaryRepresentation().keys.first ?? "")
    }

    func testSetThenGetSingleKey() throws {
        let store = WebReaderStorage(defaults: defaults)
        store.set(["currentBookHash": "abc"])
        let got = store.get(.array(["currentBookHash"]))
        XCTAssertEqual(got["currentBookHash"] as? String, "abc")
    }

    func testGetAllReturnsKnownKeys() throws {
        let store = WebReaderStorage(defaults: defaults)
        store.set(["a": 1, "b": "two", "c": true])
        let got = store.get(.allKeys)
        XCTAssertEqual(got["a"] as? Int, 1)
        XCTAssertEqual(got["b"] as? String, "two")
        XCTAssertEqual(got["c"] as? Bool, true)
    }

    func testRemoveErases() throws {
        let store = WebReaderStorage(defaults: defaults)
        store.set(["x": "y"])
        XCTAssertEqual(store.get(.array(["x"]))["x"] as? String, "y")
        store.remove(.array(["x"]))
        XCTAssertNil(store.get(.array(["x"]))["x"])
    }

    func testGetByObjectAppliesDefaults() throws {
        let store = WebReaderStorage(defaults: defaults)
        // No value yet for theme; default should propagate.
        let got = store.get(.object(["theme": "clay-dark"]))
        XCTAssertEqual(got["theme"] as? String, "clay-dark")
        store.set(["theme": "clay-light"])
        let after = store.get(.object(["theme": "clay-dark"]))
        XCTAssertEqual(after["theme"] as? String, "clay-light")
    }

    func testChangeListenersFireOnSet() throws {
        let store = WebReaderStorage(defaults: defaults)
        let exp = expectation(description: "change fired")
        store.onChange { changes in
            if let entry = changes["k"], entry.newValue as? String == "v" {
                exp.fulfill()
            }
        }
        store.set(["k": "v"])
        wait(for: [exp], timeout: 1.0)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/WebReaderBridgeTests 2>&1 | tail -10
```
Expected: compile error referencing `WebReaderStorage`.

- [ ] **Step 3: Implement the bridge**

Write `book-reader-mac/Reader/Web/WebReaderBridge.swift`:
```swift
import Foundation
import WebKit
import os

/// Backing store for chrome.storage.local. Keys are namespaced `wk_` in
/// UserDefaults so they don't collide with native preferences.
///
/// Supported `chrome.*` surface (see Reader/Web/CHROME_SURFACE.md):
///   - chrome.storage.local.{get,set,remove}
///   - chrome.storage.onChanged.addListener
///   - chrome.runtime.getURL
///   - chrome.runtime.openOptionsPage (stubbed to a notification)
///   - chrome.identity.{getAuthToken,clearAllCachedAuthTokens} (no-op stubs)
///
/// Anything else logs once and returns undefined.
final class WebReaderStorage {
    enum Query {
        case array([String])
        case object([String: Any])    // keys → defaults
        case allKeys
    }

    struct Change {
        let oldValue: Any?
        let newValue: Any?
    }

    private static let prefix = "wk_"
    private let defaults: UserDefaults
    private var listeners: [(([String: Change]) -> Void)] = []
    private let queue = DispatchQueue(label: "WebReaderStorage", attributes: .concurrent)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func get(_ query: Query) -> [String: Any] {
        switch query {
        case .array(let keys):
            var out: [String: Any] = [:]
            for k in keys {
                if let v = defaults.object(forKey: Self.prefix + k) { out[k] = v }
            }
            return out
        case .object(let defaultsMap):
            var out: [String: Any] = [:]
            for (k, def) in defaultsMap {
                out[k] = defaults.object(forKey: Self.prefix + k) ?? def
            }
            return out
        case .allKeys:
            var out: [String: Any] = [:]
            for (k, v) in defaults.dictionaryRepresentation() where k.hasPrefix(Self.prefix) {
                out[String(k.dropFirst(Self.prefix.count))] = v
            }
            return out
        }
    }

    func set(_ items: [String: Any]) {
        var changes: [String: Change] = [:]
        for (k, newValue) in items {
            let storageKey = Self.prefix + k
            let oldValue = defaults.object(forKey: storageKey)
            defaults.set(newValue, forKey: storageKey)
            changes[k] = Change(oldValue: oldValue, newValue: newValue)
        }
        notify(changes: changes)
    }

    func remove(_ query: Query) {
        var changes: [String: Change] = [:]
        let keys: [String]
        switch query {
        case .array(let arr): keys = arr
        case .object(let obj): keys = Array(obj.keys)
        case .allKeys:
            keys = defaults.dictionaryRepresentation().keys
                .filter { $0.hasPrefix(Self.prefix) }
                .map { String($0.dropFirst(Self.prefix.count)) }
        }
        for k in keys {
            let storageKey = Self.prefix + k
            let oldValue = defaults.object(forKey: storageKey)
            defaults.removeObject(forKey: storageKey)
            changes[k] = Change(oldValue: oldValue, newValue: nil)
        }
        notify(changes: changes)
    }

    func onChange(_ listener: @escaping ([String: Change]) -> Void) {
        queue.async(flags: .barrier) { self.listeners.append(listener) }
    }

    private func notify(changes: [String: Change]) {
        queue.sync {
            for l in listeners { l(changes) }
        }
    }
}

/// Routes `window.webkit.messageHandlers.bridge.postMessage(...)` calls from
/// the embedded React reader to native handlers.
///
/// Wire protocol (JSON):
///   { id: string, api: "storage.get"|"storage.set"|"storage.remove"
///                    | "storage.allKeys"|"runtime.openOptionsPage"
///                    | "identity.getAuthToken"|"identity.clearAllCachedAuthTokens"
///                    | "ai.stream",
///     args: <api-specific> }
///
/// Replies posted to JS by evaluating `window.__wkBridgeReply(id, payload)`.
@MainActor
final class WebReaderBridge: NSObject, WKScriptMessageHandler {
    static let messageName = "bridge"
    static let logger = Logger(subsystem: "com.profitoniumapps.instantbookreader",
                               category: "WebReaderBridge")

    private weak var webView: WKWebView?
    private let storage: WebReaderStorage

    init(storage: WebReaderStorage) {
        self.storage = storage
        super.init()
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
        storage.onChange { [weak self] changes in
            Task { @MainActor in self?.emitStorageChanged(changes) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let payload = message.body as? [String: Any],
              let id = payload["id"] as? String,
              let api = payload["api"] as? String else {
            Self.logger.error("dropped malformed bridge message")
            return
        }
        let args = payload["args"] as? [String: Any] ?? [:]
        handle(api: api, args: args, id: id)
    }

    private func handle(api: String, args: [String: Any], id: String) {
        switch api {
        case "storage.get":
            let query = parseQuery(args["keys"])
            reply(id: id, payload: storage.get(query))
        case "storage.set":
            if let items = args["items"] as? [String: Any] { storage.set(items) }
            reply(id: id, payload: [String: Any]())
        case "storage.remove":
            storage.remove(parseQuery(args["keys"]))
            reply(id: id, payload: [String: Any]())
        case "storage.allKeys":
            reply(id: id, payload: storage.get(.allKeys))
        case "runtime.openOptionsPage":
            NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
            reply(id: id, payload: [String: Any]())
        case "identity.getAuthToken":
            reply(id: id, payload: ["error": "not signed in"])
        case "identity.clearAllCachedAuthTokens":
            reply(id: id, payload: [String: Any]())
        case "ai.stream":
            // Plan 4 fills this in. For now respond with an explicit stub.
            reply(id: id, payload: ["error": "ai-not-configured"])
        default:
            Self.logger.notice("unhandled bridge api: \(api, privacy: .public)")
            reply(id: id, payload: ["error": "unsupported"])
        }
    }

    private func parseQuery(_ raw: Any?) -> WebReaderStorage.Query {
        if raw == nil { return .allKeys }
        if let s = raw as? String { return .array([s]) }
        if let arr = raw as? [String] { return .array(arr) }
        if let obj = raw as? [String: Any] { return .object(obj) }
        return .allKeys
    }

    private func reply(id: String, payload: [String: Any]) {
        guard let webView else { return }
        let json = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let js = "window.__wkBridgeReply && window.__wkBridgeReply(\(jsString(id)), \(json));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func emitStorageChanged(_ changes: [String: WebReaderStorage.Change]) {
        guard let webView else { return }
        var dict: [String: [String: Any]] = [:]
        for (k, c) in changes {
            var inner: [String: Any] = [:]
            if let o = c.oldValue { inner["oldValue"] = o }
            if let n = c.newValue { inner["newValue"] = n }
            dict[k] = inner
        }
        let json = (try? JSONSerialization.data(withJSONObject: dict))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let js = "window.__wkStorageChanged && window.__wkStorageChanged(\(json), 'local');"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
        let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(str.dropFirst().dropLast())
    }
}

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("InstantBookReader.openSettingsRequested")
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/WebReaderBridgeTests 2>&1 | tail -10
```
Expected: `Test Suite 'WebReaderBridgeTests' passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Web/WebReaderBridge.swift \
          book-reader-mac/Tests/WebReaderBridgeTests.swift && \
  git commit -m "feat(mac): WebReaderBridge with chrome.storage/runtime shims"
```

---

## Task 6: WebThemeInjector — push Clay tokens into the WKWebView

**Files:**
- Create: `book-reader-mac/Reader/Web/WebThemeInjector.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Reader/Web/WebThemeInjector.swift`:
```swift
import Foundation
import WebKit

/// Builds a `<style>` block of Clay CSS variables and injects it as a
/// WKUserScript at document-start. Re-injection on theme change calls
/// `reinject(into:)` which removes the previous style node and inserts the new one.
@MainActor
struct WebThemeInjector {
    let theme: AppTheme

    static let styleNodeID = "wk-theme-injected"

    func userScript() -> WKUserScript {
        let js = """
        (function() {
            const id = "\(Self.styleNodeID)";
            const existing = document.getElementById(id);
            if (existing) existing.remove();
            const style = document.createElement('style');
            style.id = id;
            style.textContent = \(jsLiteral(cssBody()));
            (document.head || document.documentElement).appendChild(style);
        })();
        """
        return WKUserScript(source: js,
                            injectionTime: .atDocumentStart,
                            forMainFrameOnly: true)
    }

    func reinject(into webView: WKWebView) {
        let js = """
        (function() {
            const id = "\(Self.styleNodeID)";
            const existing = document.getElementById(id);
            if (existing) existing.remove();
            const style = document.createElement('style');
            style.id = id;
            style.textContent = \(jsLiteral(cssBody()));
            (document.head || document.documentElement).appendChild(style);
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func cssBody() -> String {
        return """
        :root {
            --clay-ink: \(theme.ink.hexString);
            --clay-surface: \(theme.surface.hexString);
            --clay-border: \(theme.border.hexString);
        }
        body { background: var(--clay-surface); color: var(--clay-ink); }
        """
    }

    private func jsLiteral(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
        let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(str.dropFirst().dropLast())
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Web/WebThemeInjector.swift && \
  git commit -m "feat(mac): WebThemeInjector for Clay CSS variables"
```

---

## Task 7: WebHighlightBridge — apply/remove highlights via JS

**Files:**
- Create: `book-reader-mac/Reader/Web/WebHighlightBridge.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Reader/Web/WebHighlightBridge.swift`:
```swift
import Foundation
import WebKit

/// Sends apply/remove highlight commands into the WKWebView. The web side
/// already knows how to wrap ranges in `[data-highlight-id]` spans; this
/// bridge calls into `window.__wkHighlights` exposed by the reader bootstrap
/// shim (Task 9).
@MainActor
struct WebHighlightBridge {
    weak var webView: WKWebView?

    func apply(id: UUID, anchor: HighlightAnchor) {
        guard let webView else { return }
        let payload: [String: Any] = [
            "id": id.uuidString,
            "startOffset": anchor.startOffset,
            "length": anchor.length,
            "contextBefore": anchor.contextBefore,
            "contextAfter": anchor.contextAfter
        ]
        emit(method: "apply", payload: payload, on: webView)
    }

    func remove(id: UUID) {
        guard let webView else { return }
        emit(method: "remove", payload: ["id": id.uuidString], on: webView)
    }

    func replaceAll(_ items: [(id: UUID, anchor: HighlightAnchor)]) {
        guard let webView else { return }
        let arr: [[String: Any]] = items.map { item in
            [
                "id": item.id.uuidString,
                "startOffset": item.anchor.startOffset,
                "length": item.anchor.length,
                "contextBefore": item.anchor.contextBefore,
                "contextAfter": item.anchor.contextAfter
            ]
        }
        emit(method: "replaceAll", payload: ["items": arr], on: webView)
    }

    private func emit(method: String, payload: Any, on webView: WKWebView) {
        let json = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let js = "window.__wkHighlights && window.__wkHighlights.\(method)(\(json));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Web/WebHighlightBridge.swift && \
  git commit -m "feat(mac): WebHighlightBridge to apply highlights via JS"
```

---

## Task 8: WKWebViewReader — NSViewRepresentable shell

**Files:**
- Create: `book-reader-mac/Reader/Web/WKWebViewReader.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Reader/Web/WKWebViewReader.swift`:
```swift
import SwiftUI
import WebKit

/// SwiftUI host for the embedded React reader. Loads
/// `WebReader.bundle/index.html` and registers the bookreader:// scheme,
/// the WebReaderBridge, and the theme injector.
struct WKWebViewReader: NSViewRepresentable {
    let book: Book
    @Binding var selectionRect: CGRect?
    @Binding var selectionText: String
    let theme: AppTheme
    let onPositionChange: (String, Double, String?) -> Void   // anchor, percentage, chapterTitle
    let onHighlightAppliedFromJS: (HighlightAnchor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(book: book,
                    theme: theme,
                    onPositionChange: onPositionChange,
                    onHighlightAppliedFromJS: onHighlightAppliedFromJS,
                    onSelection: { rect, text in })
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let storage = WebReaderStorage()
        let bridge = WebReaderBridge(storage: storage)
        context.coordinator.bridge = bridge

        let bundleURL = Bundle.main.url(forResource: "WebReader", withExtension: "bundle")!
        let loader = BookContentLoader()
        let getCurrent: () -> (hash: String, ext: String)? = { [book] in
            (hash: book.sha256, ext: book.format.rawValue)
        }
        let scheme = BookURLSchemeHandler(loader: loader,
                                          bundleURL: bundleURL,
                                          getCurrent: getCurrent)
        context.coordinator.schemeHandler = scheme
        config.setURLSchemeHandler(scheme, forURLScheme: "bookreader")

        config.userContentController.add(bridge, name: WebReaderBridge.messageName)

        // Reader-side shim that wires window.__wkBridge.* / __wkHighlights / __wkSelection.
        config.userContentController.addUserScript(
            WKUserScript(source: Self.bootstrapJS,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true)
        )
        // Theme variables.
        config.userContentController.addUserScript(WebThemeInjector(theme: theme).userScript())

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // transparent
        webView.allowsMagnification = false
        webView.navigationDelegate = context.coordinator
        bridge.attach(to: webView)

        let indexURL = bundleURL.appendingPathComponent("index.html")
        webView.loadFileURL(indexURL, allowingReadAccessTo: bundleURL)

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.theme != theme {
            context.coordinator.theme = theme
            WebThemeInjector(theme: theme).reinject(into: webView)
        }
    }

    /// JS bootstrap. Defines window.__wkBridge.* and selection plumbing.
    /// The React reader detects `window.__wkBridge` and uses it in place of
    /// `chrome.*` (the extension's storage helpers already centralize through
    /// a single shim — see `book-reader-extension/src/newtab/lib/storage.ts`).
    static let bootstrapJS: String = #"""
    (function() {
        const pending = new Map();
        let nextID = 1;
        function call(api, args) {
            return new Promise((resolve) => {
                const id = "wk-" + (nextID++);
                pending.set(id, resolve);
                window.webkit.messageHandlers.bridge.postMessage({ id, api, args });
            });
        }
        window.__wkBridgeReply = function(id, payload) {
            const resolve = pending.get(id);
            if (resolve) { pending.delete(id); resolve(payload); }
        };
        window.__wkBridge = {
            storage: {
                get: (keys) => call('storage.get', { keys }),
                set: (items) => call('storage.set', { items }),
                remove: (keys) => call('storage.remove', { keys }),
                allKeys: () => call('storage.allKeys', {})
            },
            runtime: {
                getURL: (path) => "bookreader://app/" + String(path || "").replace(/^\/+/, ''),
                openOptionsPage: () => call('runtime.openOptionsPage', {})
            },
            identity: {
                getAuthToken: () => call('identity.getAuthToken', {}),
                clearAllCachedAuthTokens: () => call('identity.clearAllCachedAuthTokens', {})
            },
            ai: {
                stream: (req) => call('ai.stream', req)
            }
        };

        // Storage change fanout
        const changeListeners = [];
        window.__wkStorageChanged = function(changes, areaName) {
            for (const l of changeListeners) l(changes, areaName);
        };
        window.__wkBridge.storage.onChanged = {
            addListener: (cb) => changeListeners.push(cb),
            removeListener: (cb) => {
                const i = changeListeners.indexOf(cb);
                if (i >= 0) changeListeners.splice(i, 1);
            }
        };

        // Highlights — the reader-side renderer is provided by the extension
        // build. Native code calls window.__wkHighlights.{apply,remove,replaceAll}.
        // The default impl no-ops; the extension overrides on bootstrap.
        window.__wkHighlights = window.__wkHighlights || {
            apply: function() {},
            remove: function() {},
            replaceAll: function() {}
        };

        // Selection plumbing
        document.addEventListener('selectionchange', function() {
            const sel = window.getSelection();
            if (!sel || sel.isCollapsed || sel.rangeCount === 0) {
                window.webkit.messageHandlers.bridge.postMessage({
                    id: 'sel-' + Date.now(), api: 'selection.clear', args: {}
                });
                return;
            }
            const range = sel.getRangeAt(0);
            const rect = range.getBoundingClientRect();
            window.webkit.messageHandlers.bridge.postMessage({
                id: 'sel-' + Date.now(), api: 'selection.changed',
                args: { rect: { x: rect.x, y: rect.y, w: rect.width, h: rect.height }, text: sel.toString() }
            });
        });

        // Position
        window.__wkReportPosition = function(anchor, pct, chapter) {
            window.webkit.messageHandlers.bridge.postMessage({
                id: 'pos-' + Date.now(), api: 'position.changed',
                args: { anchor, percentage: pct, chapterTitle: chapter || null }
            });
        };
    })();
    """#

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let book: Book
        var theme: AppTheme
        var bridge: WebReaderBridge?
        var schemeHandler: BookURLSchemeHandler?
        weak var webView: WKWebView?
        let onPositionChange: (String, Double, String?) -> Void
        let onHighlightAppliedFromJS: (HighlightAnchor) -> Void
        let onSelection: (CGRect, String) -> Void

        init(book: Book,
             theme: AppTheme,
             onPositionChange: @escaping (String, Double, String?) -> Void,
             onHighlightAppliedFromJS: @escaping (HighlightAnchor) -> Void,
             onSelection: @escaping (CGRect, String) -> Void) {
            self.book = book
            self.theme = theme
            self.onPositionChange = onPositionChange
            self.onHighlightAppliedFromJS = onHighlightAppliedFromJS
            self.onSelection = onSelection
        }
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Web/WKWebViewReader.swift && \
  git commit -m "feat(mac): WKWebViewReader NSViewRepresentable"
```

---

## Task 9: Extend WebReaderBridge with selection + position channels

**Files:**
- Modify: `book-reader-mac/Reader/Web/WebReaderBridge.swift`

- [ ] **Step 1: Add selection/position callbacks and route them**

Replace the `handle` function inside `WebReaderBridge` in
`book-reader-mac/Reader/Web/WebReaderBridge.swift` and add the new callbacks
to the type. Final form of the relevant slice:

Locate `final class WebReaderBridge: NSObject, WKScriptMessageHandler {` and replace its body with:
```swift
@MainActor
final class WebReaderBridge: NSObject, WKScriptMessageHandler {
    static let messageName = "bridge"
    static let logger = Logger(subsystem: "com.profitoniumapps.instantbookreader",
                               category: "WebReaderBridge")

    private weak var webView: WKWebView?
    private let storage: WebReaderStorage

    var onSelectionChanged: ((CGRect, String) -> Void)?
    var onSelectionCleared: (() -> Void)?
    var onPositionChanged: ((String, Double, String?) -> Void)?

    init(storage: WebReaderStorage) {
        self.storage = storage
        super.init()
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
        storage.onChange { [weak self] changes in
            Task { @MainActor in self?.emitStorageChanged(changes) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let payload = message.body as? [String: Any],
              let id = payload["id"] as? String,
              let api = payload["api"] as? String else {
            Self.logger.error("dropped malformed bridge message")
            return
        }
        let args = payload["args"] as? [String: Any] ?? [:]
        handle(api: api, args: args, id: id)
    }

    private func handle(api: String, args: [String: Any], id: String) {
        switch api {
        case "storage.get":
            reply(id: id, payload: storage.get(parseQuery(args["keys"])))
        case "storage.set":
            if let items = args["items"] as? [String: Any] { storage.set(items) }
            reply(id: id, payload: [String: Any]())
        case "storage.remove":
            storage.remove(parseQuery(args["keys"]))
            reply(id: id, payload: [String: Any]())
        case "storage.allKeys":
            reply(id: id, payload: storage.get(.allKeys))
        case "runtime.openOptionsPage":
            NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
            reply(id: id, payload: [String: Any]())
        case "identity.getAuthToken":
            reply(id: id, payload: ["error": "not signed in"])
        case "identity.clearAllCachedAuthTokens":
            reply(id: id, payload: [String: Any]())
        case "ai.stream":
            reply(id: id, payload: ["error": "ai-not-configured"])
        case "selection.changed":
            if let rect = args["rect"] as? [String: Any],
               let x = (rect["x"] as? NSNumber)?.doubleValue,
               let y = (rect["y"] as? NSNumber)?.doubleValue,
               let w = (rect["w"] as? NSNumber)?.doubleValue,
               let h = (rect["h"] as? NSNumber)?.doubleValue {
                let r = CGRect(x: x, y: y, width: w, height: h)
                onSelectionChanged?(r, (args["text"] as? String) ?? "")
            }
        case "selection.clear":
            onSelectionCleared?()
        case "position.changed":
            let anchor = (args["anchor"] as? String) ?? ""
            let pct = (args["percentage"] as? NSNumber)?.doubleValue ?? 0
            let chapter = args["chapterTitle"] as? String
            onPositionChanged?(anchor, pct, chapter)
        default:
            Self.logger.notice("unhandled bridge api: \(api, privacy: .public)")
            reply(id: id, payload: ["error": "unsupported"])
        }
    }

    private func parseQuery(_ raw: Any?) -> WebReaderStorage.Query {
        if raw == nil { return .allKeys }
        if let s = raw as? String { return .array([s]) }
        if let arr = raw as? [String] { return .array(arr) }
        if let obj = raw as? [String: Any] { return .object(obj) }
        return .allKeys
    }

    private func reply(id: String, payload: [String: Any]) {
        guard let webView else { return }
        let json = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let js = "window.__wkBridgeReply && window.__wkBridgeReply(\(jsString(id)), \(json));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func emitStorageChanged(_ changes: [String: WebReaderStorage.Change]) {
        guard let webView else { return }
        var dict: [String: [String: Any]] = [:]
        for (k, c) in changes {
            var inner: [String: Any] = [:]
            if let o = c.oldValue { inner["oldValue"] = o }
            if let n = c.newValue { inner["newValue"] = n }
            dict[k] = inner
        }
        let json = (try? JSONSerialization.data(withJSONObject: dict))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let js = "window.__wkStorageChanged && window.__wkStorageChanged(\(json), 'local');"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
        let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(str.dropFirst().dropLast())
    }
}
```

- [ ] **Step 2: Build and rerun WebReaderBridgeTests**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/WebReaderBridgeTests 2>&1 | tail -10
```
Expected: `Test Suite 'WebReaderBridgeTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Web/WebReaderBridge.swift && \
  git commit -m "feat(mac): bridge channels for selection and position"
```

---

## Task 10: PDFDisplayMode enum

**Files:**
- Create: `book-reader-mac/Reader/PDF/PDFDisplayMode.swift`
- Create: `book-reader-mac/Tests/PDFDisplayModeTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/PDFDisplayModeTests.swift`:
```swift
import XCTest
import PDFKit
@testable import InstantBookReader

final class PDFDisplayModeTests: XCTestCase {
    func testMapsToPDFKitModes() {
        XCTAssertEqual(PDFDisplayModeOption.singlePage.pdfKit, .singlePage)
        XCTAssertEqual(PDFDisplayModeOption.singlePageContinuous.pdfKit, .singlePageContinuous)
        XCTAssertEqual(PDFDisplayModeOption.twoUp.pdfKit, .twoUp)
        XCTAssertEqual(PDFDisplayModeOption.twoUpContinuous.pdfKit, .twoUpContinuous)
    }

    func testAllCasesHaveLabels() {
        for option in PDFDisplayModeOption.allCases {
            XCTAssertFalse(option.label.isEmpty)
        }
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PDFDisplayModeTests 2>&1 | tail -10
```
Expected: compile error.

- [ ] **Step 3: Implement**

Write `book-reader-mac/Reader/PDF/PDFDisplayMode.swift`:
```swift
import PDFKit

enum PDFDisplayModeOption: String, CaseIterable, Identifiable, Sendable {
    case singlePage
    case singlePageContinuous
    case twoUp
    case twoUpContinuous

    var id: String { rawValue }

    var pdfKit: PDFDisplayMode {
        switch self {
        case .singlePage:           return .singlePage
        case .singlePageContinuous: return .singlePageContinuous
        case .twoUp:                return .twoUp
        case .twoUpContinuous:      return .twoUpContinuous
        }
    }

    var label: String {
        switch self {
        case .singlePage:           return "Single page"
        case .singlePageContinuous: return "Continuous"
        case .twoUp:                return "Spread"
        case .twoUpContinuous:      return "Continuous spread"
        }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PDFDisplayModeTests 2>&1 | tail -10
```
Expected: `Test Suite 'PDFDisplayModeTests' passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/PDF/PDFDisplayMode.swift \
          book-reader-mac/Tests/PDFDisplayModeTests.swift && \
  git commit -m "feat(mac): PDFDisplayModeOption enum"
```

---

## Task 11: PDFAnchorResolver — anchor PDF selections by surrounding text

**Files:**
- Create: `book-reader-mac/Reader/Anchors/PDFAnchorResolver.swift`
- Create: `book-reader-mac/Tests/PDFAnchorResolverTests.swift`

- [ ] **Step 1: Write the failing test using the fixture PDF**

Write `book-reader-mac/Tests/PDFAnchorResolverTests.swift`:
```swift
import XCTest
import PDFKit
@testable import InstantBookReader

final class PDFAnchorResolverTests: XCTestCase {
    func testRoundTripSelectionToAnchorBackToSelection() throws {
        let url = Fixtures.pdfURL
        let doc = try XCTUnwrap(PDFDocument(url: url))
        let page = try XCTUnwrap(doc.page(at: 0))
        let pageText = page.string ?? ""
        XCTAssertGreaterThan(pageText.count, 40, "fixture PDF must have at least 40 chars of text on page 0")

        // Pick a word from the middle so context is real on both sides.
        let lower = max(20, pageText.utf16.count / 2)
        let upper = lower + 8
        let nsText = pageText as NSString
        let probeRange = NSRange(location: lower, length: 8)
        let probeText = nsText.substring(with: probeRange)
        let selection = try XCTUnwrap(page.selection(for: probeRange))
        XCTAssertEqual(selection.string, probeText)

        let resolver = PDFAnchorResolver()
        let anchor = resolver.makeAnchor(from: selection, on: page, pageIndex: 0)
        XCTAssertEqual(anchor.text, probeText)
        XCTAssertEqual(anchor.pageIndex, 0)

        let resolved = try XCTUnwrap(resolver.resolve(anchor: anchor, in: doc))
        XCTAssertEqual(resolved.selection.string, probeText)
        XCTAssertEqual(resolved.pageIndex, 0)
    }

    func testResolveReturnsNilWhenContextDoesNotMatch() throws {
        let url = Fixtures.pdfURL
        let doc = try XCTUnwrap(PDFDocument(url: url))
        let resolver = PDFAnchorResolver()
        let anchor = PDFAnchorResolver.Anchor(
            pageIndex: 0,
            text: "definitely-not-in-this-pdf-xyzzy-987",
            inner: HighlightAnchor(startOffset: 0, length: 36,
                                   contextBefore: "nope-no-such-context-before-anywhere",
                                   contextAfter: "nope-no-such-context-after-anywhere")
        )
        XCTAssertNil(resolver.resolve(anchor: anchor, in: doc))
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PDFAnchorResolverTests 2>&1 | tail -10
```
Expected: compile error.

- [ ] **Step 3: Implement the resolver**

Write `book-reader-mac/Reader/Anchors/PDFAnchorResolver.swift`:
```swift
import Foundation
import PDFKit

/// Anchors PDF text selections using surrounding-text + offset, the same
/// scheme as the EPUB/TXT reader. Offsets are measured in UTF-16 units within
/// the page's `string` property.
struct PDFAnchorResolver {
    struct Anchor: Equatable {
        let pageIndex: Int
        let text: String
        let inner: HighlightAnchor
    }

    struct Resolved {
        let selection: PDFSelection
        let pageIndex: Int
    }

    func makeAnchor(from selection: PDFSelection, on page: PDFPage, pageIndex: Int) -> Anchor {
        let pageString = page.string ?? ""
        let selText = selection.string ?? ""
        let nsPage = pageString as NSString

        // Locate selection within page string. PDFSelection doesn't expose the
        // index directly; characterBounds(at:) lets us reverse-engineer it.
        let startOffset = offsetOfFirstCharacter(of: selection, in: page, pageString: pageString)
            ?? nsPage.range(of: selText).location
        let length = selText.utf16.count

        let inner = HighlightAnchor.build(plainText: pageString,
                                          startOffset: startOffset,
                                          length: length)
        return Anchor(pageIndex: pageIndex, text: selText, inner: inner)
    }

    func resolve(anchor: Anchor, in document: PDFDocument) -> Resolved? {
        guard let page = document.page(at: anchor.pageIndex) else { return nil }
        let pageString = page.string ?? ""
        guard let resolved = HighlightAnchor.resolve(plainText: pageString, anchor: anchor.inner) else {
            return nil
        }
        let range = NSRange(location: resolved.startOffset, length: resolved.length)
        guard let selection = page.selection(for: range) else { return nil }
        return Resolved(selection: selection, pageIndex: anchor.pageIndex)
    }

    /// Probes the first character's bounds and walks the page string for a
    /// match. Returns the UTF-16 offset of the first selected char.
    private func offsetOfFirstCharacter(of selection: PDFSelection,
                                        in page: PDFPage,
                                        pageString: String) -> Int? {
        let selText = selection.string ?? ""
        guard !selText.isEmpty else { return nil }
        let bounds = selection.bounds(for: page)
        let probePoint = CGPoint(x: bounds.minX + 1, y: bounds.midY)
        let charIndex = page.characterIndex(at: probePoint)
        if charIndex >= 0 { return charIndex }
        // Fallback: substring search.
        let ns = pageString as NSString
        let r = ns.range(of: selText)
        return r.location == NSNotFound ? nil : r.location
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PDFAnchorResolverTests 2>&1 | tail -10
```
Expected: `Test Suite 'PDFAnchorResolverTests' passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Anchors/PDFAnchorResolver.swift \
          book-reader-mac/Tests/PDFAnchorResolverTests.swift && \
  git commit -m "feat(mac): PDFAnchorResolver round-trip via fixture PDF"
```

---

## Task 12: TXTAnchorResolver — plain-text anchoring

**Files:**
- Create: `book-reader-mac/Reader/Anchors/TXTAnchorResolver.swift`
- Create: `book-reader-mac/Tests/TXTAnchorResolverTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/TXTAnchorResolverTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

final class TXTAnchorResolverTests: XCTestCase {
    func testRoundTripAgainstFixtureTXT() throws {
        let text = try String(contentsOf: Fixtures.txtURL, encoding: .utf8)
        XCTAssertGreaterThan(text.utf16.count, 120, "fixture TXT must have enough text to anchor in")

        let start = 60
        let length = 12
        let nsText = text as NSString
        let original = nsText.substring(with: NSRange(location: start, length: length))

        let resolver = TXTAnchorResolver()
        let anchor = resolver.makeAnchor(in: text, startOffset: start, length: length)
        XCTAssertEqual(anchor.text, original)

        let resolved = try XCTUnwrap(resolver.resolve(anchor: anchor, in: text))
        XCTAssertEqual(resolved.startOffset, start)
        XCTAssertEqual(resolved.length, length)
        let resolvedText = nsText.substring(with: NSRange(location: resolved.startOffset, length: resolved.length))
        XCTAssertEqual(resolvedText, original)
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/TXTAnchorResolverTests 2>&1 | tail -10
```
Expected: compile error.

- [ ] **Step 3: Implement**

Write `book-reader-mac/Reader/Anchors/TXTAnchorResolver.swift`:
```swift
import Foundation

/// Thin wrapper around HighlightAnchor for plain-text bodies. Adds the
/// selected `text` for convenience so the UI can display it without
/// re-slicing the document.
struct TXTAnchorResolver {
    struct Anchor: Equatable {
        let text: String
        let inner: HighlightAnchor
    }

    func makeAnchor(in plainText: String, startOffset: Int, length: Int) -> Anchor {
        let ns = plainText as NSString
        let safeRange = NSRange(location: max(0, startOffset),
                                length: min(length, ns.length - max(0, startOffset)))
        let selected = ns.substring(with: safeRange)
        let inner = HighlightAnchor.build(plainText: plainText,
                                          startOffset: safeRange.location,
                                          length: safeRange.length)
        return Anchor(text: selected, inner: inner)
    }

    func resolve(anchor: Anchor, in plainText: String) -> (startOffset: Int, length: Int)? {
        HighlightAnchor.resolve(plainText: plainText, anchor: anchor.inner)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/TXTAnchorResolverTests 2>&1 | tail -10
```
Expected: `Test Suite 'TXTAnchorResolverTests' passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Anchors/TXTAnchorResolver.swift \
          book-reader-mac/Tests/TXTAnchorResolverTests.swift && \
  git commit -m "feat(mac): TXTAnchorResolver for plain-text bodies"
```

---

## Task 13: HighlightedPDFView — PDFView subclass drawing PDFAnnotations

**Files:**
- Create: `book-reader-mac/Reader/PDF/HighlightedPDFView.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Reader/PDF/HighlightedPDFView.swift`:
```swift
import AppKit
import PDFKit

/// PDFView subclass that overlays `PDFAnnotation.highlight` on each saved
/// highlight. The owner calls `setHighlights(_:)` whenever the SwiftData
/// list changes; the view rebuilds the annotation set on each call.
final class HighlightedPDFView: PDFView {
    struct ResolvedHighlight {
        let id: UUID
        let pageIndex: Int
        let bounds: CGRect  // page coordinates
    }

    private var annotations: [UUID: PDFAnnotation] = [:]

    /// Replace the entire annotation set. Existing annotations are removed
    /// from their pages first.
    func setHighlights(_ items: [ResolvedHighlight], color: NSColor = NSColor.systemYellow.withAlphaComponent(0.4)) {
        for (_, annotation) in annotations {
            annotation.page?.removeAnnotation(annotation)
        }
        annotations.removeAll()

        guard let document else { return }
        for item in items {
            guard let page = document.page(at: item.pageIndex) else { continue }
            let annotation = PDFAnnotation(bounds: item.bounds,
                                           forType: .highlight,
                                           withProperties: nil)
            annotation.color = color
            annotation.userName = item.id.uuidString
            page.addAnnotation(annotation)
            annotations[item.id] = annotation
        }
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/PDF/HighlightedPDFView.swift && \
  git commit -m "feat(mac): HighlightedPDFView for PDFAnnotation overlays"
```

---

## Task 14: PDFReaderCoordinator — page change, selection, draw-fetch test

**Files:**
- Create: `book-reader-mac/Reader/PDF/PDFReaderCoordinator.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Reader/PDF/PDFReaderCoordinator.swift`:
```swift
import AppKit
import PDFKit

/// Owns notification subscriptions for a HighlightedPDFView and translates
/// them into typed Swift callbacks.
@MainActor
final class PDFReaderCoordinator: NSObject {
    private weak var pdfView: HighlightedPDFView?
    private var observers: [NSObjectProtocol] = []

    var onPageChanged: ((Int) -> Void)?
    var onSelectionChanged: ((PDFSelection?) -> Void)?

    func attach(to view: HighlightedPDFView) {
        self.pdfView = view
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .PDFViewPageChanged, object: view, queue: .main
        ) { [weak self] _ in
            guard let pdfView = self?.pdfView,
                  let current = pdfView.currentPage,
                  let index = pdfView.document?.index(for: current) else { return }
            self?.onPageChanged?(index)
        })
        observers.append(center.addObserver(
            forName: .PDFViewSelectionChanged, object: view, queue: .main
        ) { [weak self] _ in
            self?.onSelectionChanged?(self?.pdfView?.currentSelection)
        })
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/PDF/PDFReaderCoordinator.swift && \
  git commit -m "feat(mac): PDFReaderCoordinator for page/selection events"
```

---

## Task 15: PDFThumbnailStripView and PDFOutlinePanel

**Files:**
- Create: `book-reader-mac/Reader/PDF/PDFThumbnailStripView.swift`
- Create: `book-reader-mac/Reader/PDF/PDFOutlinePanel.swift`

- [ ] **Step 1: Implement the thumbnail strip**

Write `book-reader-mac/Reader/PDF/PDFThumbnailStripView.swift`:
```swift
import SwiftUI
import PDFKit

struct PDFThumbnailStripView: NSViewRepresentable {
    weak var pdfView: PDFView?
    let thumbnailSize: CGSize

    func makeNSView(context: Context) -> PDFThumbnailView {
        let strip = PDFThumbnailView()
        strip.thumbnailSize = thumbnailSize
        strip.layoutMode = .horizontal
        strip.backgroundColor = .clear
        strip.pdfView = pdfView
        return strip
    }

    func updateNSView(_ nsView: PDFThumbnailView, context: Context) {
        nsView.pdfView = pdfView
        nsView.thumbnailSize = thumbnailSize
    }
}
```

- [ ] **Step 2: Implement the outline panel**

Write `book-reader-mac/Reader/PDF/PDFOutlinePanel.swift`:
```swift
import SwiftUI
import PDFKit

/// Recursive disclosure tree for `PDFDocument.outlineRoot`. Clicking an
/// entry navigates the supplied PDFView to the entry's destination.
struct PDFOutlinePanel: View {
    let document: PDFDocument
    weak var pdfView: PDFView?

    var body: some View {
        if let root = document.outlineRoot, root.numberOfChildren > 0 {
            List {
                outlineRows(node: root)
            }
            .listStyle(.sidebar)
        } else {
            Text("No outline available")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding()
        }
    }

    @ViewBuilder
    private func outlineRows(node: PDFOutline) -> some View {
        ForEach(0..<node.numberOfChildren, id: \.self) { i in
            let child = node.child(at: i)!
            if child.numberOfChildren == 0 {
                Button(action: { go(to: child) }) {
                    Text(child.label ?? "Untitled")
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else {
                DisclosureGroup(child.label ?? "Untitled") {
                    outlineRows(node: child)
                }
            }
        }
    }

    private func go(to entry: PDFOutline) {
        guard let pdfView, let destination = entry.destination else { return }
        pdfView.go(to: destination)
    }
}
```

- [ ] **Step 3: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/PDF/PDFThumbnailStripView.swift \
          book-reader-mac/Reader/PDF/PDFOutlinePanel.swift && \
  git commit -m "feat(mac): PDF thumbnail strip and outline panel"
```

---

## Task 16: PDFReaderView — main NSViewRepresentable

**Files:**
- Create: `book-reader-mac/Reader/PDF/PDFReaderView.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Reader/PDF/PDFReaderView.swift`:
```swift
import SwiftUI
import PDFKit

/// Top-level PDF reader. Hosts a HighlightedPDFView and exposes display
/// mode, current page, selection, and TOC outline to SwiftUI bindings.
struct PDFReaderView: NSViewRepresentable {
    let book: Book
    let document: PDFDocument
    @Binding var displayMode: PDFDisplayModeOption
    @Binding var currentPageIndex: Int
    @Binding var currentSelection: PDFSelection?
    let onSelectionRect: (CGRect?) -> Void   // converted into pdfView.bounds coordinates

    func makeCoordinator() -> PDFReaderCoordinator {
        let coordinator = PDFReaderCoordinator()
        coordinator.onPageChanged = { idx in
            DispatchQueue.main.async { currentPageIndex = idx }
        }
        coordinator.onSelectionChanged = { selection in
            DispatchQueue.main.async {
                currentSelection = selection
                if let selection,
                   let page = selection.pages.first {
                    // bounds in page space → pdfView space
                    onSelectionRect(nil) // computed by the host in updateNSView
                    _ = page
                } else {
                    onSelectionRect(nil)
                }
            }
        }
        return coordinator
    }

    func makeNSView(context: Context) -> HighlightedPDFView {
        let view = HighlightedPDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = displayMode.pdfKit
        view.backgroundColor = .clear
        view.displaysPageBreaks = true
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: HighlightedPDFView, context: Context) {
        if nsView.displayMode != displayMode.pdfKit {
            nsView.displayMode = displayMode.pdfKit
        }
        if nsView.document !== document {
            nsView.document = document
        }
        if let target = document.page(at: currentPageIndex),
           nsView.currentPage !== target {
            nsView.go(to: target)
        }
        if let selection = nsView.currentSelection,
           let page = selection.pages.first {
            let pageRect = selection.bounds(for: page)
            let viewRect = nsView.convert(pageRect, from: page)
            onSelectionRect(viewRect)
        } else {
            onSelectionRect(nil)
        }
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/PDF/PDFReaderView.swift && \
  git commit -m "feat(mac): PDFReaderView NSViewRepresentable"
```

---

## Task 17: TXTReaderView — chunked SwiftUI ScrollView

**Files:**
- Create: `book-reader-mac/Reader/TXT/TXTReaderView.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Reader/TXT/TXTReaderView.swift`:
```swift
import SwiftUI

/// Plain text reader. Splits the document into ~4 KB chunks rendered as
/// separate `Text` views inside a ScrollView, so SwiftUI's diffing stays
/// cheap on long files. Position anchor is the leading UTF-16 offset of the
/// chunk most visible in the scroll viewport.
struct TXTReaderView: View {
    let book: Book
    let plainText: String
    @Environment(\.appTheme) private var theme
    @Binding var currentOffset: Int
    @Binding var selectedRange: NSRange?
    let onSelectionRect: (CGRect?, String) -> Void

    private static let chunkSize = 4_096

    private struct Chunk: Identifiable {
        let id: Int      // chunk index
        let startOffset: Int
        let text: String
    }

    private var chunks: [Chunk] {
        let ns = plainText as NSString
        let total = ns.length
        var out: [Chunk] = []
        var i = 0
        var idx = 0
        while i < total {
            let len = min(Self.chunkSize, total - i)
            out.append(Chunk(id: idx, startOffset: i, text: ns.substring(with: NSRange(location: i, length: len))))
            i += len
            idx += 1
        }
        return out
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(chunks) { chunk in
                        Text(chunk.text)
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .foregroundStyle(theme.ink.swiftUI)
                            .textSelection(.enabled)
                            .frame(maxWidth: 720, alignment: .leading)
                            .padding(.horizontal, 48)
                            .id(chunk.id)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: TXTVisibleChunkKey.self,
                                        value: geo.frame(in: .named("txt-scroll")).minY < 200
                                            ? chunk.startOffset
                                            : Int.max
                                    )
                                }
                            )
                    }
                }
                .padding(.vertical, 48)
            }
            .coordinateSpace(name: "txt-scroll")
            .onPreferenceChange(TXTVisibleChunkKey.self) { offset in
                if offset != Int.max && offset != currentOffset {
                    currentOffset = offset
                }
            }
        }
    }
}

private struct TXTVisibleChunkKey: PreferenceKey {
    static var defaultValue: Int = Int.max
    static func reduce(value: inout Int, nextValue: () -> Int) {
        value = min(value, nextValue())
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/TXT/TXTReaderView.swift && \
  git commit -m "feat(mac): TXTReaderView chunked ScrollView"
```

---

## Task 18: PositionRecorder — 500 ms debounce

**Files:**
- Create: `book-reader-mac/Reader/Position/PositionRecorder.swift`
- Create: `book-reader-mac/Tests/PositionRecorderTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/PositionRecorderTests.swift`:
```swift
import XCTest
import SwiftData
@testable import InstantBookReader

final class PositionRecorderTests: XCTestCase {
    @MainActor
    func testDebouncesRapidWritesIntoSingleSave() async throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)
        let book = Book(sha256: "deadbeef", title: "T", format: .pdf, filePath: "x")
        context.insert(book)
        try context.save()

        let recorder = PositionRecorder(modelContainer: container, debounce: 0.2)
        for i in 0..<10 {
            recorder.record(bookHash: "deadbeef", anchor: "page:\(i)", percentage: Double(i) * 0.1, chapterTitle: nil)
        }
        try await Task.sleep(nanoseconds: 400_000_000)

        let positions = try ModelContext(container).fetch(FetchDescriptor<Position>())
        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions.first?.anchor, "page:9")
        XCTAssertEqual(positions.first?.bookHash, "deadbeef")
    }

    @MainActor
    func testFlushWritesImmediately() async throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(Book(sha256: "abc", title: "B", format: .epub, filePath: "y"))
        try context.save()

        let recorder = PositionRecorder(modelContainer: container, debounce: 5.0)
        recorder.record(bookHash: "abc", anchor: "cfi:/4/2", percentage: 0.5, chapterTitle: "Chapter 2")
        await recorder.flush()

        let positions = try ModelContext(container).fetch(FetchDescriptor<Position>())
        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions.first?.chapterTitle, "Chapter 2")
        XCTAssertEqual(positions.first?.percentage, 0.5, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PositionRecorderTests 2>&1 | tail -10
```
Expected: compile error.

- [ ] **Step 3: Implement**

Write `book-reader-mac/Reader/Position/PositionRecorder.swift`:
```swift
import Foundation
import SwiftData

/// Debounced position writer. Coalesces 500 ms of rapid scroll/page-change
/// events into a single SwiftData save.
@MainActor
final class PositionRecorder {
    private struct Pending {
        let bookHash: String
        let anchor: String
        let percentage: Double
        let chapterTitle: String?
    }

    private let modelContainer: ModelContainer
    private let debounce: TimeInterval
    private var task: Task<Void, Never>?
    private var pending: Pending?

    init(modelContainer: ModelContainer, debounce: TimeInterval = 0.5) {
        self.modelContainer = modelContainer
        self.debounce = debounce
    }

    func record(bookHash: String, anchor: String, percentage: Double, chapterTitle: String?) {
        pending = Pending(bookHash: bookHash,
                          anchor: anchor,
                          percentage: percentage,
                          chapterTitle: chapterTitle)
        task?.cancel()
        let interval = debounce
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if Task.isCancelled { return }
            await self?.flush()
        }
    }

    func flush() async {
        task?.cancel()
        task = nil
        guard let p = pending else { return }
        pending = nil
        let context = ModelContext(modelContainer)
        let hash = p.bookHash
        let descriptor = FetchDescriptor<Position>(
            predicate: #Predicate { $0.bookHash == hash }
        )
        do {
            let existing = try context.fetch(descriptor)
            if let position = existing.first {
                position.anchor = p.anchor
                position.percentage = p.percentage
                position.chapterTitle = p.chapterTitle
                position.updatedAt = .now
            } else {
                context.insert(Position(bookHash: p.bookHash,
                                        anchor: p.anchor,
                                        percentage: p.percentage,
                                        chapterTitle: p.chapterTitle))
            }
            try context.save()
        } catch {
            // Surfacing this through a UI banner is a Plan 7 concern.
            // For now, silently drop — re-recording will retry within debounce.
            _ = error
        }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PositionRecorderTests 2>&1 | tail -10
```
Expected: `Test Suite 'PositionRecorderTests' passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Position/PositionRecorder.swift \
          book-reader-mac/Tests/PositionRecorderTests.swift && \
  git commit -m "feat(mac): PositionRecorder debounces 500ms writes"
```

---

## Task 19: SelectionToolbarView — SwiftUI toolbar UI

**Files:**
- Create: `book-reader-mac/Reader/Selection/SelectionToolbarView.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Reader/Selection/SelectionToolbarView.swift`:
```swift
import SwiftUI

/// SwiftUI content for the selection popover. v1 buttons:
///   Highlight — saves a Highlight via the supplied closure.
///   Copy — copies the selected text to the pasteboard.
///   Explain — disabled stub; Plan 4 wires the AI call.
struct SelectionToolbarView: View {
    let selectedText: String
    let onHighlight: () -> Void
    let onCopy: () -> Void
    let onExplain: () -> Void
    let aiConfigured: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            button("Highlight", systemImage: "highlighter", action: onHighlight)
            divider
            button("Copy", systemImage: "doc.on.doc", action: onCopy)
            divider
            VStack(spacing: 2) {
                button("Explain", systemImage: "sparkles", action: onExplain, enabled: aiConfigured)
                if !aiConfigured {
                    Text("Add an AI key in Settings")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.ink.swiftUI.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(theme.surface.swiftUI)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.border.swiftUI, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.border.swiftUI.opacity(0.6))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }

    private func button(_ title: String,
                        systemImage: String,
                        action: @escaping () -> Void,
                        enabled: Bool = true) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(theme.ink.swiftUI.opacity(enabled ? 1.0 : 0.4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Selection/SelectionToolbarView.swift && \
  git commit -m "feat(mac): SelectionToolbarView with Highlight/Copy/Explain"
```

---

## Task 20: SelectionPopover — NSPopover host

**Files:**
- Create: `book-reader-mac/Reader/Selection/SelectionPopover.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Reader/Selection/SelectionPopover.swift`:
```swift
import AppKit
import SwiftUI

/// AppKit popover host for the selection toolbar. The owner positions the
/// popover via `show(over:rect:)` using rects expressed in the supplied
/// `positioningView`'s coordinate space.
@MainActor
final class SelectionPopover {
    private let popover: NSPopover
    private var hostingController: NSHostingController<SelectionToolbarView>?
    private let theme: AppTheme

    init(theme: AppTheme) {
        self.theme = theme
        self.popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
    }

    func show(over view: NSView,
              rect: CGRect,
              selectedText: String,
              aiConfigured: Bool,
              onHighlight: @escaping () -> Void,
              onCopy: @escaping () -> Void,
              onExplain: @escaping () -> Void) {
        let content = SelectionToolbarView(
            selectedText: selectedText,
            onHighlight: { [weak self] in
                onHighlight()
                self?.dismiss()
            },
            onCopy: { [weak self] in
                onCopy()
                self?.dismiss()
            },
            onExplain: onExplain,
            aiConfigured: aiConfigured
        ).environment(\.appTheme, theme)

        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = [.intrinsicContentSize]
        hostingController = controller
        popover.contentViewController = controller

        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    }

    func dismiss() {
        popover.close()
        hostingController = nil
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Selection/SelectionPopover.swift && \
  git commit -m "feat(mac): SelectionPopover NSPopover host"
```

---

## Task 21: ReaderRouter SwiftUI view

**Files:**
- Create: `book-reader-mac/Reader/ReaderRouter.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Reader/ReaderRouter.swift`:
```swift
import SwiftUI
import SwiftData
import PDFKit
import AppKit

/// Top-level router for the active reader. Resolves the current book from
/// ReadingState and dispatches to the format-specific view. Owns the
/// PositionRecorder and the selection popover.
struct ReaderRouter: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(ReadingState.self) private var state
    @Query private var books: [Book]

    @State private var pdfDocument: PDFDocument?
    @State private var pdfDisplayMode: PDFDisplayModeOption = .singlePageContinuous
    @State private var pdfPageIndex: Int = 0
    @State private var pdfSelection: PDFSelection?
    @State private var pdfSelectionRect: CGRect?

    @State private var txtPlainText: String = ""
    @State private var txtOffset: Int = 0
    @State private var txtSelectedRange: NSRange?

    @State private var webSelectionRect: CGRect?
    @State private var webSelectionText: String = ""

    @State private var recorder: PositionRecorder?
    @State private var popoverHost = SelectionPopoverHost()

    private var currentBook: Book? {
        guard let hash = state.currentBookHash else { return nil }
        return books.first(where: { $0.sha256 == hash })
    }

    var body: some View {
        Group {
            if let book = currentBook {
                content(for: book)
            } else {
                emptyState
            }
        }
        .background(theme.surface.swiftUI)
        .onAppear { ensureRecorder() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No book open")
                .font(.system(size: 24, weight: .medium, design: .serif))
                .foregroundStyle(theme.ink.swiftUI)
            Text("Open a book from the Library window")
                .font(.system(size: 13))
                .foregroundStyle(theme.ink.swiftUI.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for book: Book) -> some View {
        switch book.format {
        case .pdf:
            pdfContent(book: book)
        case .epub:
            webContent(book: book)
        case .txt:
            txtContent(book: book)
        }
    }

    @ViewBuilder
    private func pdfContent(book: Book) -> some View {
        if let doc = pdfDocument {
            HStack(spacing: 0) {
                PDFOutlinePanel(document: doc, pdfView: nil)
                    .frame(width: 240)
                VStack(spacing: 0) {
                    PDFReaderView(book: book,
                                  document: doc,
                                  displayMode: $pdfDisplayMode,
                                  currentPageIndex: $pdfPageIndex,
                                  currentSelection: $pdfSelection,
                                  onSelectionRect: { rect in pdfSelectionRect = rect })
                    PDFThumbnailStripView(pdfView: nil, thumbnailSize: CGSize(width: 80, height: 100))
                        .frame(height: 110)
                }
            }
            .onChange(of: pdfPageIndex) { _, newValue in
                let pct = Double(newValue) / Double(max(1, doc.pageCount - 1))
                recorder?.record(bookHash: book.sha256,
                                 anchor: "\(newValue):0",
                                 percentage: pct,
                                 chapterTitle: nil)
            }
        } else {
            ProgressView()
                .onAppear {
                    let url = AppSupportPaths.books.appendingPathComponent("\(book.sha256).pdf")
                    pdfDocument = PDFDocument(url: url)
                }
        }
    }

    @ViewBuilder
    private func webContent(book: Book) -> some View {
        WKWebViewReader(
            book: book,
            selectionRect: $webSelectionRect,
            selectionText: $webSelectionText,
            theme: theme,
            onPositionChange: { anchor, pct, chapter in
                recorder?.record(bookHash: book.sha256,
                                 anchor: anchor,
                                 percentage: pct,
                                 chapterTitle: chapter)
            },
            onHighlightAppliedFromJS: { _ in }
        )
    }

    @ViewBuilder
    private func txtContent(book: Book) -> some View {
        TXTReaderView(book: book,
                      plainText: txtPlainText,
                      currentOffset: $txtOffset,
                      selectedRange: $txtSelectedRange,
                      onSelectionRect: { _, _ in })
            .onAppear {
                let url = AppSupportPaths.books.appendingPathComponent("\(book.sha256).txt")
                txtPlainText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            }
            .onChange(of: txtOffset) { _, newValue in
                let total = max(1, txtPlainText.utf16.count)
                recorder?.record(bookHash: book.sha256,
                                 anchor: "\(newValue)",
                                 percentage: Double(newValue) / Double(total),
                                 chapterTitle: nil)
            }
    }

    private func ensureRecorder() {
        guard recorder == nil else { return }
        recorder = PositionRecorder(modelContainer: modelContext.container)
    }
}

/// Tiny @Observable container for the SelectionPopover so we can mutate it
/// without re-creating per render. The popover itself is AppKit; we hold it
/// via a class so SwiftUI doesn't try to compare or recreate it.
@MainActor
final class SelectionPopoverHost: ObservableObject {
    let popover = SelectionPopover(theme: .clayDark)
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/ReaderRouter.swift && \
  git commit -m "feat(mac): ReaderRouter dispatches by Book.format"
```

---

## Task 22: Wire ReaderRouter into ReaderWindowController

**Files:**
- Modify: `book-reader-mac/Windows/ReaderWindowController.swift`

- [ ] **Step 1: Replace PlaceholderReaderView with ReaderRouter**

Open `book-reader-mac/Windows/ReaderWindowController.swift`. In the `init` method, replace the `PlaceholderReaderView()` content with `ReaderRouter()`. The init becomes:

```swift
    init(state: ReadingState, modelContainer: ModelContainer, theme: AppTheme) {
        self.state = state
        self.modelContainer = modelContainer
        self.theme = theme
        self.window = ReaderWindow()
        let content = ReaderRouter()
            .environment(\.appTheme, theme)
            .environment(state)
            .modelContainer(modelContainer)
        self.window.contentView = NSHostingView(rootView: content)
        self.window.alphaValue = 0
        self.window.orderOut(nil)
    }
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Windows/ReaderWindowController.swift && \
  git commit -m "feat(mac): ReaderWindowController hosts ReaderRouter"
```

---

## Task 23: Wire PDF selection toolbar in PDFReaderView via a host NSView

**Files:**
- Modify: `book-reader-mac/Reader/PDF/PDFReaderView.swift`
- Modify: `book-reader-mac/Reader/ReaderRouter.swift`

- [ ] **Step 1: Pass an `onSaveHighlight` callback through PDFReaderView and show the popover**

Open `book-reader-mac/Reader/PDF/PDFReaderView.swift` and extend it to accept the popover host + a save callback. Replace the struct with:

```swift
import SwiftUI
import PDFKit

struct PDFReaderView: NSViewRepresentable {
    let book: Book
    let document: PDFDocument
    @Binding var displayMode: PDFDisplayModeOption
    @Binding var currentPageIndex: Int
    @Binding var currentSelection: PDFSelection?
    let theme: AppTheme
    let aiConfigured: Bool
    let onSaveHighlight: (PDFAnchorResolver.Anchor, String) -> Void
    let onCopyText: (String) -> Void
    let onExplain: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> HighlightedPDFView {
        let view = HighlightedPDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = displayMode.pdfKit
        view.backgroundColor = .clear
        view.displaysPageBreaks = true
        context.coordinator.popover = SelectionPopover(theme: theme)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: HighlightedPDFView, context: Context) {
        if nsView.displayMode != displayMode.pdfKit {
            nsView.displayMode = displayMode.pdfKit
        }
        if nsView.document !== document {
            nsView.document = document
        }
        if let target = document.page(at: currentPageIndex),
           nsView.currentPage !== target {
            nsView.go(to: target)
        }
        context.coordinator.theme = theme
        context.coordinator.aiConfigured = aiConfigured
    }

    @MainActor
    final class Coordinator: NSObject {
        let parent: PDFReaderView
        weak var pdfView: HighlightedPDFView?
        var popover: SelectionPopover?
        var theme: AppTheme
        var aiConfigured: Bool
        private var observers: [NSObjectProtocol] = []
        private let resolver = PDFAnchorResolver()

        init(parent: PDFReaderView) {
            self.parent = parent
            self.theme = parent.theme
            self.aiConfigured = parent.aiConfigured
        }

        func attach(to view: HighlightedPDFView) {
            self.pdfView = view
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: .PDFViewPageChanged, object: view, queue: .main
            ) { [weak self] _ in
                guard let self,
                      let view = self.pdfView,
                      let current = view.currentPage,
                      let index = view.document?.index(for: current) else { return }
                self.parent.currentPageIndex = index
            })
            observers.append(center.addObserver(
                forName: .PDFViewSelectionChanged, object: view, queue: .main
            ) { [weak self] _ in
                self?.handleSelectionChanged()
            })
        }

        private func handleSelectionChanged() {
            guard let view = pdfView,
                  let selection = view.currentSelection,
                  let page = selection.pages.first,
                  let text = selection.string,
                  !text.isEmpty,
                  let pageIndex = view.document?.index(for: page) else {
                popover?.dismiss()
                parent.currentSelection = nil
                return
            }
            parent.currentSelection = selection
            let pageRect = selection.bounds(for: page)
            let viewRect = view.convert(pageRect, from: page)
            let anchor = resolver.makeAnchor(from: selection, on: page, pageIndex: pageIndex)
            popover?.show(
                over: view,
                rect: viewRect,
                selectedText: text,
                aiConfigured: aiConfigured,
                onHighlight: { [weak self] in
                    self?.parent.onSaveHighlight(anchor, text)
                },
                onCopy: { [weak self] in
                    self?.parent.onCopyText(text)
                },
                onExplain: { [weak self] in
                    self?.parent.onExplain(text)
                }
            )
        }

        deinit {
            for o in observers { NotificationCenter.default.removeObserver(o) }
        }
    }
}
```

- [ ] **Step 2: Update ReaderRouter's `pdfContent(book:)` to provide the new callbacks**

In `book-reader-mac/Reader/ReaderRouter.swift`, replace `pdfContent(book:)` with:

```swift
    @ViewBuilder
    private func pdfContent(book: Book) -> some View {
        if let doc = pdfDocument {
            HStack(spacing: 0) {
                PDFOutlinePanel(document: doc, pdfView: nil)
                    .frame(width: 240)
                VStack(spacing: 0) {
                    PDFReaderView(book: book,
                                  document: doc,
                                  displayMode: $pdfDisplayMode,
                                  currentPageIndex: $pdfPageIndex,
                                  currentSelection: $pdfSelection,
                                  theme: theme,
                                  aiConfigured: false,
                                  onSaveHighlight: { anchor, text in
                                      saveHighlight(book: book, anchor: anchor, text: text)
                                  },
                                  onCopyText: { text in
                                      NSPasteboard.general.clearContents()
                                      NSPasteboard.general.setString(text, forType: .string)
                                  },
                                  onExplain: { _ in
                                      // Plan 4 wires this. v1: no-op (button is disabled).
                                  })
                    PDFThumbnailStripView(pdfView: nil, thumbnailSize: CGSize(width: 80, height: 100))
                        .frame(height: 110)
                }
            }
            .onChange(of: pdfPageIndex) { _, newValue in
                let pct = Double(newValue) / Double(max(1, doc.pageCount - 1))
                recorder?.record(bookHash: book.sha256,
                                 anchor: "\(newValue):0",
                                 percentage: pct,
                                 chapterTitle: nil)
            }
        } else {
            ProgressView()
                .onAppear {
                    let url = AppSupportPaths.books.appendingPathComponent("\(book.sha256).pdf")
                    pdfDocument = PDFDocument(url: url)
                }
        }
    }

    private func saveHighlight(book: Book,
                               anchor: PDFAnchorResolver.Anchor,
                               text: String) {
        let serialized = "pdf:\(anchor.pageIndex):\(anchor.inner.startOffset)"
        let highlight = Highlight(bookHash: book.sha256,
                                  text: text,
                                  surroundingText: serialized,
                                  offset: anchor.inner.startOffset)
        highlight.book = book
        modelContext.insert(highlight)
        try? modelContext.save()
    }
```

The `serialized` form encodes `pageIndex:startOffset:length:contextBefore:contextAfter` would be cleaner, but for v1 the SwiftData model only stores `surroundingText: String + offset: Int`, so the resolver-side encoding is `pdf:<pageIndex>:<startOffset>` and the surrounding-text JSON is left for Task 24.

- [ ] **Step 3: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/PDF/PDFReaderView.swift \
          book-reader-mac/Reader/ReaderRouter.swift && \
  git commit -m "feat(mac): PDF selection popover wired through ReaderRouter"
```

---

## Task 24: Serialize PDF highlights with full anchor — round-trip test

**Files:**
- Create: `book-reader-mac/Reader/Anchors/PDFHighlightSerializer.swift`
- Modify: `book-reader-mac/Tests/PDFAnchorResolverTests.swift`

- [ ] **Step 1: Implement the serializer**

Write `book-reader-mac/Reader/Anchors/PDFHighlightSerializer.swift`:
```swift
import Foundation

/// Serializes a PDFAnchorResolver.Anchor into the `surroundingText: String`
/// column of the SwiftData Highlight model. JSON-encoded so we don't depend
/// on schema migrations to widen the model.
struct PDFHighlightSerializer {
    enum Error: Swift.Error { case malformed }

    func encode(_ anchor: PDFAnchorResolver.Anchor) -> String {
        let payload: [String: Any] = [
            "pageIndex": anchor.pageIndex,
            "text": anchor.text,
            "inner": [
                "startOffset": anchor.inner.startOffset,
                "length": anchor.inner.length,
                "contextBefore": anchor.inner.contextBefore,
                "contextAfter": anchor.inner.contextAfter
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func decode(_ string: String) throws -> PDFAnchorResolver.Anchor {
        guard let data = string.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pageIndex = obj["pageIndex"] as? Int,
              let text = obj["text"] as? String,
              let inner = obj["inner"] as? [String: Any],
              let startOffset = inner["startOffset"] as? Int,
              let length = inner["length"] as? Int,
              let contextBefore = inner["contextBefore"] as? String,
              let contextAfter = inner["contextAfter"] as? String
        else { throw Error.malformed }
        return PDFAnchorResolver.Anchor(
            pageIndex: pageIndex,
            text: text,
            inner: HighlightAnchor(startOffset: startOffset,
                                   length: length,
                                   contextBefore: contextBefore,
                                   contextAfter: contextAfter)
        )
    }
}
```

- [ ] **Step 2: Add a round-trip test to PDFAnchorResolverTests**

Append the following test method to
`book-reader-mac/Tests/PDFAnchorResolverTests.swift`:
```swift
    func testSerializerRoundTrip() throws {
        let url = Fixtures.pdfURL
        let doc = try XCTUnwrap(PDFDocument(url: url))
        let page = try XCTUnwrap(doc.page(at: 0))
        let pageText = page.string ?? ""
        let nsText = pageText as NSString
        let lower = max(20, nsText.length / 2)
        let probeRange = NSRange(location: lower, length: 6)
        let selection = try XCTUnwrap(page.selection(for: probeRange))

        let resolver = PDFAnchorResolver()
        let serializer = PDFHighlightSerializer()
        let anchor = resolver.makeAnchor(from: selection, on: page, pageIndex: 0)
        let encoded = serializer.encode(anchor)
        let decoded = try serializer.decode(encoded)
        XCTAssertEqual(decoded.pageIndex, anchor.pageIndex)
        XCTAssertEqual(decoded.text, anchor.text)
        XCTAssertEqual(decoded.inner, anchor.inner)

        let resolved = try XCTUnwrap(resolver.resolve(anchor: decoded, in: doc))
        XCTAssertEqual(resolved.selection.string, anchor.text)
    }
```

- [ ] **Step 3: Update ReaderRouter's `saveHighlight` to use the serializer**

In `book-reader-mac/Reader/ReaderRouter.swift`, replace the `saveHighlight` method body with:
```swift
    private func saveHighlight(book: Book,
                               anchor: PDFAnchorResolver.Anchor,
                               text: String) {
        let serializer = PDFHighlightSerializer()
        let encoded = serializer.encode(anchor)
        let highlight = Highlight(bookHash: book.sha256,
                                  text: text,
                                  surroundingText: encoded,
                                  offset: anchor.inner.startOffset)
        highlight.book = book
        modelContext.insert(highlight)
        try? modelContext.save()
    }
```

- [ ] **Step 4: Run the tests**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PDFAnchorResolverTests 2>&1 | tail -10
```
Expected: `Test Suite 'PDFAnchorResolverTests' passed` with the new test included.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Anchors/PDFHighlightSerializer.swift \
          book-reader-mac/Tests/PDFAnchorResolverTests.swift \
          book-reader-mac/Reader/ReaderRouter.swift && \
  git commit -m "feat(mac): serialize PDF highlight anchors to surroundingText"
```

---

## Task 25: Apply saved PDF highlights on document load

**Files:**
- Modify: `book-reader-mac/Reader/ReaderRouter.swift`

- [ ] **Step 1: Add a renderer and call it after the document loads**

In `book-reader-mac/Reader/ReaderRouter.swift`, modify `pdfContent(book:)` and add a helper to rebuild annotations from saved highlights. Add an `@Query` for highlights filtered by book, and a `pdfViewRef` so the helper can call `setHighlights`.

Replace the existing struct's stored properties block (top of `ReaderRouter`) with:

```swift
struct ReaderRouter: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(ReadingState.self) private var state
    @Query private var books: [Book]
    @Query private var highlights: [Highlight]

    @State private var pdfDocument: PDFDocument?
    @State private var pdfDisplayMode: PDFDisplayModeOption = .singlePageContinuous
    @State private var pdfPageIndex: Int = 0
    @State private var pdfSelection: PDFSelection?
    @State private var pdfSelectionRect: CGRect?
    @State private var pdfViewRef = WeakBox<HighlightedPDFView>()

    @State private var txtPlainText: String = ""
    @State private var txtOffset: Int = 0
    @State private var txtSelectedRange: NSRange?

    @State private var webSelectionRect: CGRect?
    @State private var webSelectionText: String = ""

    @State private var recorder: PositionRecorder?
```

Add `WeakBox` at file scope (below the file's `ReaderRouter` body, alongside `SelectionPopoverHost`):

```swift
@MainActor
final class WeakBox<T: AnyObject> {
    weak var value: T?
}
```

Then in `pdfContent(book:)`, after `pdfDocument = PDFDocument(url: url)`, set the highlights on appear and on highlights change. Replace `pdfContent(book:)` with:

```swift
    @ViewBuilder
    private func pdfContent(book: Book) -> some View {
        let savedHighlights = highlights.filter { $0.bookHash == book.sha256 }
        if let doc = pdfDocument {
            HStack(spacing: 0) {
                PDFOutlinePanel(document: doc, pdfView: pdfViewRef.value)
                    .frame(width: 240)
                VStack(spacing: 0) {
                    PDFReaderView(book: book,
                                  document: doc,
                                  displayMode: $pdfDisplayMode,
                                  currentPageIndex: $pdfPageIndex,
                                  currentSelection: $pdfSelection,
                                  theme: theme,
                                  aiConfigured: false,
                                  onSaveHighlight: { anchor, text in
                                      saveHighlight(book: book, anchor: anchor, text: text)
                                  },
                                  onCopyText: { text in
                                      NSPasteboard.general.clearContents()
                                      NSPasteboard.general.setString(text, forType: .string)
                                  },
                                  onExplain: { _ in })
                    .background(
                        PDFViewCapture(pdfViewRef: pdfViewRef)
                    )
                    PDFThumbnailStripView(pdfView: pdfViewRef.value,
                                          thumbnailSize: CGSize(width: 80, height: 100))
                        .frame(height: 110)
                }
            }
            .onChange(of: pdfPageIndex) { _, newValue in
                let pct = Double(newValue) / Double(max(1, doc.pageCount - 1))
                recorder?.record(bookHash: book.sha256,
                                 anchor: "\(newValue):0",
                                 percentage: pct,
                                 chapterTitle: nil)
            }
            .onChange(of: savedHighlights.count) { _, _ in
                rebuildPDFHighlights(book: book, document: doc, highlights: savedHighlights)
            }
            .task { rebuildPDFHighlights(book: book, document: doc, highlights: savedHighlights) }
        } else {
            ProgressView()
                .onAppear {
                    let url = AppSupportPaths.books.appendingPathComponent("\(book.sha256).pdf")
                    pdfDocument = PDFDocument(url: url)
                }
        }
    }

    private func rebuildPDFHighlights(book: Book,
                                      document: PDFDocument,
                                      highlights: [Highlight]) {
        guard let view = pdfViewRef.value else { return }
        let resolver = PDFAnchorResolver()
        let serializer = PDFHighlightSerializer()
        var resolved: [HighlightedPDFView.ResolvedHighlight] = []
        for h in highlights {
            guard let anchor = try? serializer.decode(h.surroundingText),
                  let r = resolver.resolve(anchor: anchor, in: document),
                  let page = r.selection.pages.first else { continue }
            let bounds = r.selection.bounds(for: page)
            resolved.append(.init(id: h.clientID,
                                  pageIndex: r.pageIndex,
                                  bounds: bounds))
        }
        view.setHighlights(resolved)
    }
```

Add the capture helper at file scope:

```swift
private struct PDFViewCapture: NSViewRepresentable {
    let pdfViewRef: WeakBox<HighlightedPDFView>

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Walk up until we find the HighlightedPDFView sibling.
        DispatchQueue.main.async {
            guard let parent = nsView.superview else { return }
            for sibling in parent.subviews {
                if let pdfView = sibling as? HighlightedPDFView {
                    pdfViewRef.value = pdfView
                    return
                }
                if let pdfView = findPDFView(in: sibling) {
                    pdfViewRef.value = pdfView
                    return
                }
            }
        }
    }

    private func findPDFView(in view: NSView) -> HighlightedPDFView? {
        if let v = view as? HighlightedPDFView { return v }
        for sub in view.subviews {
            if let found = findPDFView(in: sub) { return found }
        }
        return nil
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/ReaderRouter.swift && \
  git commit -m "feat(mac): rebuild PDF annotations from saved highlights"
```

---

## Task 26: Wire web selection popover via the bridge

**Files:**
- Modify: `book-reader-mac/Reader/Web/WKWebViewReader.swift`
- Modify: `book-reader-mac/Reader/ReaderRouter.swift`

- [ ] **Step 1: Surface selection events out of WKWebViewReader**

In `book-reader-mac/Reader/Web/WKWebViewReader.swift`, replace `makeCoordinator()` and `makeNSView(context:)` so the bridge's selection callbacks flow up. Update the struct's public surface to accept `onSelectionChanged` and `onSelectionCleared`:

Replace the struct declaration block (top of file) with:

```swift
struct WKWebViewReader: NSViewRepresentable {
    let book: Book
    let theme: AppTheme
    let onPositionChange: (String, Double, String?) -> Void
    let onSelectionChanged: (CGRect, String) -> Void
    let onSelectionCleared: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(book: book, theme: theme)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let storage = WebReaderStorage()
        let bridge = WebReaderBridge(storage: storage)
        bridge.onSelectionChanged = onSelectionChanged
        bridge.onSelectionCleared = onSelectionCleared
        bridge.onPositionChanged = onPositionChange
        context.coordinator.bridge = bridge

        let bundleURL = Bundle.main.url(forResource: "WebReader", withExtension: "bundle")!
        let loader = BookContentLoader()
        let getCurrent: () -> (hash: String, ext: String)? = { [book] in
            (hash: book.sha256, ext: book.format.rawValue)
        }
        let scheme = BookURLSchemeHandler(loader: loader,
                                          bundleURL: bundleURL,
                                          getCurrent: getCurrent)
        context.coordinator.schemeHandler = scheme
        config.setURLSchemeHandler(scheme, forURLScheme: "bookreader")
        config.userContentController.add(bridge, name: WebReaderBridge.messageName)
        config.userContentController.addUserScript(
            WKUserScript(source: Self.bootstrapJS,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: true)
        )
        config.userContentController.addUserScript(WebThemeInjector(theme: theme).userScript())

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = false
        webView.navigationDelegate = context.coordinator
        bridge.attach(to: webView)

        let indexURL = bundleURL.appendingPathComponent("index.html")
        webView.loadFileURL(indexURL, allowingReadAccessTo: bundleURL)

        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.theme != theme {
            context.coordinator.theme = theme
            WebThemeInjector(theme: theme).reinject(into: webView)
        }
    }
```

Trim the Coordinator init signature accordingly:

```swift
    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let book: Book
        var theme: AppTheme
        var bridge: WebReaderBridge?
        var schemeHandler: BookURLSchemeHandler?
        weak var webView: WKWebView?

        init(book: Book, theme: AppTheme) {
            self.book = book
            self.theme = theme
        }
    }
```

(Drop the old, unused `onHighlightAppliedFromJS` callback path — Plan 4 adds it back if needed.)

- [ ] **Step 2: Update ReaderRouter's `webContent(book:)` to provide the new closures and host the popover**

In `book-reader-mac/Reader/ReaderRouter.swift`, replace `webContent(book:)` with:

```swift
    @ViewBuilder
    private func webContent(book: Book) -> some View {
        ZStack {
            WKWebViewReader(
                book: book,
                theme: theme,
                onPositionChange: { anchor, pct, chapter in
                    recorder?.record(bookHash: book.sha256,
                                     anchor: anchor,
                                     percentage: pct,
                                     chapterTitle: chapter)
                },
                onSelectionChanged: { rect, text in
                    webSelectionRect = rect
                    webSelectionText = text
                },
                onSelectionCleared: {
                    webSelectionRect = nil
                    webSelectionText = ""
                }
            )
            if let rect = webSelectionRect, !webSelectionText.isEmpty {
                WebSelectionOverlay(rect: rect,
                                    text: webSelectionText,
                                    theme: theme,
                                    onHighlight: { /* Plan 4 wires JS-side anchor */ },
                                    onCopy: {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(webSelectionText, forType: .string)
                                    },
                                    onExplain: {})
            }
        }
    }
```

Add `WebSelectionOverlay` at file scope:

```swift
private struct WebSelectionOverlay: View {
    let rect: CGRect
    let text: String
    let theme: AppTheme
    let onHighlight: () -> Void
    let onCopy: () -> Void
    let onExplain: () -> Void

    var body: some View {
        SelectionToolbarView(selectedText: text,
                             onHighlight: onHighlight,
                             onCopy: onCopy,
                             onExplain: onExplain,
                             aiConfigured: false)
            .environment(\.appTheme, theme)
            .fixedSize()
            .offset(x: rect.minX, y: rect.maxY + 8)
            .allowsHitTesting(true)
    }
}
```

(EPUB highlight save needs the JS-side text offset within the chapter. Plan 4 wires that flow once the extension's bootstrap exposes the chapter+offset event. v1 of Plan 3 leaves `onHighlight: { }` as a no-op for the EPUB path — the PDF path is the demonstration case for the highlight flow.)

- [ ] **Step 3: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Reader/Web/WKWebViewReader.swift \
          book-reader-mac/Reader/ReaderRouter.swift && \
  git commit -m "feat(mac): web selection overlay wired through bridge"
```

---

## Task 27: Manual smoke test of the active reader

This task has no code changes; it validates the integrated active reader against real fixtures.

- [ ] **Step 1: Build and launch the app**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -configuration Debug \
    -derivedDataPath ./build build 2>&1 | tail -5 && \
  open ./build/Build/Products/Debug/InstantBookReader.app
```

Expected: `** BUILD SUCCEEDED **`, app launches.

- [ ] **Step 2: Import a PDF, then summon the reader**

From the Library window (added by Plan 2), use "Add books" to import `book-reader-mac/Tests/Fixtures/sample.pdf`. Double-click to open. Confirm:

- The reader window appears centered, hosting `ReaderRouter`.
- The PDF renders in continuous mode with `autoScales = true`.
- A TOC panel appears on the left (or the "No outline available" message if the fixture lacks an outline).
- A thumbnail strip appears under the page area.
- Selecting a word brings up the selection popover anchored to the selection rect.
- Clicking "Highlight" persists a `Highlight` (verify via `sqlite3` against `~/Library/Application Support/com.profitoniumapps.instantbookreader/Database/InstantBookReader.store`, table `ZHIGHLIGHT`, expecting one new row).
- Closing and re-opening the book redraws the highlight as a yellow overlay on the same selection.

- [ ] **Step 3: Import an EPUB**

Open `book-reader-mac/Tests/Fixtures/sample.epub`. Confirm:

- The WKWebView loads the bundled extension React app.
- Clay variables are present (`document.documentElement.style.getPropertyValue('--clay-ink')` is non-empty when inspected via web inspector).
- Position changes (page-turn, scroll) trigger debounced writes; verify exactly one `Position` row exists for the EPUB hash after 2 seconds idle.
- Selecting text in the chapter view shows the SwiftUI selection overlay.

- [ ] **Step 4: Import a TXT**

Open `book-reader-mac/Tests/Fixtures/sample.txt`. Confirm:

- The chunked SwiftUI ScrollView renders the file.
- Scrolling updates the persisted Position with monotonically increasing offsets.

- [ ] **Step 5: Run all tests**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -25
```

Expected: every test suite passes — at minimum:
- `BookHashTests` (Plan 1)
- `ReadingStateTests` (Plan 1)
- `PersistenceTests` (Plan 1)
- `ThemeEnvironmentTests` (Plan 1)
- `HighlightAnchorTests`
- `PDFAnchorResolverTests`
- `TXTAnchorResolverTests`
- `WebReaderBridgeTests`
- `BookContentLoaderTests`
- `PositionRecorderTests`
- `PDFDisplayModeTests`

- [ ] **Step 6: Tag the milestone**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git tag -a mac-v0.3.0-active-reader -m "Active reader plan complete"
```

---

## Self-review notes

Coverage check against Plan 3 scope (see prompt's enumerated list):

| Requirement | Tasks |
|---|---|
| 1. Pre-build script that builds + copies the extension dist; gitignored | Task 1 |
| 2. WKWebViewReader + chrome.* shim (storage/runtime/identity; openOptionsPage stub; unsupported logged) | Tasks 5, 8, 9 |
| 3. BookContentLoader + bookreader:// scheme | Task 4 |
| 4. PDFReaderView with all four display modes, thumbnails, outline; page+offset position serialization | Tasks 10, 13, 14, 15, 16, 23 |
| 5. TXTReaderView with char-offset anchor | Task 17 |
| 6. ReaderRouter dispatching by Book.format, replaces PlaceholderReaderView | Tasks 21, 22 |
| 7. HighlightAnchor port, round-trip tests for PDF + EPUB/TXT | Tasks 3, 11, 12, 24 |
| 8. SelectionPopover anchored to selection rect; v1 buttons Highlight/Copy/Explain (Explain stubbed) | Tasks 19, 20, 23, 26 |
| 9. EPUB highlight rendering via CSS injection + JS bridge | Tasks 6, 7 (apply mechanism); v1 of Plan 3 surfaces the JS save flow as a no-op pending Plan 4's chapter+offset event |
| 10. PDF highlight rendering via PDFAnnotation; draw-then-fetch round-trip tested | Tasks 13, 24, 25 |
| 11. PositionRecorder debounced writes | Task 18 |
| 12. Theme handoff via Clay CSS variables; re-inject on theme change | Tasks 6, 8 (initial inject), Task 8 `updateNSView` (re-inject) |

Notes on intentional defers within Plan 3:

- The EPUB-side save-highlight flow ends at the `onHighlight: {}` no-op in Task 26. The extension's React reader already exposes a `selection` event with chapter index + offset; wiring that into `Highlight` requires the bridge to receive a chapter-context payload (handled in Plan 4 along with the AI provider plumbing the bridge already routes via `ai.stream`). The PDF path (Task 25) is the round-trip-tested demonstration that the highlight architecture works end-to-end.
- The Explain button is intentionally disabled with the "Add an AI key in Settings" inline label; Plan 4 enables it.
- `chrome.alarms` and `chrome.tabs` are deliberately not bridged; CHROME_SURFACE.md documents the audit that confirmed `src/newtab/` does not call them.

Self-checks performed:

- Placeholder scan: no "TBD" / "implement later" / "similar to" strings.
- Type consistency: `PDFAnchorResolver.Anchor`, `HighlightAnchor`, `PDFHighlightSerializer`, `HighlightedPDFView.ResolvedHighlight`, `WebReaderStorage.Query`, and all callbacks line up between definition and consumer tasks.
- Existing models from Plan 1 are not redefined; only consumed via SwiftData `@Query` / `ModelContext`.
- Every Swift test contains a real assertion (`XCTAssertEqual`, `XCTAssertNotNil`, `XCTAssertNil`, `XCTAssertThrowsError` with payload inspection).
