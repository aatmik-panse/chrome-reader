# Instant Book Reader — macOS

macOS-native sibling to the Chrome extension. Renders the user's current
book on the desktop wallpaper layer, with a hotkey-summoned full reader.

## Build

Requires Xcode 15.3+, macOS 14.4+, and XcodeGen.

    brew install xcodegen
    xcodegen generate
    open book-reader-mac.xcodeproj

The Xcode project is generated from `project.yml` and is not checked in.

## Status

v1 in development. See `docs/superpowers/specs/2026-05-13-macos-wallpaper-reader-design.md`
for the spec and `docs/superpowers/plans/2026-05-13-macos-reader-*` for plans.

## Page mode smoke test (Plan 6)

1. Run the app. Switch to page mode (menu bar → "Toggle Wallpaper Mode").
2. Import a PDF, EPUB, and TXT via the library (Plan 2).
3. Open each in the active reader (⌃⌥B) and advance one page so a Position
   row is created.
4. Dismiss the reader. The wallpaper should now render the current page of
   the active book in a centered 720pt column.
5. Press ⌃⌥→ — the page advances. ⌃⌥← steps back.
6. Toggle system dark mode. PDF pages should invert (selection unavailable;
   this is expected). EPUB and TXT inherit the WKWebView / SwiftUI dark
   palette.
7. Resize the column from Settings → Page mode. The reserved right 200pt
   strip must stay clear regardless of placement (left / center / right).
8. Wait 10 minutes idle (or set `pageModeIdleTimeout` to 30 via `defaults
   write <bundle-id> pageModeIdleTimeout -float 30`). The wallpaper should
   crossfade to the ambient cover-card overlay. Move the mouse — page mode
   returns.
9. Connect a second display. Both displays should render the same page.
