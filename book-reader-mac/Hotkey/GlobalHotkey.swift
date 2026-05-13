import AppKit
import KeyboardShortcuts

/// Global keyboard shortcuts. The defaults are the ones marketed; Settings
/// (Plan 7) exposes a Recorder UI for each.
extension KeyboardShortcuts.Name {
    /// Summon / dismiss the active reader window. Default ⌃⌥B.
    static let toggleReader = Self("toggleReader",
                                   default: .init(.b, modifiers: [.control, .option]))

    /// Advance one page in page mode (spec §6.1). Default ⌃⌥→.
    static let pageModeNext = Self("pageModeNext",
                                   default: .init(.rightArrow, modifiers: [.control, .option]))

    /// Step back one page in page mode (spec §6.1). Default ⌃⌥←.
    static let pageModePrevious = Self("pageModePrevious",
                                       default: .init(.leftArrow, modifiers: [.control, .option]))
}

/// Registers global hotkeys and forwards their key-up callbacks. The owner
/// (AppDelegate in Plan 1, extended by Plan 6) supplies the actions.
@MainActor
final class GlobalHotkey {
    private let onToggleReader: () -> Void
    private let onPageNext: () -> Void
    private let onPagePrevious: () -> Void

    init(onToggleReader: @escaping () -> Void,
         onPageNext: @escaping () -> Void = {},
         onPagePrevious: @escaping () -> Void = {}) {
        self.onToggleReader = onToggleReader
        self.onPageNext = onPageNext
        self.onPagePrevious = onPagePrevious
    }

    /// Backwards-compatible initializer for Plan 1 callers.
    convenience init(onToggle: @escaping () -> Void) {
        self.init(onToggleReader: onToggle, onPageNext: {}, onPagePrevious: {})
    }

    func register() {
        KeyboardShortcuts.onKeyUp(for: .toggleReader) { [weak self] in
            self?.onToggleReader()
        }
        KeyboardShortcuts.onKeyUp(for: .pageModeNext) { [weak self] in
            self?.onPageNext()
        }
        KeyboardShortcuts.onKeyUp(for: .pageModePrevious) { [weak self] in
            self?.onPagePrevious()
        }
    }
}
