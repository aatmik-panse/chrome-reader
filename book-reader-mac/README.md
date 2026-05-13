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
