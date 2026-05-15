import SwiftUI

/// SwiftUI content for the selection popover. v1 buttons:
///   Highlight — saves a Highlight via the supplied closure.
///   Copy — copies the selected text to the pasteboard.
///   Explain — disabled stub; Plan 4 wires the AI call.
struct SelectionToolbarView: View {
    let selectedText: String
    let onHighlight: () -> Void
    let onCopy: () -> Void
    let onExplain: () -> Void
    let aiConfigured: Bool

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 0) {
            button("Highlight", systemImage: "highlighter", action: onHighlight)
            divider
            button("Copy", systemImage: "doc.on.doc", action: onCopy)
            divider
            VStack(spacing: 2) {
                button("Explain", systemImage: "sparkles", action: onExplain, enabled: aiConfigured)
                if !aiConfigured {
                    Text("Add an AI key in Settings")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.ink.swiftUI.opacity(0.55))
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(theme.surface.swiftUI)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(theme.border.swiftUI, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.border.swiftUI.opacity(0.6))
            .frame(width: 1, height: 20)
            .padding(.horizontal, 4)
    }

    private func button(_ title: String,
                        systemImage: String,
                        action: @escaping () -> Void,
                        enabled: Bool = true) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(theme.ink.swiftUI.opacity(enabled ? 1.0 : 0.4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
