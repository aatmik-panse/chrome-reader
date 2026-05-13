import AppKit
import KeyboardShortcuts

/// Registers the global hotkey for summoning the reader. Default ⌃⌥B.
/// Settings (Plan 7) exposes a Recorder; this file holds only the name +
/// registration glue.
extension KeyboardShortcuts.Name {
    static let toggleReader = Self("toggleReader",
                                   default: .init(.b, modifiers: [.control, .option]))
}

@MainActor
final class GlobalHotkey {
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
    }

    func register() {
        KeyboardShortcuts.onKeyUp(for: .toggleReader) { [weak self] in
            self?.onToggle()
        }
    }
}
