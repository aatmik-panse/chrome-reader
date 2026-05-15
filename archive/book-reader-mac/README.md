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

## Release engineering

### Generate the Sparkle EdDSA keypair (one-time, on the dev machine)

Run this exactly once on a trusted developer machine. The plan does **not**
run this command — operator action is required.

    swift run -c release --package-path \
      ~/Library/Developer/Xcode/DerivedData/<derived>/SourcePackages/checkouts/Sparkle \
      generate_keys

A simpler alternative on a fresh checkout:

    git clone --depth 1 https://github.com/sparkle-project/Sparkle /tmp/sparkle
    cd /tmp/sparkle && ./bin/generate_keys

`generate_keys` prints the public key (paste it into `project.yml` under
`SUPublicEDKey` and regenerate the project) and stores the private key in
the macOS Keychain. Export the private key with:

    ./bin/generate_keys -x sparkle.key

Upload `sparkle.key` as the `SPARKLE_ED_PRIVATE_KEY` GitHub Actions secret,
then delete the local copy. Never commit it.

### Required GitHub Actions secrets

- `APPLE_ID`
- `APPLE_PASSWORD` (app-specific)
- `TEAM_ID`
- `APPLE_DEVELOPER_ID_P12`
- `APPLE_DEVELOPER_ID_P12_PASSWORD`
- `SPARKLE_ED_PRIVATE_KEY`

### Cutting a release

    git tag mac-v0.1.0
    git push origin mac-v0.1.0

The `mac-release.yml` workflow archives, notarizes, signs for Sparkle, and
uploads to a GitHub Release.
