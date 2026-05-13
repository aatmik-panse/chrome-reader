import KeyboardShortcuts

/// Named global hotkeys. `.toggleReader`, `.pageModeNext`, and
/// `.pageModePrevious` are defined in `GlobalHotkey.swift` (Plan 1).
/// The Shortcuts tab adds aliases (`.nextPage`, `.previousPage`) for
/// the page-mode shortcuts and introduces two new ones (`.nextQuote`,
/// `.toggleWallpaperMode`) so all five user-facing shortcuts live in
/// a single namespace.
extension KeyboardShortcuts.Name {
    static let nextQuote = Self("nextQuote")
    static let toggleWallpaperMode = Self("toggleWallpaperMode")
    static let nextPage = Self("nextPage",
                              default: .init(.rightArrow, modifiers: [.control, .option]))
    static let previousPage = Self("previousPage",
                                   default: .init(.leftArrow, modifiers: [.control, .option]))
}
