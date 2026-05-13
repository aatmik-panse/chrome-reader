import AppIntents
import Foundation

struct OpenBookIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Book"
    static var description = IntentDescription("Open a book in the Instant Book Reader.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Book")
    var book: BookEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDelegate.shared?.openBook(withHash: book.id)
        return .result()
    }
}
