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
