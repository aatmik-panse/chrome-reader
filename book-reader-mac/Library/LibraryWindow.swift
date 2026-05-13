import AppKit

/// Standard `.normal` level window for the library grid. Sized 1000×680
/// with a title bar so the user can move/close it.
final class LibraryWindow: NSWindow {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                   backing: .buffered,
                   defer: false)
        self.title = "Library"
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.fullScreenPrimary, .managed]
        self.setFrameAutosaveName("InstantBookReader.Library")
        self.center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
