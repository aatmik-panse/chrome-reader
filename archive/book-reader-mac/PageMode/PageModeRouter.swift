import SwiftUI
import SwiftData
import AppKit

/// Routes the current book to the appropriate page-mode renderer based on
/// `Book.format`. Used by `WallpaperWindowCoordinator` for the `.page`
/// branch (Plan 5 + Plan 6).
///
/// One screen at a time. Multi-monitor: every screen renders the same page
/// for v1 (spec §6). No continuation across displays.
struct PageModeRouter: View {

    let screen: NSScreen

    @Environment(ReadingState.self) private var state
    @Environment(\.modelContext) private var modelContext

    /// Pull the current book by sha256 from SwiftData.
    @Query private var allBooks: [Book]

    @AppStorage("pageModeColumnWidth") private var columnWidth: Double = Double(SafeColumn.defaultWidth)
    @AppStorage("pageModeColumnPlacement") private var placementRaw: String = SafeColumnPlacement.center.rawValue
    @AppStorage("pageModeIdleTimeout") private var idleTimeoutSeconds: Double = 600

    @State private var isIdle: Bool = false
    @State private var idleWatcher: IdleWatcher?

    var body: some View {
        ZStack {
            Color.clear
            if let book = currentBook {
                content(for: book)
                    .frame(width: column.width, height: column.height)
                    .position(x: column.midX, y: column.midY)
                    .opacity(isIdle ? 0 : 1)
                    .animation(.easeInOut(duration: 0.4), value: isIdle)

                if isIdle {
                    IdleAmbientOverlay(book: book, screen: screen)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.4), value: isIdle)
                }
            }
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
        .onAppear(perform: startIdleWatcher)
        .onDisappear(perform: stopIdleWatcher)
        .onChange(of: idleTimeoutSeconds) { _, _ in restartIdleWatcher() }
    }

    private func startIdleWatcher() {
        idleWatcher = IdleWatcher(
            idleThreshold: idleTimeoutSeconds,
            tickInterval: 10,
            onIdle: { isIdle = true },
            onWake: { isIdle = false }
        )
        idleWatcher?.start()
    }

    private func stopIdleWatcher() {
        idleWatcher?.stop()
        idleWatcher = nil
    }

    private func restartIdleWatcher() {
        stopIdleWatcher()
        startIdleWatcher()
    }

    private var currentBook: Book? {
        guard let hash = state.currentBookHash else { return nil }
        return allBooks.first { $0.sha256 == hash }
    }

    private var placement: SafeColumnPlacement {
        SafeColumnPlacement(rawValue: placementRaw) ?? .center
    }

    private var column: CGRect {
        SafeColumn.frame(
            for: CGRect(origin: .zero, size: screen.frame.size),
            placement: placement,
            width: CGFloat(columnWidth)
        )
    }

    private var bodyPointSize: CGFloat {
        PhysicalTypeMetrics(screen: screen).recommendedBodyPointSize
    }

    private var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    @ViewBuilder
    private func content(for book: Book) -> some View {
        switch book.format {
        case .pdf:
            let pageIndex = decodedPDFPageIndex(book.position?.anchor ?? "1:0")
            PageModePDFView(book: book,
                            pageIndex: pageIndex,
                            isDark: isDark)

        case .epub:
            PageModeEPUBView(
                book: book,
                safeColumnWidth: column.width,
                bodyPointSize: bodyPointSize,
                pendingScrollDirection: book.position?.pendingScrollDirection,
                onPendingConsumed: { clearPending(on: book) }
            )

        case .txt:
            PageModeTXTView(
                book: book,
                charOffset: Int(book.position?.anchor ?? "0") ?? 0,
                safeColumnWidth: column.width,
                bodyPointSize: bodyPointSize,
                pendingScrollDirection: book.position?.pendingScrollDirection,
                onPendingConsumed: { clearPending(on: book) }
            )
        }
    }

    private func decodedPDFPageIndex(_ anchor: String) -> Int {
        let parts = anchor.split(separator: ":")
        let oneBased = Int(parts.first ?? "1") ?? 1
        return max(0, oneBased - 1)
    }

    private func clearPending(on book: Book) {
        book.position?.pendingScrollDirection = nil
        try? modelContext.save()
    }
}

/// Overlay shown after the idle threshold trips. Reuses Plan 5's
/// `AmbientCornerCard` with no chapter / highlight — just cover + footer.
private struct IdleAmbientOverlay: View {
    let book: Book
    let screen: NSScreen

    var body: some View {
        // AmbientCornerCard (Plan 5) takes (book, highlight, chapterTitle, progressPercent).
        // For the idle overlay we drop the chapter line and quote — only the
        // cover + title-author footer remain.
        AmbientCornerCard(
            book: book,
            highlight: nil,
            chapterTitle: nil,
            progressPercent: nil
        )
        .frame(width: screen.frame.width, height: screen.frame.height,
               alignment: .bottomLeading)
        .padding([.bottom, .leading], 64)
    }
}
