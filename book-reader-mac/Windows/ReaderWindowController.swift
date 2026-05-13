import AppKit
import SwiftUI
import SwiftData

/// Owns the single ReaderWindow. `toggle()` is bound to the global hotkey.
@MainActor
final class ReaderWindowController {
    private let window: ReaderWindow
    private let state: ReadingState
    private let modelContainer: ModelContainer
    private let theme: AppTheme

    init(state: ReadingState, modelContainer: ModelContainer, theme: AppTheme) {
        self.state = state
        self.modelContainer = modelContainer
        self.theme = theme
        self.window = ReaderWindow()
        let content = ReaderRouter()
            .environment(\.appTheme, theme)
            .environment(state)
            .modelContainer(modelContainer)
        self.window.contentView = NSHostingView(rootView: content)
        self.window.alphaValue = 0
        self.window.orderOut(nil)
    }

    func toggle() {
        if window.isVisible {
            dismiss()
        } else {
            summon()
        }
    }

    func summon() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window.orderOut(nil)
        })
    }
}
