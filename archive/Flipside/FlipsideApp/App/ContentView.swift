import SwiftUI

struct ContentView: View {
    @ObservedObject private var settings = ReaderSettings.shared

    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationDestination(for: Book.self) { book in
                    ReaderView(book: book)
                }
        }
        .tint(.matcha600)
        .environmentObject(settings)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Book.self, ReadingPosition.self], inMemory: true)
}
