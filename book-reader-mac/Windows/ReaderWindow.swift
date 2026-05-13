import AppKit

/// Standard `.normal` level window, hidden on launch, summoned by hotkey.
/// Sized 1100×800 by default and remembered via autosaveName.
final class ReaderWindow: NSWindow {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 800),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)

        self.title = "Instant Book Reader"
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isOpaque = true
        self.backgroundColor = .windowBackgroundColor
        self.hasShadow = true
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.fullScreenPrimary, .managed]
        self.setFrameAutosaveName("InstantBookReader.Reader")
        self.center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
