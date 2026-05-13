import AppKit

/// Borderless click-through window pinned to the desktop window level
/// (just above the wallpaper image, just below desktop icons).
/// Modeled on Plash's DesktopWindow.swift.
final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false,
                   screen: screen)

        self.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1
        )
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenNone
        ]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.isExcludedFromWindowsMenu = true
        self.isReleasedWhenClosed = false
        self.canHide = false
        self.animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
