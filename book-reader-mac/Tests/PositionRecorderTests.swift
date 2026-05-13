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
        XCTAssertEqual(positions.first?.percentage ?? -1, 0.5, accuracy: 0.0001)
    }
}
