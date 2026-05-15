import SwiftUI

struct TXTReaderView: View {
    let book: Book
    var position: ReadingPosition

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: ReaderSettings

    @State private var pages: [CachedPage] = []
    @State private var currentPageIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isTransitioning = false

    private var theme: Theme {
        settings.resolvedTheme(for: colorScheme)
    }

    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()

            if pages.isEmpty {
                loadingState
            } else {
                readerBody
            }
        }
        .onAppear(perform: loadPages)
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: ClayConstants.spacingMD) {
            ProgressView()
                .tint(.matcha600)
            Text("Preparing pages...")
                .clayCaption()
                .foregroundStyle(theme.secondaryText)
        }
    }

    // MARK: - Reader Body

    private var readerBody: some View {
        GeometryReader { geo in
            ZStack {
                pageContent
                    .offset(x: dragOffset)

                tapZones(width: geo.size.width)
            }
            .gesture(swipeGesture(width: geo.size.width))
            .overlay(alignment: .bottom) {
                pageIndicator
            }
        }
    }

    // MARK: - Page Content

    private var pageContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(pages[currentPageIndex].text)
                .font(.custom(settings.resolvedFontName, size: settings.fontSize))
                .lineSpacing(settings.fontSize * (settings.lineHeight - 1))
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, ClayConstants.spacingLG)
                .padding(.top, ClayConstants.spacingMD)
                .padding(.bottom, 80)
        }
        .id(currentPageIndex)
    }

    // MARK: - Tap Zones

    private func tapZones(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .frame(width: width * 0.33)
                .onTapGesture { goToPreviousPage() }

            Color.clear
                .contentShape(Rectangle())
                .frame(width: width * 0.34)

            Color.clear
                .contentShape(Rectangle())
                .frame(width: width * 0.33)
                .onTapGesture { goToNextPage() }
        }
        .allowsHitTesting(!isTransitioning)
    }

    // MARK: - Swipe Gesture

    private func swipeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 30, coordinateSpace: .local)
            .onChanged { value in
                dragOffset = value.translation.width * 0.4
            }
            .onEnded { value in
                let threshold: CGFloat = width * 0.2
                if value.translation.width < -threshold {
                    goToNextPage()
                } else if value.translation.width > threshold {
                    goToPreviousPage()
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    dragOffset = 0
                }
            }
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: ClayConstants.spacingSM) {
            if let chapterTitle = pages[currentPageIndex].chapterTitle {
                Text(chapterTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)

                Text("·")
                    .foregroundStyle(theme.secondaryText)
            }

            Text("\(currentPageIndex + 1) / \(pages.count)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.secondaryText)

            Spacer()

            Text("\(Int(currentProgress * 100))%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.accent)
        }
        .padding(.horizontal, ClayConstants.spacingLG)
        .padding(.vertical, ClayConstants.spacingSM)
        .background(
            theme.backgroundColor.opacity(0.95)
                .background(.ultraThinMaterial)
        )
    }

    // MARK: - Navigation

    private func goToNextPage() {
        guard currentPageIndex < pages.count - 1, !isTransitioning else { return }
        isTransitioning = true
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPageIndex += 1
        }
        updatePosition()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isTransitioning = false
        }
    }

    private func goToPreviousPage() {
        guard currentPageIndex > 0, !isTransitioning else { return }
        isTransitioning = true
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPageIndex -= 1
        }
        updatePosition()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isTransitioning = false
        }
    }

    // MARK: - Position

    private var currentProgress: Double {
        pages.isEmpty ? 0 : Double(currentPageIndex) / Double(max(pages.count - 1, 1))
    }

    private func updatePosition() {
        position.pageIndex = currentPageIndex
        position.percentage = currentProgress
        position.updatedAt = Date()
    }

    // MARK: - Loading

    private func loadPages() {
        if let cache = AppGroupManager.shared.getPageCache(for: book.id), !cache.isEmpty {
            pages = cache.pages
        } else {
            let extractor = TextExtractor()
            let cache = extractor.extractPages(from: book.fileURL, format: .txt, bookID: book.id)
            AppGroupManager.shared.savePageCache(cache, for: book.id)
            pages = cache.pages
        }

        currentPageIndex = min(position.pageIndex, max(pages.count - 1, 0))
    }
}
