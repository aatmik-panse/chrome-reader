import AppKit
import SwiftUI

/// One per NSScreen: the wallpaper window, its hosting view, and the
/// Finder-frontmost fader bound to that window's contentView alpha.
@MainActor
final class AmbientScreenInstance {
    let window: WallpaperWindow
    let fader: FinderFrontmostFader

    init(screen: NSScreen,
         reduceMotion: AmbientReduceMotion,
         rootView: AnyView) {
        let window = WallpaperWindow(screen: screen)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        window.contentView = hostingView
        window.setFrame(screen.frame, display: true)

        // Bind the fader's `apply` closure to the contentView's alpha so
        // the policy module (Task 7) stays free of NSWindow references.
        let fader = FinderFrontmostFader(
            isReducedMotion: { reduceMotion.isEnabled },
            apply: { [weak hostingView] target, duration in
                guard let hostingView else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = duration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    hostingView.animator().alphaValue = target
                }
            }
        )

        self.window = window
        self.fader = fader
    }

    func show() {
        window.orderFront(nil)
        fader.start()
    }

    func hide() {
        fader.stop()
        window.orderOut(nil)
    }

    func relayout(to screen: NSScreen) {
        window.setFrame(screen.frame, display: true)
    }
}
