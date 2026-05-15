import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Reading Widget Definition

struct ReadingWidget: Widget {
    let kind = AppGroupManager.widgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: ReadingWidgetConfigurationIntent.self,
            provider: ReadingTimelineProvider()
        ) { entry in
            ReadingWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    ClayColors.cream
                }
        }
        .configurationDisplayName("Read")
        .description("Read your current book right from the Home Screen.")
        .supportedFamilies([.systemLarge, .systemExtraLarge])
    }
}

// MARK: - Text Truncation

private enum TextTruncation {
    static func truncate(_ text: String, to limit: Int) -> String {
        let cleaned = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count > limit else { return cleaned }

        let trimmed = String(cleaned.prefix(limit))

        let sentenceEnders: [Character] = [".", "!", "?", "\"", "\u{201D}"]
        if let lastSentenceEnd = trimmed.lastIndex(where: { sentenceEnders.contains($0) }),
           trimmed.distance(from: trimmed.startIndex, to: lastSentenceEnd) > limit / 3 {
            return String(trimmed[...lastSentenceEnd])
        }

        if let lastSpace = trimmed.lastIndex(of: " ") {
            return String(trimmed[..<lastSpace]) + "\u{2026}"
        }

        return trimmed + "\u{2026}"
    }
}

// MARK: - Entry View

struct ReadingWidgetEntryView: View {
    let entry: ReadingEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var layout: StandByLayout {
        .resolve(showsBackground: showsBackground, family: family)
    }

    var body: some View {
        Group {
            if entry.hasBook {
                if entry.isPDF {
                    pdfContent
                } else {
                    textContent
                }
            } else {
                emptyState
            }
        }
        .widgetURL(URL(string: "flipside://read"))
    }

    // MARK: - PDF Content (renders the actual PDF page as an image)

    private var isZoomed: Bool { entry.zoomLevel > 1.01 }
    private var zoomLabelText: String {
        let pct = Int(entry.zoomLevel * 100)
        return "\(pct)%"
    }

    @ViewBuilder
    private var pdfContent: some View {
        VStack(spacing: 0) {
            pdfHeader

            if let imageData = entry.pageImageData,
               let uiImage = UIImage(data: imageData) {
                GeometryReader { geo in
                    let scaledW = geo.size.width * entry.zoomLevel
                    let scaledH = (uiImage.size.height / uiImage.size.width) * scaledW
                    let overflowX = max(0, scaledW - geo.size.width)
                    let overflowY = max(0, scaledH - geo.size.height)
                    let xOffset = -overflowX * entry.scrollOffsetX
                    let yOffset = -overflowY * entry.scrollOffsetY

                    Image(uiImage: uiImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: scaledW, height: scaledH)
                        .offset(x: xOffset, y: yOffset)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                        .clipped()
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                .padding(.vertical, 2)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(layout.separatorColor.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 28))
                                .foregroundStyle(layout.secondaryTextColor)
                            Text("Loading page...")
                                .font(.system(size: 11))
                                .foregroundStyle(layout.secondaryTextColor)
                        }
                    }
            }

            pdfNavigationBar
                .padding(.top, 4)
        }
    }

    private var pdfHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .font(.system(size: 9))
            Text(entry.bookTitle)
                .lineLimit(1)

            Spacer(minLength: 4)

            Text("p.\(entry.currentPage + 1)/\(entry.totalPages)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(layout.accentColor)
                .standByAccent()
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(layout.secondaryTextColor)
        .padding(.bottom, 4)
    }

    private var canScrollUp: Bool { isZoomed && entry.scrollOffsetY > 0.001 }
    private var canScrollDown: Bool {
        guard isZoomed else { return false }
        let maxY = max(0, 1.0 - (1.0 / entry.zoomLevel))
        return entry.scrollOffsetY < maxY - 0.001
    }
    private var canScrollLeft: Bool { isZoomed && entry.scrollOffsetX > 0.001 }
    private var canScrollRight: Bool { isZoomed && entry.scrollOffsetX < 0.999 }

    private var pdfNavigationBar: some View {
        VStack(spacing: 4) {
            if isZoomed {
                HStack(spacing: 6) {
                    arrowButton(intent: ScrollLeftIntent(), icon: "chevron.left", active: canScrollLeft)
                    arrowButton(intent: ScrollUpIntent(), icon: "chevron.up", active: canScrollUp)
                    arrowButton(intent: ScrollDownIntent(), icon: "chevron.down", active: canScrollDown)
                    arrowButton(intent: ScrollRightIntent(), icon: "chevron.right", active: canScrollRight)
                }
            }

            HStack(spacing: 5) {
                Button(intent: PrevPageIntent()) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(layout.accentColor)
                        .frame(width: 30, height: 26)
                        .background(layout.buttonBackgroundColor, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button(intent: ZoomOutIntent()) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.zoomLevel > 1.01 ? layout.accentColor : layout.secondaryTextColor.opacity(0.4))
                        .frame(width: 28, height: 26)
                        .background(layout.buttonBackgroundColor, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(zoomLabelText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(layout.secondaryTextColor)
                    .contentTransition(.numericText())

                Spacer()

                Button(intent: ZoomInIntent()) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.zoomLevel < 2.99 ? layout.accentColor : layout.secondaryTextColor.opacity(0.4))
                        .frame(width: 28, height: 26)
                        .background(layout.buttonBackgroundColor, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button(intent: NextPageIntent()) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(layout.accentColor)
                        .frame(width: 30, height: 26)
                        .background(layout.buttonBackgroundColor, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func arrowButton(intent: some AppIntent, icon: String, active: Bool) -> some View {
        Button(intent: intent) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(active ? layout.accentColor : layout.secondaryTextColor.opacity(0.3))
                .frame(width: 36, height: 22)
                .background(layout.buttonBackgroundColor, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Text Content (EPUB / TXT)

    @ViewBuilder
    private var textContent: some View {
        switch family {
        case .systemExtraLarge:
            extraLargeTextBody
        default:
            largeTextBody
        }
    }

    private var charLimit: Int {
        switch family {
        case .systemExtraLarge: return 1000
        default: return 650
        }
    }

    private var displayText: String {
        TextTruncation.truncate(entry.pageText, to: charLimit)
    }

    private var largeTextBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            textHeader
                .padding(.bottom, 8)

            progressBar
                .padding(.bottom, 10)

            Text(displayText)
                .font(.system(size: layout.isStandBy ? 20 : 15, design: .serif))
                .foregroundStyle(layout.textColor)
                .lineSpacing(layout.isStandBy ? 7 : 5)
                .tracking(0.1)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: false)
                .frame(maxHeight: .infinity, alignment: .topLeading)

            separator
                .padding(.top, 6)

            textNavigationBar
                .padding(.top, 10)
        }
    }

    private var extraLargeTextBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                coverColumn

                VStack(alignment: .leading, spacing: 0) {
                    textHeader
                        .padding(.bottom, 8)

                    progressBar
                        .padding(.bottom, 10)

                    Text(displayText)
                        .font(.system(size: layout.isStandBy ? 20 : 15, design: .serif))
                        .foregroundStyle(layout.textColor)
                        .lineSpacing(layout.isStandBy ? 7 : 5)
                        .tracking(0.1)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: false)
                        .frame(maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)

            separator

            textNavigationBar
                .padding(.top, 10)
        }
    }

    // MARK: - Shared Components

    private var textHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Label {
                Text(entry.chapterTitle.isEmpty ? entry.bookTitle : entry.chapterTitle)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "book.fill")
                    .font(.system(size: layout.isStandBy ? 13 : 11))
            }
            .font(layout.headerFont)
            .foregroundStyle(layout.secondaryTextColor)

            Spacer(minLength: 4)

            Text("\(Int(entry.percentage * 100))%")
                .font(layout.captionFont)
                .foregroundStyle(layout.accentColor)
                .standByAccent()
        }
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(layout.separatorColor)
                    .frame(height: 3)

                Capsule()
                    .fill(layout.accentColor)
                    .frame(width: max(3, geo.size.width * entry.percentage), height: 3)
                    .standByAccent()
            }
        }
        .frame(height: 3)
    }

    private var textNavigationBar: some View {
        HStack {
            pageButton(
                intent: PrevPageIntent(),
                label: "Prev",
                systemImage: "chevron.left",
                imageFirst: true
            )

            Spacer()

            Text("Page \(entry.currentPage + 1) of \(entry.totalPages)")
                .font(.system(size: layout.isStandBy ? 15 : 12, weight: .medium, design: .rounded))
                .foregroundStyle(layout.secondaryTextColor)
                .contentTransition(.numericText())

            Spacer()

            pageButton(
                intent: NextPageIntent(),
                label: "Next",
                systemImage: "chevron.right",
                imageFirst: false
            )
        }
    }

    @ViewBuilder
    private var coverColumn: some View {
        VStack(spacing: 8) {
            if let data = entry.coverImageData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(layout.separatorColor)
                    .frame(width: 90, height: 130)
                    .overlay {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(layout.secondaryTextColor)
                    }
            }

            Text(entry.bookTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(layout.secondaryTextColor)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 90)
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(layout.separatorColor)
            .frame(height: 1)
    }

    // MARK: - Page Button

    private func pageButton(
        intent: some AppIntent,
        label: String,
        systemImage: String,
        imageFirst: Bool
    ) -> some View {
        Button(intent: intent) {
            HStack(spacing: 4) {
                if imageFirst {
                    Image(systemName: systemImage)
                        .font(.system(size: layout.isStandBy ? 12 : 10, weight: .bold))
                }

                Text(label)
                    .font(.system(size: layout.isStandBy ? 15 : 13, weight: .semibold))

                if !imageFirst {
                    Image(systemName: systemImage)
                        .font(.system(size: layout.isStandBy ? 12 : 10, weight: .bold))
                }
            }
            .foregroundStyle(layout.accentColor)
            .padding(.horizontal, layout.isStandBy ? 16 : 14)
            .padding(.vertical, layout.isStandBy ? 9 : 7)
            .background(layout.buttonBackgroundColor, in: Capsule())
        }
        .buttonStyle(.plain)
        .standByAccent()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: layout.isStandBy ? 50 : 40))
                .foregroundStyle(layout.accentColor)
                .standByAccent()

            Text("Open Flipside to start reading")
                .font(.system(size: layout.isStandBy ? 18 : 15, weight: .medium))
                .foregroundStyle(layout.secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview("Large – PDF", as: .systemLarge) {
    ReadingWidget()
} timeline: {
    ReadingEntry.placeholder
}

#Preview("Large – Empty", as: .systemLarge) {
    ReadingWidget()
} timeline: {
    ReadingEntry.empty
}
