import AppKit
import UniformTypeIdentifiers

/// Drop-target overlay added on top of an NSStatusBarButton. Forwards mouse
/// events to the underlying button so menu activation still works, but
/// captures file-URL drag-and-drop and dispatches it to a closure.
final class StatusItemDropTarget: NSView {
    private let onDrop: ([URL]) -> Void

    init(frame: NSRect, onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // Let menu clicks pass through.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        urls(in: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let dropped = urls(in: sender)
        guard !dropped.isEmpty else { return false }
        onDrop(dropped)
        return true
    }

    private func urls(in info: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: BookFileExtension.supportedContentTypes.map(\.identifier)
        ]
        return (info.draggingPasteboard
                    .readObjects(forClasses: [NSURL.self], options: options)
                as? [URL]) ?? []
    }
}

extension NSStatusItem {
    /// Attaches a file-URL drop overlay to this status item's button.
    @MainActor
    func installDropTarget(onDrop: @escaping ([URL]) -> Void) {
        guard let button = self.button else { return }
        let overlay = StatusItemDropTarget(frame: button.bounds, onDrop: onDrop)
        overlay.autoresizingMask = [.width, .height]
        button.addSubview(overlay)
    }
}
