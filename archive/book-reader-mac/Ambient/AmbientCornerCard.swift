import SwiftUI

/// The visible ambient corner card. Composition (top → bottom):
///   1. 60×80 cover thumbnail
///   2. "Ch. 7 · 43%" chapter+progress label
///   3. Rotating highlight (or empty)
///   4. Title + author footer
/// A NSVisualEffectView plate sits behind the text block only — never behind
/// the cover. The card pins to the bottom-left of its container.
struct AmbientCornerCard: View {
    let book: Book?
    let highlight: Highlight?
    let chapterTitle: String?
    let progressPercent: Int?

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: AmbientLayoutMetrics.coverToTextGap) {
            AmbientCoverImage(coverPath: book?.coverPath)

            VStack(alignment: .leading, spacing: AmbientLayoutMetrics.blockSpacing) {
                chapterProgressLabel
                quoteText
                titleAuthorFooter
            }
            .background(
                VisualEffectPlate()
                    .opacity(0.3)
                    .padding(EdgeInsets(
                        top: -AmbientLayoutMetrics.plateInsets.top,
                        leading: -AmbientLayoutMetrics.plateInsets.left,
                        bottom: -AmbientLayoutMetrics.plateInsets.bottom,
                        trailing: -AmbientLayoutMetrics.plateInsets.right
                    ))
                    .allowsHitTesting(false)
            )
        }
        .frame(width: AmbientLayoutMetrics.cardWidth, alignment: .topLeading)
        .padding(EdgeInsets(
            top: AmbientLayoutMetrics.screenPadding.top,
            leading: AmbientLayoutMetrics.screenPadding.left,
            bottom: AmbientLayoutMetrics.screenPadding.bottom,
            trailing: AmbientLayoutMetrics.screenPadding.right
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Subviews

    @ViewBuilder private var chapterProgressLabel: some View {
        Text(chapterProgressString)
            .font(.system(size: AmbientLayoutMetrics.labelFontSize, weight: .medium))
            .tracking(AmbientLayoutMetrics.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(theme.ink.swiftUI.opacity(0.92))
            .shadow(color: textShadowColor, radius: 0, x: 0, y: 1)
    }

    @ViewBuilder private var quoteText: some View {
        if let highlight {
            let truncated = AmbientLayoutMetrics.truncateForDisplay(highlight.text)
            let fontSize = AmbientLayoutMetrics.quoteFontSize(for: truncated.text)
            let leading = AmbientLayoutMetrics.quoteLeadingMultiple(for: truncated.text)
            VStack(alignment: .leading, spacing: 6) {
                Text(truncated.text)
                    .font(.system(size: fontSize, weight: .medium, design: .serif))
                    .lineSpacing(fontSize * (leading - 1.0))
                    .foregroundStyle(theme.ink.swiftUI.opacity(0.92))
                    .shadow(color: textShadowColor, radius: 0, x: 0, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                if truncated.wasTruncated {
                    Text("Read more…")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(AmbientLayoutMetrics.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.ink.swiftUI.opacity(0.65))
                }
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder private var titleAuthorFooter: some View {
        if let book {
            Text(titleAuthorString(for: book))
                .font(.system(size: AmbientLayoutMetrics.footerFontSize, weight: .medium))
                .tracking(AmbientLayoutMetrics.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(theme.ink.swiftUI.opacity(AmbientLayoutMetrics.footerOpacity))
                .shadow(color: textShadowColor, radius: 0, x: 0, y: 1)
        }
    }

    // MARK: - Helpers

    private var chapterProgressString: String {
        switch (chapterTitle, progressPercent) {
        case let (title?, pct?): return "\(title) · \(pct)%"
        case let (title?, nil):  return title
        case let (nil, pct?):    return "\(pct)%"
        case (nil, nil):         return ""
        }
    }

    private func titleAuthorString(for book: Book) -> String {
        if let author = book.author, !author.isEmpty {
            return "\(book.title) · \(author)"
        }
        return book.title
    }

    /// Spec §11.1: shadow `0 1px 2px rgba(0,0,0,0.35)` in dark, inverted in light.
    private var textShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.35)
            : Color.white.opacity(0.4)
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if let book { parts.append(book.title) }
        if let chapterTitle { parts.append(chapterTitle) }
        if let pct = progressPercent { parts.append("\(pct) percent") }
        if let highlight { parts.append(highlight.text) }
        return parts.joined(separator: ", ")
    }
}

/// NSVisualEffectView bridged into SwiftUI as the plate behind the text block.
struct VisualEffectPlate: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
