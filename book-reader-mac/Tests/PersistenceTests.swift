import XCTest
import SwiftData
@testable import InstantBookReader

final class PersistenceTests: XCTestCase {
    func testInMemoryContainerCanInsertAndFetchBook() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)
        let book = Book(sha256: "deadbeef",
                        title: "Test Book",
                        format: .epub,
                        filePath: "Books/deadbeef.epub")
        context.insert(book)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.sha256, "deadbeef")
    }

    func testFetchByHashFindsSingleBook() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(Book(sha256: "abc", title: "A", format: .epub, filePath: "x"))
        context.insert(Book(sha256: "def", title: "D", format: .pdf, filePath: "y"))
        try context.save()

        let predicate = #Predicate<Book> { $0.sha256 == "abc" }
        let fetched = try context.fetch(FetchDescriptor<Book>(predicate: predicate))
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "A")
    }

    func testHighlightCascadesWhenBookDeleted() throws {
        let container = try PersistenceController.makeInMemoryContainer()
        let context = ModelContext(container)
        let book = Book(sha256: "xyz", title: "X", format: .pdf, filePath: "x")
        context.insert(book)
        let hl = Highlight(bookHash: "xyz",
                           text: "important sentence",
                           surroundingText: "context before important sentence context after",
                           offset: 15)
        hl.book = book
        context.insert(hl)
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<Highlight>()).count, 1)
        context.delete(book)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<Highlight>()).count, 0)
    }
}
