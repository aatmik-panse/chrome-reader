# Instant Book Reader for macOS — design spec

**Date:** 2026-05-13
**Status:** Approved for implementation planning
**Target:** macOS 14.4+

## 1. Product

A macOS-native sibling to the Chrome extension (`book-reader-extension/`) that renders the user's current book on the desktop wallpaper layer, with two user-toggleable modes, plus a global-hotkey-summoned full reader at normal window level.

**Ambient mode (default).** Atomic, glanceable units on the wallpaper layer: book cover, chapter title + progress, and a single rotating user highlight. Type-only, deferential to user-placed icons, calm.

**Page mode.** The current page itself rendered at ~22pt physical type in a centered 720pt safe column. Advances only when the user advances in the active reader. Framed in marketing as the "kitchen-counter / standing-desk / treadmill Mac" mode, not "read while you work."

**Active reader.** Summoned via global hotkey (default ⌃⌥B). Standard window-level, feature parity with the extension: EPUB/PDF/TXT, highlights, AI lookup, vocab, themes.

State across the wallpaper layer, active reader, and the Chrome extension is unified through the existing `book-reader-api`. Books stay local on each client; only position, highlights, and vocab cross-sync. No backend schema changes for v1.

## 2. Stack

| Concern | Decision |
|---|---|
| Language / UI | Swift + AppKit-hosted SwiftUI. `@NSApplicationDelegateAdaptor` + custom `NSWindow` subclass + `NSHostingView`. Pure SwiftUI cannot express the desktop-level window. |
| Target OS | macOS 14.4+ (SwiftData stability floor) |
| App lifecycle | `LSUIElement = YES` agent app, `NSStatusItem` menu bar, optional Dock-mode toggle via `NSApp.setActivationPolicy(.regular)` |
| EPUB / TXT rendering | WKWebView hosting the extension's React reader, lifted with minimal porting from `book-reader-extension/src/newtab/` |
| PDF rendering | PDFKit native (`PDFView` wrapped via `NSViewRepresentable`) for single, continuous, and spread modes plus thumbnails and outlines |
| Library / persistence | SwiftData. Books stored at `~/Library/Application Support/<bundle-id>/Books/`, keyed by SHA-256 of file bytes (matches the extension's `computeFileHash` in `lib/storage.ts`). |
| Cover extraction | EPUB via ZIPFoundation + OPF parse; PDF via `PDFPage.thumbnail`; TXT via rendered first-paragraph PNG. Cached as small PNGs in App Support. |
| AI clients | Hand-rolled REST per provider behind shared `AIProvider` protocol (mirrors extension's `AiClient` in `lib/ai/types.ts`). Providers: OpenAI, Anthropic, Google, OpenRouter. |
| AI streaming | `URLSession.bytes(for:)` + `AsyncSequence` SSE parser. ~30 LOC parser shared across providers. |
| BYOK storage | Keychain (`SecItemAdd` / `SecItemCopyMatching`). `kSecAttrService = <bundle-id>`, one entry per provider keyed by `kSecAttrAccount`. `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` by default. iCloud Keychain sync opt-in via `kSecAttrSynchronizable`. |
| Server fallback | Existing `/ai/*` endpoints called with `Bearer <jwt>`. Add SSE-streaming variants (`/ai/summarize/stream`, etc.) using Hono's `streamSSE`. |
| Hotkey | `KeyboardShortcuts` (sindresorhus) — Carbon-backed, no Accessibility prompt |
| Sandbox | Non-sandboxed v1 (direct distribution). MAS-compatible sandboxing tracked as a separate hardening pass post-v1. |
| Distribution | Direct download + Sparkle 2.x with EdDSA signing. Notarized via `notarytool` in CI. |
| Update mechanism | Sparkle 2.x feed served from the marketing site |

## 3. Window architecture

### 3.1 Wallpaper windows (one per `NSScreen`)

```
level              = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
isOpaque           = false
backgroundColor    = .clear
hasShadow          = false
ignoresMouseEvents = true
isExcludedFromWindowsMenu = true
```

Windows are keyed by `NSScreen.localizedName` + `displayID` (not array index — index reshuffles on hotplug). The wallpaper coordinator subscribes to `NSApplication.didChangeScreenParametersNotification`, `NSWorkspace.didWakeNotification`, and `CGDisplayRegisterReconfigurationCallback` to add/remove windows. On wake, it validates `NSScreen.screens.contains(window.screen)`; orphan windows are torn down.

### 3.2 Active reader window

Standard `.normal` level, hidden by default, summoned via global hotkey. Transition order from hidden → visible:

1. `collectionBehavior = [.fullScreenPrimary, .managed]`
2. `level = .normal`
3. `makeKeyAndOrderFront(nil)`
4. `NSApp.activate(ignoringOtherApps: true)`
5. Animate contentView alpha 0.85 → 1.0 over 150ms (masks the WindowServer ordering pop)

Dismiss: escape, click outside (via `NSEvent.addLocalMonitorForEvents(.leftMouseDown)` on `resignKey`), or hotkey re-press. Animate alpha 1.0 → 0 over 150ms, then `orderOut(nil)`.

## 4. State and sync

```
App
├── ModelContainer (SwiftData, shared)
├── @Observable ReadingState
│    ├── currentBookHash: String?     // @AppStorage-backed
│    ├── currentPosition: Position?
│    ├── theme: ThemeID
│    └── ambientMode: .atomic | .page
├── actor SyncCoordinator
│    ├── pull(): GET /position, /highlights, /vocabulary → merge SwiftData
│    └── push(): drain pending mutations → PUT /position, /highlights, /vocabulary
├── actor SyncScheduler
│    ├── Task loop with adaptive Task.sleep
│    └── Subscribes to: didBecomeActive, willSleep, didWake,
│                       NWPathMonitor, isLowPowerModeEnabled
└── WindowGroups (ambient × N + reader)
     read .environment(readingState) and @Query for SwiftData
```

**Sync cadence:**

| Condition | Pull interval |
|---|---|
| Active reader visible | 15s |
| Ambient only, foreground | 60s |
| Background (no active window) | 5min |
| `isLowPowerModeEnabled` | Suspend periodic loop; rely on event hooks only |

Push is debounced 2s on any position change. `NSApplication.didBecomeActiveNotification` triggers an immediate pull. `NSWorkspace.willSleepNotification` flushes pending mutations synchronously.

**Conflict resolution.** Books-style:

- Position: last-write-wins on `updatedAt` if local is newer. If remote is newer by >3% of book length AND within the last hour, show a non-modal toast in the active reader: "Jump to page N" / "Stay here."
- Highlights / vocab: set-union merge by stable client UUID (the API already does this).

**Cross-device push (SSE).** Deferred to v1.1. The 15s active-reader cadence + `didBecomeActive` immediate pull covers the "feels instant when I tab over to the Mac" case.

## 5. Ambient mode

### 5.1 Content units (priority order)

1. Cover image — anchor element
2. Chapter title + progress, combined as "Ch. 7 · 43%"
3. Rotating highlight from the user's own library — never AI-generated. If the user has no highlights for the current book, the highlight slot stays empty and the card shows cover + progress only.

Cut: AI-extracted passages, raw page numbers, "next-up" cues, time-since-last-read under 24h. Vocab cards are deferred to v1.1.

### 5.2 Layout: corner-anchored card

Single ~360pt-wide card pinned to the bottom-left of each screen. The bottom-left quadrant is statistically icon-free on user desktops (Finder arranges from top-right).

Card composition (top to bottom):
- 60×80 cover thumbnail (left), aligned with first text line
- "Ch. 7 · 43%" — DM Sans 500, uppercase, 1.08px tracking, 13pt (Clay `.clay-label`)
- Current highlight (or empty) — New York Medium, 28pt, leading 1.4, max 280 chars, 4 lines max
- Book title + author — DM Sans 500, uppercase, 1.08px tracking, 11pt

A user setting offers two alternate layouts (left rail, dock flank) but corner-card is the default.

### 5.3 Rotation logic

| Trigger | Behavior |
|---|---|
| Slow timer (default 90s, min 45s, max 10min — user setting) | Advance to next highlight in shuffle |
| Screen wake (`NSWorkspace.screensDidWakeNotification`) | Advance immediately |
| Finder becomes frontmost | Advance after 800ms (only if cursor not in safe zone) |
| Cursor enters safe zone on a screen | Pause that screen's rotation; resume 5s after exit |
| Menu-bar "Next quote" command | Advance immediately, all screens |

**Multi-monitor:** independent shuffles per screen, shared highlight pool. Same current book on every screen for v1.

### 5.4 Icon mitigation

Three layered defenses:

1. **Position** in the icon-free bottom-left only. Resolves 80% of conflicts.
2. **`NSVisualEffectView` plate** (`.behindWindow` material, ~0.3 alpha) sized to the text-block bounding box only. Preserves cover legibility, kills text-vs-icon-label collisions.
3. **Frontmost-app fade.** When Finder is frontmost, fade entire layer to 15% opacity over 400ms. Restore on Finder resign. Observed via `NSWorkspace.didActivateApplicationNotification`.

## 6. Page mode

### 6.1 Advance model

**Static only.** The page changes when the user advances in the active reader, or via a global `⌃⌥→` / `⌃⌥←` hotkey. No auto-timer.

### 6.2 Typography

Target ~22pt physical body type (0.22"–0.25" cap height). Compute via `NSScreen.deviceDescription[.size]` for ppi and scale base point size logarithmically (13" base × log curve up to 27"+). Line length capped at 66 characters regardless of canvas width — on a 5K, most of the screen is intentionally empty.

### 6.3 Safe column

Centered 720pt-wide column, with user preset for left / center / right placement. Right-side ~200pt always reserved for desktop icons.

### 6.4 PDF page mode

- `PDFView` with `displayMode = .singlePage`, `autoScales = true`, `backgroundColor = .clear`
- **Light mode:** live `PDFView`, text selection works when window becomes key
- **Dark mode:** render `PDFPage.thumbnail(of:for:)` through `CIColorInvert` + `CIColorControls` (hue rotate to preserve diagrams roughly). Selection unavailable. Documented as an accepted limitation.

### 6.5 EPUB page mode

Do not use epub.js pagination. Lift `book-reader-extension/src/newtab/lib/parsers/epub.ts` chapter-flattening and `.prose-reader` HTML rendering. Inject CSS that:

- Constrains content to the safe column width
- Sets `column-width: none` (no automatic pagination)
- Applies physical-size body type from §6.2

The WKWebView is sized to the safe column, not the screen. The wallpaper background paints around it. Manual height measurement determines page breaks.

### 6.6 Idle behavior

After 10min of no input (via `CGEventSource.secondsSinceLastEventType`), crossfade (400ms) from page mode to ambient mode's cover + quote display. Resume page on mouse-move with a 400ms crossfade back.

## 7. Active reader

Hotkey-summoned `.normal`-level window. Feature parity targets with the extension:

| Feature | Approach |
|---|---|
| EPUB | WKWebView hosting the existing React reader. Bundle the built `dist/` from the extension into the app's resources. Bridge `chrome.storage` / `chrome.identity` / `chrome.alarms` via `WKScriptMessageHandler`. |
| PDF | `NSViewRepresentable<PDFView>`. Single, continuous, two-up, two-up continuous modes via PDFKit's built-in display modes. `PDFThumbnailView` for the strip. `PDFDocument.outlineRoot` for TOC. |
| TXT | SwiftUI `ScrollView` with chunked `Text` views, virtualized. |
| Highlights | Existing content-addressed anchor scheme (surrounding text + offset) ports unchanged. PDF anchors via `PDFSelection` + `characterBounds(at:)`. EPUB/TXT anchors via the WKWebView DOM. |
| Selection toolbar | `NSPopover` anchored to the selection rect. PDFKit: `selection.bounds(for: page)` converted via `pdfView.convert(_:from:)`. WKWebView: JS bridge posting `getBoundingClientRect()` adjusted for scroll. |
| AI lookup | Calls the `AIProvider` for the user's chosen provider+model, streaming response into the popover. Falls back to server endpoints if no BYOK key. |
| Theme system | Ports Clay tokens (`book-reader-extension/themes.css`, `lib/themes/`) into a `Theme` environment value. WKWebView reader inherits CSS variables; PDF reader maps tokens to SwiftUI styles. |
| Vocab cards | Same Leitner stages, same `/vocabulary` endpoints. Native SwiftUI card review UI. |
| Reading position | Per-format anchor (EPUB CFI / chapter+offset, PDF page+offset, TXT char offset). Stored in SwiftData and synced to API. |

## 8. AI

### 8.1 Provider interface

```swift
protocol AIProvider {
    var id: ProviderID { get }
    var defaultModel: String { get }
    var availableModels: [String] { get }
    func stream(_ request: AIRequest) -> AsyncThrowingStream<AIChunk, Error>
    func test() async throws  // 1-token request used by Settings "Test" button
}
```

Implementations: `OpenAIProvider`, `AnthropicProvider`, `GoogleProvider`, `OpenRouterProvider` (`OpenAIProvider` with different base URL + headers).

### 8.2 Routing

Mirror `book-reader-extension/src/newtab/lib/ai/router.ts`: per-feature provider preference (summarize → user's choice → server fallback). Falls back to server-side `/ai/*` endpoints when no BYOK key exists for the selected provider.

### 8.3 Cache

Local SwiftData table keyed by `(provider, model, sha256(prompt), bookHash)` → response text + timestamp. Mirrors the extension's IndexedDB cache schema field-for-field. 200 MB cap, LRU eviction. Server-side cache is unchanged.

### 8.4 Selection actions

Mirrors extension: Explain, Summarize, Ask, Translate, Highlights-from-selection. Each maps to one `AIRequest` shape. Streamed responses render into the popover with a copy / save-as-note / re-prompt action row.

## 9. Library and import

### 9.1 Book sources

- In-app library window with "Add books" button (`NSOpenPanel`, UTI filter for `org.idpf.epub-container`, `com.adobe.pdf`, `public.plain-text`)
- Drag-and-drop onto the library window
- Drag-and-drop onto the menu-bar icon (custom `NSStatusItem.button` subclass implementing `NSDraggingDestination`)
- "Open With → Instant Book Reader" from Finder, via `CFBundleDocumentTypes` in Info.plist registering the three UTIs

Folder watching is out of scope for v1.

### 9.2 Storage

Book bytes copied into `~/Library/Application Support/<bundle-id>/Books/<sha256>.<ext>` on import. The library window offers a "Reveal in Finder" action; "Library location" is an advanced preference (default = App Support).

### 9.3 Schema (SwiftData)

```swift
@Model class Book {
    @Attribute(.unique) var sha256: String
    var title: String
    var author: String?
    var format: BookFormat       // .epub / .pdf / .txt
    var coverPath: String?       // relative to App Support
    var filePath: String         // relative to App Support
    var addedAt: Date
    var lastOpenedAt: Date?
    @Relationship(deleteRule: .cascade) var position: Position?
    @Relationship(deleteRule: .cascade) var highlights: [Highlight]
}

@Model class Position {
    var bookHash: String
    var anchor: String           // CFI for EPUB, page+offset for PDF, charOffset for TXT
    var percentage: Double
    var chapterTitle: String?
    var updatedAt: Date
}

@Model class Highlight {
    @Attribute(.unique) var clientID: UUID
    var bookHash: String
    var text: String
    var surroundingText: String  // anchor scheme
    var offset: Int
    var color: String?
    var note: String?
    var createdAt: Date
    var updatedAt: Date
}

@Model class VocabEntry {
    @Attribute(.unique) var clientID: UUID
    var word: String
    var definition: String?
    var bookHash: String?
    var leitnerStage: Int        // 0..4
    var lastReviewedAt: Date?
    var nextReviewAt: Date?
    var createdAt: Date
    var updatedAt: Date
}

@Model class AICacheEntry {
    var key: String              // sha256("provider|model|prompt|bookHash")
    var response: String
    var createdAt: Date
    var sizeBytes: Int
}
```

### 9.4 Current-book selection

`@AppStorage("currentBookHash")` holds the SHA-256 of the active book. Updated when the user opens a book in the reader. Ambient layers observe via `@Environment`. On launch with no value set, falls back to the most recent `Book.lastOpenedAt`.

## 10. Settings

A single `Settings { TabView { … } }` scene. Each tab is a `Form` with `.formStyle(.grouped)`.

| Tab | Contents |
|---|---|
| General | Launch at login (`SMAppService.mainApp.register()`), summon hotkey, Dock-mode toggle |
| Appearance | macOS-appearance follow / light / dark; theme preset selector for active reader |
| Ambient | Layout (corner card / left rail / dock flank); rotation cadence (45s / 90s / 5min / 10min); scrim on/off; content units toggle; Finder-frontmost fade on/off |
| Page mode | Column width, column placement (L / C / R), font size override, idle-to-ambient timeout |
| Reading | Line height, justification, hyphenation, font family (mirrors extension) |
| Library | Storage location, current book selector, import folder action |
| Sync | Google sign-in via `ASWebAuthenticationSession` against Google's OAuth 2.0 endpoints. The Mac app registers a separate Google OAuth client ID (the extension's `chrome-extension://` client ID cannot be reused); the API accepts ID tokens issued to either client ID. Cadence override, force-pull, force-push. |
| AI | Per-provider BYOK field + "Test" button; per-feature model selection; server-fallback toggle; cache size cap with current usage readout |
| Shortcuts | Page-turn keys, next/previous quote, summon reader, toggle wallpaper mode |
| Privacy & Data | Clear AI cache, export library to ZIP, reset all positions |
| Advanced | Sparkle channel (stable / beta), enable diagnostics |

## 11. Visual language

### 11.1 Ambient layer

- Type-only on the wallpaper. No fill, no border. Resolves the Clay-vs-wallpaper tension by being chrome-less.
- **Quote face:** New York (Apple's system serif). Medium for short quotes (≤120 chars) at 44–52pt with 1.25 leading; Regular for longer (120–280 chars) at 28–32pt with 1.45 leading. Hard cap 280 chars; longer truncates with a "Read more" affordance that opens the active reader.
- **Attribution face:** Clay `.clay-label` verbatim — DM Sans 500, uppercase, 1.08px tracking, 13pt.
- **Ink:** `#f0ede8` (Clay dark-bg text) at 92% opacity in dark appearance; `#1a1815` (Clay dark-bg) in light appearance. Single color, no gradients.
- **Type shadow:** `0 1px 2px rgba(0,0,0,0.35)` in dark appearance; inverted (`rgba(255,255,255,0.4)`) in light. Documented exception to Clay's "no blur shadow" rule — applies to chrome, not to type-on-wallpaper.
- **Optional scrim:** 240pt-tall radial gradient behind the quote block, `rgba(20,18,15,0.0) → rgba(20,18,15,0.28)`. User-toggleable.
- **Placement:** optical center at 42% from top of card (not 50%); content left-aligned.

### 11.2 Active reader

Uses the existing Clay design system as-is. WKWebView reader inherits via existing CSS variables. SwiftUI PDF reader exposes a `Theme` environment value mapping Clay tokens to SwiftUI styles. Active-reader theme presets are user-selectable (mirrors extension).

### 11.3 Hover-summoned controls

When the user invokes an ambient control (next quote, save quote, open book), a Clay card appears: 24px radius, `1px solid #3a362f` (dark-theme oat) border, Clay hard-offset shadow `-4px 4px`. Interaction-summoned only — never ambient. Dismisses on click-outside or 3s timeout.

### 11.4 Motion

- Quote transitions: **crossfade only.** 800ms ease-out outgoing, 1200ms ease-in incoming, ~400ms overlap.
- Ambient → active reader: 150ms alpha fade on contentView.
- `prefers-reduced-motion` (observed via `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`): 100ms opacity blink replaces all crossfades; window-level transitions become instant.

### 11.5 Appearance

Respects `NSApp.effectiveAppearance` (KVO-observed). User override: Auto / Always dark ink / Always light ink. No time-of-day theming, no wallpaper-luminance sampling.

## 12. Platform integrations

### 12.1 v1 must-haves

- **Energy discipline.** Subscribe to `NSWindow.didChangeOcclusionStateNotification`; suspend animations and timers when occluded. Coalesce `Timer`s with `.tolerance = interval * 0.1`. Render static text to a `CALayer` and avoid redraws unless the page changes. Suspend periodic sync loop when `ProcessInfo.processInfo.isLowPowerModeEnabled` is true.
- **Accessibility.** Ambient layer exposes a single readable region with `accessibilityLabel` = current quote text. Respect Reduce Motion, Reduce Transparency, Increase Contrast (observed via `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`). Honor Dynamic Type via `NSFont.preferredFont(forTextStyle:)` in the active reader.
- **External display handling.** Observe `NSApplication.didChangeScreenParametersNotification`; key wallpaper windows by `NSScreen` UUID; validate screens-still-exist on wake.
- **App Intents.** `OpenBookIntent` (with `BookEntity` query), `ToggleWallpaperModeIntent`, `NextPageIntent`, `PreviousPageIntent`, `NextQuoteIntent`. Surfaces in Shortcuts, Spotlight, Siri.
- **Stage Manager.** Active reader window uses `[.fullScreenPrimary, .managed]`; wallpaper windows use `.stationary` to opt out. Both paths tested.

### 12.2 Deferred (v1.1 or later)

- Focus Filters (`INFocusFilterIntent` — "Reading Focus enables wallpaper mode")
- WidgetKit complement (cover + streak widget)
- Live Activities — no native Mac API
- Handoff — defer until an iOS peer exists
- Mac App Store distribution (requires sandboxing pass)

## 13. Build, sign, ship

- Single Xcode project at `book-reader-mac/`. SPM dependencies: `KeyboardShortcuts`, `ZIPFoundation`, `Sparkle`.
- The Chrome extension's built `dist/` is embedded as a resource (`WebReader.bundle/`) and loaded into the active reader's WKWebView. Build script copies from `book-reader-extension/dist/` after `npm run build` in that subproject.
- CI: GitHub Actions runs `xcodebuild archive` + `notarytool submit --wait` on tag push. Sparkle appcast generated and uploaded to S3/R2.
- Signing: Developer ID Application cert. EdDSA private key for Sparkle stored as a CI secret.

## 14. Out of scope for v1

- Real-time sync push (SSE/WebSocket from server)
- Book blob storage server-side (users re-import on each device; hash matches)
- Folder watch / Hazel-style auto-import
- iOS / iPadOS apps
- Mac App Store distribution
- WidgetKit widget
- Focus Filters
- Vocab cards in ambient mode (cover + chapter + highlight only for v1)
- Page-mode auto-advance (static only)
- Time-of-day or wallpaper-luminance theming

## 15. Open product decisions (do not block planning)

These are not architectural risks; they're product calls the user can make any time before launch:

1. Whether to launch ambient-only and add page mode in v1.1 to cut scope. Current spec keeps both in v1.
2. Whether to add a "currently reading shelf" (multi-book rotation in ambient layer) post-v1.
3. Whether to ship a complimentary WidgetKit widget at v1.0 or v1.1.

## 16. Repository layout

A new top-level directory `book-reader-mac/` containing the Xcode project. The two existing subprojects (`book-reader-extension/`, `book-reader-api/`) are unchanged in v1 except for:

- `book-reader-api`: add `/ai/*/stream` SSE-streaming variants
- `book-reader-extension`: a build hook that publishes `dist/` to a location the Mac app's Xcode project can consume as a resource bundle. Could be a sibling `dist-shared/` checked into git or built on demand by the Mac project's pre-build script.
