import SwiftUI

struct PlaceholderReaderView: View {
    @Environment(\.appTheme) private var theme
    @Environment(ReadingState.self) private var state

    var body: some View {
        VStack(spacing: 16) {
            Text("Active Reader")
                .font(.system(size: 32, weight: .medium, design: .serif))
                .foregroundStyle(theme.ink.swiftUI)
            Text("Current book hash: \(state.currentBookHash ?? "none")")
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.ink.swiftUI.opacity(0.7))
            Text("Ambient mode: \(state.ambientMode.rawValue)")
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundStyle(theme.ink.swiftUI.opacity(0.7))
            Text("Plan 3 replaces this with the EPUB/PDF/TXT reader.")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(theme.ink.swiftUI.opacity(0.5))
                .padding(.top, 24)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface.swiftUI)
    }
}
