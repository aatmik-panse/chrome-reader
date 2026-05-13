# Library + Import Implementation Plan — macOS Wallpaper Reader

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the library + import pipeline on top of Plan 1's foundation. The user can add EPUB / PDF / TXT files via an in-app library window, drag-and-drop onto either the library window or the menu-bar icon, or "Open With → Instant Book Reader" from Finder. Each imported book is content-addressed by SHA-256, deduped, has its metadata (title, author) parsed from format-native sources, and gets a cover PNG cached under App Support. The library window grids the imported books and lets the user pick the active book (`ReadingState.currentBookHash`). The ambient placeholder renders the active book's cover.

**Architecture:** Pure-Swift import pipeline. `EPUBMetadata` parses `META-INF/container.xml` + the referenced OPF file via `XMLParser` to extract title, author, and cover image href. `PDFMetadata` reads `PDFDocument.documentAttributes` for title/author and `PDFPage.thumbnail` for the cover. `TXTMetadata` derives a title from the filename and renders the first 300 chars into a 400×600 PNG. `CoverExtractor` orchestrates per-format cover generation and writes `<sha256>.png` under `AppSupportPaths.covers`. `BookImporter` is the single entry point: copy file → hash → parse metadata → extract cover → upsert SwiftData `Book`. A SwiftUI `LibraryView` (hosted in `LibraryWindow` / `LibraryWindowController`) renders the grid. `DraggableStatusItemButton` is a custom `NSButton` subclass conforming to `NSDraggingDestination` for menu-bar drop. `AppDelegate.application(_:open:)` dispatches Finder "Open With" through the same importer.

**Tech Stack:** Swift 5.10, AppKit + SwiftUI, SwiftData, PDFKit, ZIPFoundation 0.9.x via SwiftPM, XCTest.

---

## File structure

This plan adds the following under `book-reader-mac/`. Files marked **M** are modified; everything else is new.

```
book-reader-mac/
├── project.yml                                      M  (add ZIPFoundation, CFBundleDocumentTypes)
├── App/
│   └── AppDelegate.swift                            M  (open-file dispatch, library controller)
├── Core/
│   └── BookFileExtension.swift                       new  (UTI ↔ ext mapping)
├── Library/
│   ├── BookImporter.swift                            new
│   ├── EPUBMetadata.swift                            new
│   ├── PDFMetadata.swift                             new
│   ├── TXTMetadata.swift                             new
│   ├── CoverExtractor.swift                          new
│   ├── LibraryWindow.swift                           new
│   ├── LibraryWindowController.swift                 new
│   └── LibraryView.swift                             new
├── MenuBar/
│   ├── MenuBarController.swift                      M  (Open Library, Add Books… items)
│   └── DraggableStatusItemButton.swift               new
├── Placeholders/
│   └── PlaceholderAmbientView.swift                 M  (render current book cover)
└── Tests/
    ├── BookImporterTests.swift                       new
    ├── EPUBMetadataTests.swift                       new
    ├── PDFMetadataTests.swift                        new
    ├── TXTMetadataTests.swift                        new
    ├── CoverExtractorTests.swift                     new
    └── Fixtures/
        ├── sample.epub                               new  (small valid EPUB 3, ~15 KB)
        ├── sample.pdf                                new  (1-page PDF, ~3 KB)
        └── sample.txt                                new  (~1 KB lorem ipsum)
```

---

## Task 1: Add ZIPFoundation dependency and document-type UTIs

**Files:**
- Modify: `book-reader-mac/project.yml`

- [ ] **Step 1: Add ZIPFoundation to the SwiftPM packages list and `CFBundleDocumentTypes` to info.properties**

Edit `book-reader-mac/project.yml`. Replace the existing `packages:` block and the existing `info.properties` block with the versions below (leave the rest of the file untouched).

`packages:` becomes:
```yaml
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    minVersion: 2.0.0
  ZIPFoundation:
    url: https://github.com/weichsel/ZIPFoundation
    minVersion: 0.9.19
```

In the `InstantBookReader` target's `dependencies:`, add a second line so it reads:
```yaml
    dependencies:
      - package: KeyboardShortcuts
      - package: ZIPFoundation
```

Add a new sources entry so the new `Library` directory compiles:
```yaml
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
      - path: Resources
```

The `info.properties` block of `InstantBookReader` becomes:
```yaml
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
        CFBundleDocumentTypes:
          - CFBundleTypeName: "EPUB Book"
            CFBundleTypeRole: Viewer
            LSHandlerRank: Alternate
            LSItemContentTypes:
              - org.idpf.epub-container
          - CFBundleTypeName: "PDF Document"
            CFBundleTypeRole: Viewer
            LSHandlerRank: Alternate
            LSItemContentTypes:
              - com.adobe.pdf
          - CFBundleTypeName: "Plain Text"
            CFBundleTypeRole: Viewer
            LSHandlerRank: Alternate
            LSItemContentTypes:
              - public.plain-text
```

For the `InstantBookReaderTests` target, add `Tests/Fixtures` as a resource so the bundled fixture files are accessible from tests. The target block becomes:
```yaml
  InstantBookReaderTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: Tests
        excludes:
          - "Fixtures/**"
      - path: Tests/Fixtures
        buildPhase: resources
        type: folder
    dependencies:
      - target: InstantBookReader
    settings:
      base:
        BUNDLE_LOADER: $(TEST_HOST)
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/InstantBookReader.app/Contents/MacOS/InstantBookReader
```

- [ ] **Step 2: Regenerate the project and confirm it still builds**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. (Tests targets reference a `Tests/Fixtures` folder that does not yet exist on disk; Task 3 creates it. If XcodeGen complains about a missing folder, create an empty one first: `mkdir -p book-reader-mac/Tests/Fixtures`.)

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/project.yml && \
  git commit -m "feat(mac): add ZIPFoundation dep and CFBundleDocumentTypes for EPUB/PDF/TXT"
```

---

## Task 2: BookFileExtension helper

**Files:**
- Create: `book-reader-mac/Core/BookFileExtension.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Core/BookFileExtension.swift`:
```swift
import Foundation
import UniformTypeIdentifiers

/// Maps file URLs to the app's three supported formats. Single source of
/// truth for both the importer and the NSOpenPanel content-type filter.
enum BookFileExtension {
    /// All UTIs the app advertises in `CFBundleDocumentTypes`.
    static let supportedContentTypes: [UTType] = {
        var types: [UTType] = []
        if let epub = UTType("org.idpf.epub-container") { types.append(epub) }
        types.append(.pdf)
        types.append(.plainText)
        return types
    }()

    /// Returns the `BookFormat` for a file URL based on its extension.
    /// Returns nil for unsupported types.
    static func format(for url: URL) -> BookFormat? {
        switch url.pathExtension.lowercased() {
        case "epub": return .epub
        case "pdf": return .pdf
        case "txt", "text": return .txt
        default: return nil
        }
    }

    /// Canonical filesystem extension used when storing a copy under App Support.
    static func canonicalExtension(for format: BookFormat) -> String {
        switch format {
        case .epub: return "epub"
        case .pdf: return "pdf"
        case .txt: return "txt"
        }
    }
}
```

- [ ] **Step 2: Build**

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
  git add book-reader-mac/Core/BookFileExtension.swift && \
  git commit -m "feat(mac): BookFileExtension UTI/format mapping"
```

---

## Task 3: Generate test fixtures (EPUB, PDF, TXT)

**Files:**
- Create: `book-reader-mac/Tests/Fixtures/sample.epub`
- Create: `book-reader-mac/Tests/Fixtures/sample.pdf`
- Create: `book-reader-mac/Tests/Fixtures/sample.txt`

These are tiny, deterministic, hand-built fixtures. We create them with a one-off Swift script so the content is reproducible and reviewable in the plan.

- [ ] **Step 1: Create the fixture directory**

```bash
mkdir -p /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/Fixtures
```

- [ ] **Step 2: Write the plain-text fixture**

Write `book-reader-mac/Tests/Fixtures/sample.txt` with the exact contents below (no trailing newline beyond what is shown):
```
The Lighthouse Keeper

Marlow had spent thirty-one winters on the rock before he understood why
the wind sounded different on the seaward side. It wasn't the cliffs.
It wasn't the gulls. It was the lamp itself: a low, breath-like
resonance that only carried when the glass was cold. He wrote that
down, in pencil, in the back of the logbook, and underlined it twice.
```

- [ ] **Step 3: Generate the PDF fixture**

The PDF needs to be a valid 1-page PDF small enough to check in. Generate it with a one-off command using macOS's built-in tools:

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/Fixtures && \
  /usr/bin/python3 - <<'PY'
# 1-page minimal PDF with Title/Author metadata, written by hand.
pdf = b"""%PDF-1.4
1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj
2 0 obj<< /Type /Pages /Count 1 /Kids [3 0 R] >>endobj
3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>endobj
4 0 obj<< /Length 60 >>stream
BT /F1 24 Tf 72 720 Td (The Lighthouse Keeper) Tj ET
endstream endobj
5 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>endobj
6 0 obj<< /Title (The Lighthouse Keeper) /Author (Joseph Marlow) >>endobj
xref
0 7
0000000000 65535 f
0000000009 00000 n
0000000058 00000 n
0000000109 00000 n
0000000207 00000 n
0000000312 00000 n
0000000376 00000 n
trailer<< /Size 7 /Root 1 0 R /Info 6 0 R >>
startxref
448
%%EOF
"""
open("sample.pdf", "wb").write(pdf)
PY
```

Verify with:
```bash
/usr/bin/file /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/Fixtures/sample.pdf
```
Expected output contains `PDF document`.

- [ ] **Step 4: Generate the EPUB fixture**

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/Fixtures && \
  /usr/bin/python3 - <<'PY'
import zipfile, io, os, struct

# 1x1 PNG (red pixel) for the cover.
PNG = bytes.fromhex(
    "89504E470D0A1A0A0000000D49484452000000010000000108060000001F15C489"
    "0000000D49444154789C63F8CFC0F01F0005000201A8B3F2810000000049454E44AE426082"
)

container_xml = b"""<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

content_opf = b"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:uuid:fixture-0001</dc:identifier>
    <dc:title>The Lighthouse Keeper</dc:title>
    <dc:creator>Joseph Marlow</dc:creator>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="cover" href="cover.png" media-type="image/png" properties="cover-image"/>
    <item id="ch1"   href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="nav"   href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
  </manifest>
  <spine>
    <itemref idref="ch1"/>
  </spine>
</package>
"""

nav_xhtml = b"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>Nav</title></head>
<body><nav epub:type="toc"><ol><li><a href="chapter1.xhtml">Chapter 1</a></li></ol></nav></body>
</html>
"""

chapter1 = b"""<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter 1</title></head>
<body><h1>Chapter 1</h1><p>It wasn't the cliffs. It wasn't the gulls.</p></body>
</html>
"""

buf = io.BytesIO()
with zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED) as z:
    # The mimetype entry must be first and stored uncompressed.
    z.writestr(zipfile.ZipInfo("mimetype"), b"application/epub+zip")
    z.writestr("META-INF/container.xml", container_xml)
    z.writestr("OEBPS/content.opf", content_opf)
    z.writestr("OEBPS/nav.xhtml", nav_xhtml)
    z.writestr("OEBPS/chapter1.xhtml", chapter1)
    z.writestr("OEBPS/cover.png", PNG)

open("sample.epub", "wb").write(buf.getvalue())
PY
```

Verify with:
```bash
/usr/bin/file /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/Fixtures/sample.epub
```
Expected output contains `Zip archive data` or `EPUB`.

- [ ] **Step 5: Commit fixtures**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/Fixtures && \
  git commit -m "test(mac): bundle sample EPUB/PDF/TXT fixtures"
```

---

## Task 4: EPUBMetadata parser — tests first

**Files:**
- Create: `book-reader-mac/Tests/EPUBMetadataTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/EPUBMetadataTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

final class EPUBMetadataTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: "sample", withExtension: "epub")
        return try XCTUnwrap(url, "sample.epub fixture missing from test bundle")
    }

    func testParsesTitleAuthorAndCover() throws {
        let url = try fixtureURL()
        let parsed = try EPUBMetadata.parse(at: url)
        XCTAssertEqual(parsed.title, "The Lighthouse Keeper")
        XCTAssertEqual(parsed.author, "Joseph Marlow")
        XCTAssertNotNil(parsed.coverImageData, "cover bytes should be extracted")
        // The fixture's cover is a 1x1 PNG, so check the PNG magic header.
        let prefix = parsed.coverImageData!.prefix(8)
        let expected: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        XCTAssertEqual(Array(prefix), expected)
    }

    func testParseThrowsForNonZIPFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-an-epub-\(UUID().uuidString).epub")
        try "definitely not a zip".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertThrowsError(try EPUBMetadata.parse(at: tmp))
    }
}
```

- [ ] **Step 2: Run the tests; expect compile failure**

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: compile error referencing `EPUBMetadata`.

- [ ] **Step 3: Commit the test scaffolding**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/EPUBMetadataTests.swift && \
  git commit -m "test(mac): EPUB metadata parser tests (failing)"
```

---

## Task 5: EPUBMetadata parser — implementation

**Files:**
- Create: `book-reader-mac/Library/EPUBMetadata.swift`

The parser flow:
1. Open the EPUB with ZIPFoundation (it's a ZIP archive).
2. Read `META-INF/container.xml`, find the `<rootfile full-path="…opf"/>` — that's the OPF path.
3. Read the OPF, which is XML. Extract `<dc:title>`, `<dc:creator>` (the first non-empty values).
4. Find the cover image:
   - **EPUB 3:** an `<item properties="cover-image">` element in `<manifest>`. Use that item's `href`.
   - **EPUB 2 fallback:** a `<meta name="cover" content="…id…">` in `<metadata>`; resolve to the `<item id="…id…">` and use its `href`.
5. Resolve the cover href relative to the OPF's directory and read the bytes out of the ZIP.

- [ ] **Step 1: Implement the file**

Write `book-reader-mac/Library/EPUBMetadata.swift`:
```swift
import Foundation
import ZIPFoundation

/// Parsed EPUB metadata. Cover bytes are returned as-is (PNG, JPEG, etc.);
/// CoverExtractor re-encodes them to PNG before writing to disk.
struct ParsedEPUBMetadata: Equatable {
    let title: String?
    let author: String?
    let coverImageData: Data?
}

enum EPUBMetadataError: Error, CustomStringConvertible {
    case notAnArchive
    case missingContainer
    case missingOPFPath
    case missingOPFEntry
    case malformedOPF

    var description: String {
        switch self {
        case .notAnArchive:     return "Not a valid EPUB ZIP archive"
        case .missingContainer: return "META-INF/container.xml missing"
        case .missingOPFPath:   return "container.xml did not declare an OPF rootfile"
        case .missingOPFEntry:  return "Declared OPF file not found inside archive"
        case .malformedOPF:     return "OPF could not be parsed as XML"
        }
    }
}

enum EPUBMetadata {
    static func parse(at url: URL) throws -> ParsedEPUBMetadata {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw EPUBMetadataError.notAnArchive
        }

        // 1. container.xml -> OPF rootfile path
        let containerData = try readEntry(archive: archive, path: "META-INF/container.xml",
                                          missing: EPUBMetadataError.missingContainer)
        guard let opfPath = ContainerXMLParser.rootfilePath(from: containerData) else {
            throw EPUBMetadataError.missingOPFPath
        }

        // 2. OPF document
        let opfData = try readEntry(archive: archive, path: opfPath,
                                    missing: EPUBMetadataError.missingOPFEntry)
        guard let opf = OPFParser.parse(opfData) else {
            throw EPUBMetadataError.malformedOPF
        }

        // 3. Resolve cover href to an archive entry path
        let opfDir = (opfPath as NSString).deletingLastPathComponent
        let coverData: Data?
        if let coverHref = opf.coverHref {
            let resolved = resolve(href: coverHref, base: opfDir)
            coverData = try? readEntry(archive: archive, path: resolved,
                                       missing: EPUBMetadataError.missingOPFEntry)
        } else {
            coverData = nil
        }

        return ParsedEPUBMetadata(title: opf.title,
                                  author: opf.author,
                                  coverImageData: coverData)
    }

    private static func readEntry(archive: Archive, path: String,
                                  missing: EPUBMetadataError) throws -> Data {
        guard let entry = archive[path] else { throw missing }
        var data = Data()
        _ = try archive.extract(entry) { chunk in data.append(chunk) }
        return data
    }

    private static func resolve(href: String, base: String) -> String {
        if base.isEmpty { return href }
        // Treat the OPF directory and href as POSIX components.
        let combined = (base as NSString).appendingPathComponent(href)
        return (combined as NSString).standardizingPath
    }
}

// MARK: - container.xml parser

private final class ContainerXMLParser: NSObject, XMLParserDelegate {
    private(set) var path: String?

    static func rootfilePath(from data: Data) -> String? {
        let delegate = ContainerXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.path
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        if elementName == "rootfile", path == nil {
            path = attributeDict["full-path"]
        }
    }
}

// MARK: - OPF parser

struct OPFMetadata {
    var title: String?
    var author: String?
    var coverHref: String?
}

private final class OPFParser: NSObject, XMLParserDelegate {
    static func parse(_ data: Data) -> OPFMetadata? {
        let delegate = OPFParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        if parser.parse() {
            delegate.resolveLegacyCover()
            return delegate.meta
        }
        return nil
    }

    private var meta = OPFMetadata()
    private var currentElement: String?
    private var currentText: String = ""

    // EPUB 2 fallback bookkeeping.
    private var coverManifestID: String?
    private var manifest: [String: String] = [:]  // id -> href
    private var manifestCoverHref: String?       // already-found EPUB 3 cover (wins)

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""

        // Manifest items: build id->href map and detect EPUB 3 cover-image.
        if elementName == "item" {
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = href
                if let props = attributeDict["properties"],
                   props.split(separator: " ").contains("cover-image") {
                    manifestCoverHref = href
                }
            }
        }

        // EPUB 2: <meta name="cover" content="<manifest-id>"/>
        if elementName == "meta",
           let name = attributeDict["name"],
           name.lowercased() == "cover",
           let content = attributeDict["content"] {
            coverManifestID = content
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { currentElement = nil; currentText = "" }

        if value.isEmpty { return }

        // dc:title (or just "title"), and dc:creator (or "creator").
        let lower = elementName.lowercased()
        if (lower == "dc:title" || lower == "title"), meta.title == nil {
            meta.title = value
        }
        if (lower == "dc:creator" || lower == "creator"), meta.author == nil {
            meta.author = value
        }
    }

    fileprivate func resolveLegacyCover() {
        // EPUB 3 cover wins if present.
        if let href = manifestCoverHref {
            meta.coverHref = href
            return
        }
        if let id = coverManifestID, let href = manifest[id] {
            meta.coverHref = href
        }
    }
}
```

- [ ] **Step 2: Run the tests; expect them to pass**

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `Test Suite 'EPUBMetadataTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Library/EPUBMetadata.swift && \
  git commit -m "feat(mac): EPUB OPF metadata + cover extraction via ZIPFoundation"
```

---

## Task 6: PDFMetadata parser

**Files:**
- Create: `book-reader-mac/Tests/PDFMetadataTests.swift`
- Create: `book-reader-mac/Library/PDFMetadata.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/PDFMetadataTests.swift`:
```swift
import XCTest
import AppKit
@testable import InstantBookReader

final class PDFMetadataTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        let url = Bundle(for: type(of: self)).url(forResource: "sample", withExtension: "pdf")
        return try XCTUnwrap(url, "sample.pdf fixture missing")
    }

    func testParseReadsTitleAndAuthor() throws {
        let parsed = try PDFMetadata.parse(at: try fixtureURL())
        XCTAssertEqual(parsed.title, "The Lighthouse Keeper")
        XCTAssertEqual(parsed.author, "Joseph Marlow")
    }

    func testRenderCoverProducesAtLeastOnePixel() throws {
        let image = try PDFMetadata.renderCover(at: try fixtureURL(),
                                                size: CGSize(width: 400, height: 600))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }
}
```

- [ ] **Step 2: Implement**

Write `book-reader-mac/Library/PDFMetadata.swift`:
```swift
import AppKit
import PDFKit

struct ParsedPDFMetadata: Equatable {
    let title: String?
    let author: String?
}

enum PDFMetadataError: Error, CustomStringConvertible {
    case cannotOpen
    case noPages

    var description: String {
        switch self {
        case .cannotOpen: return "PDFKit could not open this file"
        case .noPages:    return "PDF has no pages to render"
        }
    }
}

enum PDFMetadata {
    static func parse(at url: URL) throws -> ParsedPDFMetadata {
        guard let doc = PDFDocument(url: url) else { throw PDFMetadataError.cannotOpen }
        let attrs = doc.documentAttributes ?? [:]
        let title = (attrs[PDFDocumentAttribute.titleAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let author = (attrs[PDFDocumentAttribute.authorAttribute] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedPDFMetadata(
            title: (title?.isEmpty ?? true) ? nil : title,
            author: (author?.isEmpty ?? true) ? nil : author
        )
    }

    /// Renders the first page as an NSImage of the requested size.
    static func renderCover(at url: URL, size: CGSize) throws -> NSImage {
        guard let doc = PDFDocument(url: url) else { throw PDFMetadataError.cannotOpen }
        guard let page = doc.page(at: 0) else { throw PDFMetadataError.noPages }
        return page.thumbnail(of: size, for: .mediaBox)
    }
}
```

- [ ] **Step 3: Run the tests; expect pass**

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `Test Suite 'PDFMetadataTests' passed`.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/PDFMetadataTests.swift \
          book-reader-mac/Library/PDFMetadata.swift && \
  git commit -m "feat(mac): PDF metadata + first-page thumbnail extraction"
```

---

## Task 7: TXTMetadata parser

**Files:**
- Create: `book-reader-mac/Tests/TXTMetadataTests.swift`
- Create: `book-reader-mac/Library/TXTMetadata.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/TXTMetadataTests.swift`:
```swift
import XCTest
import AppKit
@testable import InstantBookReader

final class TXTMetadataTests: XCTestCase {
    private func fixtureURL() throws -> URL {
        let url = Bundle(for: type(of: self)).url(forResource: "sample", withExtension: "txt")
        return try XCTUnwrap(url, "sample.txt fixture missing")
    }

    func testTitleDerivedFromFilename() throws {
        let parsed = try TXTMetadata.parse(at: try fixtureURL())
        XCTAssertEqual(parsed.title, "sample")
        XCTAssertNil(parsed.author)
    }

    func testTitleStripsExtensionAndUnderscores() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("the_pale_horse_v2.txt")
        try "body".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let parsed = try TXTMetadata.parse(at: tmp)
        XCTAssertEqual(parsed.title, "the pale horse v2")
    }

    func testRenderCoverProducesNonEmptyImage() throws {
        let image = try TXTMetadata.renderCover(at: try fixtureURL(),
                                                size: CGSize(width: 400, height: 600))
        XCTAssertEqual(image.size, CGSize(width: 400, height: 600))
    }
}
```

- [ ] **Step 2: Implement**

Write `book-reader-mac/Library/TXTMetadata.swift`:
```swift
import AppKit
import Foundation

struct ParsedTXTMetadata: Equatable {
    let title: String?
    let author: String?
}

enum TXTMetadataError: Error {
    case cannotRead
}

enum TXTMetadata {
    static func parse(at url: URL) throws -> ParsedTXTMetadata {
        let raw = (url.deletingPathExtension().lastPathComponent)
        let cleaned = raw
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedTXTMetadata(title: cleaned.isEmpty ? nil : cleaned, author: nil)
    }

    /// Renders the first 300 characters as an NSAttributedString into an
    /// NSImage of the requested size, using a serif body face on a warm cream
    /// background. Plan 5 may revisit styling.
    static func renderCover(at url: URL, size: CGSize) throws -> NSImage {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            throw TXTMetadataError.cannotRead
        }
        let snippet = String(raw.prefix(300))

        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        // Background — clay cream.
        NSColor(calibratedRed: 0.984, green: 0.976, blue: 0.969, alpha: 1.0).setFill()
        NSRect(origin: .zero, size: size).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "New York Medium", size: 16)
                ?? NSFont.systemFont(ofSize: 16),
            .foregroundColor: NSColor(calibratedRed: 0.102, green: 0.094, blue: 0.082,
                                      alpha: 1.0),
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: snippet, attributes: attributes)
        let inset: CGFloat = 32
        let drawRect = NSRect(x: inset, y: inset,
                              width: size.width - inset * 2,
                              height: size.height - inset * 2)
        attributed.draw(in: drawRect)

        return image
    }
}
```

- [ ] **Step 3: Run the tests; expect pass**

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `Test Suite 'TXTMetadataTests' passed`.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/TXTMetadataTests.swift \
          book-reader-mac/Library/TXTMetadata.swift && \
  git commit -m "feat(mac): TXT metadata (filename) + first-paragraph cover render"
```

---

## Task 8: CoverExtractor (writes PNGs to App Support)

**Files:**
- Create: `book-reader-mac/Tests/CoverExtractorTests.swift`
- Create: `book-reader-mac/Library/CoverExtractor.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/CoverExtractorTests.swift`:
```swift
import XCTest
import AppKit
@testable import InstantBookReader

final class CoverExtractorTests: XCTestCase {
    private var tempCoverDir: URL!

    override func setUpWithError() throws {
        tempCoverDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CoverExtractorTests-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: tempCoverDir,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempCoverDir)
    }

    private func fixture(_ name: String, ext: String) throws -> URL {
        let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: ext)
        return try XCTUnwrap(url, "\(name).\(ext) fixture missing")
    }

    func testEPUBCoverWritesPNGAtSha256Path() throws {
        let src = try fixture("sample", ext: "epub")
        let written = try CoverExtractor.extract(
            from: src, format: .epub, sha256: "abc123",
            coversDirectory: tempCoverDir
        )
        XCTAssertEqual(written.lastPathComponent, "abc123.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path))
        let data = try Data(contentsOf: written)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])  // PNG magic
    }

    func testPDFCoverWritesPNG() throws {
        let src = try fixture("sample", ext: "pdf")
        let written = try CoverExtractor.extract(
            from: src, format: .pdf, sha256: "pdf-1",
            coversDirectory: tempCoverDir
        )
        XCTAssertEqual(written.lastPathComponent, "pdf-1.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path))
    }

    func testTXTCoverWritesPNG() throws {
        let src = try fixture("sample", ext: "txt")
        let written = try CoverExtractor.extract(
            from: src, format: .txt, sha256: "txt-1",
            coversDirectory: tempCoverDir
        )
        XCTAssertEqual(written.lastPathComponent, "txt-1.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.path))
    }
}
```

- [ ] **Step 2: Implement**

Write `book-reader-mac/Library/CoverExtractor.swift`:
```swift
import AppKit
import Foundation

enum CoverExtractorError: Error, CustomStringConvertible {
    case noCoverFound
    case pngEncodingFailed

    var description: String {
        switch self {
        case .noCoverFound:       return "No cover image could be derived from this file"
        case .pngEncodingFailed:  return "Failed to encode generated cover as PNG"
        }
    }
}

enum CoverExtractor {
    /// Writes `<sha256>.png` into `coversDirectory` and returns the URL.
    /// Overwrites an existing file at the same path (idempotent).
    static func extract(from source: URL,
                        format: BookFormat,
                        sha256: String,
                        coversDirectory: URL) throws -> URL {
        let target = coversDirectory.appendingPathComponent("\(sha256).png")

        let image: NSImage
        switch format {
        case .epub:
            let parsed = try EPUBMetadata.parse(at: source)
            guard let data = parsed.coverImageData,
                  let nsimage = NSImage(data: data) else {
                throw CoverExtractorError.noCoverFound
            }
            image = nsimage
        case .pdf:
            image = try PDFMetadata.renderCover(at: source,
                                                size: CGSize(width: 400, height: 600))
        case .txt:
            image = try TXTMetadata.renderCover(at: source,
                                                size: CGSize(width: 400, height: 600))
        }

        guard let pngData = pngData(from: image) else {
            throw CoverExtractorError.pngEncodingFailed
        }

        try FileManager.default.createDirectory(at: coversDirectory,
                                                withIntermediateDirectories: true)
        try pngData.write(to: target, options: .atomic)
        return target
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
```

- [ ] **Step 3: Run the tests; expect pass**

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `Test Suite 'CoverExtractorTests' passed`.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/CoverExtractorTests.swift \
          book-reader-mac/Library/CoverExtractor.swift && \
  git commit -m "feat(mac): CoverExtractor writes per-book PNGs under App Support"
```

---

## Task 9: BookImporter — tests first

**Files:**
- Create: `book-reader-mac/Tests/BookImporterTests.swift`

- [ ] **Step 1: Write the failing tests**

`BookImporter` takes a source URL + a SwiftData `ModelContext` + filesystem directories (covers, books) so it can be tested without touching the user's real App Support. The full set of behaviors under test:

- Importing an EPUB inserts exactly one `Book` row with parsed title + author and a cover path.
- Re-importing the same EPUB is a no-op (matching hash → no second row).
- Importing a PDF derives title/author from PDF metadata.
- Importing a TXT derives the title from the filename.
- The source file is copied to `<booksDir>/<sha256>.<ext>`.

Write `book-reader-mac/Tests/BookImporterTests.swift`:
```swift
import XCTest
import SwiftData
@testable import InstantBookReader

@MainActor
final class BookImporterTests: XCTestCase {
    private var booksDir: URL!
    private var coversDir: URL!
    private var container: ModelContainer!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookImporterTests-\(UUID().uuidString)",
                                    isDirectory: true)
        booksDir = root.appendingPathComponent("Books", isDirectory: true)
        coversDir = root.appendingPathComponent("Covers", isDirectory: true)
        try FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coversDir, withIntermediateDirectories: true)

        container = try PersistenceController.makeInMemoryContainer()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: booksDir.deletingLastPathComponent())
    }

    private func fixture(_ name: String, ext: String) throws -> URL {
        let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: ext)
        return try XCTUnwrap(url, "\(name).\(ext) fixture missing")
    }

    func testImportingEPUBInsertsBookWithTitleAuthorCoverAndFile() throws {
        let importer = BookImporter(booksDirectory: booksDir,
                                    coversDirectory: coversDir)
        let context = ModelContext(container)

        let book = try importer.importBook(from: try fixture("sample", ext: "epub"),
                                           into: context)
        try context.save()

        XCTAssertEqual(book.title, "The Lighthouse Keeper")
        XCTAssertEqual(book.author, "Joseph Marlow")
        XCTAssertEqual(book.format, .epub)
        XCTAssertNotNil(book.coverPath)

        // File copied into books dir under <sha>.epub
        let storedURL = booksDir.appendingPathComponent("\(book.sha256).epub")
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))

        // Exactly one Book row.
        let all = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(all.count, 1)
    }

    func testReimportingSameFileIsIdempotent() throws {
        let importer = BookImporter(booksDirectory: booksDir,
                                    coversDirectory: coversDir)
        let context = ModelContext(container)
        let src = try fixture("sample", ext: "epub")

        let first = try importer.importBook(from: src, into: context)
        try context.save()
        let second = try importer.importBook(from: src, into: context)
        try context.save()

        XCTAssertEqual(first.sha256, second.sha256)
        let all = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(all.count, 1)
    }

    func testImportingPDFUsesPDFMetadata() throws {
        let importer = BookImporter(booksDirectory: booksDir,
                                    coversDirectory: coversDir)
        let context = ModelContext(container)

        let book = try importer.importBook(from: try fixture("sample", ext: "pdf"),
                                           into: context)
        try context.save()

        XCTAssertEqual(book.title, "The Lighthouse Keeper")
        XCTAssertEqual(book.author, "Joseph Marlow")
        XCTAssertEqual(book.format, .pdf)
    }

    func testImportingTXTUsesFilenameForTitle() throws {
        let importer = BookImporter(booksDirectory: booksDir,
                                    coversDirectory: coversDir)
        let context = ModelContext(container)

        let book = try importer.importBook(from: try fixture("sample", ext: "txt"),
                                           into: context)
        try context.save()

        XCTAssertEqual(book.title, "sample")
        XCTAssertNil(book.author)
        XCTAssertEqual(book.format, .txt)
    }

    func testUnsupportedExtensionThrows() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("garbage-\(UUID().uuidString).xyz")
        try "nope".write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let importer = BookImporter(booksDirectory: booksDir,
                                    coversDirectory: coversDir)
        let context = ModelContext(container)
        XCTAssertThrowsError(try importer.importBook(from: tmp, into: context))
    }
}
```

- [ ] **Step 2: Run; expect compile failure**

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: compile error referencing `BookImporter`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/BookImporterTests.swift && \
  git commit -m "test(mac): BookImporter test suite (failing)"
```

---

## Task 10: BookImporter — implementation

**Files:**
- Create: `book-reader-mac/Library/BookImporter.swift`

The flow per import:

1. Resolve the `BookFormat` from the URL extension; throw if unsupported.
2. SHA-256 the source bytes.
3. Check SwiftData for an existing `Book` with the same `sha256`. If found, return it (no-op).
4. Copy the file to `<booksDir>/<sha256>.<ext>` (overwrite if a stale copy is there from an aborted import).
5. Parse metadata (EPUB/PDF/TXT).
6. Generate a cover via `CoverExtractor` (best-effort; failure is logged but does not abort the import — books without covers are valid).
7. Insert a new `Book` row.

- [ ] **Step 1: Implement**

Write `book-reader-mac/Library/BookImporter.swift`:
```swift
import Foundation
import OSLog
import SwiftData

enum BookImporterError: Error, CustomStringConvertible {
    case unsupportedFormat(String)

    var description: String {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported file extension: .\(ext)"
        }
    }
}

/// Single entry point for adding a book to the library.
/// All side effects happen against the injected directories + ModelContext,
/// so tests can run against tmp dirs and an in-memory container.
@MainActor
final class BookImporter {
    private let booksDirectory: URL
    private let coversDirectory: URL
    private let log = Logger(subsystem: "com.profitoniumapps.instantbookreader",
                             category: "BookImporter")

    init(booksDirectory: URL, coversDirectory: URL) {
        self.booksDirectory = booksDirectory
        self.coversDirectory = coversDirectory
    }

    /// Convenience initializer that imports into the user's real App Support
    /// directories. Production code uses this; tests use the explicit init.
    convenience init() {
        self.init(booksDirectory: AppSupportPaths.books,
                  coversDirectory: AppSupportPaths.covers)
    }

    /// Imports `source` and returns the resulting `Book`. Idempotent: a second
    /// call with the same content hashes returns the existing row unchanged.
    @discardableResult
    func importBook(from source: URL, into context: ModelContext) throws -> Book {
        guard let format = BookFileExtension.format(for: source) else {
            throw BookImporterError.unsupportedFormat(source.pathExtension)
        }

        try FileManager.default.createDirectory(at: booksDirectory,
                                                withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coversDirectory,
                                                withIntermediateDirectories: true)

        let sha = try BookHash.sha256Hex(ofFileAt: source)

        // Dedup: return the existing row if any.
        let predicate = #Predicate<Book> { $0.sha256 == sha }
        if let existing = try context.fetch(FetchDescriptor<Book>(predicate: predicate)).first {
            log.info("re-import noop for \(sha, privacy: .public)")
            return existing
        }

        // 1. Copy bytes to <booksDir>/<sha>.<ext>
        let ext = BookFileExtension.canonicalExtension(for: format)
        let stored = booksDirectory.appendingPathComponent("\(sha).\(ext)")
        if FileManager.default.fileExists(atPath: stored.path) {
            try FileManager.default.removeItem(at: stored)
        }
        try FileManager.default.copyItem(at: source, to: stored)

        // 2. Parse metadata.
        let title: String
        let author: String?
        switch format {
        case .epub:
            let parsed = try EPUBMetadata.parse(at: stored)
            title = parsed.title ?? source.deletingPathExtension().lastPathComponent
            author = parsed.author
        case .pdf:
            let parsed = try PDFMetadata.parse(at: stored)
            title = parsed.title ?? source.deletingPathExtension().lastPathComponent
            author = parsed.author
        case .txt:
            let parsed = try TXTMetadata.parse(at: stored)
            title = parsed.title ?? source.deletingPathExtension().lastPathComponent
            author = parsed.author
        }

        // 3. Cover (best-effort).
        var coverRelative: String? = nil
        do {
            let coverURL = try CoverExtractor.extract(from: stored,
                                                      format: format,
                                                      sha256: sha,
                                                      coversDirectory: coversDirectory)
            coverRelative = "Covers/" + coverURL.lastPathComponent
        } catch {
            log.warning("cover extraction failed for \(sha, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        // 4. Insert.
        let book = Book(
            sha256: sha,
            title: title,
            author: author,
            format: format,
            coverPath: coverRelative,
            filePath: "Books/\(sha).\(ext)",
            addedAt: .now,
            lastOpenedAt: nil
        )
        context.insert(book)
        return book
    }
}
```

- [ ] **Step 2: Run the tests; expect pass**

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: `Test Suite 'BookImporterTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Library/BookImporter.swift && \
  git commit -m "feat(mac): BookImporter pipeline — hash, dedup, copy, metadata, cover"
```

---

## Task 11: LibraryView SwiftUI grid

**Files:**
- Create: `book-reader-mac/Library/LibraryView.swift`

`LibraryView` queries `Book` via `@Query`, renders a `LazyVGrid` of cover tiles, and exposes "Add Books…" + drag-and-drop. Selecting a cover updates `ReadingState.currentBookHash` and `Book.lastOpenedAt`.

- [ ] **Step 1: Implement**

Write `book-reader-mac/Library/LibraryView.swift`:
```swift
import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.modelContext) private var context
    @Environment(ReadingState.self) private var state
    @Query(sort: [SortDescriptor(\Book.addedAt, order: .reverse)]) private var books: [Book]

    /// Injected by the window controller so the view can show NSOpenPanel
    /// and drive imports without owning any AppKit state itself.
    let onAddBooks: () -> Void

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 24)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(theme.border.swiftUI)
            if books.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 28) {
                        ForEach(books) { book in
                            BookTile(book: book, isCurrent: book.sha256 == state.currentBookHash)
                                .onTapGesture { selectBook(book) }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 480)
        .background(theme.surface.swiftUI)
        .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    private var header: some View {
        HStack {
            Text("LIBRARY")
                .font(.system(size: 13, weight: .medium))
                .tracking(1.08)
                .foregroundStyle(theme.ink.swiftUI.opacity(0.92))
            Spacer()
            Button("Add Books…", action: onAddBooks)
                .keyboardShortcut("o", modifiers: [.command])
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No books yet")
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(theme.ink.swiftUI)
            Text("Drop EPUB, PDF, or TXT files here, or click Add Books…")
                .font(.system(size: 13))
                .foregroundStyle(theme.ink.swiftUI.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func selectBook(_ book: Book) {
        state.currentBookHash = book.sha256
        book.lastOpenedAt = .now
        try? context.save()
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let importer = BookImporter()
        var imported = false
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    do {
                        _ = try importer.importBook(from: url, into: context)
                        try context.save()
                    } catch {
                        NSAlert(error: error).runModal()
                    }
                }
                imported = true
            }
        }
        return imported
    }
}

private struct BookTile: View {
    @Environment(\.appTheme) private var theme
    let book: Book
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
                .frame(width: 160, height: 230)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isCurrent ? theme.ink.swiftUI : theme.border.swiftUI,
                                      lineWidth: isCurrent ? 2 : 1)
                )
            Text(book.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.ink.swiftUI)
                .lineLimit(2)
            if let author = book.author {
                Text(author)
                    .font(.system(size: 11))
                    .tracking(1.08)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.ink.swiftUI.opacity(0.6))
            }
            if let opened = book.lastOpenedAt {
                Text("Opened \(opened.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.ink.swiftUI.opacity(0.5))
            }
        }
        .frame(width: 160, alignment: .leading)
    }

    @ViewBuilder private var cover: some View {
        if let path = book.coverPath,
           let nsImage = NSImage(contentsOfFile: AppSupportPaths.root
                                    .appendingPathComponent(path).path) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            theme.border.swiftUI.opacity(0.4)
        }
    }
}
```

- [ ] **Step 2: Build**

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
  git add book-reader-mac/Library/LibraryView.swift && \
  git commit -m "feat(mac): LibraryView grid with cover tiles and drop target"
```

---

## Task 12: LibraryWindow + LibraryWindowController

**Files:**
- Create: `book-reader-mac/Library/LibraryWindow.swift`
- Create: `book-reader-mac/Library/LibraryWindowController.swift`

- [ ] **Step 1: Implement the window subclass**

Write `book-reader-mac/Library/LibraryWindow.swift`:
```swift
import AppKit

/// Standard `.normal` level window for the library grid. Sized 1000×680
/// with a title bar so the user can move/close it.
final class LibraryWindow: NSWindow {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered,
                   defer: false)
        self.title = "Library"
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.fullScreenPrimary, .managed]
        self.setFrameAutosaveName("InstantBookReader.Library")
        self.center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

- [ ] **Step 2: Implement the controller**

Write `book-reader-mac/Library/LibraryWindowController.swift`:
```swift
import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryWindowController {
    private let window: LibraryWindow
    private let state: ReadingState
    private let modelContainer: ModelContainer
    private let theme: AppTheme

    init(state: ReadingState, modelContainer: ModelContainer, theme: AppTheme) {
        self.state = state
        self.modelContainer = modelContainer
        self.theme = theme
        self.window = LibraryWindow()

        let root = LibraryView(onAddBooks: { [weak self] in self?.presentOpenPanel() })
            .environment(\.appTheme, theme)
            .environment(state)
            .modelContainer(modelContainer)
        window.contentView = NSHostingView(rootView: root)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Opens an NSOpenPanel filtered to EPUB/PDF/TXT and imports each pick.
    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = BookFileExtension.supportedContentTypes
        panel.prompt = "Add to Library"
        panel.message = "Select EPUB, PDF, or TXT files to add"

        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            Task { @MainActor in
                self.importMany(panel.urls)
            }
        }
    }

    /// Public hook used by AppDelegate (Open With) and the menu bar drop target.
    func importMany(_ urls: [URL]) {
        let importer = BookImporter()
        let context = ModelContext(modelContainer)
        for url in urls {
            do {
                _ = try importer.importBook(from: url, into: context)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
        try? context.save()
        show()
    }
}
```

- [ ] **Step 3: Build**

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
  git add book-reader-mac/Library/LibraryWindow.swift \
          book-reader-mac/Library/LibraryWindowController.swift && \
  git commit -m "feat(mac): LibraryWindow + controller with NSOpenPanel import"
```

---

## Task 13: DraggableStatusItemButton for menu-bar drops

**Files:**
- Create: `book-reader-mac/MenuBar/DraggableStatusItemButton.swift`

The standard `NSStatusItem.button` is an `NSStatusBarButton`. We attach a delegate-style closure-based drop handler by registering a custom view as the button's subview, taking up the full button bounds and forwarding mouse events. The subview implements `NSDraggingDestination` for `.fileURL`.

- [ ] **Step 1: Implement**

Write `book-reader-mac/MenuBar/DraggableStatusItemButton.swift`:
```swift
import AppKit
import UniformTypeIdentifiers

/// Drop-target overlay added on top of an NSStatusBarButton. Forwards mouse
/// events to the underlying button so menu activation still works, but
/// captures file-URL drag-and-drop and dispatches it to a closure.
final class StatusItemDropTarget: NSView {
    private let onDrop: ([URL]) -> Void

    init(frame: NSRect, onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // Let menu clicks pass through.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        urls(in: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let dropped = urls(in: sender)
        guard !dropped.isEmpty else { return false }
        onDrop(dropped)
        return true
    }

    private func urls(in info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: BookFileExtension.supportedContentTypes.map(\.identifier)
        ]
        return (info.draggingPasteboard
                    .readObjects(forClasses: [NSURL.self], options: options)
                as? [URL]) ?? []
    }
}

extension NSStatusItem {
    /// Attaches a file-URL drop overlay to this status item's button.
    @MainActor
    func installDropTarget(onDrop: @escaping ([URL]) -> Void) {
        guard let button = self.button else { return }
        let overlay = StatusItemDropTarget(frame: button.bounds, onDrop: onDrop)
        overlay.autoresizingMask = [.width, .height]
        button.addSubview(overlay)
    }
}
```

- [ ] **Step 2: Build**

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
  git add book-reader-mac/MenuBar/DraggableStatusItemButton.swift && \
  git commit -m "feat(mac): status-item drop target for file-URL drag-and-drop"
```

---

## Task 14: Extend MenuBarController with library and add-books items

**Files:**
- Modify: `book-reader-mac/MenuBar/MenuBarController.swift`

- [ ] **Step 1: Replace `MenuBarController.swift` with the extended version**

Write `book-reader-mac/MenuBar/MenuBarController.swift`:
```swift
import AppKit

/// Owns the NSStatusItem. Menu items wire to closures supplied by AppDelegate.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let onToggleReader: () -> Void
    private let onToggleAmbientMode: () -> Void
    private let onOpenLibrary: () -> Void
    private let onAddBooks: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    init(onToggleReader: @escaping () -> Void,
         onToggleAmbientMode: @escaping () -> Void,
         onOpenLibrary: @escaping () -> Void,
         onAddBooks: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void,
         onDropFiles: @escaping ([URL]) -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onToggleReader = onToggleReader
        self.onToggleAmbientMode = onToggleAmbientMode
        self.onOpenLibrary = onOpenLibrary
        self.onAddBooks = onAddBooks
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        configure()
        statusItem.installDropTarget(onDrop: onDropFiles)
    }

    private func configure() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "book.closed",
                                   accessibilityDescription: "Instant Book Reader")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(makeItem(title: "Open Reader (⌃⌥B)",
                              action: #selector(toggleReaderClicked),
                              keyEquivalent: ""))
        menu.addItem(makeItem(title: "Toggle Wallpaper Mode",
                              action: #selector(toggleAmbientClicked),
                              keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Open Library",
                              action: #selector(openLibraryClicked),
                              keyEquivalent: "l"))
        menu.addItem(makeItem(title: "Add Books…",
                              action: #selector(addBooksClicked),
                              keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Settings…",
                              action: #selector(openSettingsClicked),
                              keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit Instant Book Reader",
                              action: #selector(quitClicked),
                              keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func makeItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func toggleReaderClicked() { onToggleReader() }
    @objc private func toggleAmbientClicked() { onToggleAmbientMode() }
    @objc private func openLibraryClicked() { onOpenLibrary() }
    @objc private func addBooksClicked() { onAddBooks() }
    @objc private func openSettingsClicked() { onOpenSettings() }
    @objc private func quitClicked() { onQuit() }
}
```

- [ ] **Step 2: Build (will fail until AppDelegate is updated in Task 15)**

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -10
```
Expected at this point: a compile error in `AppDelegate.swift` because the `MenuBarController` initializer signature changed. That gets resolved in Task 15. **Do not commit yet** — combine with Task 15.

---

## Task 15: Wire library + drop dispatch into AppDelegate

**Files:**
- Modify: `book-reader-mac/App/AppDelegate.swift`

- [ ] **Step 1: Replace AppDelegate with the library-aware version**

Write `book-reader-mac/App/AppDelegate.swift`:
```swift
import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: ReadingState!
    private var modelContainer: ModelContainer!
    private var wallpaperCoordinator: WallpaperWindowCoordinator!
    private var readerController: ReaderWindowController!
    private var libraryController: LibraryWindowController!
    private var menuBar: MenuBarController!
    private var hotkey: GlobalHotkey!
    private var systemEvents: SystemEventObserver!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try AppSupportPaths.ensureCreated()
            modelContainer = try PersistenceController.makeContainer()
        } catch {
            NSApp.presentError(error)
            NSApp.terminate(nil)
            return
        }

        state = ReadingState()
        let theme: AppTheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .clayDark : .clayLight

        wallpaperCoordinator = WallpaperWindowCoordinator(
            state: state, modelContainer: modelContainer, theme: theme)
        readerController = ReaderWindowController(
            state: state, modelContainer: modelContainer, theme: theme)
        libraryController = LibraryWindowController(
            state: state, modelContainer: modelContainer, theme: theme)

        menuBar = MenuBarController(
            onToggleReader: { [weak self] in self?.readerController.toggle() },
            onToggleAmbientMode: { [weak self] in
                guard let self else { return }
                state.ambientMode = state.ambientMode == .atomic ? .page : .atomic
            },
            onOpenLibrary: { [weak self] in self?.libraryController.show() },
            onAddBooks: { [weak self] in self?.libraryController.presentOpenPanel() },
            onOpenSettings: {
                if #available(macOS 14.0, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            },
            onQuit: { NSApp.terminate(nil) },
            onDropFiles: { [weak self] urls in self?.libraryController.importMany(urls) }
        )

        hotkey = GlobalHotkey(onToggle: { [weak self] in self?.readerController.toggle() })
        hotkey.register()

        systemEvents = SystemEventObserver(
            onWillSleep: { [weak self] in try? self?.modelContainer.mainContext.save() },
            onDidWake: { _ = self },
            onLowPowerModeChange: { _ in }
        )
        systemEvents.start()

        wallpaperCoordinator.start()
    }

    /// Handles Finder "Open With → Instant Book Reader". The app is launched
    /// (or activated) with one or more file URLs; we route them through the
    /// importer and surface the library.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let libraryController else {
            // Launched specifically to open these files — defer until bootstrap completes.
            DispatchQueue.main.async { [weak self] in
                self?.application(application, open: urls)
            }
            return
        }
        libraryController.importMany(urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperCoordinator?.stop()
        systemEvents?.stop()
        try? modelContainer?.mainContext.save()
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit Tasks 14 + 15 together**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/MenuBar/MenuBarController.swift \
          book-reader-mac/App/AppDelegate.swift && \
  git commit -m "feat(mac): wire library window, add-books, and Open-With into AppDelegate"
```

---

## Task 16: Render current book's cover in the ambient placeholder

**Files:**
- Modify: `book-reader-mac/Placeholders/PlaceholderAmbientView.swift`

Plan 5 will replace this view entirely. For now we make it useful: if `ReadingState.currentBookHash` matches a `Book` in SwiftData with a `coverPath`, render that image at quarter-size in the corner card. Otherwise keep the existing placeholder text.

- [ ] **Step 1: Implement**

Write `book-reader-mac/Placeholders/PlaceholderAmbientView.swift`:
```swift
import AppKit
import SwiftData
import SwiftUI

/// Bottom-left ambient placeholder. Plan 5 replaces this with the full
/// corner-card layout (cover + chapter label + rotating highlight). For
/// the library milestone we render the current book's cover at quarter
/// size so the import pipeline is observable end-to-end on the desktop.
struct PlaceholderAmbientView: View {
    @Environment(\.appTheme) private var theme
    @Environment(ReadingState.self) private var state
    let screenName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                Spacer()
                CurrentBookCover(currentHash: state.currentBookHash)
                    .frame(width: 90, height: 130)
                Text("AMBIENT LAYER")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(1.08)
                    .foregroundStyle(theme.ink.swiftUI.opacity(0.92))
                Text(state.currentBookHash == nil
                     ? "No book selected · \(screenName)"
                     : "Plan 5 content goes here · \(screenName)")
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(theme.ink.swiftUI.opacity(0.92))
                    .lineLimit(2)
                    .padding(.bottom, 80)
            }
            .padding(.leading, 56)
            .frame(maxWidth: 360, alignment: .leading)
            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

/// Looks up the currently-selected Book and draws its cover, or a flat
/// theme-tinted rectangle if nothing is selected or no cover exists.
private struct CurrentBookCover: View {
    @Environment(\.appTheme) private var theme
    @Query private var matches: [Book]

    init(currentHash: String?) {
        let predicate: Predicate<Book>
        if let hash = currentHash {
            predicate = #Predicate<Book> { $0.sha256 == hash }
        } else {
            predicate = #Predicate<Book> { _ in false }
        }
        _matches = Query(filter: predicate)
    }

    var body: some View {
        if let book = matches.first,
           let relative = book.coverPath,
           let image = NSImage(contentsOfFile: AppSupportPaths.root
                                .appendingPathComponent(relative).path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .cornerRadius(4)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.border.swiftUI.opacity(0.4))
        }
    }
}
```

- [ ] **Step 2: Build**

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
  git add book-reader-mac/Placeholders/PlaceholderAmbientView.swift && \
  git commit -m "feat(mac): ambient placeholder shows current book cover at quarter size"
```

---

## Task 17: Manual smoke test of the library + import flow

This task has no code changes; it validates the pipeline end-to-end on a real Mac.

- [ ] **Step 1: Run all tests**

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -25
```

Expected: all test suites pass, including the four added in this plan:
- `EPUBMetadataTests`
- `PDFMetadataTests`
- `TXTMetadataTests`
- `CoverExtractorTests`
- `BookImporterTests`
…plus the four from Plan 1 (`BookHashTests`, `ReadingStateTests`, `PersistenceTests`, `ThemeEnvironmentTests`).

- [ ] **Step 2: Build and launch**

```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -configuration Debug \
    -derivedDataPath ./build build 2>&1 | tail -5 && \
  open ./build/Build/Products/Debug/InstantBookReader.app
```

- [ ] **Step 3: Visually verify**

Confirm each of the following on the running machine:

1. The menu-bar icon shows the book glyph, and the menu now includes "Open Library" and "Add Books…".
2. "Add Books…" opens an `NSOpenPanel` that only allows EPUB / PDF / TXT files.
3. After adding the bundled `sample.epub` (or any other book), the Library window opens and shows the cover, title "The Lighthouse Keeper", and author "Joseph Marlow".
4. Clicking the cover updates the ambient layer (bottom-left of every screen) to show that book's cover at quarter size.
5. Dragging a `.pdf` or `.txt` file from Finder **onto the Library window** imports it.
6. Dragging the same file **onto the menu-bar icon** imports it (no duplicate row appears because hashes match).
7. Right-click an EPUB in Finder → "Open With → Instant Book Reader" imports it through the same pipeline.
8. Re-importing the same file does not create a second row (check the count of tiles).
9. Quitting and relaunching preserves the library (SwiftData store survives).

If any of the above fails, file the failure as a bug task before moving on to Plan 3.

- [ ] **Step 4: Tag the milestone**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git tag -a mac-v0.2.0-library -m "Library + import plan complete"
```

---

## Self-review notes

Coverage check against the plan brief:

| Capability | Task(s) |
|---|---|
| ZIPFoundation SwiftPM dep added to `project.yml` | 1 |
| CFBundleDocumentTypes for EPUB/PDF/TXT | 1 |
| EPUB cover extraction via OPF (EPUB 3 properties + EPUB 2 fallback) | 4, 5 |
| PDF cover via `PDFPage.thumbnail` | 6 |
| TXT cover via attributed-string render | 7 |
| Tests against bundled EPUB/PDF/TXT fixtures | 3, 4, 6, 7, 8, 9 |
| BookImporter: copy → hash → metadata → cover → SwiftData upsert | 9, 10 |
| Dedup on re-import | 9, 10 |
| LibraryView grid + selection updates ReadingState | 11, 12 |
| "Add books…" NSOpenPanel | 11, 12 |
| Drag-and-drop onto library window | 11 |
| Drag-and-drop onto menu-bar icon | 13, 14, 15 |
| Menu bar "Open Library" and "Add Books…" items | 14 |
| Open With handling via `application(_:open:)` and CFBundleDocumentTypes | 1, 15 |
| Ambient placeholder renders the current book's cover | 16 |

What this plan deliberately defers (called out in Plan 3+):
- Actual reading of EPUB/PDF/TXT content (Plan 3)
- Highlights and per-format anchors (Plan 3)
- The real ambient corner-card layout — only the cover-quarter teaser lands here (Plan 5)
- Folder watching / Hazel-style auto-import (out of scope per spec §9.1)
- Storage location preference and "Reveal in Finder" affordance (Plan 7)

Type consistency: this plan only references types introduced in Plan 1 (`Book`, `BookFormat`, `Position`, `Highlight`, `VocabEntry`, `AICacheEntry`, `AppSupportPaths`, `BookHash`, `ReadingState`, `AppTheme`, `PersistenceController`, `WallpaperWindowCoordinator`, `ReaderWindowController`, `MenuBarController`, `GlobalHotkey`, `SystemEventObserver`) or introduced here. No "TBD"/"TODO"/placeholder code is present — every Swift block compiles as written.
