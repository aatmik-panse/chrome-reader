import AppKit
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

    func dismiss() {
        popover.close()
        hostingController = nil
    }
}
