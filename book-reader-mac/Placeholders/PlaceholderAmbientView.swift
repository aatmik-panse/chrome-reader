import SwiftUI

/// Stand-in for the ambient layer's content. Plan 5 replaces this with
/// the corner card. Sized to bottom-left so we can verify layout against
/// real screens during foundation work.
struct PlaceholderAmbientView: View {
    @Environment(\.appTheme) private var theme
    let screenName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                Text("AMBIENT LAYER")
                    .font(.system(size: 13, weight: .medium, design: .default))
                    .tracking(1.08)
                    .foregroundStyle(theme.ink.swiftUI.opacity(0.92))
                Text("Plan 5 content goes here · \(screenName)")
                    .font(.system(size: 28, weight: .medium, design: .serif))
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
    }
}
