# Polish, Settings, and Signing Implementation Plan — macOS Wallpaper Reader

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the foundation's `Settings { EmptyView() }` scene with a unified ten-tab `TabView` covering General, Appearance, Ambient, Page mode, Reading, Library, AI, Shortcuts, Privacy & Data, and Advanced; add App Intents for Shortcuts/Spotlight/Siri integration; add energy and accessibility polish; integrate Sparkle 2.x for updates; and commit a notarized-release GitHub Actions workflow.

**Architecture:** A single `SettingsScene` hosts `SettingsRootView`, which renders a `TabView` of ten leaf views. Each leaf is a `Form { ... }.formStyle(.grouped)` view bound to `@AppStorage`-backed preferences or to existing controllers from Plans 1–6 (`AmbientRotationController`, `PageModeController`, `AICache`, `PersistenceController`, `MenuBarController`). App Intents live in `Intents/` and call the same controllers in-process via `@MainActor` shared singletons exposed by `AppDelegate`. Sparkle is wrapped by `UpdateController` and surfaced through `MenuBarController`. CI is a GitHub Actions workflow triggered on `mac-v*` tag push that archives, notarizes, and uploads to GitHub Releases.

**Tech Stack:** Swift 5.10, Xcode 15.3+, macOS 14.4 target, SwiftUI + AppKit, SwiftData, XcodeGen 2.39+, `KeyboardShortcuts` (already a dep), `ZIPFoundation` (added in Plan 2 — verified here), `Sparkle` 2.x (added in this plan), `ServiceManagement` (`SMAppService`), AppIntents framework, GitHub Actions for CI.

---

## File structure

This plan creates and modifies the following files under `book-reader-mac/`. Anything not listed here is owned by Plans 1–6 and is treated as a stable dependency.

```
book-reader-mac/
├── project.yml                                # MODIFY: add Sparkle dep, Info.plist keys
├── Settings/
│   ├── SettingsScene.swift                    # CREATE: hosts SettingsRootView
│   ├── SettingsRootView.swift                 # CREATE: TabView with 10 tabs
│   └── Tabs/
│       ├── GeneralTab.swift                   # CREATE
│       ├── AppearanceTab.swift                # CREATE
│       ├── AmbientTab.swift                   # CREATE
│       ├── PageModeTab.swift                  # CREATE
│       ├── ReadingTab.swift                   # CREATE
│       ├── LibraryTab.swift                   # CREATE
│       ├── AITab.swift                        # MOVE from Plan 4 (or CREATE wrapper)
│       ├── ShortcutsTab.swift                 # CREATE
│       ├── PrivacyDataTab.swift               # CREATE
│       └── AdvancedTab.swift                  # CREATE
├── Intents/
│   ├── BookEntity.swift                       # CREATE: AppEntity + EntityQuery over Book
│   ├── OpenBookIntent.swift                   # CREATE
│   ├── ToggleWallpaperModeIntent.swift        # CREATE
│   ├── NextPageIntent.swift                   # CREATE
│   ├── PreviousPageIntent.swift               # CREATE
│   ├── NextQuoteIntent.swift                  # CREATE
│   ├── PageAdvance.swift                      # CREATE: shared in-process bus
│   └── AppShortcuts.swift                     # CREATE: AppShortcutsProvider
├── Accessibility/
│   └── AccessibilityFlags.swift               # CREATE: @Observable accessibility env
├── Update/
│   ├── UpdateController.swift                 # CREATE: wraps SPUStandardUpdaterController
│   └── appcast.xml                            # CREATE: sample 0.1.0 feed
├── App/
│   ├── AppDelegate.swift                      # MODIFY: register intents, accessibility, update
│   └── InstantBookReaderApp.swift             # MODIFY: replace Settings { EmptyView() }
├── Windows/
│   └── WallpaperWindow.swift                  # MODIFY: occlusion observer
├── MenuBar/
│   └── MenuBarController.swift                # MODIFY: "Check for updates…" item
├── Tests/
│   ├── SettingsTabsTests.swift                # CREATE: scaffolds render
│   ├── IntentsTests.swift                     # CREATE: in-process invocation
│   ├── AccessibilityFlagsTests.swift          # CREATE
│   └── UpdateControllerTests.swift            # CREATE
└── .github/
    └── workflows/
        └── mac-release.yml                    # CREATE: archive + notarize on tag
```

---

## Task 1: Verify dependencies and add Sparkle to project.yml

**Files:**
- Modify: `book-reader-mac/project.yml`

- [ ] **Step 1: Confirm `ZIPFoundation` is already declared (added in Plan 2)**

Run:
```bash
grep -n "ZIPFoundation" /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/project.yml
```

Expected: at least one match under `packages:`. If no match, append `ZIPFoundation:` block as shown in step 2.

- [ ] **Step 2: Add Sparkle (and ZIPFoundation if missing) and Info.plist keys**

Open `book-reader-mac/project.yml` and add the `Sparkle` entry to `packages:` and a `Sparkle` dependency to the `InstantBookReader` target. Add the Sparkle `info.properties` keys. The completed `packages:` block looks like this:

```yaml
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    minVersion: 2.0.0
  ZIPFoundation:
    url: https://github.com/weichsel/ZIPFoundation
    minVersion: 0.9.19
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    minVersion: 2.6.0
```

Add to the `InstantBookReader` target's `dependencies:` list:

```yaml
    dependencies:
      - package: KeyboardShortcuts
      - package: ZIPFoundation
      - package: Sparkle
```

Add these keys inside the target's `info.properties:` mapping (preserve existing keys):

```yaml
        SUFeedURL: https://updates.instantbookreader.app/appcast.xml
        SUPublicEDKey: REPLACE_WITH_EDDSA_PUBLIC_KEY_AFTER_KEYGEN
        SUEnableInstallerLauncherService: true
        NSAppleEventsUsageDescription: "Instant Book Reader uses Apple Events for the Reveal in Finder action."
```

- [ ] **Step 3: Regenerate and build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`. SwiftPM may emit a one-time `Resolving package graph` line.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/project.yml && \
  git commit -m "feat(mac): add Sparkle SwiftPM dep and update Info.plist keys"
```

---

## Task 2: SettingsScene scaffold replacing EmptyView

**Files:**
- Create: `book-reader-mac/Settings/SettingsScene.swift`
- Create: `book-reader-mac/Settings/SettingsRootView.swift`
- Modify: `book-reader-mac/App/InstantBookReaderApp.swift`

- [ ] **Step 1: Create the SettingsRootView shell with ten placeholder tabs**

Write `book-reader-mac/Settings/SettingsRootView.swift`:
```swift
import SwiftUI

/// Hosts the unified ten-tab Settings UI. Each tab is implemented in its
/// own file under Settings/Tabs/ and is rendered as a Form with grouped
/// style. Order matches §10 of the spec.
struct SettingsRootView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            AmbientTab()
                .tabItem { Label("Ambient", systemImage: "sparkles") }
            PageModeTab()
                .tabItem { Label("Page mode", systemImage: "doc.text") }
            ReadingTab()
                .tabItem { Label("Reading", systemImage: "text.book.closed") }
            LibraryTab()
                .tabItem { Label("Library", systemImage: "books.vertical") }
            AITab()
                .tabItem { Label("AI", systemImage: "bolt.fill") }
            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            PrivacyDataTab()
                .tabItem { Label("Privacy & Data", systemImage: "lock.shield") }
            AdvancedTab()
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
```

- [ ] **Step 2: Wrap in a Settings scene**

Write `book-reader-mac/Settings/SettingsScene.swift`:
```swift
import SwiftUI

/// SwiftUI `Settings` scene wrapper. Hosted by `InstantBookReaderApp`.
/// Kept as a separate `Scene`-builder type so AppDelegate's bootstrap
/// is not coupled to view internals.
struct SettingsScene: Scene {
    var body: some Scene {
        Settings {
            SettingsRootView()
        }
    }
}
```

- [ ] **Step 3: Replace `Settings { EmptyView() }` in the App entry point**

Open `book-reader-mac/App/InstantBookReaderApp.swift`. Replace the existing body with:
```swift
import SwiftUI

@main
struct InstantBookReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        SettingsScene()
    }
}
```

- [ ] **Step 4: Update project.yml sources to include Settings + Intents + Accessibility + Update**

Open `book-reader-mac/project.yml` and add to the `InstantBookReader` target's `sources:` array (preserve existing entries):
```yaml
      - path: Settings
      - path: Intents
      - path: Accessibility
      - path: Update
```

- [ ] **Step 5: Build will fail until tabs exist — stub each tab type now**

For every tab type the root view references, write a one-line stub so the project compiles. Write `book-reader-mac/Settings/Tabs/GeneralTab.swift`:
```swift
import SwiftUI
struct GeneralTab: View { var body: some View { Form {}.formStyle(.grouped) } }
```
Write `book-reader-mac/Settings/Tabs/AppearanceTab.swift`:
```swift
import SwiftUI
struct AppearanceTab: View { var body: some View { Form {}.formStyle(.grouped) } }
```
Write `book-reader-mac/Settings/Tabs/AmbientTab.swift`:
```swift
import SwiftUI
struct AmbientTab: View { var body: some View { Form {}.formStyle(.grouped) } }
```
Write `book-reader-mac/Settings/Tabs/PageModeTab.swift`:
```swift
import SwiftUI
struct PageModeTab: View { var body: some View { Form {}.formStyle(.grouped) } }
```
Write `book-reader-mac/Settings/Tabs/ReadingTab.swift`:
```swift
import SwiftUI
struct ReadingTab: View { var body: some View { Form {}.formStyle(.grouped) } }
```
Write `book-reader-mac/Settings/Tabs/LibraryTab.swift`:
```swift
import SwiftUI
struct LibraryTab: View { var body: some View { Form {}.formStyle(.grouped) } }
```
Write `book-reader-mac/Settings/Tabs/ShortcutsTab.swift`:
```swift
import SwiftUI
struct ShortcutsTab: View { var body: some View { Form {}.formStyle(.grouped) } }
```
Write `book-reader-mac/Settings/Tabs/PrivacyDataTab.swift`:
```swift
import SwiftUI
struct PrivacyDataTab: View { var body: some View { Form {}.formStyle(.grouped) } }
```
Write `book-reader-mac/Settings/Tabs/AdvancedTab.swift`:
```swift
import SwiftUI
struct AdvancedTab: View { var body: some View { Form {}.formStyle(.grouped) } }
```

- [ ] **Step 6: AITab handling**

If Plan 4 already placed `AITab.swift` under `book-reader-mac/Settings/Tabs/AITab.swift`, do nothing — the file is reused as-is. Verify:
```bash
test -f /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Settings/Tabs/AITab.swift && echo OK || echo MISSING
```

If `MISSING`, locate the existing `AITab` (it may live at `book-reader-mac/AI/AITab.swift` from Plan 4) and move it:
```bash
mkdir -p /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Settings/Tabs && \
  git mv /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/AI/AITab.swift \
         /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Settings/Tabs/AITab.swift
```

If no `AITab.swift` exists anywhere (Plan 4 hasn't landed yet on this branch), write a minimal stub so the build passes — Plan 4 will replace its contents:
```swift
import SwiftUI
struct AITab: View {
    var body: some View {
        Form {
            Section("AI") {
                Text("AI settings are implemented in Plan 4.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 7: Regenerate, build, confirm**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Settings book-reader-mac/App/InstantBookReaderApp.swift \
          book-reader-mac/project.yml && \
  git commit -m "feat(mac): SettingsRootView TabView scaffold with ten tabs"
```

---

## Task 3: GeneralTab — launch-at-login, summon hotkey, Dock-mode toggle

**Files:**
- Modify: `book-reader-mac/Settings/Tabs/GeneralTab.swift`

- [ ] **Step 1: Replace the stub with the full GeneralTab**

Write `book-reader-mac/Settings/Tabs/GeneralTab.swift`:
```swift
import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

/// General preferences: launch at login, summon hotkey, Dock-mode toggle.
/// Launch-at-login uses SMAppService.mainApp; the macOS user may be asked
/// to approve in System Settings → General → Login Items the first time.
struct GeneralTab: View {
    @AppStorage("dockMode") private var dockMode: Bool = false
    @State private var loginItemStatus: SMAppService.Status = .notRegistered
    @State private var lastError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItemStatus == .enabled },
                    set: { newValue in setLoginItem(enabled: newValue) }
                ))
                if loginItemStatus == .requiresApproval {
                    Text("Approval required — open System Settings → General → Login Items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Hotkey") {
                LabeledContent("Summon Reader") {
                    KeyboardShortcuts.Recorder(for: .toggleReader)
                }
            }

            Section("Dock") {
                Toggle("Show app in Dock", isOn: $dockMode)
                Text("When off, the app runs as a menu-bar agent only. Reading is unaffected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItemStatus = SMAppService.mainApp.status }
        .onChange(of: dockMode) { _, newValue in
            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
        }
    }

    private func setLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemStatus = SMAppService.mainApp.status
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Settings/Tabs/GeneralTab.swift && \
  git commit -m "feat(mac): GeneralTab with login item, hotkey, Dock-mode toggle"
```

---

## Task 4: AppearanceTab — appearance preference + theme preset selector

**Files:**
- Modify: `book-reader-mac/Settings/Tabs/AppearanceTab.swift`

- [ ] **Step 1: Replace the stub**

Write `book-reader-mac/Settings/Tabs/AppearanceTab.swift`:
```swift
import AppKit
import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Follow macOS"
        case .light:  return "Always light"
        case .dark:   return "Always dark"
        }
    }
}

enum ReaderThemePreset: String, CaseIterable, Identifiable {
    case clayLight = "clay-light"
    case clayDark  = "clay-dark"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clayLight: return "Clay Light"
        case .clayDark:  return "Clay Dark"
        }
    }
}

/// macOS-appearance preference + active reader theme preset.
/// Applies NSApp.appearance live when the user changes the dropdown.
struct AppearanceTab: View {
    @AppStorage("appearancePreference") private var appearance: AppearancePreference = .system
    @AppStorage("readerThemePreset") private var themePreset: ReaderThemePreset = .clayDark

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Window appearance", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
            }
            Section("Active reader") {
                Picker("Theme preset", selection: $themePreset) {
                    ForEach(ReaderThemePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                Text("Themes follow the Clay design system from the Chrome extension.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: appearance) { _, newValue in apply(newValue) }
        .onAppear { apply(appearance) }
    }

    private func apply(_ preference: AppearancePreference) {
        switch preference {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Settings/Tabs/AppearanceTab.swift && \
  git commit -m "feat(mac): AppearanceTab with appearance + theme preset"
```

---

## Task 5: AmbientTab — layout, rotation, scrim, content units, Finder fade

**Files:**
- Modify: `book-reader-mac/Settings/Tabs/AmbientTab.swift`

- [ ] **Step 1: Replace the stub**

Write `book-reader-mac/Settings/Tabs/AmbientTab.swift`:
```swift
import SwiftUI

enum AmbientLayout: String, CaseIterable, Identifiable {
    case cornerCard = "corner-card"
    case leftRail   = "left-rail"
    case dockFlank  = "dock-flank"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cornerCard: return "Corner card (default)"
        case .leftRail:   return "Left rail"
        case .dockFlank:  return "Dock flank"
        }
    }
}

enum AmbientCadence: Int, CaseIterable, Identifiable {
    case fast = 45, normal = 90, slow = 300, slowest = 600
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .fast: return "45 seconds"
        case .normal: return "90 seconds (default)"
        case .slow: return "5 minutes"
        case .slowest: return "10 minutes"
        }
    }
}

/// Ambient mode tunables. Bound to @AppStorage; the runtime layer
/// (Plan 5 — AmbientRotationController) reads these via the same keys.
struct AmbientTab: View {
    @AppStorage("ambientLayout") private var layout: AmbientLayout = .cornerCard
    @AppStorage("ambientCadenceSeconds") private var cadence: AmbientCadence = .normal
    @AppStorage("ambientScrimEnabled") private var scrim: Bool = true
    @AppStorage("ambientShowCover") private var showCover: Bool = true
    @AppStorage("ambientShowProgress") private var showProgress: Bool = true
    @AppStorage("ambientShowHighlight") private var showHighlight: Bool = true
    @AppStorage("ambientFinderFade") private var finderFade: Bool = true

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Layout", selection: $layout) {
                    ForEach(AmbientLayout.allCases) { l in Text(l.label).tag(l) }
                }
            }

            Section("Rotation") {
                Picker("Quote cadence", selection: $cadence) {
                    ForEach(AmbientCadence.allCases) { c in Text(c.label).tag(c) }
                }
                Text("Rotation also advances on screen wake, Finder activation, and the menu-bar Next quote command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Toggle("Show scrim behind quote", isOn: $scrim)
                Toggle("Fade when Finder is frontmost", isOn: $finderFade)
            }

            Section("Content units") {
                Toggle("Cover image", isOn: $showCover)
                Toggle("Chapter title + progress", isOn: $showProgress)
                Toggle("Rotating highlight", isOn: $showHighlight)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Settings/Tabs/AmbientTab.swift && \
  git commit -m "feat(mac): AmbientTab with layout, rotation, scrim, units, fade"
```

---

## Task 6: PageModeTab — column width, placement, font override, idle timeout

**Files:**
- Modify: `book-reader-mac/Settings/Tabs/PageModeTab.swift`

- [ ] **Step 1: Replace the stub**

Write `book-reader-mac/Settings/Tabs/PageModeTab.swift`:
```swift
import SwiftUI

enum ColumnPlacement: String, CaseIterable, Identifiable {
    case left, center, right
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FontSizeOverride: String, CaseIterable, Identifiable {
    case none, sixteen, twenty, twentyFour, twentyEight
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None (auto)"
        case .sixteen: return "16 pt"
        case .twenty: return "20 pt"
        case .twentyFour: return "24 pt"
        case .twentyEight: return "28 pt"
        }
    }
    var points: Double? {
        switch self {
        case .none: return nil
        case .sixteen: return 16
        case .twenty: return 20
        case .twentyFour: return 24
        case .twentyEight: return 28
        }
    }
}

/// Page-mode tunables. Bound to @AppStorage; PageModeController (Plan 6)
/// reads these keys.
struct PageModeTab: View {
    @AppStorage("pageModeColumnWidth") private var columnWidth: Double = 720
    @AppStorage("pageModeColumnPlacement") private var placement: ColumnPlacement = .center
    @AppStorage("pageModeFontOverride") private var fontOverride: FontSizeOverride = .none
    @AppStorage("pageModeIdleMinutes") private var idleMinutes: Double = 10

    var body: some View {
        Form {
            Section("Column") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Width")
                        Spacer()
                        Text("\(Int(columnWidth)) pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $columnWidth, in: 480...960, step: 10)
                }
                Picker("Placement", selection: $placement) {
                    ForEach(ColumnPlacement.allCases) { p in Text(p.label).tag(p) }
                }
            }

            Section("Typography") {
                Picker("Font size override", selection: $fontOverride) {
                    ForEach(FontSizeOverride.allCases) { f in Text(f.label).tag(f) }
                }
                Text("Auto picks size based on screen ppi. Override applies a fixed point size everywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Idle behavior") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Crossfade to ambient after")
                        Spacer()
                        Text("\(Int(idleMinutes)) min")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $idleMinutes, in: 5...30, step: 1)
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Settings/Tabs/PageModeTab.swift && \
  git commit -m "feat(mac): PageModeTab with column, font override, idle timeout"
```

---

## Task 7: ReadingTab — line height, justification, hyphenation, font family

**Files:**
- Modify: `book-reader-mac/Settings/Tabs/ReadingTab.swift`

- [ ] **Step 1: Replace the stub**

Write `book-reader-mac/Settings/Tabs/ReadingTab.swift`:
```swift
import SwiftUI

enum ReadingFontFamily: String, CaseIterable, Identifiable {
    case newYork = "new-york"
    case sfPro   = "sf-pro"
    case georgia = "georgia"
    case iowan   = "iowan-old-style"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .newYork: return "New York (default)"
        case .sfPro:   return "SF Pro"
        case .georgia: return "Georgia"
        case .iowan:   return "Iowan Old Style"
        }
    }
}

/// Active-reader typography. Plan 3's reader views read these keys.
struct ReadingTab: View {
    @AppStorage("readingLineHeight") private var lineHeight: Double = 1.5
    @AppStorage("readingJustify") private var justify: Bool = false
    @AppStorage("readingHyphenate") private var hyphenate: Bool = true
    @AppStorage("readingFontFamily") private var fontFamily: ReadingFontFamily = .newYork

    var body: some View {
        Form {
            Section("Typography") {
                Picker("Font family", selection: $fontFamily) {
                    ForEach(ReadingFontFamily.allCases) { f in Text(f.label).tag(f) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Line height")
                        Spacer()
                        Text(String(format: "%.2f", lineHeight))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $lineHeight, in: 1.2...2.0, step: 0.05)
                }
            }
            Section("Layout") {
                Toggle("Justify text", isOn: $justify)
                Toggle("Hyphenation", isOn: $hyphenate)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Settings/Tabs/ReadingTab.swift && \
  git commit -m "feat(mac): ReadingTab typography preferences"
```

---

## Task 8: LibraryTab — storage location, current book, import folder

**Files:**
- Modify: `book-reader-mac/Settings/Tabs/LibraryTab.swift`

- [ ] **Step 1: Replace the stub**

Write `book-reader-mac/Settings/Tabs/LibraryTab.swift`:
```swift
import AppKit
import SwiftData
import SwiftUI

/// Library tab: storage location readout, current book selector,
/// "Import folder…" entry point. Plan 2 owns the import pipeline;
/// this tab calls `BookImporter.importFolder(at:into:)` for recursion.
struct LibraryTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Book.title) private var books: [Book]
    @AppStorage("currentBookHash") private var currentBookHash: String = ""
    @State private var importErrors: [String] = []
    @State private var isImporting: Bool = false

    var body: some View {
        Form {
            Section("Storage") {
                LabeledContent("Location", value: AppSupportPaths.root.path)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppSupportPaths.root])
                }
            }

            Section("Current book") {
                Picker("Currently reading", selection: $currentBookHash) {
                    Text("None").tag("")
                    ForEach(books, id: \.sha256) { book in
                        Text("\(book.title) — \(book.author ?? "Unknown")")
                            .tag(book.sha256)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Import") {
                Button(isImporting ? "Importing…" : "Import folder…") {
                    importFolder()
                }
                .disabled(isImporting)
                if !importErrors.isEmpty {
                    DisclosureGroup("Skipped \(importErrors.count) file(s)") {
                        ForEach(importErrors, id: \.self) { line in
                            Text(line).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func importFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        isImporting = true
        importErrors.removeAll()
        Task { @MainActor in
            defer { isImporting = false }
            do {
                let report = try await BookImporter.importFolder(at: folder, into: modelContext)
                importErrors = report.skipped.map { "\($0.url.lastPathComponent): \($0.reason)" }
            } catch {
                importErrors = ["Folder import failed: \(error.localizedDescription)"]
            }
        }
    }
}
```

Note: this tab relies on `BookImporter.importFolder(at:into:)` and a `BookImportReport` shape with a `skipped: [(url: URL, reason: String)]` field, both delivered by Plan 2. If Plan 2 named them differently, adjust the two call sites in `importFolder()` to match — the rest of the file remains correct.

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. If `BookImporter` is unresolved on a branch where Plan 2 hasn't landed yet, ship the file with the body of `importFolder()` temporarily replaced by `importErrors = ["Plan 2 BookImporter not yet present"]` — but only as a branch-merge convenience.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Settings/Tabs/LibraryTab.swift && \
  git commit -m "feat(mac): LibraryTab with storage, current book, folder import"
```

---

## Task 9: ShortcutsTab — KeyboardShortcuts.Recorder per named shortcut

**Files:**
- Create: `book-reader-mac/Hotkey/HotkeyNames.swift`
- Modify: `book-reader-mac/Settings/Tabs/ShortcutsTab.swift`

- [ ] **Step 1: Centralize all KeyboardShortcuts.Name values**

`GlobalHotkey.swift` (from Plan 1, Task 17) already defines `.toggleReader`. This task adds the other four. Write `book-reader-mac/Hotkey/HotkeyNames.swift`:
```swift
import KeyboardShortcuts

/// Named global hotkeys. `.toggleReader` is defined in `GlobalHotkey.swift`
/// (Plan 1). The others land here so the Shortcuts tab and any later
/// callers can reference them by name.
extension KeyboardShortcuts.Name {
    static let nextQuote = Self("nextQuote")
    static let toggleWallpaperMode = Self("toggleWallpaperMode")
    static let nextPage = Self("nextPage",
                              default: .init(.rightArrow, modifiers: [.control, .option]))
    static let previousPage = Self("previousPage",
                                   default: .init(.leftArrow, modifiers: [.control, .option]))
}
```

- [ ] **Step 2: Replace the stub ShortcutsTab**

Write `book-reader-mac/Settings/Tabs/ShortcutsTab.swift`:
```swift
import KeyboardShortcuts
import SwiftUI

/// All named global shortcuts, one Recorder row each. Defaults are seeded
/// where the spec calls for them; Summon Reader is ⌃⌥B (set in Plan 1),
/// page-turn keys are ⌃⌥← / ⌃⌥→.
struct ShortcutsTab: View {
    var body: some View {
        Form {
            Section("Global shortcuts") {
                LabeledContent("Summon Reader") {
                    KeyboardShortcuts.Recorder(for: .toggleReader)
                }
                LabeledContent("Next Quote") {
                    KeyboardShortcuts.Recorder(for: .nextQuote)
                }
                LabeledContent("Toggle Wallpaper Mode") {
                    KeyboardShortcuts.Recorder(for: .toggleWallpaperMode)
                }
                LabeledContent("Next Page") {
                    KeyboardShortcuts.Recorder(for: .nextPage)
                }
                LabeledContent("Previous Page") {
                    KeyboardShortcuts.Recorder(for: .previousPage)
                }
            }
            Section {
                Text("Shortcuts are global. Recording while another app holds the same combination silently replaces this app's binding only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 3: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Hotkey/HotkeyNames.swift \
          book-reader-mac/Settings/Tabs/ShortcutsTab.swift && \
  git commit -m "feat(mac): ShortcutsTab with five named global hotkeys"
```

---

## Task 10: PrivacyDataTab — clear AI cache, export library, reset positions

**Files:**
- Modify: `book-reader-mac/Settings/Tabs/PrivacyDataTab.swift`

- [ ] **Step 1: Replace the stub**

Write `book-reader-mac/Settings/Tabs/PrivacyDataTab.swift`:
```swift
import AppKit
import SwiftData
import SwiftUI
import ZIPFoundation

/// Destructive-action tab. All three buttons confirm before acting; the
/// reset-positions action uses an alert because the operation is silent
/// and not reversible.
struct PrivacyDataTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var statusMessage: String?
    @State private var showResetAlert: Bool = false

    var body: some View {
        Form {
            Section("AI cache") {
                Button("Clear AI cache") {
                    do {
                        try AICache.evictAll(in: modelContext)
                        statusMessage = "AI cache cleared."
                    } catch {
                        statusMessage = "Failed to clear cache: \(error.localizedDescription)"
                    }
                }
                Text("Removes all locally cached AI responses. Server-side cache is untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Library export") {
                Button("Export library to ZIP…") { exportLibrary() }
                Text("Bundles every imported book file into a single ZIP archive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Positions") {
                Button("Reset all reading positions…", role: .destructive) {
                    showResetAlert = true
                }
            }

            if let statusMessage {
                Section { Text(statusMessage).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .alert("Reset all reading positions?",
               isPresented: $showResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { resetAllPositions() }
        } message: {
            Text("Every book will lose its current position. Highlights and the library are preserved.")
        }
    }

    private func exportLibrary() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "InstantBookReader-Library.zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.zipItem(at: AppSupportPaths.books, to: destination)
            statusMessage = "Exported library to \(destination.lastPathComponent)."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    private func resetAllPositions() {
        do {
            let positions = try modelContext.fetch(FetchDescriptor<Position>())
            for p in positions { modelContext.delete(p) }
            try modelContext.save()
            statusMessage = "Cleared \(positions.count) reading position(s)."
        } catch {
            statusMessage = "Reset failed: \(error.localizedDescription)"
        }
    }
}
```

Note: `AICache.evictAll(in:)` is provided by Plan 4. If Plan 4 named it `AICache.evictAll(context:)` or similar, adjust the single call site to match.

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Settings/Tabs/PrivacyDataTab.swift && \
  git commit -m "feat(mac): PrivacyDataTab with cache clear, export, reset"
```

---

## Task 11: AdvancedTab — Sparkle channel + diagnostics

**Files:**
- Modify: `book-reader-mac/Settings/Tabs/AdvancedTab.swift`

- [ ] **Step 1: Replace the stub**

Write `book-reader-mac/Settings/Tabs/AdvancedTab.swift`:
```swift
import SwiftUI

enum SparkleChannel: String, CaseIterable, Identifiable {
    case stable, beta
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Advanced toggles. `sparkleChannel` is read by UpdateController when
/// constructing the feed URL; `diagnosticsEnabled` opts the user into
/// crash-log uploads (post-v1; the toggle exists but is wired to nothing
/// in v1.0).
struct AdvancedTab: View {
    @AppStorage("sparkleChannel") private var channel: SparkleChannel = .stable
    @AppStorage("diagnosticsEnabled") private var diagnostics: Bool = false

    var body: some View {
        Form {
            Section("Updates") {
                Picker("Update channel", selection: $channel) {
                    ForEach(SparkleChannel.allCases) { c in Text(c.label).tag(c) }
                }
                Text("Beta delivers releases before they go to the Stable channel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Diagnostics") {
                Toggle("Send anonymous diagnostics", isOn: $diagnostics)
                Text("Wired to a no-op in v1.0; reserved for a future crash-reporter integration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Settings/Tabs/AdvancedTab.swift && \
  git commit -m "feat(mac): AdvancedTab with Sparkle channel and diagnostics"
```

---

## Task 12: SettingsTabsTests — smoke render every tab

**Files:**
- Create: `book-reader-mac/Tests/SettingsTabsTests.swift`

- [ ] **Step 1: Write the test**

Write `book-reader-mac/Tests/SettingsTabsTests.swift`:
```swift
import SwiftUI
import XCTest
@testable import InstantBookReader

/// Smoke test: every tab's body resolves without crashing. Catches
/// the "I forgot to add this tab to the project sources" regression.
@MainActor
final class SettingsTabsTests: XCTestCase {
    func testRootViewBodyResolves() {
        _ = SettingsRootView().body
    }
    func testGeneralTabBodyResolves() { _ = GeneralTab().body }
    func testAppearanceTabBodyResolves() { _ = AppearanceTab().body }
    func testAmbientTabBodyResolves() { _ = AmbientTab().body }
    func testPageModeTabBodyResolves() { _ = PageModeTab().body }
    func testReadingTabBodyResolves() { _ = ReadingTab().body }
    func testLibraryTabBodyResolves() {
        let container = try! PersistenceController.makeInMemoryContainer()
        _ = LibraryTab().environment(\.modelContext, ModelContext(container)).body
    }
    func testAITabBodyResolves() { _ = AITab().body }
    func testShortcutsTabBodyResolves() { _ = ShortcutsTab().body }
    func testPrivacyDataTabBodyResolves() {
        let container = try! PersistenceController.makeInMemoryContainer()
        _ = PrivacyDataTab().environment(\.modelContext, ModelContext(container)).body
    }
    func testAdvancedTabBodyResolves() { _ = AdvancedTab().body }
}
```

The `import SwiftData` is implicit through `PersistenceController`; if the test file needs `ModelContext` explicitly, add `import SwiftData` at the top.

- [ ] **Step 2: Run the test**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `Test Suite 'SettingsTabsTests' passed`. If `import SwiftData` is needed, add it and re-run.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/SettingsTabsTests.swift && \
  git commit -m "test(mac): smoke-render every Settings tab"
```

---

## Task 13: PageAdvance shared in-process bus

**Files:**
- Create: `book-reader-mac/Intents/PageAdvance.swift`

- [ ] **Step 1: Implement**

Page-mode windows (Plan 6) and the active reader (Plan 3) both want to react to page-advance events from intents and from the global hotkeys. The simplest in-process bus is an `@Observable` singleton; views observe its `sequence` counter and direction enum.

Write `book-reader-mac/Intents/PageAdvance.swift`:
```swift
import Foundation
import Observation

enum PageDirection: Int, Sendable { case next = 1, previous = -1 }

/// In-process page-advance bus. Intents and global hotkeys post here;
/// the active reader and page-mode windows observe `sequence` to react.
/// Pure singleton, MainActor-confined.
@Observable
@MainActor
final class PageAdvanceBus {
    static let shared = PageAdvanceBus()
    private init() {}

    /// Monotonically increasing on every post — views observe this to fire effects.
    private(set) var sequence: Int = 0
    private(set) var lastDirection: PageDirection = .next

    func post(_ direction: PageDirection) {
        lastDirection = direction
        sequence &+= 1
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Intents/PageAdvance.swift && \
  git commit -m "feat(mac): PageAdvanceBus in-process bus for page intents"
```

---

## Task 14: BookEntity for App Intents

**Files:**
- Create: `book-reader-mac/Intents/BookEntity.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Intents/BookEntity.swift`:
```swift
import AppIntents
import Foundation
import SwiftData

/// App Intents entity wrapping a SwiftData Book.
/// The identifier is the SHA-256 hash (stable across launches).
struct BookEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Book" }
    static var defaultQuery = BookEntityQuery()

    var id: String       // sha256
    var title: String
    var author: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)",
                              subtitle: author.map { "\($0)" })
    }
}

/// EntityQuery: resolve by id and search by prefix.
struct BookEntityQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BookEntity] {
        try await fetch { books in books.filter { identifiers.contains($0.sha256) } }
    }

    func suggestedEntities() async throws -> [BookEntity] {
        try await fetch { $0 }
    }

    func entities(matching string: String) async throws -> [BookEntity] {
        let q = string.lowercased()
        return try await fetch { books in
            books.filter { $0.title.lowercased().contains(q)
                || ($0.author?.lowercased().contains(q) ?? false) }
        }
    }

    @MainActor
    private func fetch(_ transform: ([Book]) -> [Book]) async throws -> [BookEntity] {
        let container = try PersistenceController.makeContainer()
        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.title)]))
        return transform(books).map {
            BookEntity(id: $0.sha256, title: $0.title, author: $0.author)
        }
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Intents/BookEntity.swift && \
  git commit -m "feat(mac): BookEntity + EntityQuery for App Intents"
```

---

## Task 15: Five App Intents (Open / Toggle / Next page / Previous page / Next quote)

**Files:**
- Create: `book-reader-mac/Intents/OpenBookIntent.swift`
- Create: `book-reader-mac/Intents/ToggleWallpaperModeIntent.swift`
- Create: `book-reader-mac/Intents/NextPageIntent.swift`
- Create: `book-reader-mac/Intents/PreviousPageIntent.swift`
- Create: `book-reader-mac/Intents/NextQuoteIntent.swift`

This task expects two MainActor-confined globals that other plans provide:
- `AppDelegate.shared` — set in Task 21 below.
- `AmbientRotationController.shared.advance()` — Plan 5 ships this as a singleton.

If either is named differently when this plan lands, adjust the single call site per intent.

- [ ] **Step 1: Implement OpenBookIntent**

Write `book-reader-mac/Intents/OpenBookIntent.swift`:
```swift
import AppIntents
import Foundation

struct OpenBookIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Book"
    static var description = IntentDescription("Open a book in the Instant Book Reader.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Book")
    var book: BookEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDelegate.shared?.openBook(withHash: book.id)
        return .result()
    }
}
```

- [ ] **Step 2: Implement ToggleWallpaperModeIntent**

Write `book-reader-mac/Intents/ToggleWallpaperModeIntent.swift`:
```swift
import AppIntents

struct ToggleWallpaperModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Wallpaper Mode"
    static var description = IntentDescription("Switch between ambient and page wallpaper modes.")

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let state = AppDelegate.shared?.state else { return .result() }
        state.ambientMode = (state.ambientMode == .atomic) ? .page : .atomic
        return .result()
    }
}
```

- [ ] **Step 3: Implement NextPageIntent and PreviousPageIntent**

Write `book-reader-mac/Intents/NextPageIntent.swift`:
```swift
import AppIntents

struct NextPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Page"
    static var description = IntentDescription("Advance to the next page in the current book.")

    @MainActor
    func perform() async throws -> some IntentResult {
        PageAdvanceBus.shared.post(.next)
        return .result()
    }
}
```

Write `book-reader-mac/Intents/PreviousPageIntent.swift`:
```swift
import AppIntents

struct PreviousPageIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Page"
    static var description = IntentDescription("Go back one page in the current book.")

    @MainActor
    func perform() async throws -> some IntentResult {
        PageAdvanceBus.shared.post(.previous)
        return .result()
    }
}
```

- [ ] **Step 4: Implement NextQuoteIntent**

Write `book-reader-mac/Intents/NextQuoteIntent.swift`:
```swift
import AppIntents

struct NextQuoteIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Quote"
    static var description = IntentDescription("Show the next quote on the wallpaper layer.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AmbientRotationController.shared?.advance()
        return .result()
    }
}
```

If Plan 5 named the singleton accessor differently (e.g. `AmbientRotationController.current`), replace the property access here.

- [ ] **Step 5: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. If `AppDelegate.shared` or `AmbientRotationController.shared` is unresolved, complete Task 21 first, then re-run.

- [ ] **Step 6: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Intents/OpenBookIntent.swift \
          book-reader-mac/Intents/ToggleWallpaperModeIntent.swift \
          book-reader-mac/Intents/NextPageIntent.swift \
          book-reader-mac/Intents/PreviousPageIntent.swift \
          book-reader-mac/Intents/NextQuoteIntent.swift && \
  git commit -m "feat(mac): five App Intents for Shortcuts/Siri integration"
```

---

## Task 16: AppShortcutsProvider registration

**Files:**
- Create: `book-reader-mac/Intents/AppShortcuts.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/Intents/AppShortcuts.swift`:
```swift
import AppIntents

/// Registers all intents so they appear in Shortcuts, Spotlight, and Siri.
/// Phrase strings include "${applicationName}" so the app name resolves
/// from Info.plist at runtime.
struct InstantBookReaderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenBookIntent(),
            phrases: ["Open \(.applicationName) book \(\.$book)"],
            shortTitle: "Open Book",
            systemImageName: "book"
        )
        AppShortcut(
            intent: ToggleWallpaperModeIntent(),
            phrases: ["Toggle \(.applicationName) wallpaper mode"],
            shortTitle: "Toggle Wallpaper Mode",
            systemImageName: "rectangle.on.rectangle"
        )
        AppShortcut(
            intent: NextPageIntent(),
            phrases: ["\(.applicationName) next page"],
            shortTitle: "Next Page",
            systemImageName: "arrow.right"
        )
        AppShortcut(
            intent: PreviousPageIntent(),
            phrases: ["\(.applicationName) previous page"],
            shortTitle: "Previous Page",
            systemImageName: "arrow.left"
        )
        AppShortcut(
            intent: NextQuoteIntent(),
            phrases: ["\(.applicationName) next quote"],
            shortTitle: "Next Quote",
            systemImageName: "quote.bubble"
        )
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Intents/AppShortcuts.swift && \
  git commit -m "feat(mac): AppShortcutsProvider with five intent phrases"
```

---

## Task 17: IntentsTests — invoke each intent and assert the side effect

**Files:**
- Create: `book-reader-mac/Tests/IntentsTests.swift`

- [ ] **Step 1: Write the tests**

Write `book-reader-mac/Tests/IntentsTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

@MainActor
final class IntentsTests: XCTestCase {
    func testNextPageIntentAdvancesBus() async throws {
        let before = PageAdvanceBus.shared.sequence
        _ = try await NextPageIntent().perform()
        XCTAssertEqual(PageAdvanceBus.shared.sequence, before + 1)
        XCTAssertEqual(PageAdvanceBus.shared.lastDirection.rawValue, 1)
    }

    func testPreviousPageIntentAdvancesBus() async throws {
        let before = PageAdvanceBus.shared.sequence
        _ = try await PreviousPageIntent().perform()
        XCTAssertEqual(PageAdvanceBus.shared.sequence, before + 1)
        XCTAssertEqual(PageAdvanceBus.shared.lastDirection.rawValue, -1)
    }

    func testToggleWallpaperModeFlipsState() async throws {
        // ToggleWallpaperModeIntent reads AppDelegate.shared, which is
        // nil in unit tests. The intent must not throw or crash; it should
        // no-op silently. Verifies the guard clause.
        _ = try await ToggleWallpaperModeIntent().perform()
    }

    func testNextQuoteIntentNoOpsWithoutController() async throws {
        // AmbientRotationController.shared is nil in unit tests; intent
        // must not crash. Verifies optional chaining.
        _ = try await NextQuoteIntent().perform()
    }

    func testOpenBookIntentNoOpsWithoutAppDelegate() async throws {
        var intent = OpenBookIntent()
        intent.book = BookEntity(id: "deadbeef", title: "T", author: nil)
        _ = try await intent.perform()
    }
}
```

- [ ] **Step 2: Run the tests**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `Test Suite 'IntentsTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/IntentsTests.swift && \
  git commit -m "test(mac): invoke every App Intent in-process"
```

---

## Task 18: AccessibilityFlags @Observable env

**Files:**
- Create: `book-reader-mac/Accessibility/AccessibilityFlags.swift`
- Create: `book-reader-mac/Tests/AccessibilityFlagsTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/AccessibilityFlagsTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

@MainActor
final class AccessibilityFlagsTests: XCTestCase {
    func testDefaultFlagsMatchWorkspaceState() {
        let flags = AccessibilityFlags()
        // Defaults should mirror NSWorkspace.shared values at init time.
        XCTAssertEqual(flags.reduceMotion, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        XCTAssertEqual(flags.reduceTransparency, NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
        XCTAssertEqual(flags.increaseContrast, NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    }

    func testRefreshUpdatesFromWorkspace() {
        let flags = AccessibilityFlags()
        flags.reduceMotion = !flags.reduceMotion // simulate stale
        flags.refresh()
        XCTAssertEqual(flags.reduceMotion, NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: compile error referencing `AccessibilityFlags`.

- [ ] **Step 3: Implement**

Write `book-reader-mac/Accessibility/AccessibilityFlags.swift`:
```swift
import AppKit
import Observation
import SwiftUI

/// @Observable mirror of NSWorkspace accessibility display options.
/// AppDelegate refreshes on
/// NSWorkspace.accessibilityDisplayOptionsDidChangeNotification.
@Observable
@MainActor
final class AccessibilityFlags {
    var reduceMotion: Bool
    var reduceTransparency: Bool
    var increaseContrast: Bool

    init() {
        self.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        self.reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        self.increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    func refresh() {
        let ws = NSWorkspace.shared
        reduceMotion = ws.accessibilityDisplayShouldReduceMotion
        reduceTransparency = ws.accessibilityDisplayShouldReduceTransparency
        increaseContrast = ws.accessibilityDisplayShouldIncreaseContrast
    }
}

private struct AccessibilityFlagsKey: EnvironmentKey {
    @MainActor static let defaultValue = AccessibilityFlags()
}

extension EnvironmentValues {
    var accessibilityFlags: AccessibilityFlags {
        get { self[AccessibilityFlagsKey.self] }
        set { self[AccessibilityFlagsKey.self] = newValue }
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `Test Suite 'AccessibilityFlagsTests' passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Accessibility/AccessibilityFlags.swift \
          book-reader-mac/Tests/AccessibilityFlagsTests.swift && \
  git commit -m "feat(mac): AccessibilityFlags @Observable env"
```

---

## Task 19: WallpaperWindow occlusion subscription + timer tolerance helper

**Files:**
- Modify: `book-reader-mac/Windows/WallpaperWindow.swift`
- Create: `book-reader-mac/System/TimerTolerance.swift`

- [ ] **Step 1: Extend WallpaperWindow to observe occlusion state**

Open `book-reader-mac/Windows/WallpaperWindow.swift`. Append the following inside the class body (after the existing init), so the file ends with this additional content:

```swift
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
```

- [ ] **Step 2: Create the timer-tolerance helper**

Write `book-reader-mac/System/TimerTolerance.swift`:
```swift
import Foundation

/// Energy discipline helper. Every recurring Timer in the app should
/// pass through `Timer.applyDefaultTolerance(_:)` to allow the system
/// to coalesce wakeups with other timers.
extension Timer {
    /// 10% tolerance per §12.1 of the spec.
    static func applyDefaultTolerance(_ timer: Timer) {
        timer.tolerance = timer.timeInterval * 0.1
    }
}
```

- [ ] **Step 3: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Windows/WallpaperWindow.swift \
          book-reader-mac/System/TimerTolerance.swift && \
  git commit -m "feat(mac): wallpaper occlusion notification + timer tolerance helper"
```

---

## Task 20: UpdateController wrapping Sparkle 2.x

**Files:**
- Create: `book-reader-mac/Update/UpdateController.swift`
- Create: `book-reader-mac/Update/appcast.xml`
- Create: `book-reader-mac/Tests/UpdateControllerTests.swift`

- [ ] **Step 1: Write the failing test**

Write `book-reader-mac/Tests/UpdateControllerTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

@MainActor
final class UpdateControllerTests: XCTestCase {
    func testCanInstantiateController() {
        let controller = UpdateController.shared
        XCTAssertNotNil(controller.updater)
    }

    func testCheckForUpdatesInvokesUpdater() {
        // checkForUpdates is fire-and-forget; just verify it doesn't crash.
        UpdateController.shared.checkForUpdates(nil)
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: compile error referencing `UpdateController`.

- [ ] **Step 3: Implement `UpdateController`**

Write `book-reader-mac/Update/UpdateController.swift`:
```swift
import AppKit
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` as a MainActor singleton.
/// The "Check for updates…" menu item in MenuBarController calls
/// `UpdateController.shared.checkForUpdates(_:)`. The feed URL and
/// EdDSA public key are set in Info.plist (Task 1).
@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateController()

    let updater: SPUUpdater
    private let controller: SPUStandardUpdaterController

    private override init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updater = controller.updater
        super.init()
        controller.updater.delegate = self
    }

    @objc func checkForUpdates(_ sender: Any?) {
        controller.checkForUpdates(sender)
    }

    // MARK: SPUUpdaterDelegate

    /// Override the appcast URL when the user picks the Beta channel.
    func feedURLString(for updater: SPUUpdater) -> String? {
        let channel = UserDefaults.standard.string(forKey: "sparkleChannel") ?? "stable"
        if channel == "beta" {
            return "https://updates.instantbookreader.app/appcast-beta.xml"
        }
        return nil // fall back to Info.plist SUFeedURL
    }
}
```

- [ ] **Step 4: Write the sample appcast**

Write `book-reader-mac/Update/appcast.xml`:
```xml
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/"
     version="2.0">
    <channel>
        <title>Instant Book Reader — Stable</title>
        <link>https://updates.instantbookreader.app/appcast.xml</link>
        <description>Stable releases of Instant Book Reader for macOS.</description>
        <language>en</language>
        <item>
            <title>Version 0.1.0</title>
            <pubDate>Wed, 13 May 2026 00:00:00 +0000</pubDate>
            <sparkle:version>1</sparkle:version>
            <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.4</sparkle:minimumSystemVersion>
            <description><![CDATA[
                <h2>Initial release</h2>
                <p>Ambient wallpaper reader, page mode, active reader, AI lookup.</p>
            ]]></description>
            <enclosure
                url="https://updates.instantbookreader.app/InstantBookReader-0.1.0.zip"
                sparkle:edSignature="REPLACE_WITH_EDDSA_SIGNATURE_AFTER_NOTARIZATION"
                length="0"
                type="application/octet-stream"/>
        </item>
    </channel>
</rss>
```

- [ ] **Step 5: Run the test and confirm it passes**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `Test Suite 'UpdateControllerTests' passed`.

- [ ] **Step 6: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Update/UpdateController.swift \
          book-reader-mac/Update/appcast.xml \
          book-reader-mac/Tests/UpdateControllerTests.swift && \
  git commit -m "feat(mac): UpdateController wrapping Sparkle 2.x"
```

---

## Task 21: MenuBarController "Check for updates…" item + AppDelegate.shared

**Files:**
- Modify: `book-reader-mac/MenuBar/MenuBarController.swift`
- Modify: `book-reader-mac/App/AppDelegate.swift`

- [ ] **Step 1: Add an "onCheckForUpdates" closure to MenuBarController**

Open `book-reader-mac/MenuBar/MenuBarController.swift`. The existing class has four closures (`onToggleReader`, `onToggleAmbientMode`, `onOpenSettings`, `onQuit`). Add a fifth, wire it into the menu, and add an `@objc` handler. The full new file:

```swift
import AppKit

/// Owns the NSStatusItem. Menu items wire to closures supplied by AppDelegate.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let onToggleReader: () -> Void
    private let onToggleAmbientMode: () -> Void
    private let onOpenSettings: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onQuit: () -> Void

    init(onToggleReader: @escaping () -> Void,
         onToggleAmbientMode: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onCheckForUpdates: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onToggleReader = onToggleReader
        self.onToggleAmbientMode = onToggleAmbientMode
        self.onOpenSettings = onOpenSettings
        self.onCheckForUpdates = onCheckForUpdates
        self.onQuit = onQuit
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "book.closed",
                                   accessibilityDescription: "Instant Book Reader")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        menu.addItem(makeItem(title: "Open Reader (⌃⌥B)",
                              action: #selector(toggleReaderClicked),
                              keyEquivalent: ""))
        menu.addItem(makeItem(title: "Toggle Wallpaper Mode",
                              action: #selector(toggleAmbientClicked),
                              keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Settings…",
                              action: #selector(openSettingsClicked),
                              keyEquivalent: ","))
        menu.addItem(makeItem(title: "Check for Updates…",
                              action: #selector(checkForUpdatesClicked),
                              keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit Instant Book Reader",
                              action: #selector(quitClicked),
                              keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func makeItem(title: String, action: Selector, keyEquivalent: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func toggleReaderClicked() { onToggleReader() }
    @objc private func toggleAmbientClicked() { onToggleAmbientMode() }
    @objc private func openSettingsClicked() { onOpenSettings() }
    @objc private func checkForUpdatesClicked() { onCheckForUpdates() }
    @objc private func quitClicked() { onQuit() }
}
```

- [ ] **Step 2: Add `AppDelegate.shared` and a public `openBook(withHash:)` plus expose `state`**

Open `book-reader-mac/App/AppDelegate.swift`. Replace the existing file with this version. It preserves Plan 1's bootstrap, adds the singleton accessor used by intents, exposes the `state` property, wires the new menu-bar update entry, refreshes accessibility flags on workspace notification, and registers the in-environment accessibility object:

```swift
import AppIntents
import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set during `applicationDidFinishLaunching`. Read by App Intents.
    static private(set) weak var shared: AppDelegate?

    private(set) var state: ReadingState!
    private var modelContainer: ModelContainer!
    private var wallpaperCoordinator: WallpaperWindowCoordinator!
    private var readerController: ReaderWindowController!
    private var menuBar: MenuBarController!
    private var hotkey: GlobalHotkey!
    private var systemEvents: SystemEventObserver!
    private(set) var accessibilityFlags: AccessibilityFlags!
    private var accessibilityObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        do {
            try AppSupportPaths.ensureCreated()
            modelContainer = try PersistenceController.makeContainer()
        } catch {
            NSApp.presentError(error)
            NSApp.terminate(nil)
            return
        }

        state = ReadingState()
        accessibilityFlags = AccessibilityFlags()
        let theme: AppTheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .clayDark : .clayLight

        wallpaperCoordinator = WallpaperWindowCoordinator(
            state: state, modelContainer: modelContainer, theme: theme)
        readerController = ReaderWindowController(
            state: state, modelContainer: modelContainer, theme: theme)

        menuBar = MenuBarController(
            onToggleReader: { [weak self] in self?.readerController.toggle() },
            onToggleAmbientMode: { [weak self] in
                guard let self else { return }
                state.ambientMode = state.ambientMode == .atomic ? .page : .atomic
            },
            onOpenSettings: {
                if #available(macOS 14.0, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            },
            onCheckForUpdates: {
                UpdateController.shared.checkForUpdates(nil)
            },
            onQuit: { NSApp.terminate(nil) }
        )

        hotkey = GlobalHotkey(onToggle: { [weak self] in self?.readerController.toggle() })
        hotkey.register()

        systemEvents = SystemEventObserver(
            onWillSleep: { [weak self] in try? self?.modelContainer.mainContext.save() },
            onDidWake: { _ = self },
            onLowPowerModeChange: { _ in }
        )
        systemEvents.start()

        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.accessibilityFlags.refresh() }
        }

        wallpaperCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperCoordinator?.stop()
        systemEvents?.stop()
        if let observer = accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        try? modelContainer?.mainContext.save()
    }

    /// Called by `OpenBookIntent`. Resolves the book by hash, marks it
    /// current, and summons the active reader window.
    func openBook(withHash hash: String) {
        state.currentBookHash = hash
        UserDefaults.standard.set(hash, forKey: "currentBookHash")
        if let book = try? modelContainer.mainContext.fetch(
            FetchDescriptor<Book>(predicate: #Predicate { $0.sha256 == hash })
        ).first {
            book.lastOpenedAt = .now
            try? modelContainer.mainContext.save()
        }
        readerController.show()
    }
}
```

This file references `readerController.show()` (Plan 1 named it `toggle()`; if Plan 1's controller has only `toggle()` and an `isVisible` getter, change `readerController.show()` to: `if !readerController.isVisible { readerController.toggle() }`).

- [ ] **Step 3: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. If `readerController.show()` is unresolved, apply the fallback noted at the end of step 2 and rebuild.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/MenuBar/MenuBarController.swift \
          book-reader-mac/App/AppDelegate.swift && \
  git commit -m "feat(mac): AppDelegate.shared + Check for Updates menu item"
```

---

## Task 22: VoiceOver labels + Dynamic Type hooks on placeholder ambient/reader views

**Files:**
- Modify: `book-reader-mac/Placeholders/PlaceholderAmbientView.swift`
- Modify: `book-reader-mac/Placeholders/PlaceholderReaderView.swift`

These two files are scaffolded in Plan 1 (Task 14). Plans 5 and 3 replace them with real content. This task adds the accessibility hooks that the final views must keep: a single readable region for the ambient layer and a `font(.body)`-derived dynamic-type binding for the reader.

- [ ] **Step 1: Open `PlaceholderAmbientView.swift` and replace the file**

Write `book-reader-mac/Placeholders/PlaceholderAmbientView.swift`:
```swift
import SwiftUI

/// Plan-1 placeholder for the wallpaper layer. Plans 5/6 replace the body.
/// This file pins the *accessibility contract*: ambient layer must expose
/// a single combined readable region with `accessibilityLabel` = quote text
/// + chapter info, per §12.1 of the spec.
struct PlaceholderAmbientView: View {
    let screenName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AMBIENT LAYER · Plan 5 content goes here · \(screenName)")
                .font(.body)
        }
        .padding(24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ambient reading layer on \(screenName). No book selected.")
    }
}
```

- [ ] **Step 2: Open `PlaceholderReaderView.swift` and replace the file**

Write `book-reader-mac/Placeholders/PlaceholderReaderView.swift`:
```swift
import SwiftUI

/// Plan-1 placeholder for the active reader. Plan 3 replaces the body
/// with EPUB/PDF/TXT renderers. This file pins the Dynamic Type contract:
/// reader views must use `.font(.body)` (system styles) so users get
/// system-wide text size respect.
struct PlaceholderReaderView: View {
    @Environment(ReadingState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Active Reader")
                .font(.title)
            Text("Current book hash: \(state.currentBookHash ?? "—")")
                .font(.body)
            Text("Ambient mode: \(state.ambientMode.rawValue)")
                .font(.body)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 3: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. If Plan 1's `PlaceholderAmbientView` had a different initializer signature (no `screenName`), keep the existing signature and apply only the `.accessibilityElement(children: .combine)` + `.accessibilityLabel(...)` modifiers.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Placeholders/PlaceholderAmbientView.swift \
          book-reader-mac/Placeholders/PlaceholderReaderView.swift && \
  git commit -m "feat(mac): accessibility labels + dynamic type on placeholder views"
```

---

## Task 23: notarized-release CI workflow

**Files:**
- Create: `.github/workflows/mac-release.yml`

- [ ] **Step 1: Confirm `.github/workflows/` exists**

Run:
```bash
ls /Users/profitoniumapps/Documents/chromeApps/.github/workflows/ 2>&1 || \
  mkdir -p /Users/profitoniumapps/Documents/chromeApps/.github/workflows
```

- [ ] **Step 2: Write the workflow**

Write `.github/workflows/mac-release.yml`:
```yaml
name: macOS Release (notarize + Sparkle)

on:
  push:
    tags:
      - 'mac-v*'

permissions:
  contents: write

jobs:
  build:
    name: Archive, notarize, release
    runs-on: macos-14
    env:
      APP_NAME: InstantBookReader
      SCHEME: InstantBookReader
      WORKSPACE: book-reader-mac/book-reader-mac.xcodeproj
      ARCHIVE_PATH: build/InstantBookReader.xcarchive
      EXPORT_PATH: build/Export
      BUNDLE_ID: com.profitoniumapps.instantbookreader
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install XcodeGen
        run: brew install xcodegen

      - name: Generate Xcode project
        working-directory: book-reader-mac
        run: xcodegen generate

      - name: Import signing certificate
        uses: apple-actions/import-codesign-certs@v3
        with:
          p12-file-base64: ${{ secrets.APPLE_DEVELOPER_ID_P12 }}
          p12-password: ${{ secrets.APPLE_DEVELOPER_ID_P12_PASSWORD }}

      - name: Build archive
        run: |
          xcodebuild \
            -project "${WORKSPACE}" \
            -scheme "${SCHEME}" \
            -configuration Release \
            -destination 'generic/platform=macOS' \
            -archivePath "${ARCHIVE_PATH}" \
            archive

      - name: Export signed app
        run: |
          mkdir -p "${EXPORT_PATH}"
          cat > exportOptions.plist <<'PLIST'
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
            "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
              <key>method</key>
              <string>developer-id</string>
              <key>signingStyle</key>
              <string>automatic</string>
              <key>teamID</key>
              <string>${{ secrets.TEAM_ID }}</string>
          </dict>
          </plist>
          PLIST
          xcodebuild \
            -exportArchive \
            -archivePath "${ARCHIVE_PATH}" \
            -exportPath "${EXPORT_PATH}" \
            -exportOptionsPlist exportOptions.plist

      - name: Zip for notarization
        run: |
          cd "${EXPORT_PATH}"
          ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip"

      - name: Notarize with notarytool
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_PASSWORD: ${{ secrets.APPLE_PASSWORD }}
          TEAM_ID: ${{ secrets.TEAM_ID }}
        run: |
          xcrun notarytool submit \
            "${EXPORT_PATH}/${APP_NAME}.zip" \
            --apple-id "${APPLE_ID}" \
            --password "${APPLE_PASSWORD}" \
            --team-id "${TEAM_ID}" \
            --wait

      - name: Staple ticket
        run: |
          xcrun stapler staple "${EXPORT_PATH}/${APP_NAME}.app"
          cd "${EXPORT_PATH}"
          rm -f "${APP_NAME}.zip"
          ditto -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip"

      - name: Sign Sparkle update with EdDSA
        env:
          SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}
        run: |
          # The Sparkle SwiftPM checkout includes `sign_update`. Locate it.
          SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData \
            -name 'sign_update' -type f 2>/dev/null | head -1)
          if [ -z "$SIGN_UPDATE" ]; then
            echo "::error::sign_update binary not found in DerivedData"
            exit 1
          fi
          echo "$SPARKLE_ED_PRIVATE_KEY" > /tmp/sparkle.key
          chmod 600 /tmp/sparkle.key
          "$SIGN_UPDATE" -f /tmp/sparkle.key "${EXPORT_PATH}/${APP_NAME}.zip" \
            > "${EXPORT_PATH}/${APP_NAME}.zip.sig"
          rm /tmp/sparkle.key

      - name: Upload to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          files: |
            build/Export/InstantBookReader.zip
            build/Export/InstantBookReader.zip.sig
            book-reader-mac/Update/appcast.xml
          fail_on_unmatched_files: true
```

This workflow requires the following secrets, which a maintainer must provision in repository settings before the first `mac-v*` tag is pushed. The plan does **not** create the secrets:
- `APPLE_ID` — Apple ID email
- `APPLE_PASSWORD` — app-specific password generated at appleid.apple.com
- `TEAM_ID` — Apple Developer team ID (10-character alphanumeric)
- `APPLE_DEVELOPER_ID_P12` — base64-encoded Developer ID Application `.p12` file
- `APPLE_DEVELOPER_ID_P12_PASSWORD` — password for the p12
- `SPARKLE_ED_PRIVATE_KEY` — output of `generate_keys` (see Task 24)

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add .github/workflows/mac-release.yml && \
  git commit -m "ci(mac): notarized release workflow on mac-v* tag"
```

---

## Task 24: Document the EdDSA keygen step (do NOT execute)

**Files:**
- Modify: `book-reader-mac/README.md`

- [ ] **Step 1: Append a release-engineering section to the existing README**

Open `book-reader-mac/README.md`. Append the following block to the end of the file (do not modify existing content):

```markdown

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
```

- [ ] **Step 2: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/README.md && \
  git commit -m "docs(mac): document EdDSA keygen and release workflow"
```

---

## Task 25: End-to-end build, test, smoke-launch

This task has no new code; it validates the polish layer works together.

- [ ] **Step 1: Full test run**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: every test suite from Plans 1–6 plus this plan's new suites passes — `SettingsTabsTests`, `IntentsTests`, `AccessibilityFlagsTests`, `UpdateControllerTests`.

- [ ] **Step 2: Manual smoke checklist**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -configuration Debug \
    -derivedDataPath ./build build 2>&1 | tail -5 && \
  open ./build/Build/Products/Debug/InstantBookReader.app
```

Verify by inspection:
- Menu-bar item now has "Check for Updates…" between Settings… and Quit.
- Clicking "Settings…" opens the unified Settings window with ten tabs in this exact order: General, Appearance, Ambient, Page mode, Reading, Library, AI, Shortcuts, Privacy & Data, Advanced.
- General tab: toggling "Launch at login" prompts approval in System Settings; toggling "Show app in Dock" causes the Dock icon to appear/disappear immediately.
- Appearance tab: switching to "Always dark" instantly recolors the Settings window.
- Shortcuts tab: each Recorder accepts a new combo and clears with the X button.
- Privacy & Data: "Reset all reading positions" shows the confirmation alert and only acts on confirm.
- The Shortcuts app (System app) → Add Action → search "Instant Book Reader" lists all five intents.

If any of the above fails, file the failure as a bug task before tagging. Do not paper over with shrugs.

- [ ] **Step 3: Tag the polish milestone**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git tag -a mac-v0.1.0-polish -m "Polish + Settings + Signing plan complete"
```

---

## Self-review notes

Coverage check against the spec sections this plan is responsible for:

| Spec section | Task |
|---|---|
| §10 General tab — launch at login, hotkey, Dock toggle | Task 3 |
| §10 Appearance tab — appearance follow + theme preset | Task 4 |
| §10 Ambient tab — layout, cadence, scrim, units, fade | Task 5 |
| §10 Page mode tab — width, placement, font override, idle | Task 6 |
| §10 Reading tab — line height, justify, hyphenate, font family | Task 7 |
| §10 Library tab — storage, current book, import folder | Task 8 |
| §10 AI tab — wired into TabView (content owned by Plan 4) | Task 2 |
| §10 Shortcuts tab — all five named recorders | Task 9 |
| §10 Privacy & Data tab — clear AI cache, export, reset | Task 10 |
| §10 Advanced tab — Sparkle channel + diagnostics | Task 11 |
| §12.1 App Intents — five intents + entity + provider | Tasks 13–17 |
| §12.1 Energy: occlusion observer, timer tolerance | Task 19 |
| §12.1 Accessibility flags + label + dynamic type | Tasks 18, 22 |
| §13 Sparkle 2.x integration | Tasks 1, 20, 21, 24 |
| §13 Notarization + CI on tag push | Task 23 |
| §13 EdDSA keygen documented (not executed) | Task 24 |

Type and naming consistency checks:
- `AmbientLayout`, `AmbientCadence`, `ColumnPlacement`, `FontSizeOverride`, `ReadingFontFamily`, `AppearancePreference`, `ReaderThemePreset`, `SparkleChannel` are each defined exactly once (in their tab files) and not redeclared elsewhere in this plan.
- `KeyboardShortcuts.Name.toggleReader` is the name set in Plan 1's `GlobalHotkey.swift`; Task 9 adds `.nextQuote`, `.toggleWallpaperMode`, `.nextPage`, `.previousPage` in `HotkeyNames.swift` so they live in a single namespace with no duplication.
- `PageAdvanceBus.shared.post(_:)` is defined in Task 13 and called by `NextPageIntent` / `PreviousPageIntent` (Task 15) and verified in Task 17.
- `AppDelegate.shared` is set in Task 21 step 2 and read by `OpenBookIntent` and `ToggleWallpaperModeIntent` (Task 15). `state` is exposed as `private(set)` so intents can mutate `ambientMode` directly.
- `UpdateController.shared.checkForUpdates(_:)` matches the call sites in `MenuBarController` (Task 21) and `UpdateControllerTests` (Task 20).
- `AICache.evictAll(in:)` and `BookImporter.importFolder(at:into:)` are external dependencies on Plans 4 and 2; both call sites have a documented adjustment path if the dependency lands with a different signature.

Plan boundaries:
- This plan does not implement AI Tab contents (Plan 4 owns it) or any rotation logic (Plan 5 owns it).
- The CI workflow is committed but never invoked by this plan. The `generate_keys` invocation is documented but not executed.
- The `.github/workflows/mac-release.yml` file lives at the repository root, not under `book-reader-mac/`, because GitHub Actions resolves workflows only from `.github/workflows/` at the repo root.

Task count: 25, within the 25–35 target.
