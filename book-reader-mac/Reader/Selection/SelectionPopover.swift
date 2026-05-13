import AppKit
import SwiftData
import SwiftUI

/// AppKit popover host for the selection toolbar. The owner positions the
/// popover via `show(over:rect:)` using rects expressed in the supplied
/// `positioningView`'s coordinate space.
@MainActor
final class SelectionPopover {
    private let popover: NSPopover
    private var hostingController: NSHostingController<AnyView>?
    private let theme: AppTheme

    init(theme: AppTheme) {
        self.theme = theme
        self.popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
    }

    func show(over view: NSView,
              rect: CGRect,
              selectedText: String,
              aiConfigured: Bool,
              onHighlight: @escaping () -> Void,
              onCopy: @escaping () -> Void,
              onExplain: @escaping () -> Void) {
        let content = SelectionToolbarView(
            selectedText: selectedText,
            onHighlight: { [weak self] in
                onHighlight()
                self?.dismiss()
            },
            onCopy: { [weak self] in
                onCopy()
                self?.dismiss()
            },
            onExplain: onExplain,
            aiConfigured: aiConfigured
        ).environment(\.appTheme, theme)

        let controller = NSHostingController(rootView: AnyView(content))
        controller.sizingOptions = [.intrinsicContentSize]
        hostingController = controller
        popover.contentViewController = controller

        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    }

    /// Plan 4 streaming variant: shows the toolbar plus a live AI output area
    /// driven by `SelectionAIController`. The popover stays open while the
    /// stream runs and exposes a Save-as-note button when finished.
    func showStreaming(over view: NSView,
                       rect: CGRect,
                       selectedText: String,
                       surroundingContext: String,
                       bookHash: String,
                       container: ModelContainer,
                       onHighlight: @escaping () -> Void,
                       onCopy: @escaping () -> Void,
                       onSaveNote: @escaping (String) -> Void) {
        let controller = SelectionAIController(container: container,
                                               bookHash: { bookHash })
        let content = SelectionStreamingView(
            selectedText: selectedText,
            surroundingContext: surroundingContext,
            controller: controller,
            onHighlight: { [weak self] in
                onHighlight()
                self?.dismiss()
            },
            onCopy: { [weak self] in
                onCopy()
                self?.dismiss()
            },
            onSaveNote: { [weak self] note in
                onSaveNote(note)
                self?.dismiss()
            }
        ).environment(\.appTheme, theme)

        let hosting = NSHostingController(rootView: AnyView(content))
        hosting.sizingOptions = [.intrinsicContentSize]
        hostingController = hosting
        popover.contentViewController = hosting
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
    }

    func dismiss() {
        popover.close()
        hostingController = nil
    }
}

/// Plan 4 streaming popover content. Drives a SelectionAIController and
/// renders the output text live.
private struct SelectionStreamingView: View {
    let selectedText: String
    let surroundingContext: String
    @State var controller: SelectionAIController
    let onHighlight: () -> Void
    let onCopy: () -> Void
    let onSaveNote: (String) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Highlight", action: onHighlight)
                Button("Copy", action: onCopy)
                Button("Explain") {
                    controller.run(feature: .explain,
                                   selection: selectedText,
                                   context: surroundingContext)
                }
                Button("Summarize") {
                    controller.run(feature: .summarize,
                                   selection: selectedText,
                                   chapterText: surroundingContext)
                }
                Button("Translate") {
                    controller.run(feature: .translate,
                                   selection: selectedText)
                }
            }
            outputArea
        }
        .padding(12)
        .frame(minWidth: 360, maxWidth: 480)
        .background(theme.surface.swiftUI)
    }

    @ViewBuilder
    private var outputArea: some View {
        switch controller.state {
        case .idle:
            EmptyView()
        case .streaming, .finished:
            ScrollView {
                Text(controller.outputText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(maxHeight: 240)
            HStack {
                Spacer()
                if controller.state == .finished {
                    Button("Save as note") {
                        onSaveNote(controller.outputText)
                    }
                }
            }
        case .needsKey(let provider):
            AddKeyAffordance(provider: provider)
        case .error(let msg):
            Text(msg).foregroundStyle(.red).font(.caption)
        }
    }
}

struct AddKeyAffordance: View {
    let provider: ProviderID
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add an API key in Settings → AI")
                .font(.body)
            Text("Provider: \(provider.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            SettingsLink {
                Text("Open Settings…")
            }
        }
        .padding(8)
    }
}
