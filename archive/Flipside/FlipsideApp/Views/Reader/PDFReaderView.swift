import SwiftUI
import PDFKit

struct PDFReaderView: View {
    let book: Book
    var position: ReadingPosition

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: ReaderSettings

    @State private var currentPage: Int = 0
    @State private var totalPages: Int = 0
    @State private var isContinuousScroll = false
    @State private var showingPageJump = false
    @State private var jumpToPageText = ""

    private var theme: Theme {
        settings.resolvedTheme(for: colorScheme)
    }

    private var readingProgress: Double {
        guard totalPages > 0 else { return 0 }
        return Double(currentPage + 1) / Double(totalPages)
    }

    private var warmBackground: Color {
        theme == .light
            ? Color(red: 0.97, green: 0.95, blue: 0.92)
            : Color(red: 0.12, green: 0.12, blue: 0.11)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            warmBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                PDFKitViewRepresentable(
                    url: book.fileURL,
                    currentPage: $currentPage,
                    totalPages: $totalPages,
                    isContinuous: isContinuousScroll,
                    initialPage: position.pageIndex
                )
                .ignoresSafeArea(edges: .bottom)

                bottomBar
            }

            progressStrip
        }
        .background(warmBackground)
        .onAppear {
            isContinuousScroll = settings.pdfViewMode == .continuous
        }
        .onChange(of: currentPage) { _, newPage in
            position.pageIndex = newPage
            position.percentage = totalPages > 0 ? Double(newPage) / Double(totalPages) : 0
            position.updatedAt = Date()
        }
        .alert("Go to Page", isPresented: $showingPageJump) {
            TextField("Page number", text: $jumpToPageText)
                .keyboardType(.numberPad)
            Button("Go") {
                if let page = Int(jumpToPageText), page > 0, page <= totalPages {
                    currentPage = page - 1
                }
                jumpToPageText = ""
            }
            Button("Cancel", role: .cancel) {
                jumpToPageText = ""
            }
        } message: {
            Text("Enter a page number (1\u{2013}\(totalPages))")
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if totalPages > 1 {
                pageSlider
            }

            HStack(spacing: ClayConstants.spacingMD) {
                navButton(
                    systemImage: "chevron.left",
                    disabled: currentPage <= 0
                ) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentPage = max(0, currentPage - 1)
                    }
                }

                Spacer()

                Button {
                    showingPageJump = true
                } label: {
                    Text("Page \(currentPage + 1) of \(totalPages)")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(theme.divider.opacity(0.5), lineWidth: 0.5)
                        )
                }

                Spacer()

                HStack(spacing: ClayConstants.spacingSM) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isContinuousScroll.toggle()
                        }
                    } label: {
                        Image(systemName: isContinuousScroll ? "rectangle.split.1x2" : "rectangle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.primaryText)
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(theme.divider.opacity(0.5), lineWidth: 0.5)
                            )
                    }

                    navButton(
                        systemImage: "chevron.right",
                        disabled: currentPage >= totalPages - 1
                    ) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentPage = min(totalPages - 1, currentPage + 1)
                        }
                    }
                }
            }
            .padding(.horizontal, ClayConstants.spacingMD)
            .padding(.vertical, ClayConstants.spacingSM + 2)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.divider.opacity(0.4))
                .frame(height: 0.5)
        }
    }

    // MARK: - Navigation Button

    private func navButton(
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(disabled ? theme.divider : theme.accent)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(
                            disabled ? theme.divider.opacity(0.3) : theme.accent.opacity(0.3),
                            lineWidth: 0.5
                        )
                )
        }
        .disabled(disabled)
    }

    // MARK: - Page Slider

    private var pageSlider: some View {
        Slider(
            value: Binding(
                get: { Double(currentPage) },
                set: { currentPage = Int($0) }
            ),
            in: 0...Double(max(1, totalPages - 1)),
            step: 1
        )
        .tint(.matcha600)
        .padding(.horizontal, ClayConstants.spacingMD)
        .padding(.top, ClayConstants.spacingSM)
    }

    // MARK: - Bottom Progress Strip

    private var progressStrip: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Spacer()
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(theme.divider.opacity(0.3))
                        .frame(height: 2.5)

                    Rectangle()
                        .fill(theme.accent)
                        .frame(width: max(2.5, geo.size.width * readingProgress), height: 2.5)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - PDFKit UIViewRepresentable

struct PDFKitViewRepresentable: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int
    @Binding var totalPages: Int
    var isContinuous: Bool
    var initialPage: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = isContinuous ? .singlePageContinuous : .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        pdfView.pageShadowsEnabled = true
        pdfView.pageBreakMargins = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)

        if let document = PDFDocument(url: url) {
            pdfView.document = document
            DispatchQueue.main.async {
                totalPages = document.pageCount
            }

            if initialPage > 0, initialPage < document.pageCount,
               let page = document.page(at: initialPage) {
                pdfView.go(to: page)
            }
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        let newMode: PDFDisplayMode = isContinuous ? .singlePageContinuous : .singlePage
        if pdfView.displayMode != newMode {
            pdfView.displayMode = newMode
        }

        if let document = pdfView.document,
           currentPage < document.pageCount,
           let page = document.page(at: currentPage),
           pdfView.currentPage != page {
            pdfView.go(to: page)
        }
    }

    @MainActor
    class Coordinator: NSObject {
        var parent: PDFKitViewRepresentable

        init(parent: PDFKitViewRepresentable) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let currentPage = pdfView.currentPage,
                  let document = pdfView.document else { return }

            let pageIndex = document.index(for: currentPage)
            parent.currentPage = pageIndex
        }
    }
}
