import SwiftUI
import SwiftData

struct ReaderView: View {
    let book: Book

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: ReaderSettings

    @State private var position: ReadingPosition?
    @State private var showingSettings = false

    private var theme: Theme {
        settings.resolvedTheme(for: colorScheme)
    }

    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()

            if let position {
                readerContent(position: position)
            } else {
                loadingState
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar { readerToolbar }
        .onAppear { loadOrCreatePosition() }
        .onDisappear { syncPosition() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                syncPosition()
            }
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsPanel()
                .environmentObject(settings)
        }
    }

    // MARK: - Reader Content

    @ViewBuilder
    private func readerContent(position: ReadingPosition) -> some View {
        switch book.format {
        case .epub:
            EPUBReaderView(book: book, position: position)
        case .pdf:
            PDFReaderView(book: book, position: position)
        case .txt:
            TXTReaderView(book: book, position: position)
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: ClayConstants.spacingMD) {
            ProgressView()
                .tint(.matcha600)
            Text("Preparing your book...")
                .clayCaption()
                .foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                syncPosition()
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Library")
                        .font(.system(size: 15))
                }
                .foregroundStyle(theme.accent)
            }
        }

        ToolbarItem(placement: .principal) {
            VStack(spacing: 1) {
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)

                if let position {
                    Text("\(Int(position.percentage * 100))%")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.primaryText)
            }
        }
    }

    // MARK: - Position Management

    private func loadOrCreatePosition() {
        let bookID = book.id
        let descriptor = FetchDescriptor<ReadingPosition>(
            predicate: #Predicate<ReadingPosition> { $0.bookID == bookID }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            position = existing
        } else {
            let newPosition = ReadingPosition(bookID: bookID)
            modelContext.insert(newPosition)
            try? modelContext.save()
            position = newPosition
        }

        book.lastOpened = Date()
        AppGroupManager.shared.setCurrentBook(id: bookID, format: book.format)
        AppGroupManager.shared.setCurrentBookMetadata(
            title: book.title,
            author: book.author,
            coverData: book.coverImageData
        )
    }

    private func syncPosition() {
        guard let position else { return }
        position.updatedAt = Date()
        book.readingProgress = position.percentage
        try? modelContext.save()

        let payload = ReadingPositionPayload(
            bookID: position.bookID,
            chapterIndex: position.chapterIndex,
            pageIndex: position.pageIndex,
            scrollOffset: position.scrollOffset,
            percentage: position.percentage
        )
        AppGroupManager.shared.saveReadingPosition(payload)
    }
}

// MARK: - Reader Settings Panel

struct ReaderSettingsPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: ReaderSettings

    private var theme: Theme {
        settings.resolvedTheme(for: colorScheme)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    previewCard
                }
                .listRowBackground(theme.surfaceColor)

                Section("Typography") {
                    Picker("Font", selection: $settings.fontFamily) {
                        ForEach(ReaderSettings.availableFonts, id: \.self) { font in
                            Text(font)
                                .font(.custom(
                                    font == "System Serif" ? ".AppleSystemUIFontSerif" : font,
                                    size: 15
                                ))
                                .tag(font)
                        }
                    }

                    HStack {
                        Text("Size")
                        Spacer()
                        HStack(spacing: ClayConstants.spacingSM) {
                            Button {
                                settings.fontSize = max(12, settings.fontSize - 1)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.silver)
                            }

                            Text("\(Int(settings.fontSize))pt")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .frame(width: 44)

                            Button {
                                settings.fontSize = min(32, settings.fontSize + 1)
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.matcha600)
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading) {
                        Text("Line Spacing: \(String(format: "%.1f", settings.lineHeight))x")
                        Slider(value: $settings.lineHeight, in: 1.0...2.5, step: 0.1)
                            .tint(.matcha600)
                    }
                }
                .listRowBackground(theme.surfaceColor)

                Section("Theme") {
                    Picker("Appearance", selection: $settings.theme) {
                        ForEach(AppThemeMode.allCases) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(theme.surfaceColor)
            }
            .scrollContentBackground(.hidden)
            .background(theme.backgroundColor)
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.matcha600)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The quick brown fox jumps over the lazy dog. In a hole in the ground there lived a hobbit.")
                .font(.custom(settings.resolvedFontName, size: settings.fontSize))
                .lineSpacing(settings.fontSize * (settings.lineHeight - 1))
                .foregroundStyle(theme.primaryText)
        }
        .padding(ClayConstants.spacingMD)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: ClayConstants.cornerRadiusSmall))
    }
}
