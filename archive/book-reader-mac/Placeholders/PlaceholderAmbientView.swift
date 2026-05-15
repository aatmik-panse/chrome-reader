import AppKit
import SwiftData
import SwiftUI

/// Bottom-left ambient placeholder. Plan 5 replaces this with the full
/// corner-card layout (cover + chapter label + rotating highlight). For
/// the library milestone we render the current book's cover at quarter
/// size so the import pipeline is observable end-to-end on the desktop.
struct PlaceholderAmbientView: View {
    @Environment(\.appTheme) private var theme
    @Environment(ReadingState.self) private var state
    let screenName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                Spacer()
                CurrentBookCover(currentHash: state.currentBookHash)
                    .frame(width: 90, height: 130)
                Text("AMBIENT LAYER")
                    .font(.system(size: 13, weight: .medium))
                    .tracking(1.08)
                    .foregroundStyle(theme.ink.swiftUI.opacity(0.92))
                Text(state.currentBookHash == nil
                     ? "No book selected · \(screenName)"
                     : "Plan 5 content goes here · \(screenName)")
                    .font(.system(size: 22, weight: .medium, design: .serif))
                    .foregroundStyle(theme.ink.swiftUI.opacity(0.92))
                    .lineLimit(2)
                    .padding(.bottom, 80)
            }
            .padding(.leading, 56)
            .frame(maxWidth: 360, alignment: .leading)
            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: 1)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        // Plan 7 §12.1 accessibility contract: the ambient layer exposes a
        // single combined readable region so VoiceOver announces it once.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            state.currentBookHash == nil
            ? "Ambient reading layer on \(screenName). No book selected."
            : "Ambient reading layer on \(screenName)."
        )
    }
}

/// Looks up the currently-selected Book and draws its cover, or a flat
/// theme-tinted rectangle if nothing is selected or no cover exists.
private struct CurrentBookCover: View {
    @Environment(\.appTheme) private var theme
    @Query private var matches: [Book]

    init(currentHash: String?) {
        let predicate: Predicate<Book>
        if let hash = currentHash {
            predicate = #Predicate<Book> { $0.sha256 == hash }
        } else {
            predicate = #Predicate<Book> { _ in false }
        }
        _matches = Query(filter: predicate)
    }

    var body: some View {
        if let book = matches.first,
           let relative = book.coverPath,
           let image = NSImage(contentsOfFile: AppSupportPaths.root
                                .appendingPathComponent(relative).path) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .cornerRadius(4)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(theme.border.swiftUI.opacity(0.4))
        }
    }
}
