import AppKit
import SwiftUI

/// Loads a `Book.coverPath`-relative PNG from Application Support and renders
/// it at the spec's 60×80 size. Falls back to a Clay-tinted placeholder when
/// the cover file is absent or unreadable.
struct AmbientCoverImage: View {
    /// Relative path stored on `Book.coverPath`, e.g. "Covers/<sha256>.png".
    let coverPath: String?
    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.border.swiftUI.opacity(0.6))
            }
        }
        .frame(width: AmbientLayoutMetrics.coverSize.width,
               height: AmbientLayoutMetrics.coverSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
    }

    private func loadImage() -> NSImage? {
        guard let coverPath, !coverPath.isEmpty else { return nil }
        // `coverPath` is stored as a path relative to AppSupportPaths.root
        // (e.g. "Covers/<sha>.png"), matching BookImporter's behaviour.
        let url = AppSupportPaths.root.appendingPathComponent(coverPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }
}
