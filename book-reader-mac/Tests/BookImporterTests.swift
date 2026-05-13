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
