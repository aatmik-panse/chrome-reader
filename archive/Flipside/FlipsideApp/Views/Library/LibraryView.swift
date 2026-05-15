import SwiftUI
import SwiftData
import PDFKit
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: ReaderSettings

    @Query(sort: \Book.dateAdded, order: .reverse) private var books: [Book]

    @State private var showingImportSheet = false
    @State private var importError: String?
    @State private var showingError = false

    private var theme: Theme {
        settings.resolvedTheme(for: colorScheme)
    }

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: ClayConstants.spacingMD), count: count)
    }

    private var currentlyReading: Book? {
        if let currentID = AppGroupManager.shared.getCurrentBookID() {
            return books.first { $0.id == currentID }
        }
        return books.first
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            theme.backgroundColor.ignoresSafeArea()

            if books.isEmpty {
                emptyState
            } else {
                scrollContent
            }

            floatingAddButton
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { syncWidgetDataIfNeeded() }
        .sheet(isPresented: $showingImportSheet) {
            ImportSheet { result in
                handleFileImport(result)
            }
        }
        .alert("Import Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(importError ?? "An unknown error occurred.")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.primaryText)
            }
        }
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClayConstants.spacingXL) {
                header

                if let current = currentlyReading {
                    currentlyReadingSection(current)
                }

                libraryGridSection
            }
            .padding(.horizontal, ClayConstants.spacingMD)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: ClayConstants.spacingXS) {
            Text("Flipside")
                .clayTitle()
                .foregroundStyle(theme.primaryText)

            Text("Stop scrolling. Start reading.")
                .clayCaption()
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.top, ClayConstants.spacingSM)
    }

    // MARK: - Currently Reading

    private func currentlyReadingSection(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: ClayConstants.spacingSM) {
            Text("CURRENTLY READING")
                .clayLabel()
                .foregroundStyle(theme.secondaryText)

            NavigationLink(value: book) {
                HStack(spacing: ClayConstants.spacingMD) {
                    bookCoverImage(book)
                        .frame(width: 80, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: ClayConstants.cornerRadiusSmall))

                    VStack(alignment: .leading, spacing: ClayConstants.spacingSM) {
                        Text(book.title)
                            .font(.system(size: 18, weight: .semibold, design: .serif))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(book.author)
                            .clayCaption()
                            .foregroundStyle(theme.secondaryText)

                        Spacer(minLength: 0)

                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: book.readingProgress)
                                .tint(.matcha600)

                            Text("\(Int(book.readingProgress * 100))% complete")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    .padding(.vertical, ClayConstants.spacingSM)
                }
                .padding(ClayConstants.spacingMD)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surfaceColor)
                .clipShape(RoundedRectangle(cornerRadius: ClayConstants.cornerRadiusMedium))
                .clayShadow(theme: theme)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Library Grid

    private var libraryGridSection: some View {
        VStack(alignment: .leading, spacing: ClayConstants.spacingSM) {
            HStack {
                Text("LIBRARY")
                    .clayLabel()
                    .foregroundStyle(theme.secondaryText)

                Spacer()

                Text("\(books.count) books")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)
            }

            LazyVGrid(columns: columns, spacing: ClayConstants.spacingMD) {
                ForEach(books) { book in
                    bookCard(book)
                }
            }
        }
    }

    // MARK: - Book Card

    private func bookCard(_ book: Book) -> some View {
        NavigationLink(value: book) {
            VStack(alignment: .leading, spacing: ClayConstants.spacingSM) {
                bookCoverImage(book)
                    .frame(maxWidth: .infinity)
                    .frame(height: sizeClass == .regular ? 240 : 200)
                    .clipShape(RoundedRectangle(cornerRadius: ClayConstants.cornerRadiusSmall))

                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(book.author)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }

                if book.readingProgress > 0 {
                    ProgressView(value: book.readingProgress)
                        .tint(.matcha600)
                }
            }
            .padding(ClayConstants.spacingSM)
            .background(theme.surfaceColor)
            .clipShape(RoundedRectangle(cornerRadius: ClayConstants.cornerRadiusMedium))
            .clayShadow(theme: theme)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                AppGroupManager.shared.setCurrentBook(id: book.id, format: book.format)
            } label: {
                Label("Set as Current", systemImage: "bookmark")
            }

            Divider()

            Button(role: .destructive) {
                deleteBook(book)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Cover Image

    @ViewBuilder
    private func bookCoverImage(_ book: Book) -> some View {
        if let data = book.coverImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            let hue = Double(abs(book.title.hashValue) % 360) / 360.0
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hue: hue, saturation: 0.12, brightness: 0.95),
                        Color(hue: hue, saturation: 0.18, brightness: 0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                VStack(spacing: 8) {
                    Text(String(book.title.prefix(1)).uppercased())
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(Color.charcoal.opacity(0.25))

                    Text(book.format.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(Color.charcoal.opacity(0.15))
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: ClayConstants.spacingLG) {
            Spacer()

            VStack(spacing: ClayConstants.spacingMD) {
                ZStack {
                    Circle()
                        .fill(Color.oat.opacity(0.5))
                        .frame(width: 120, height: 120)

                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(theme.secondaryText.opacity(0.6))
                }

                VStack(spacing: ClayConstants.spacingSM) {
                    Text("Your library is empty")
                        .clayHeading()
                        .foregroundStyle(theme.primaryText)

                    Text("Import your first book to start reading.\nSupports EPUB, PDF, and plain text files.")
                        .clayBody(size: 15)
                        .foregroundStyle(theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                showingImportSheet = true
            } label: {
                Label("Import a Book", systemImage: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, ClayConstants.spacingLG)
                    .padding(.vertical, ClayConstants.spacingMD)
                    .background(Color.matcha600)
                    .clipShape(Capsule())
                    .clayShadow()
            }

            Spacer()
        }
        .padding(ClayConstants.spacingXL)
    }

    // MARK: - Floating Add Button

    private var floatingAddButton: some View {
        Button {
            showingImportSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(Color.matcha600)
                        .clayShadow(theme: theme)
                )
        }
        .padding(.trailing, ClayConstants.spacingLG)
        .padding(.bottom, ClayConstants.spacingLG)
    }

    // MARK: - Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }

        Task {
            do {
                let importer = BookImporter()
                let book = try await importer.importBook(from: url)
                await MainActor.run {
                    modelContext.insert(book)
                    try? modelContext.save()
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    showingError = true
                }
            }
        }
    }

    private func deleteBook(_ book: Book) {
        try? FileManager.default.removeItem(at: book.fileURL)
        AppGroupManager.shared.deletePageCache(for: book.id)
        AppGroupManager.shared.deletePageImages(for: book.id)
        modelContext.delete(book)
        try? modelContext.save()
    }

    private func syncWidgetDataIfNeeded() {
        let manager = AppGroupManager.shared

        if manager.getCurrentBookID() != nil { return }
        guard let book = books.first else { return }

        manager.setCurrentBook(id: book.id, format: book.format)
        manager.setCurrentBookMetadata(
            title: book.title,
            author: book.author,
            coverData: book.coverImageData
        )

        if manager.getReadingPosition(for: book.id) == nil {
            manager.saveReadingPosition(ReadingPositionPayload(bookID: book.id))
        }

        Task {
            if book.format == .pdf && manager.pageImageCount(for: book.id) == 0 {
                prerenderPDFPages(book: book)
            }

            if manager.getPageCache(for: book.id) == nil {
                let extractor = TextExtractor()
                let cache = extractor.extractPages(from: book.fileURL, format: book.format, bookID: book.id)
                manager.savePageCache(cache, for: book.id)
            }
        }
    }

    private func prerenderPDFPages(book: Book) {
        guard let document = PDFKit.PDFDocument(url: book.fileURL) else { return }
        let targetWidth: CGFloat = 500

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let scale = targetWidth / bounds.width
            let size = CGSize(width: targetWidth, height: bounds.height * scale)

            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                ctx.cgContext.translateBy(x: 0, y: size.height)
                ctx.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: ctx.cgContext)
            }

            if let data = image.jpegData(compressionQuality: 0.7) {
                AppGroupManager.shared.savePageImage(data, for: book.id, pageIndex: i)
            }
        }
    }
}
