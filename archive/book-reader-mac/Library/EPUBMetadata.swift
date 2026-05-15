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
