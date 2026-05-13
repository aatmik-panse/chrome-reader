import AppKit

/// Borderless click-through window pinned to the desktop window level
/// (just above the wallpaper image, just below desktop icons).
/// Modeled on Plash's DesktopWindow.swift.
final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        self.setFrame(screen.frame, display: false)

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

    /// Posted with `userInfo["isVisible": Bool]`. The wallpaper coordinator
    /// or AmbientRotationController subscribes to suspend/resume timers.
    static let occlusionStateChanged = Notification.Name("WallpaperWindow.occlusionStateChanged")

    override var occlusionState: NSWindow.OcclusionState {
        let state = super.occlusionState
        let visible = state.contains(.visible)
        NotificationCenter.default.post(
            name: WallpaperWindow.occlusionStateChanged,
            object: self,
            userInfo: ["isVisible": visible]
        )
        return state
    }
}
