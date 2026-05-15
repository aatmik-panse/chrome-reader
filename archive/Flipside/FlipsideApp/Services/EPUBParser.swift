import Foundation
import ZIPFoundation

// MARK: - EPUB Models

struct EPUBChapter: Sendable {
    let title: String
    let htmlContent: String
    let plainText: String
}

struct EPUBBook: Sendable {
    let title: String
    let author: String
    let coverImageData: Data?
    let chapters: [EPUBChapter]

    var totalCharacterCount: Int {
        chapters.reduce(0) { $0 + $1.plainText.count }
    }
}

// MARK: - Errors

enum EPUBError: LocalizedError {
    case fileNotFound
    case extractionFailed(underlying: Error)
    case missingContainerXML
    case missingOPFPath
    case invalidOPF

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            "EPUB file not found at the specified path"
        case .extractionFailed(let error):
            "Failed to extract EPUB archive: \(error.localizedDescription)"
        case .missingContainerXML:
            "EPUB is missing META-INF/container.xml"
        case .missingOPFPath:
            "Could not locate the OPF file path in container.xml"
        case .invalidOPF:
            "The OPF package file is invalid or unreadable"
        }
    }
}

// MARK: - EPUBParser

struct EPUBParser: Sendable {

    func parse(epubAt url: URL) throws -> EPUBBook {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw EPUBError.fileNotFound
        }

        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("epub_\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: tempDir) }

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try fm.unzipItem(at: url, to: tempDir)
        } catch {
            throw EPUBError.extractionFailed(underlying: error)
        }

        let opfRelativePath = try findOPFPath(in: tempDir)
        let opfURL = tempDir.appendingPathComponent(opfRelativePath)
        let opfBaseURL = opfURL.deletingLastPathComponent()

        let opf = try parseOPF(at: opfURL)
        let coverData = loadCoverImage(itemID: opf.coverItemID, manifest: opf.manifest, baseURL: opfBaseURL)
        let chapters = loadChapters(spineRefs: opf.spineItemRefs, manifest: opf.manifest, baseURL: opfBaseURL)

        return EPUBBook(
            title: opf.title ?? url.deletingPathExtension().lastPathComponent,
            author: opf.author ?? "Unknown Author",
            coverImageData: coverData,
            chapters: chapters
        )
    }

    // MARK: - Container XML

    private func findOPFPath(in extractedDir: URL) throws -> String {
        let containerURL = extractedDir
            .appendingPathComponent("META-INF")
            .appendingPathComponent("container.xml")

        guard FileManager.default.fileExists(atPath: containerURL.path) else {
            throw EPUBError.missingContainerXML
        }

        let data = try Data(contentsOf: containerURL)
        let delegate = ContainerXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        guard let path = delegate.opfPath else {
            throw EPUBError.missingOPFPath
        }
        return path
    }

    // MARK: - OPF Parsing

    private struct OPFResult {
        var title: String?
        var author: String?
        var coverItemID: String?
        var manifest: [String: ManifestItem]
        var spineItemRefs: [String]
    }

    private struct ManifestItem {
        let id: String
        let href: String
        let mediaType: String
        let properties: String?
    }

    private func parseOPF(at url: URL) throws -> OPFResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw EPUBError.invalidOPF
        }

        let data = try Data(contentsOf: url)
        let delegate = OPFXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        var coverID = delegate.coverMetaContent
        if coverID == nil {
            coverID = delegate.manifest.first(where: { $0.value.properties?.contains("cover-image") == true })?.key
        }

        return OPFResult(
            title: delegate.title,
            author: delegate.author,
            coverItemID: coverID,
            manifest: delegate.manifest.mapValues { item in
                ManifestItem(id: item.id, href: item.href, mediaType: item.mediaType, properties: item.properties)
            },
            spineItemRefs: delegate.spineItemRefs
        )
    }

    // MARK: - Cover Image

    private func loadCoverImage(itemID: String?, manifest: [String: ManifestItem], baseURL: URL) -> Data? {
        guard let id = itemID, let item = manifest[id] else { return nil }
        let imageURL = baseURL.appendingPathComponent(item.href)
        return try? Data(contentsOf: imageURL)
    }

    // MARK: - Chapters

    private func loadChapters(
        spineRefs: [String],
        manifest: [String: ManifestItem],
        baseURL: URL
    ) -> [EPUBChapter] {
        var chapters: [EPUBChapter] = []
        var chapterNumber = 1

        for idref in spineRefs {
            guard let item = manifest[idref] else { continue }
            let isContent = item.mediaType == "application/xhtml+xml" || item.mediaType == "text/html"
            guard isContent else { continue }

            let chapterURL = baseURL.appendingPathComponent(item.href)
            guard let htmlData = try? Data(contentsOf: chapterURL),
                  let html = String(data: htmlData, encoding: .utf8) else { continue }

            let plainText = Self.stripHTMLTags(from: html)
            let trimmed = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let title = Self.extractHTMLTitle(from: html) ?? "Chapter \(chapterNumber)"
            chapters.append(EPUBChapter(title: title, htmlContent: html, plainText: trimmed))
            chapterNumber += 1
        }

        return chapters
    }

    // MARK: - HTML Processing

    static func stripHTMLTags(from html: String) -> String {
        var text = html
        text = text.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(
            of: "<(br|p|div|h[1-6]|li|tr|blockquote|hr)[^>]*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeHTMLEntities(text)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractHTMLTitle(from html: String) -> String? {
        guard let range = html.range(
            of: "<title[^>]*>(.*?)</title>",
            options: .regularExpression,
            range: html.startIndex..<html.endIndex
        ) else { return nil }

        let match = String(html[range])
        let title = match
            .replacingOccurrences(of: "<title[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "</title>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        let entities: [(pattern: String, replacement: String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&nbsp;", " "), ("&quot;", "\""), ("&apos;", "'"),
            ("&#39;", "'"), ("&#x27;", "'"), ("&mdash;", "—"),
            ("&ndash;", "–"), ("&hellip;", "…"), ("&lsquo;", "\u{2018}"),
            ("&rsquo;", "\u{2019}"), ("&ldquo;", "\u{201C}"), ("&rdquo;", "\u{201D}"),
        ]
        var result = text
        for (pattern, replacement) in entities {
            result = result.replacingOccurrences(of: pattern, with: replacement)
        }
        result = result.replacingOccurrences(
            of: "&#(\\d+);",
            with: "",
            options: .regularExpression
        )
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let mutable = NSMutableString(string: result)
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: mutable.length))
            for match in matches.reversed() {
                let codeRange = match.range(at: 1)
                if let swiftRange = Range(codeRange, in: result),
                   let code = UInt32(result[swiftRange]),
                   let scalar = Unicode.Scalar(code) {
                    mutable.replaceCharacters(in: match.range, with: String(scalar))
                }
            }
            result = mutable as String
        }
        return result
    }
}

// MARK: - Container XML Delegate

private final class ContainerXMLDelegate: NSObject, XMLParserDelegate {
    var opfPath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "rootfile" || elementName.hasSuffix(":rootfile") {
            opfPath = attributeDict["full-path"]
        }
    }
}

// MARK: - OPF XML Delegate

private final class OPFXMLDelegate: NSObject, XMLParserDelegate {
    struct Item {
        let id: String
        let href: String
        let mediaType: String
        let properties: String?
    }

    var title: String?
    var author: String?
    var coverMetaContent: String?
    var manifest: [String: Item] = [:]
    var spineItemRefs: [String] = []

    private var currentElement = ""
    private var currentText = ""
    private var insideMetadata = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = localElementName(elementName)
        currentElement = localName
        currentText = ""

        switch localName {
        case "metadata":
            insideMetadata = true
        case "item":
            if let id = attributeDict["id"],
               let href = attributeDict["href"],
               let mediaType = attributeDict["media-type"] {
                manifest[id] = Item(
                    id: id,
                    href: href,
                    mediaType: mediaType,
                    properties: attributeDict["properties"]
                )
            }
        case "itemref":
            if let idref = attributeDict["idref"] {
                spineItemRefs.append(idref)
            }
        case "meta":
            if attributeDict["name"] == "cover",
               let content = attributeDict["content"] {
                coverMetaContent = content
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard insideMetadata else { return }
        let localName = localElementName(elementName)
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch localName {
        case "title":
            if title == nil, !trimmed.isEmpty { title = trimmed }
        case "creator":
            if author == nil, !trimmed.isEmpty { author = trimmed }
        case "metadata":
            insideMetadata = false
        default:
            break
        }
    }

    private func localElementName(_ qualifiedName: String) -> String {
        if let colonIndex = qualifiedName.lastIndex(of: ":") {
            return String(qualifiedName[qualifiedName.index(after: colonIndex)...])
        }
        return qualifiedName
    }
}
