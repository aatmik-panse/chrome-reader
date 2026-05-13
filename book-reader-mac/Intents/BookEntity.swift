import AppIntents
import Foundation
import SwiftData

/// App Intents entity wrapping a SwiftData Book.
/// The identifier is the SHA-256 hash (stable across launches).
struct BookEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Book" }
    static var defaultQuery = BookEntityQuery()

    var id: String       // sha256
    var title: String
    var author: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)",
                              subtitle: author.map { "\($0)" })
    }
}

/// EntityQuery: resolve by id and search by prefix.
struct BookEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BookEntity] {
        try await fetch { books in books.filter { identifiers.contains($0.sha256) } }
    }

    func suggestedEntities() async throws -> [BookEntity] {
        try await fetch { $0 }
    }

    func entities(matching string: String) async throws -> [BookEntity] {
        let q = string.lowercased()
        return try await fetch { books in
            books.filter { $0.title.lowercased().contains(q)
                || ($0.author?.lowercased().contains(q) ?? false) }
        }
    }

    @MainActor
    private func fetch(_ transform: ([Book]) -> [Book]) async throws -> [BookEntity] {
        let container = try PersistenceController.makeContainer()
        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.title)]))
        return transform(books).map {
            BookEntity(id: $0.sha256, title: $0.title, author: $0.author)
        }
    }
}
