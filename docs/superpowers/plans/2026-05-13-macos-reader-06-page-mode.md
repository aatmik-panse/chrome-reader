# Page Mode Implementation Plan — macOS Wallpaper Reader

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the "page" branch of the wallpaper layer (spec §6). When `ReadingState.ambientMode == .page`, each wallpaper window renders the current book's current page itself — PDF via PDFKit, EPUB via the WKWebView bridge, TXT via native SwiftUI — at a physically calibrated ~22pt body size inside a centered 720pt safe column. Advance is static-only: the user advances in the active reader, or presses a new global hotkey pair (`⌃⌥→` / `⌃⌥←`). After 10 minutes idle the layer crossfades to an ambient cover+quote card; mouse-move crossfades back.

**Architecture:** All new files live under `book-reader-mac/PageMode/`. A `PageModeRouter` SwiftUI view chooses PDF / EPUB / TXT based on `Book.format`. `PhysicalTypeMetrics` and `SafeColumn` are pure value-type helpers reused by every renderer. PDF reuses the Plan 3 `PDFView` representable directly; EPUB reuses the Plan 3 WKWebView reader bridge and adds a CSS-injection layer plus a screen-height pagination measurer. The page mode coexists with atomic mode inside the existing `WallpaperWindowCoordinator` — `ReadingState.ambientMode` is the switch. Two new `KeyboardShortcuts.Name` values write Position updates into SwiftData; views observe via `@Query`. Idle is detected via `CGEventSource.secondsSinceLastEventType` polled on a 10s `Timer`; a `CGEventTap` watches mouse-move to wake. Both are injectable behind a protocol so tests run without real input events.

**Tech Stack:** Swift 5.10, SwiftUI + AppKit, PDFKit, WebKit, CoreImage (CIColorInvert, CIColorControls), CoreGraphics (CGEventSource, CGEventTap), SwiftData, KeyboardShortcuts (sindresorhus), XCTest.

---

## Assumptions about prior plans

This plan assumes Plans 2, 3, and 5 have already landed:

- **Plan 2 (library + import)** has shipped `Book` import + `Book.filePath` resolution under `AppSupportPaths.books`, plus a `BookImporter` helper this plan does not call.
- **Plan 3 (active reader bridge)** has shipped:
  - `book-reader-mac/Reader/PDFKitReaderView.swift` — a `struct PDFKitReaderView: NSViewRepresentable` exposing an internal `static func makePDFView(url: URL) -> PDFView` factory. We reuse `makePDFView` so PDFView configuration stays in one place.
  - `book-reader-mac/Reader/WebReaderView.swift` — a `struct WebReaderView: NSViewRepresentable` over `WKWebView` with an `init(book: Book, injectedCSS: String?, onReady: ((WKWebView) -> Void)?)` initializer. We pass `injectedCSS` and capture the underlying `WKWebView` via `onReady` so we can call `evaluateJavaScript` for pagination.
  - `book-reader-mac/Reader/HighlightAnchor.swift` — not used by this plan, but tests must compile against it.
- **Plan 5 (atomic mode)** has shipped `AtomicAmbientView` and modified `WallpaperWindowCoordinator.reconcile()` so each window's hosted content is now:

  ```swift
  Group {
      switch state.ambientMode {
      case .atomic: AtomicAmbientView(screen: screen)
      case .page:   EmptyView() // populated by Plan 6
      }
  }
  ```

  This plan replaces the `.page` branch with `PageModeRouter(screen: screen)`.

If any of those interfaces differ at execution time, the executing agent must reconcile before writing files (do not silently rename — pause and ask).

---

## File structure

```
book-reader-mac/
└── PageMode/
    ├── PhysicalTypeMetrics.swift        # ppi + log curve → recommended body pt
    ├── SafeColumn.swift                  # centered/left/right 720pt CGRect helper
    ├── PageModeRouter.swift              # routes Book.format → PDF/EPUB/TXT view
    ├── PageModePDFView.swift             # PDFKit live (light) or CIFilter (dark)
    ├── PageModeEPUBView.swift            # WKWebView + injected CSS + paginator
    ├── PageModeTXTView.swift             # SwiftUI Text inside SafeColumn
    ├── PageModeAdvance.swift             # SwiftData Position mutation helpers
    ├── IdleWatcher.swift                 # CGEvent idle detection + crossfade
    └── Resources/
        └── epub-pagination.js            # JS injected for EPUB measurement

book-reader-mac/Hotkey/
    └── GlobalHotkey.swift                # extend with pageNext / pagePrev

book-reader-mac/Tests/PageMode/
    ├── PhysicalTypeMetricsTests.swift
    ├── SafeColumnTests.swift
    ├── PageModeEPUBCSSTests.swift
    ├── PageModeEPUBPaginationTests.swift
    ├── PDFDarkModeTests.swift
    ├── IdleWatcherTests.swift
    └── Fixtures/
        ├── sample.pdf                    # 1-page fixture
        ├── sample.epub                   # 3-chapter fixture
        └── pdf-dark-reference.png        # checked-in inverted reference
```

`book-reader-mac/project.yml` adds the `PageMode/` and `Tests/PageMode/` directories to the existing `InstantBookReader` and `InstantBookReaderTests` targets. Fixtures are included via the `resources` clause of the test target.

---

## Task 1: Add `PageMode/` directories to the Xcode project

**Files:**
- Modify: `book-reader-mac/project.yml`

- [ ] **Step 1: Inspect current project.yml structure**

Run:
```bash
grep -n "sources\|InstantBookReader\|InstantBookReaderTests" /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/project.yml
```
Expected: lists existing source roots. Note the indentation style so the edit below matches.

- [ ] **Step 2: Add `PageMode/` to the app target and `Tests/PageMode/` to the test target**

Edit `book-reader-mac/project.yml`. Inside the `InstantBookReader` target's `sources:` list (the list that already contains `App`, `Core`, `Persistence`, `Windows`, `MenuBar`, `Hotkey`, `System`, `Placeholders`, `Resources` per Plan 1), add a new entry:

```yaml
      - path: PageMode
        type: group
```

Inside the `InstantBookReaderTests` target's `sources:` list, add:

```yaml
      - path: Tests/PageMode
        type: group
```

Also under `InstantBookReaderTests`, add a `resources` clause referencing the fixtures directory:

```yaml
    resources:
      - path: Tests/PageMode/Fixtures
        buildPhase: resources
```

- [ ] **Step 3: Create the new directories**

Run:
```bash
mkdir -p /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/PageMode/Resources \
         /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/PageMode/Fixtures
```

- [ ] **Step 4: Regenerate the Xcode project and verify it still builds**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/project.yml \
          book-reader-mac/PageMode \
          book-reader-mac/Tests/PageMode && \
  git commit -m "build(mac): add PageMode source group and test resources"
```

---

## Task 2: `PhysicalTypeMetrics` — tests first

**Files:**
- Create: `book-reader-mac/Tests/PageMode/PhysicalTypeMetricsTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/PageMode/PhysicalTypeMetricsTests.swift`:

```swift
import XCTest
import AppKit
@testable import InstantBookReader

final class PhysicalTypeMetricsTests: XCTestCase {

    /// A stub that mimics `NSScreen` for metric calculation. We can't
    /// instantiate NSScreen ourselves, so PhysicalTypeMetrics is fed a
    /// `ScreenMetricsInput` value instead of a screen reference.
    private func input(
        widthPx: CGFloat,
        heightPx: CGFloat,
        widthMM: CGFloat,
        heightMM: CGFloat
    ) -> ScreenMetricsInput {
        ScreenMetricsInput(
            pixelSize: CGSize(width: widthPx, height: heightPx),
            physicalSizeMillimeters: CGSize(width: widthMM, height: heightMM)
        )
    }

    func testPointsPerInchFor13InchMBP() {
        // 13" MBP retina: 2560x1600 px, 286.1x178.8 mm → 227 ppi physical,
        // logical 1440x900 pt at 2x scale. We compute physical ppi (px/in).
        let metrics = PhysicalTypeMetrics(input: input(
            widthPx: 2560, heightPx: 1600,
            widthMM: 286.1, heightMM: 178.8
        ))
        XCTAssertEqual(metrics.pixelsPerInch, 227, accuracy: 2)
    }

    func testRecommendedBodyPointSizeFor13InchMBP() {
        let metrics = PhysicalTypeMetrics(input: input(
            widthPx: 2560, heightPx: 1600,
            widthMM: 286.1, heightMM: 178.8
        ))
        // 13" is the base; spec says ~22pt.
        XCTAssertEqual(metrics.recommendedBodyPointSize, 22, accuracy: 0.5)
    }

    func testRecommendedBodyPointSizeFor14InchMBP() {
        // 14" MBP: 3024x1964 px, 302.2x196.3 mm.
        let metrics = PhysicalTypeMetrics(input: input(
            widthPx: 3024, heightPx: 1964,
            widthMM: 302.2, heightMM: 196.3
        ))
        XCTAssertGreaterThanOrEqual(metrics.recommendedBodyPointSize, 22)
        XCTAssertLessThanOrEqual(metrics.recommendedBodyPointSize, 24)
    }

    func testRecommendedBodyPointSizeFor27InchStudioDisplay() {
        // 27" Studio Display: 5120x2880 px, 596x335 mm. 218 ppi.
        let metrics = PhysicalTypeMetrics(input: input(
            widthPx: 5120, heightPx: 2880,
            widthMM: 596, heightMM: 335
        ))
        // Spec: 27" capped at ~30pt.
        XCTAssertEqual(metrics.recommendedBodyPointSize, 30, accuracy: 1.0)
    }

    func testRecommendedBodyPointSizeFor32InchProDisplayXDR() {
        // 32" Pro Display XDR: 6016x3384 px, 698x393 mm.
        let metrics = PhysicalTypeMetrics(input: input(
            widthPx: 6016, heightPx: 3384,
            widthMM: 698, heightMM: 393
        ))
        // Logarithmic curve: 32" should be barely above 27" cap, not linear.
        XCTAssertLessThanOrEqual(metrics.recommendedBodyPointSize, 32)
        XCTAssertGreaterThanOrEqual(metrics.recommendedBodyPointSize, 30)
    }

    func testCapHeightTargetIsBetween22And25Hundredths() {
        // For every fixture, the cap-height-in-inches should fall in the
        // 0.22"–0.25" target band described in spec §6.2.
        let inputs = [
            input(widthPx: 2560, heightPx: 1600, widthMM: 286.1, heightMM: 178.8),
            input(widthPx: 3024, heightPx: 1964, widthMM: 302.2, heightMM: 196.3),
            input(widthPx: 5120, heightPx: 2880, widthMM: 596, heightMM: 335),
            input(widthPx: 6016, heightPx: 3384, widthMM: 698, heightMM: 393)
        ]
        for inp in inputs {
            let metrics = PhysicalTypeMetrics(input: inp)
            let capInches = metrics.estimatedCapHeightInches
            XCTAssertGreaterThanOrEqual(capInches, 0.21,
                "cap height \(capInches) below band for \(inp)")
            XCTAssertLessThanOrEqual(capInches, 0.27,
                "cap height \(capInches) above band for \(inp)")
        }
    }

    func testCurveIsLogarithmicNotLinear() {
        // The 27" point size should be much closer to the 13" size than a
        // linear scale would predict. 13"→22pt linear-to-27"→2x diagonal
        // would give 44pt. We expect ~30pt — well under half of that.
        let mbp13 = PhysicalTypeMetrics(input: input(
            widthPx: 2560, heightPx: 1600, widthMM: 286.1, heightMM: 178.8))
        let studio27 = PhysicalTypeMetrics(input: input(
            widthPx: 5120, heightPx: 2880, widthMM: 596, heightMM: 335))
        let ratio = studio27.recommendedBodyPointSize / mbp13.recommendedBodyPointSize
        XCTAssertLessThan(ratio, 1.6)
        XCTAssertGreaterThan(ratio, 1.2)
    }
}
```

- [ ] **Step 2: Run tests, confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: compile errors referencing `PhysicalTypeMetrics`, `ScreenMetricsInput`.

- [ ] **Step 3: Commit the failing tests**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/PageMode/PhysicalTypeMetricsTests.swift && \
  git commit -m "test(mac/page): failing tests for PhysicalTypeMetrics"
```

---

## Task 3: `PhysicalTypeMetrics` — implementation

**Files:**
- Create: `book-reader-mac/PageMode/PhysicalTypeMetrics.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/PageMode/PhysicalTypeMetrics.swift`:

```swift
import Foundation
import AppKit

/// Stripped-down screen metric input. Decoupling from `NSScreen` lets us
/// unit-test the curve with synthetic values — `NSScreen` cannot be
/// instantiated directly.
public struct ScreenMetricsInput: Equatable, Sendable {
    /// Pixel size, e.g. 2560x1600 for a 13" MBP retina panel.
    public let pixelSize: CGSize
    /// Physical panel size in millimeters, e.g. 286.1x178.8 mm for 13" MBP.
    public let physicalSizeMillimeters: CGSize

    public init(pixelSize: CGSize, physicalSizeMillimeters: CGSize) {
        self.pixelSize = pixelSize
        self.physicalSizeMillimeters = physicalSizeMillimeters
    }
}

/// Computes physical-size body type recommendations for page mode.
///
/// Goal: cap-height of body type lands in the 0.22"–0.25" band on every
/// supported panel. The curve is logarithmic, not linear — a 27" display
/// should not get 2× the type size of a 13" display.
public struct PhysicalTypeMetrics: Equatable, Sendable {

    public let input: ScreenMetricsInput

    public init(input: ScreenMetricsInput) {
        self.input = input
    }

    /// Convenience: extract from a real NSScreen. `deviceDescription[.size]`
    /// returns `NSValue` containing a `CGSize` in millimeters since
    /// `NSDeviceSize` is documented as physical size in points for non-print
    /// devices — but on macOS displays the value is interpreted by callers
    /// as a physical mm size in practice. We pair it with `frame.size` in
    /// points, multiplied by `backingScaleFactor` to recover pixels.
    @MainActor
    public init(screen: NSScreen) {
        let backing = screen.backingScaleFactor
        let pixelSize = CGSize(
            width: screen.frame.width * backing,
            height: screen.frame.height * backing
        )
        let descSize = (screen.deviceDescription[.size] as? NSValue)?.sizeValue
            ?? CGSize(width: 286.1, height: 178.8) // fallback: 13" MBP
        self.init(input: ScreenMetricsInput(
            pixelSize: pixelSize,
            physicalSizeMillimeters: descSize
        ))
    }

    /// Physical pixels per inch along the diagonal.
    public var pixelsPerInch: CGFloat {
        let diagonalPx = sqrt(
            input.pixelSize.width * input.pixelSize.width
          + input.pixelSize.height * input.pixelSize.height
        )
        let diagonalMM = sqrt(
            input.physicalSizeMillimeters.width * input.physicalSizeMillimeters.width
          + input.physicalSizeMillimeters.height * input.physicalSizeMillimeters.height
        )
        let diagonalInches = diagonalMM / 25.4
        guard diagonalInches > 0 else { return 0 }
        return diagonalPx / diagonalInches
    }

    /// Diagonal in inches. Used as the curve's x-axis.
    public var diagonalInches: CGFloat {
        let mm = sqrt(
            input.physicalSizeMillimeters.width * input.physicalSizeMillimeters.width
          + input.physicalSizeMillimeters.height * input.physicalSizeMillimeters.height
        )
        return mm / 25.4
    }

    /// Recommended body point size for SwiftUI Text / WebView body CSS.
    ///
    /// Curve: 13"→22pt is the anchor. 27"→30pt is the cap. Between 13" and 27"
    /// we interpolate with `log2(diagonal/13) / log2(27/13)`. Above 27" the
    /// curve continues at a much shallower slope so a 32" display lands near
    /// 30.5pt rather than blowing past 35pt.
    public var recommendedBodyPointSize: CGFloat {
        let base: CGFloat = 22
        let capDiag: CGFloat = 27
        let capPt: CGFloat = 30
        let d = max(diagonalInches, 13)

        if d <= capDiag {
            let t = log2(d / 13) / log2(capDiag / 13)
            return base + (capPt - base) * t
        } else {
            // Above 27": +0.5pt per doubling of (d - 27).
            let extra = log2(1 + (d - capDiag)) * 0.5
            return capPt + extra
        }
    }

    /// Approximate cap-height in inches at the recommended point size.
    /// Used by tests to verify the curve hits the spec target band.
    /// 1 pt = 1/72 in. Cap height for serif body type ≈ 0.71 of em.
    public var estimatedCapHeightInches: CGFloat {
        let pointSize = recommendedBodyPointSize
        let emInches = pointSize / 72.0
        return emInches * 0.71
    }
}
```

- [ ] **Step 2: Run tests, confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PhysicalTypeMetricsTests 2>&1 | tail -10
```
Expected: `Test Suite 'PhysicalTypeMetricsTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/PageMode/PhysicalTypeMetrics.swift && \
  git commit -m "feat(mac/page): PhysicalTypeMetrics with log curve 13→27→32"
```

---

## Task 4: `SafeColumn` — tests first

**Files:**
- Create: `book-reader-mac/Tests/PageMode/SafeColumnTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/PageMode/SafeColumnTests.swift`:

```swift
import XCTest
import AppKit
@testable import InstantBookReader

final class SafeColumnTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    func testCenteredColumnIsCenteredHorizontally() {
        let col = SafeColumn.frame(for: screen, placement: .center, width: 720)
        let expectedX = (screen.width - 720) / 2
        XCTAssertEqual(col.minX, expectedX, accuracy: 0.5)
        XCTAssertEqual(col.width, 720, accuracy: 0.5)
        XCTAssertEqual(col.height, screen.height, accuracy: 0.5)
    }

    func testLeftPlacementHasLeftMargin() {
        let col = SafeColumn.frame(for: screen, placement: .left, width: 720)
        XCTAssertGreaterThan(col.minX, 40)
        XCTAssertLessThan(col.minX, 200)
    }

    func testRightPlacementReservesIconArea() {
        let col = SafeColumn.frame(for: screen, placement: .right, width: 720)
        let rightGap = screen.width - col.maxX
        XCTAssertGreaterThanOrEqual(rightGap, SafeColumn.reservedRightInsetForIcons,
            "right placement must keep \(SafeColumn.reservedRightInsetForIcons)pt clear for desktop icons")
    }

    func testCenterPlacementOnUltraWideStillReservesIconArea() {
        // 5K Studio Display logical 5120x2880 — center column is still well
        // clear of the right 200pt strip.
        let big = CGRect(x: 0, y: 0, width: 5120, height: 2880)
        let col = SafeColumn.frame(for: big, placement: .center, width: 720)
        let rightGap = big.width - col.maxX
        XCTAssertGreaterThanOrEqual(rightGap, SafeColumn.reservedRightInsetForIcons)
    }

    func testWidthIsConfigurable() {
        let col = SafeColumn.frame(for: screen, placement: .center, width: 900)
        XCTAssertEqual(col.width, 900, accuracy: 0.5)
    }

    func testReservedRightInsetIs200() {
        // Spec §6.3: Right ~200pt always reserved for desktop icons.
        XCTAssertEqual(SafeColumn.reservedRightInsetForIcons, 200)
    }
}
```

- [ ] **Step 2: Run tests, confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/SafeColumnTests 2>&1 | tail -10
```
Expected: compile error referencing `SafeColumn`.

- [ ] **Step 3: Commit failing tests**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/PageMode/SafeColumnTests.swift && \
  git commit -m "test(mac/page): failing tests for SafeColumn"
```

---

## Task 5: `SafeColumn` — implementation

**Files:**
- Create: `book-reader-mac/PageMode/SafeColumn.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/PageMode/SafeColumn.swift`:

```swift
import Foundation
import CoreGraphics
import SwiftUI

/// Placement of the safe column relative to the screen's horizontal axis.
public enum SafeColumnPlacement: String, CaseIterable, Sendable {
    case left
    case center
    case right
}

/// Geometry helper for page mode's centered text column. Spec §6.3:
/// 720pt wide by default, configurable. Right 200pt always reserved
/// for desktop icons regardless of placement.
public enum SafeColumn {

    /// Reserved horizontal strip on the right edge of every screen for
    /// user-arranged desktop icons. Spec §6.3.
    public static let reservedRightInsetForIcons: CGFloat = 200

    /// Default column width — spec §6.3.
    public static let defaultWidth: CGFloat = 720

    /// Storage key for `@AppStorage("pageModeColumnWidth")` consumers.
    public static let widthStorageKey = "pageModeColumnWidth"

    /// Storage key for `@AppStorage("pageModeColumnPlacement")` consumers.
    public static let placementStorageKey = "pageModeColumnPlacement"

    /// Compute the column's CGRect inside the given screen frame.
    /// - Parameters:
    ///   - screen: the screen frame in screen-local coordinates (origin (0,0)
    ///     is fine; only the size matters).
    ///   - placement: left / center / right preset.
    ///   - width: column width in points. Use `SafeColumn.defaultWidth` for
    ///     the spec default.
    public static func frame(
        for screen: CGRect,
        placement: SafeColumnPlacement,
        width: CGFloat = SafeColumn.defaultWidth
    ) -> CGRect {
        let usableRight = screen.width - reservedRightInsetForIcons
        let leftMargin: CGFloat = 96
        let clampedWidth = min(width, usableRight - leftMargin)

        let x: CGFloat
        switch placement {
        case .left:
            x = leftMargin
        case .center:
            // Center within usable area, but never overlap the reserved strip.
            let centerX = (usableRight) / 2
            x = max(leftMargin, centerX - clampedWidth / 2)
        case .right:
            // Right-align inside the usable area.
            x = usableRight - clampedWidth
        }
        return CGRect(x: x, y: 0, width: clampedWidth, height: screen.height)
    }
}
```

- [ ] **Step 2: Run tests, confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/SafeColumnTests 2>&1 | tail -10
```
Expected: `Test Suite 'SafeColumnTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/PageMode/SafeColumn.swift && \
  git commit -m "feat(mac/page): SafeColumn helper with reserved icon strip"
```

---

## Task 6: Extend `GlobalHotkey` with page next/previous

**Files:**
- Modify: `book-reader-mac/Hotkey/GlobalHotkey.swift`

- [ ] **Step 1: Read the existing file**

Run:
```bash
cat /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Hotkey/GlobalHotkey.swift
```
Expected: shows the existing `toggleReader` shortcut and `GlobalHotkey` class from Plan 1.

- [ ] **Step 2: Add the two new shortcut names and wire them through `GlobalHotkey`**

Replace the entire contents of `book-reader-mac/Hotkey/GlobalHotkey.swift` with:

```swift
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
  git add book-reader-mac/Hotkey/GlobalHotkey.swift && \
  git commit -m "feat(mac/page): add pageModeNext / pageModePrevious global hotkeys"
```

---

## Task 7: `PageModeAdvance` — Position mutation helpers

**Files:**
- Create: `book-reader-mac/PageMode/PageModeAdvance.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/PageMode/PageModeAdvance.swift`:

```swift
import Foundation
import SwiftData

/// Helpers that mutate `Position` in response to page-mode advance commands.
/// Page mode is static-only: the page changes only when the active reader
/// advances OR when these helpers fire from the global hotkey.
@MainActor
enum PageModeAdvance {

    /// Apply a one-page advance to the currently-tracked Position. The format
    /// determines how `anchor` is decoded and re-encoded:
    /// - PDF: anchor is `"page:offset"`. We bump the page number by ±1,
    ///   clamped to `[1, pageCount]`.
    /// - EPUB / TXT: anchor is opaque to this helper; we set a
    ///   `pendingScrollDirection` flag on the Position which the relevant
    ///   page-mode view observes and consumes. The view does the actual
    ///   screen-height scroll because only it knows the rendered geometry.
    static func advance(
        position: Position,
        format: BookFormat,
        direction: Direction,
        pdfPageCount: Int? = nil
    ) {
        switch format {
        case .pdf:
            let (page, offset) = decodePDFAnchor(position.anchor)
            let next = max(1, page + (direction == .next ? 1 : -1))
            let clamped = pdfPageCount.map { max(1, min($0, next)) } ?? next
            position.anchor = "\(clamped):\(offset)"
            position.updatedAt = .now
        case .epub, .txt:
            position.pendingScrollDirection = direction.rawValue
            position.updatedAt = .now
        }
    }

    enum Direction: String, Sendable {
        case next
        case previous
    }

    private static func decodePDFAnchor(_ anchor: String) -> (page: Int, offset: Int) {
        let parts = anchor.split(separator: ":")
        let page = Int(parts.first ?? "1") ?? 1
        let offset = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return (page, offset)
    }
}
```

- [ ] **Step 2: Add the `pendingScrollDirection` field to `Position`**

Edit `book-reader-mac/Persistence/Models/Position.swift`. Add a new property after `chapterTitle` and an updated initializer parameter:

```swift
/// Transient hint set by page-mode hotkeys when format is EPUB or TXT.
/// "next" or "previous". The active page-mode view reads, applies a
/// screen-height scroll, and resets this to nil. Persisted because page-mode
/// views are recreated on every `@Query` update — the hint must survive
/// the SwiftData refresh.
var pendingScrollDirection: String?
```

Inside the existing `init`, add the parameter `pendingScrollDirection: String? = nil` and assign `self.pendingScrollDirection = pendingScrollDirection`.

- [ ] **Step 3: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

If SwiftData complains about the migration, accept lightweight migration in `PersistenceController` — Plan 1 already set `cloudKitDatabase: nil` with default migration enabled. No action required.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/PageMode/PageModeAdvance.swift \
          book-reader-mac/Persistence/Models/Position.swift && \
  git commit -m "feat(mac/page): PageModeAdvance helpers and Position.pendingScrollDirection"
```

---

## Task 8: `PageModePDFView` — light mode live PDFView

**Files:**
- Create: `book-reader-mac/PageMode/PageModePDFView.swift`

- [ ] **Step 1: Implement (light branch only — dark branch added in Task 10)**

Write `book-reader-mac/PageMode/PageModePDFView.swift`:

```swift
import SwiftUI
import PDFKit
import AppKit

/// Page-mode PDF renderer.
///
/// Light appearance: live `PDFView` so text selection is preserved when the
/// wallpaper window becomes key (page mode windows are click-through by
/// default; the active reader is where selection actually lives, but we
/// keep the PDFView native so users summoning the reader on top see a
/// matching visual).
///
/// Dark appearance: rendered `PDFPage` bitmap inverted through Core Image.
/// Selection unavailable in this branch — accepted tradeoff per spec §6.4.
///
/// Reuses `PDFKitReaderView.makePDFView(url:)` from Plan 3 so all PDFView
/// configuration (autoScales, displayMode, backgroundColor) stays in one
/// place.
struct PageModePDFView: NSViewRepresentable {

    let book: Book
    let pageIndex: Int   // 0-based; comes from Position.anchor "page:offset"
    let isDark: Bool

    final class Coordinator {
        var hostingPDFView: PDFView?
        var darkImageView: NSImageView?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear
        rebuild(into: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        rebuild(into: nsView, coordinator: context.coordinator)
    }

    private func rebuild(into container: NSView, coordinator: Coordinator) {
        // Resolve the absolute file URL from the relative filePath stored on
        // the Book by Plan 2.
        let url = AppSupportPaths.books.appendingPathComponent(book.filePath)

        container.subviews.forEach { $0.removeFromSuperview() }
        coordinator.hostingPDFView = nil
        coordinator.darkImageView = nil

        if isDark {
            // Dark branch: see Task 10 — Task 8 ships light only.
            let placeholder = NSTextField(labelWithString: "Dark PDF rendering not yet implemented")
            placeholder.textColor = .secondaryLabelColor
            placeholder.alignment = .center
            placeholder.frame = container.bounds
            placeholder.autoresizingMask = [.width, .height]
            container.addSubview(placeholder)
            return
        }

        let pdfView = PDFKitReaderView.makePDFView(url: url)
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
        pdfView.backgroundColor = .clear
        pdfView.frame = container.bounds
        pdfView.autoresizingMask = [.width, .height]
        if let document = pdfView.document, pageIndex < document.pageCount,
           let page = document.page(at: pageIndex) {
            pdfView.go(to: page)
        }
        container.addSubview(pdfView)
        coordinator.hostingPDFView = pdfView
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
  git add book-reader-mac/PageMode/PageModePDFView.swift && \
  git commit -m "feat(mac/page): PageModePDFView light-appearance branch"
```

---

## Task 9: Dark-mode PDF pipeline test (PNG reference + luminance assert)

**Files:**
- Create: `book-reader-mac/Tests/PageMode/Fixtures/sample.pdf`
- Create: `book-reader-mac/Tests/PageMode/Fixtures/pdf-dark-reference.png`
- Create: `book-reader-mac/Tests/PageMode/PDFDarkModeTests.swift`

- [ ] **Step 1: Generate a tiny fixture PDF and a checked-in reference PNG**

Run:
```bash
python3 - <<'PY'
from pathlib import Path
import subprocess, os, sys

out_pdf = Path("/Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/PageMode/Fixtures/sample.pdf")
out_pdf.parent.mkdir(parents=True, exist_ok=True)

# Build a minimal one-page PDF with black text on white.
try:
    from reportlab.pdfgen import canvas
    from reportlab.lib.pagesizes import letter
except ImportError:
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "--quiet", "reportlab"])
    from reportlab.pdfgen import canvas
    from reportlab.lib.pagesizes import letter

c = canvas.Canvas(str(out_pdf), pagesize=letter)
c.setFont("Helvetica", 24)
c.setFillColorRGB(0, 0, 0)
c.drawString(72, 720, "Page mode dark-render fixture")
c.drawString(72, 680, "Black ink on white paper.")
c.showPage()
c.save()
print("wrote", out_pdf)
PY
```

Render the reference PNG by running a one-off Swift script that performs exactly the same Core Image pipeline the production code will:

Run:
```bash
swift /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/PageMode/Fixtures/_generate_reference.swift 2>/dev/null || true
```

Since the helper script doesn't exist yet, create it:

Write `book-reader-mac/Tests/PageMode/Fixtures/_generate_reference.swift`:

```swift
#!/usr/bin/env swift
import Foundation
import PDFKit
import CoreImage
import AppKit

let fixtureDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let pdfURL = fixtureDir.appendingPathComponent("sample.pdf")
let referenceURL = fixtureDir.appendingPathComponent("pdf-dark-reference.png")

guard let doc = PDFDocument(url: pdfURL), let page = doc.page(at: 0) else {
    fatalError("missing sample.pdf at \(pdfURL.path)")
}
let pageBounds = page.bounds(for: .mediaBox)
let thumbnailSize = CGSize(width: 612, height: 792) // letter at 1pt = 1px
let thumb: NSImage = page.thumbnail(of: thumbnailSize, for: .mediaBox)

guard let tiff = thumb.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let cg = bitmap.cgImage else { fatalError("bitmap from thumbnail") }
let ciImage = CIImage(cgImage: cg)

let invert = CIFilter(name: "CIColorInvert")!
invert.setValue(ciImage, forKey: kCIInputImageKey)
let inverted = invert.outputImage!

let hue = CIFilter(name: "CIHueAdjust")!
hue.setValue(inverted, forKey: kCIInputImageKey)
hue.setValue(NSNumber(value: Double.pi), forKey: kCIInputAngleKey) // ~180°
let rotated = hue.outputImage!

let context = CIContext()
guard let outCG = context.createCGImage(rotated, from: rotated.extent) else {
    fatalError("createCGImage")
}
let rep = NSBitmapImageRep(cgImage: outCG)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("png encoding")
}
try png.write(to: referenceURL)
print("wrote", referenceURL.path)
```

Run:
```bash
chmod +x /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/PageMode/Fixtures/_generate_reference.swift && \
  /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/PageMode/Fixtures/_generate_reference.swift
```
Expected: `wrote .../pdf-dark-reference.png`.

- [ ] **Step 2: Write the failing test**

Write `book-reader-mac/Tests/PageMode/PDFDarkModeTests.swift`:

```swift
import XCTest
import PDFKit
import CoreImage
import AppKit
@testable import InstantBookReader

final class PDFDarkModeTests: XCTestCase {

    private func fixture(_ name: String, ext: String) -> URL {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: name, withExtension: ext) else {
            // XcodeGen copies fixtures with their original path; fall back to
            // the source tree path for local runs.
            let direct = URL(fileURLWithPath:
                "/Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/PageMode/Fixtures/\(name).\(ext)")
            XCTAssertTrue(FileManager.default.fileExists(atPath: direct.path),
                          "fixture \(name).\(ext) missing")
            return direct
        }
        return url
    }

    func testDarkRenderProducesPredominantlyDarkBitmap() throws {
        let url = fixture("sample", ext: "pdf")
        let doc = try XCTUnwrap(PDFDocument(url: url))
        let page = try XCTUnwrap(doc.page(at: 0))

        let bitmap = try XCTUnwrap(
            PageModePDFDarkRenderer.darkBitmap(for: page,
                                               size: CGSize(width: 612, height: 792))
        )
        let meanLum = bitmap.meanLuminance()
        XCTAssertLessThan(meanLum, 0.35,
                          "after inversion the mean luminance should be dark, got \(meanLum)")
    }

    func testDarkRenderMatchesReferencePNGWithinTolerance() throws {
        let pdfURL = fixture("sample", ext: "pdf")
        let referenceURL = fixture("pdf-dark-reference", ext: "png")

        let doc = try XCTUnwrap(PDFDocument(url: pdfURL))
        let page = try XCTUnwrap(doc.page(at: 0))
        let produced = try XCTUnwrap(
            PageModePDFDarkRenderer.darkBitmap(for: page,
                                               size: CGSize(width: 612, height: 792))
        )
        let reference = try XCTUnwrap(NSImage(contentsOf: referenceURL))

        let delta = produced.meanAbsoluteDifference(against: reference)
        XCTAssertLessThan(delta, 0.05,
                          "produced bitmap differs from reference by \(delta) (tolerance 0.05)")
    }
}

// MARK: - Test helpers

private extension NSImage {
    func meanLuminance() -> CGFloat {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return 0 }
        let pixels = rep.pixelsWide * rep.pixelsHigh
        var total: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y) else { continue }
                let r = color.redComponent, g = color.greenComponent, b = color.blueComponent
                total += 0.2126 * r + 0.7152 * g + 0.0722 * b
            }
        }
        return total / CGFloat(max(pixels, 1))
    }

    func meanAbsoluteDifference(against other: NSImage) -> CGFloat {
        guard let a = tiffRepresentation, let ar = NSBitmapImageRep(data: a),
              let b = other.tiffRepresentation, let br = NSBitmapImageRep(data: b),
              ar.pixelsWide == br.pixelsWide, ar.pixelsHigh == br.pixelsHigh
        else { return 1.0 }
        var total: CGFloat = 0
        var count = 0
        // Sub-sample on a 16x16 grid to keep the test fast.
        let stepX = max(1, ar.pixelsWide / 16)
        let stepY = max(1, ar.pixelsHigh / 16)
        for y in stride(from: 0, to: ar.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: ar.pixelsWide, by: stepX) {
                guard let ca = ar.colorAt(x: x, y: y), let cb = br.colorAt(x: x, y: y)
                else { continue }
                let dr = abs(ca.redComponent - cb.redComponent)
                let dg = abs(ca.greenComponent - cb.greenComponent)
                let db = abs(ca.blueComponent - cb.blueComponent)
                total += (dr + dg + db) / 3
                count += 1
            }
        }
        return count == 0 ? 1.0 : total / CGFloat(count)
    }
}
```

- [ ] **Step 3: Run the tests, confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PDFDarkModeTests 2>&1 | tail -10
```
Expected: compile error referencing `PageModePDFDarkRenderer`.

- [ ] **Step 4: Commit failing tests + fixtures**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/PageMode/PDFDarkModeTests.swift \
          book-reader-mac/Tests/PageMode/Fixtures/sample.pdf \
          book-reader-mac/Tests/PageMode/Fixtures/pdf-dark-reference.png \
          book-reader-mac/Tests/PageMode/Fixtures/_generate_reference.swift && \
  git commit -m "test(mac/page): PDF dark-mode pipeline tests and PDF/PNG fixtures"
```

---

## Task 10: `PageModePDFDarkRenderer` + dark branch in `PageModePDFView`

**Files:**
- Modify: `book-reader-mac/PageMode/PageModePDFView.swift`

- [ ] **Step 1: Add the dark renderer + wire it into the view**

Replace `book-reader-mac/PageMode/PageModePDFView.swift` with:

```swift
import SwiftUI
import PDFKit
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Core Image pipeline for dark-mode PDF rendering. Spec §6.4: invert color
/// to flip black-on-white → white-on-black, then hue-rotate ~180° so diagrams
/// don't end up as their literal color complement (red→cyan). Pure function,
/// unit-tested without touching any view layer.
public enum PageModePDFDarkRenderer {

    public static func darkBitmap(for page: PDFPage, size: CGSize) -> NSImage? {
        let thumb = page.thumbnail(of: size, for: .mediaBox)
        guard let tiff = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let cg = bitmap.cgImage else { return nil }

        let ciImage = CIImage(cgImage: cg)
        let invert = CIFilter.colorInvert()
        invert.inputImage = ciImage
        guard let inverted = invert.outputImage else { return nil }

        let hue = CIFilter.hueAdjust()
        hue.inputImage = inverted
        hue.angle = Float.pi // ~180°
        guard let rotated = hue.outputImage else { return nil }

        let ctx = CIContext()
        guard let outCG = ctx.createCGImage(rotated, from: rotated.extent) else { return nil }
        return NSImage(cgImage: outCG, size: size)
    }
}

/// Page-mode PDF renderer.
///
/// Light appearance: live `PDFView` so text selection is preserved if the
/// wallpaper window ever becomes key.
///
/// Dark appearance: rendered `PDFPage` bitmap inverted through Core Image.
/// Selection unavailable in this branch — accepted tradeoff per spec §6.4.
/// (Live PDFView under dark appearance renders ink as black-on-black; we
/// preserve diagrams at the cost of interactivity.)
struct PageModePDFView: NSViewRepresentable {

    let book: Book
    let pageIndex: Int   // 0-based; comes from Position.anchor "page:offset"
    let isDark: Bool

    final class Coordinator {
        var hostingPDFView: PDFView?
        var darkImageView: NSImageView?
        var appearanceObservation: NSKeyValueObservation?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear

        // Re-render when system appearance flips.
        context.coordinator.appearanceObservation = NSApp.observe(
            \.effectiveAppearance, options: [.new]
        ) { _, _ in
            DispatchQueue.main.async { [weak container] in
                guard let c = container else { return }
                // Use the latest `isDark` value from the SwiftUI update cycle —
                // updateNSView will be invoked because @AppStorage backs the
                // preference observer in the parent view.
                c.needsDisplay = true
            }
        }

        rebuild(into: container, coordinator: context.coordinator)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        rebuild(into: nsView, coordinator: context.coordinator)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.appearanceObservation?.invalidate()
        coordinator.appearanceObservation = nil
    }

    private func rebuild(into container: NSView, coordinator: Coordinator) {
        let url = AppSupportPaths.books.appendingPathComponent(book.filePath)

        container.subviews.forEach { $0.removeFromSuperview() }
        coordinator.hostingPDFView = nil
        coordinator.darkImageView = nil

        if isDark {
            guard let doc = PDFDocument(url: url),
                  pageIndex < doc.pageCount,
                  let page = doc.page(at: pageIndex) else { return }
            let size = container.bounds.size == .zero
                ? CGSize(width: 720, height: 1000)
                : container.bounds.size
            let image = PageModePDFDarkRenderer.darkBitmap(for: page, size: size)
            let imageView = NSImageView(frame: container.bounds)
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.autoresizingMask = [.width, .height]
            container.addSubview(imageView)
            coordinator.darkImageView = imageView
            return
        }

        let pdfView = PDFKitReaderView.makePDFView(url: url)
        pdfView.displayMode = .singlePage
        pdfView.autoScales = true
        pdfView.backgroundColor = .clear
        pdfView.frame = container.bounds
        pdfView.autoresizingMask = [.width, .height]
        if let document = pdfView.document, pageIndex < document.pageCount,
           let page = document.page(at: pageIndex) {
            pdfView.go(to: page)
        }
        container.addSubview(pdfView)
        coordinator.hostingPDFView = pdfView
    }
}
```

- [ ] **Step 2: Run the dark-mode tests, confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PDFDarkModeTests 2>&1 | tail -10
```
Expected: `Test Suite 'PDFDarkModeTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/PageMode/PageModePDFView.swift && \
  git commit -m "feat(mac/page): PDF dark-mode CIFilter pipeline with KVO appearance refresh"
```

---

## Task 11: EPUB pagination JavaScript

**Files:**
- Create: `book-reader-mac/PageMode/Resources/epub-pagination.js`

- [ ] **Step 1: Write the script**

Write `book-reader-mac/PageMode/Resources/epub-pagination.js`:

```javascript
/**
 * Page-mode pagination harness, injected by PageModeEPUBView into the
 * WKWebView that hosts the existing extension reader. The extension reader
 * renders the entire flattened spine into `.prose-reader`; we add a
 * single-screen scrolling paginator on top.
 *
 * Exposed API (window.__pageMode):
 *   measure()           → { scrollHeight, viewportHeight, currentTop }
 *   advance(direction)  → scrolls one viewport height, returns new state
 *   scrollTo(top)       → absolute scroll
 */
(function () {
  const reader = () => document.querySelector('.prose-reader') || document.scrollingElement;

  function measure() {
    const el = reader();
    const viewport = window.innerHeight;
    return {
      scrollHeight: el.scrollHeight,
      viewportHeight: viewport,
      currentTop: el.scrollTop || window.scrollY || 0
    };
  }

  function advance(direction) {
    const el = reader();
    const viewport = window.innerHeight;
    const current = el.scrollTop || window.scrollY || 0;
    const max = Math.max(0, el.scrollHeight - viewport);
    const delta = direction === 'previous' ? -viewport : viewport;
    const next = Math.max(0, Math.min(max, current + delta));
    if (el === document.scrollingElement) {
      window.scrollTo({ top: next, behavior: 'auto' });
    } else {
      el.scrollTop = next;
    }
    return measure();
  }

  function scrollTo(top) {
    const el = reader();
    if (el === document.scrollingElement) {
      window.scrollTo({ top, behavior: 'auto' });
    } else {
      el.scrollTop = top;
    }
    return measure();
  }

  window.__pageMode = { measure, advance, scrollTo };
})();
```

- [ ] **Step 2: Register the resource in `project.yml`**

The `PageMode/Resources/` folder is already covered by the source group added in Task 1 (XcodeGen treats arbitrary files inside source groups as resources when their type isn't recognized as Swift). Verify:

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. If the JS is not copied into the bundle, add an explicit resources clause to the `InstantBookReader` target:

```yaml
    resources:
      - path: PageMode/Resources
        buildPhase: resources
```

Then regenerate and rebuild.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/PageMode/Resources/epub-pagination.js \
          book-reader-mac/project.yml && \
  git commit -m "feat(mac/page): epub-pagination.js paginator harness"
```

---

## Task 12: `PageModeEPUBView` CSS-injection test (TDD)

**Files:**
- Create: `book-reader-mac/Tests/PageMode/PageModeEPUBCSSTests.swift`

- [ ] **Step 1: Write the failing test**

Write `book-reader-mac/Tests/PageMode/PageModeEPUBCSSTests.swift`:

```swift
import XCTest
@testable import InstantBookReader

final class PageModeEPUBCSSTests: XCTestCase {

    func testCSSConstrainsToSafeColumnWidth() {
        let css = PageModeEPUBView.injectedCSS(
            safeColumnWidth: 720,
            bodyPointSize: 22
        )
        XCTAssertTrue(css.contains("max-width: 720px"),
                      "expected max-width directive, got:\n\(css)")
    }

    func testCSSDisablesAutoColumns() {
        let css = PageModeEPUBView.injectedCSS(
            safeColumnWidth: 720,
            bodyPointSize: 22
        )
        XCTAssertTrue(css.contains("column-width: none"),
                      "expected `column-width: none`, got:\n\(css)")
        XCTAssertTrue(css.contains("column-count: 1"),
                      "expected `column-count: 1`, got:\n\(css)")
    }

    func testCSSAppliesPhysicalBodyPointSize() {
        let css = PageModeEPUBView.injectedCSS(
            safeColumnWidth: 720,
            bodyPointSize: 28
        )
        XCTAssertTrue(css.contains("font-size: 28pt"),
                      "expected font-size: 28pt, got:\n\(css)")
    }

    func testCSSChangesWithBodySize() {
        let small = PageModeEPUBView.injectedCSS(safeColumnWidth: 720, bodyPointSize: 22)
        let large = PageModeEPUBView.injectedCSS(safeColumnWidth: 720, bodyPointSize: 30)
        XCTAssertNotEqual(small, large)
    }
}
```

- [ ] **Step 2: Run, confirm it fails**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PageModeEPUBCSSTests 2>&1 | tail -10
```
Expected: compile error referencing `PageModeEPUBView`.

- [ ] **Step 3: Commit failing tests**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/PageMode/PageModeEPUBCSSTests.swift && \
  git commit -m "test(mac/page): failing CSS-injection tests for PageModeEPUBView"
```

---

## Task 13: `PageModeEPUBView` implementation

**Files:**
- Create: `book-reader-mac/PageMode/PageModeEPUBView.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/PageMode/PageModeEPUBView.swift`:

```swift
import SwiftUI
import WebKit
import AppKit

/// Page-mode EPUB renderer.
///
/// Reuses `WebReaderView` (Plan 3) which hosts the extension's React reader
/// inside a WKWebView. We inject CSS that:
///   - constrains `.prose-reader` to the safe column width
///   - disables CSS-columns (no auto-pagination)
///   - sets a physical-size body font from `PhysicalTypeMetrics`
///
/// The extension's chapter-flattening pipeline at
/// `book-reader-extension/src/newtab/lib/parsers/epub.ts` is reused via the
/// bundled WebReader.bundle (Plan 1 / 3). We do NOT reimplement EPUB parsing
/// on the Swift side — the WKWebView loads the same JS that the extension
/// uses.
///
/// Pagination: see `epub-pagination.js`. We expose `advance(direction:)`
/// which evaluates `window.__pageMode.advance(...)` and updates the
/// scroll position. Page-break logic is height-measurement based; we do not
/// inject CSS `break-inside` rules because they cause line-clipping on
/// arbitrary HTML.
struct PageModeEPUBView: NSViewRepresentable {

    let book: Book
    let safeColumnWidth: CGFloat
    let bodyPointSize: CGFloat
    /// When the user fires the page hotkey, `pendingScrollDirection` flips
    /// to "next" or "previous". We consume it, scroll, then clear it (the
    /// hotkey handler in `AppDelegate` re-clears in SwiftData; see Task 16).
    let pendingScrollDirection: String?
    let onPendingConsumed: () -> Void

    final class Coordinator {
        var webView: WKWebView?
        var lastConsumedDirection: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let injectedCSS = Self.injectedCSS(
            safeColumnWidth: safeColumnWidth,
            bodyPointSize: bodyPointSize
        )
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.backgroundColor = .clear

        let webContainer = WebReaderView(
            book: book,
            injectedCSS: injectedCSS,
            onReady: { webView in
                context.coordinator.webView = webView
                Self.injectPaginationScript(into: webView)
            }
        )
        let host = NSHostingView(rootView: webContainer)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coord = context.coordinator
        guard let direction = pendingScrollDirection,
              direction != coord.lastConsumedDirection,
              let webView = coord.webView else { return }
        coord.lastConsumedDirection = direction
        let js = "window.__pageMode && window.__pageMode.advance(\(stringLiteral(direction)));"
        webView.evaluateJavaScript(js) { _, _ in
            DispatchQueue.main.async { onPendingConsumed() }
        }
    }

    // MARK: - CSS

    /// Builds the CSS that the WKWebView will inject as a `WKUserScript` at
    /// document-end. Public so tests can assert content without firing up
    /// WebKit.
    static func injectedCSS(safeColumnWidth: CGFloat, bodyPointSize: CGFloat) -> String {
        """
        :root {
          --page-mode-column: \(Int(safeColumnWidth))px;
          --page-mode-body: \(Int(bodyPointSize))pt;
        }
        html, body {
          background: transparent !important;
          overflow: hidden !important;
          margin: 0 !important;
          padding: 0 !important;
        }
        .prose-reader {
          max-width: \(Int(safeColumnWidth))px;
          margin: 0 auto;
          padding: 2em 0;
          column-width: none;
          column-count: 1;
          font-size: \(Int(bodyPointSize))pt;
          line-height: 1.55;
        }
        .prose-reader img, .prose-reader figure {
          max-width: 100%;
          height: auto;
        }
        """
    }

    private static func injectPaginationScript(into webView: WKWebView) {
        guard let url = Bundle.main.url(forResource: "epub-pagination",
                                        withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else { return }
        let script = WKUserScript(source: source,
                                  injectionTime: .atDocumentEnd,
                                  forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(script)
        // The script also needs to run once for the already-loaded document
        // (user scripts apply to future loads):
        webView.evaluateJavaScript(source, completionHandler: nil)
    }

    private func stringLiteral(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
                           .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
```

- [ ] **Step 2: Run the CSS-injection tests, confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PageModeEPUBCSSTests 2>&1 | tail -10
```
Expected: `Test Suite 'PageModeEPUBCSSTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/PageMode/PageModeEPUBView.swift && \
  git commit -m "feat(mac/page): PageModeEPUBView with injected CSS and paginator bridge"
```

---

## Task 14: EPUB pagination correctness test

**Files:**
- Create: `book-reader-mac/Tests/PageMode/Fixtures/sample.epub`
- Create: `book-reader-mac/Tests/PageMode/PageModeEPUBPaginationTests.swift`

- [ ] **Step 1: Generate a 3-chapter EPUB fixture**

Run:
```bash
python3 - <<'PY'
import zipfile, os, pathlib

dst = pathlib.Path("/Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/PageMode/Fixtures/sample.epub")
dst.parent.mkdir(parents=True, exist_ok=True)

def chapter(n, lines):
    body = "\n".join(f"<p>{ln}</p>" for ln in lines)
    return f"""<?xml version=\"1.0\" encoding=\"utf-8\"?>
<!DOCTYPE html>
<html xmlns=\"http://www.w3.org/1999/xhtml\"><head><title>Ch{n}</title></head>
<body><h1 id=\"ch{n}\">Chapter {n}</h1>{body}</body></html>"""

ch1_lines = [f"alpha line {i} — first chapter sentinel" for i in range(60)]
ch2_lines = [f"bravo line {i} — second chapter sentinel" for i in range(60)]
ch3_lines = [f"charlie line {i} — third chapter sentinel" for i in range(60)]

with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
    z.writestr("META-INF/container.xml", """<?xml version=\"1.0\"?>
<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">
  <rootfiles><rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles>
</container>""")
    z.writestr("OEBPS/content.opf", """<?xml version=\"1.0\"?>
<package xmlns=\"http://www.idpf.org/2007/opf\" unique-identifier=\"bid\" version=\"3.0\">
  <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">
    <dc:identifier id=\"bid\">sample</dc:identifier>
    <dc:title>Sample</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id=\"c1\" href=\"ch1.xhtml\" media-type=\"application/xhtml+xml\"/>
    <item id=\"c2\" href=\"ch2.xhtml\" media-type=\"application/xhtml+xml\"/>
    <item id=\"c3\" href=\"ch3.xhtml\" media-type=\"application/xhtml+xml\"/>
  </manifest>
  <spine>
    <itemref idref=\"c1\"/><itemref idref=\"c2\"/><itemref idref=\"c3\"/>
  </spine>
</package>""")
    z.writestr("OEBPS/ch1.xhtml", chapter(1, ch1_lines))
    z.writestr("OEBPS/ch2.xhtml", chapter(2, ch2_lines))
    z.writestr("OEBPS/ch3.xhtml", chapter(3, ch3_lines))
print("wrote", dst)
PY
```

- [ ] **Step 2: Write the pagination test**

Write `book-reader-mac/Tests/PageMode/PageModeEPUBPaginationTests.swift`:

```swift
import XCTest
import WebKit
import AppKit
@testable import InstantBookReader

/// Verifies that page-mode's screen-height pagination advances exactly one
/// viewport per call and that consecutive pages do not skip content.
///
/// Uses a WKWebView loaded with a static HTML document that mimics the
/// flattened EPUB the extension's reader would produce — we don't drive the
/// real extension reader here because that requires the full WebReader bundle.
/// What we are testing is `epub-pagination.js`, not the React app.
@MainActor
final class PageModeEPUBPaginationTests: XCTestCase {

    private func loadScript() throws -> String {
        let direct = URL(fileURLWithPath:
            "/Users/profitoniumapps/Documents/chromeApps/book-reader-mac/PageMode/Resources/epub-pagination.js")
        return try String(contentsOf: direct, encoding: .utf8)
    }

    private func makeWebView() -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 720, height: 400),
                             configuration: cfg)
        return view
    }

    private func loadHTML(_ webView: WKWebView, body: String) async {
        let html = """
        <!doctype html><html><head>
          <style>
            html, body { margin:0; padding:0; }
            .prose-reader { width: 720px; font-size: 22pt; line-height: 1.55; }
            p { margin: 0 0 1em 0; }
          </style>
        </head><body><div class="prose-reader">\(body)</div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        // Wait until the document is interactive.
        for _ in 0..<50 {
            let state: String = (try? await webView.evaluateJavaScript("document.readyState") as? String) ?? ""
            if state == "complete" || state == "interactive" { return }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func testAdvanceMovesExactlyOneViewportAndDoesNotSkipContent() async throws {
        let webView = makeWebView()
        let script = try loadScript()
        let body = (1...80).map { "<p>line \($0) — sentinel \($0)</p>" }.joined()
        await loadHTML(webView, body: body)

        // Inject the paginator.
        _ = try await webView.evaluateJavaScript(script)

        // Page 1: capture the bottom-most visible line.
        let firstState = try await webView.evaluateJavaScript(
            "JSON.stringify(window.__pageMode.measure())"
        ) as? String
        XCTAssertNotNil(firstState)

        // Identify the line that sits at scrollTop + viewportHeight (the
        // last visible on page 1; equals the first visible on page 2 after
        // advance).
        let beforeBottom = try await webView.evaluateJavaScript("""
            (function(){
              const reader = document.querySelector('.prose-reader');
              const viewport = window.innerHeight;
              const bottom = (reader.scrollTop || window.scrollY || 0) + viewport;
              const paragraphs = Array.from(document.querySelectorAll('.prose-reader p'));
              const target = paragraphs.find(p => {
                const top = p.offsetTop;
                const bot = top + p.offsetHeight;
                return top < bottom && bot >= bottom - 4;
              });
              return target ? target.textContent : null;
            })()
        """) as? String

        // Advance one page.
        let advance = try await webView.evaluateJavaScript(
            "JSON.stringify(window.__pageMode.advance('next'))"
        ) as? String
        XCTAssertNotNil(advance)

        // After advance, the first visible line should be the same paragraph
        // that was at the bottom edge of page 1.
        let afterTop = try await webView.evaluateJavaScript("""
            (function(){
              const reader = document.querySelector('.prose-reader');
              const top = (reader.scrollTop || window.scrollY || 0);
              const paragraphs = Array.from(document.querySelectorAll('.prose-reader p'));
              const target = paragraphs.find(p => {
                const ptop = p.offsetTop;
                const pbot = ptop + p.offsetHeight;
                return pbot > top + 1 && ptop <= top + 4;
              });
              return target ? target.textContent : null;
            })()
        """) as? String

        XCTAssertNotNil(beforeBottom)
        XCTAssertNotNil(afterTop)
        XCTAssertEqual(beforeBottom, afterTop,
                       "page 2 should start where page 1 ended — no content skipped")
    }

    func testAdvancePreviousReturnsToOrigin() async throws {
        let webView = makeWebView()
        let script = try loadScript()
        let body = (1...80).map { "<p>line \($0)</p>" }.joined()
        await loadHTML(webView, body: body)
        _ = try await webView.evaluateJavaScript(script)

        _ = try await webView.evaluateJavaScript("window.__pageMode.advance('next')")
        _ = try await webView.evaluateJavaScript("window.__pageMode.advance('previous')")
        let top = try await webView.evaluateJavaScript("""
            (document.querySelector('.prose-reader').scrollTop || window.scrollY || 0)
        """) as? NSNumber
        XCTAssertNotNil(top)
        XCTAssertEqual(top!.doubleValue, 0, accuracy: 1.5)
    }
}
```

- [ ] **Step 3: Run the tests, confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PageModeEPUBPaginationTests 2>&1 | tail -15
```
Expected: `Test Suite 'PageModeEPUBPaginationTests' passed`. If the WKWebView tests time out under `xcodebuild test` (sometimes happens in CI), add `-parallel-testing-enabled NO`.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/PageMode/Fixtures/sample.epub \
          book-reader-mac/Tests/PageMode/PageModeEPUBPaginationTests.swift && \
  git commit -m "test(mac/page): EPUB pagination correctness (no skipped content)"
```

---

## Task 15: `PageModeTXTView`

**Files:**
- Create: `book-reader-mac/PageMode/PageModeTXTView.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/PageMode/PageModeTXTView.swift`:

```swift
import SwiftUI

/// Page-mode TXT renderer. Native SwiftUI — no WKWebView. Chunks the file
/// by paragraphs and shows the slice that fits inside the safe column at
/// the current `Position.anchor` character offset.
struct PageModeTXTView: View {

    let book: Book
    let charOffset: Int
    let safeColumnWidth: CGFloat
    let bodyPointSize: CGFloat
    let pendingScrollDirection: String?
    let onPendingConsumed: () -> Void

    @State private var chunkText: String = ""
    @State private var currentOffset: Int = 0

    var body: some View {
        GeometryReader { geo in
            let column = SafeColumn.frame(
                for: CGRect(origin: .zero, size: geo.size),
                placement: .center,
                width: safeColumnWidth
            )
            HStack(spacing: 0) {
                Spacer(minLength: column.minX)
                Text(chunkText)
                    .font(.system(size: bodyPointSize, design: .serif))
                    .lineSpacing(bodyPointSize * 0.5)
                    .multilineTextAlignment(.leading)
                    .frame(width: column.width, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 48)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onAppear { load(at: charOffset, viewportSize: nil) }
        .onChange(of: charOffset) { _, newValue in
            currentOffset = newValue
            load(at: newValue, viewportSize: nil)
        }
        .onChange(of: pendingScrollDirection) { _, direction in
            guard let direction else { return }
            advance(direction: direction)
            onPendingConsumed()
        }
    }

    private func load(at offset: Int, viewportSize: CGSize?) {
        let url = AppSupportPaths.books.appendingPathComponent(book.filePath)
        guard let data = try? Data(contentsOf: url),
              let full = String(data: data, encoding: .utf8) else {
            chunkText = ""
            return
        }
        let start = max(0, min(offset, full.count))
        let length = chunkLength(forPointSize: bodyPointSize)
        let endIdx = min(full.count, start + length)
        let lower = full.index(full.startIndex, offsetBy: start)
        let upper = full.index(full.startIndex, offsetBy: endIdx)
        chunkText = String(full[lower..<upper])
        currentOffset = start
    }

    private func advance(direction: String) {
        let url = AppSupportPaths.books.appendingPathComponent(book.filePath)
        guard let data = try? Data(contentsOf: url),
              let full = String(data: data, encoding: .utf8) else { return }
        let length = chunkLength(forPointSize: bodyPointSize)
        let delta = direction == "previous" ? -length : length
        let next = max(0, min(full.count - 1, currentOffset + delta))
        let endIdx = min(full.count, next + length)
        let lower = full.index(full.startIndex, offsetBy: next)
        let upper = full.index(full.startIndex, offsetBy: endIdx)
        chunkText = String(full[lower..<upper])
        currentOffset = next
    }

    /// Character window per screen. A 13" MBP at 22pt fits ~1800 chars; we
    /// scale linearly with the inverse of point size so 30pt fits ~1300.
    private func chunkLength(forPointSize size: CGFloat) -> Int {
        let base: CGFloat = 1800
        let baseSize: CGFloat = 22
        let scaled = base * (baseSize / max(size, 1))
        return max(400, Int(scaled))
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
  git add book-reader-mac/PageMode/PageModeTXTView.swift && \
  git commit -m "feat(mac/page): PageModeTXTView with SafeColumn chunking"
```

---

## Task 16: `PageModeRouter`

**Files:**
- Create: `book-reader-mac/PageMode/PageModeRouter.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/PageMode/PageModeRouter.swift`:

```swift
import SwiftUI
import SwiftData
import AppKit

/// Routes the current book to the appropriate page-mode renderer based on
/// `Book.format`. Used by `WallpaperWindowCoordinator` for the `.page`
/// branch added by Plan 5.
///
/// One screen at a time. Multi-monitor: every screen renders the same page
/// for v1 (spec §6). No continuation across displays.
struct PageModeRouter: View {

    let screen: NSScreen

    @Environment(ReadingState.self) private var state
    @Environment(\.modelContext) private var modelContext

    /// Pull the current book by sha256 from SwiftData.
    @Query private var allBooks: [Book]

    @AppStorage("pageModeColumnWidth") private var columnWidth: Double = Double(SafeColumn.defaultWidth)
    @AppStorage("pageModeColumnPlacement") private var placementRaw: String = SafeColumnPlacement.center.rawValue

    var body: some View {
        ZStack {
            Color.clear
            if let book = currentBook {
                content(for: book)
                    .frame(width: column.width, height: column.height)
                    .position(x: column.midX, y: column.midY)
            }
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
    }

    private var currentBook: Book? {
        guard let hash = state.currentBookHash else { return nil }
        return allBooks.first { $0.sha256 == hash }
    }

    private var placement: SafeColumnPlacement {
        SafeColumnPlacement(rawValue: placementRaw) ?? .center
    }

    private var column: CGRect {
        SafeColumn.frame(
            for: CGRect(origin: .zero, size: screen.frame.size),
            placement: placement,
            width: CGFloat(columnWidth)
        )
    }

    private var bodyPointSize: CGFloat {
        PhysicalTypeMetrics(screen: screen).recommendedBodyPointSize
    }

    private var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    @ViewBuilder
    private func content(for book: Book) -> some View {
        switch book.format {
        case .pdf:
            let pageIndex = decodedPDFPageIndex(book.position?.anchor ?? "1:0")
            PageModePDFView(book: book,
                            pageIndex: pageIndex,
                            isDark: isDark)

        case .epub:
            PageModeEPUBView(
                book: book,
                safeColumnWidth: column.width,
                bodyPointSize: bodyPointSize,
                pendingScrollDirection: book.position?.pendingScrollDirection,
                onPendingConsumed: { clearPending(on: book) }
            )

        case .txt:
            PageModeTXTView(
                book: book,
                charOffset: Int(book.position?.anchor ?? "0") ?? 0,
                safeColumnWidth: column.width,
                bodyPointSize: bodyPointSize,
                pendingScrollDirection: book.position?.pendingScrollDirection,
                onPendingConsumed: { clearPending(on: book) }
            )
        }
    }

    private func decodedPDFPageIndex(_ anchor: String) -> Int {
        let parts = anchor.split(separator: ":")
        let oneBased = Int(parts.first ?? "1") ?? 1
        return max(0, oneBased - 1)
    }

    private func clearPending(on book: Book) {
        book.position?.pendingScrollDirection = nil
        try? modelContext.save()
    }
}
```

- [ ] **Step 2: Wire `PageModeRouter` into `WallpaperWindowCoordinator`'s `.page` branch (left empty by Plan 5)**

Edit `book-reader-mac/Windows/WallpaperWindowCoordinator.swift`. Find the section Plan 5 added that switches on `state.ambientMode`:

```swift
Group {
    switch state.ambientMode {
    case .atomic: AtomicAmbientView(screen: screen)
    case .page:   EmptyView()
    }
}
```

Replace the `.page` branch with:

```swift
case .page:   PageModeRouter(screen: screen)
```

The surrounding `.environment(\.appTheme, theme)`, `.environment(state)`, and `.modelContainer(modelContainer)` chain stays as Plan 5 wrote it.

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
  git add book-reader-mac/PageMode/PageModeRouter.swift \
          book-reader-mac/Windows/WallpaperWindowCoordinator.swift && \
  git commit -m "feat(mac/page): PageModeRouter and WallpaperWindowCoordinator .page wiring"
```

---

## Task 17: Wire `pageModeNext` / `pageModePrevious` hotkeys in `AppDelegate`

**Files:**
- Modify: `book-reader-mac/App/AppDelegate.swift`

- [ ] **Step 1: Locate the existing hotkey wiring**

Run:
```bash
grep -n "GlobalHotkey\|hotkey" /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/App/AppDelegate.swift
```
Expected: shows `hotkey = GlobalHotkey(onToggle: { ... })`.

- [ ] **Step 2: Switch to the multi-callback initializer**

Edit `book-reader-mac/App/AppDelegate.swift`. Replace the line that constructs `GlobalHotkey` with:

```swift
hotkey = GlobalHotkey(
    onToggleReader: { [weak self] in self?.readerController.toggle() },
    onPageNext: { [weak self] in self?.advancePageMode(.next) },
    onPagePrevious: { [weak self] in self?.advancePageMode(.previous) }
)
hotkey.register()
```

And add this method to the `AppDelegate` body (near the other action methods):

```swift
@MainActor
private func advancePageMode(_ direction: PageModeAdvance.Direction) {
    guard state.ambientMode == .page,
          let hash = state.currentBookHash else { return }
    let context = modelContainer.mainContext
    let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.sha256 == hash })
    guard let book = try? context.fetch(descriptor).first else { return }
    let position = book.position ?? {
        let p = Position(bookHash: hash, anchor: book.format == .pdf ? "1:0" : "0",
                         percentage: 0, updatedAt: .now)
        book.position = p
        context.insert(p)
        return p
    }()

    let pdfPageCount: Int? = {
        guard book.format == .pdf else { return nil }
        let url = AppSupportPaths.books.appendingPathComponent(book.filePath)
        return PDFDocument(url: url)?.pageCount
    }()

    PageModeAdvance.advance(position: position,
                            format: book.format,
                            direction: direction,
                            pdfPageCount: pdfPageCount)
    try? context.save()
}
```

Add `import PDFKit` and `import SwiftData` at the top of `AppDelegate.swift` if not already present.

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
  git add book-reader-mac/App/AppDelegate.swift && \
  git commit -m "feat(mac/page): wire pageModeNext/Previous hotkeys to Position mutations"
```

---

## Task 18: `IdleWatcher` — tests first

**Files:**
- Create: `book-reader-mac/Tests/PageMode/IdleWatcherTests.swift`

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/PageMode/IdleWatcherTests.swift`:

```swift
import XCTest
@testable import InstantBookReader

@MainActor
final class IdleWatcherTests: XCTestCase {

    final class StubIdleProvider: IdleTimeProviding {
        var idleSeconds: TimeInterval = 0
        func currentIdleSeconds() -> TimeInterval { idleSeconds }
    }

    func testEmitsIdleAfterTenMinutes() async {
        let stub = StubIdleProvider()
        var idleCount = 0
        var wakeCount = 0
        let watcher = IdleWatcher(
            idleThreshold: 600,
            tickInterval: 0.01,
            idleProvider: stub,
            onIdle: { idleCount += 1 },
            onWake: { wakeCount += 1 }
        )
        watcher.start()
        stub.idleSeconds = 599
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(idleCount, 0)

        stub.idleSeconds = 601
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(idleCount, 1)
        watcher.stop()
    }

    func testEmitsWakeWhenIdleDropsBelowThreshold() async {
        let stub = StubIdleProvider()
        var idleCount = 0
        var wakeCount = 0
        let watcher = IdleWatcher(
            idleThreshold: 600,
            tickInterval: 0.01,
            idleProvider: stub,
            onIdle: { idleCount += 1 },
            onWake: { wakeCount += 1 }
        )
        watcher.start()
        stub.idleSeconds = 601
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(idleCount, 1)
        XCTAssertEqual(wakeCount, 0)

        stub.idleSeconds = 0.1
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(wakeCount, 1)
        watcher.stop()
    }

    func testDoesNotEmitMultipleIdleEventsWhileStillIdle() async {
        let stub = StubIdleProvider()
        var idleCount = 0
        let watcher = IdleWatcher(
            idleThreshold: 600,
            tickInterval: 0.01,
            idleProvider: stub,
            onIdle: { idleCount += 1 },
            onWake: {}
        )
        watcher.start()
        stub.idleSeconds = 700
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(idleCount, 1)
        watcher.stop()
    }
}
```

- [ ] **Step 2: Run tests, confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/IdleWatcherTests 2>&1 | tail -10
```
Expected: compile error referencing `IdleWatcher`, `IdleTimeProviding`.

- [ ] **Step 3: Commit failing tests**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/PageMode/IdleWatcherTests.swift && \
  git commit -m "test(mac/page): failing tests for IdleWatcher"
```

---

## Task 19: `IdleWatcher` — implementation

**Files:**
- Create: `book-reader-mac/PageMode/IdleWatcher.swift`

- [ ] **Step 1: Implement**

Write `book-reader-mac/PageMode/IdleWatcher.swift`:

```swift
import Foundation
import AppKit
import CoreGraphics

/// Injectable provider of "seconds since last input event". Real
/// implementation wraps `CGEventSource.secondsSinceLastEventType`; tests
/// supply a stub.
public protocol IdleTimeProviding: AnyObject {
    func currentIdleSeconds() -> TimeInterval
}

/// Production provider — combined session-state, all event types.
public final class CombinedSessionIdleProvider: IdleTimeProviding {
    public init() {}
    public func currentIdleSeconds() -> TimeInterval {
        // `kCGAnyInputEventType` is conventionally represented as UInt32.max.
        let anyEvent = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyEvent
        )
    }
}

/// Polls an `IdleTimeProviding` on a fixed cadence and emits `onIdle` /
/// `onWake` edge-transition callbacks.
///
/// Spec §6.6: 10 minutes idle → crossfade to ambient cover+quote. Mouse-move
/// → crossfade back. This class fires the edge events only; the caller
/// owns the animation.
@MainActor
public final class IdleWatcher {

    private let idleThreshold: TimeInterval
    private let tickInterval: TimeInterval
    private let idleProvider: IdleTimeProviding
    private let onIdle: () -> Void
    private let onWake: () -> Void

    private var timer: Timer?
    private var isIdle: Bool = false

    public init(
        idleThreshold: TimeInterval = 600,
        tickInterval: TimeInterval = 10,
        idleProvider: IdleTimeProviding = CombinedSessionIdleProvider(),
        onIdle: @escaping () -> Void,
        onWake: @escaping () -> Void
    ) {
        self.idleThreshold = idleThreshold
        self.tickInterval = tickInterval
        self.idleProvider = idleProvider
        self.onIdle = onIdle
        self.onWake = onWake
    }

    public func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = tickInterval * 0.1
        // Fire one tick immediately so tests don't have to wait for the
        // first scheduled fire.
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let idle = idleProvider.currentIdleSeconds()
        let shouldBeIdle = idle >= idleThreshold
        guard shouldBeIdle != isIdle else { return }
        isIdle = shouldBeIdle
        if shouldBeIdle { onIdle() } else { onWake() }
    }
}
```

- [ ] **Step 2: Run tests, confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/IdleWatcherTests 2>&1 | tail -10
```
Expected: `Test Suite 'IdleWatcherTests' passed`.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/PageMode/IdleWatcher.swift && \
  git commit -m "feat(mac/page): IdleWatcher with injectable IdleTimeProviding"
```

---

## Task 20: Idle-to-ambient crossfade in `PageModeRouter`

**Files:**
- Modify: `book-reader-mac/PageMode/PageModeRouter.swift`

- [ ] **Step 1: Add idle state to the router**

Edit `book-reader-mac/PageMode/PageModeRouter.swift`. Replace the body of `PageModeRouter` to incorporate idle crossfade:

```swift
struct PageModeRouter: View {

    let screen: NSScreen

    @Environment(ReadingState.self) private var state
    @Environment(\.modelContext) private var modelContext

    @Query private var allBooks: [Book]

    @AppStorage("pageModeColumnWidth") private var columnWidth: Double = Double(SafeColumn.defaultWidth)
    @AppStorage("pageModeColumnPlacement") private var placementRaw: String = SafeColumnPlacement.center.rawValue
    @AppStorage("pageModeIdleTimeout") private var idleTimeoutSeconds: Double = 600

    @State private var isIdle: Bool = false
    @State private var idleWatcher: IdleWatcher?

    var body: some View {
        ZStack {
            Color.clear
            if let book = currentBook {
                content(for: book)
                    .frame(width: column.width, height: column.height)
                    .position(x: column.midX, y: column.midY)
                    .opacity(isIdle ? 0 : 1)
                    .animation(.easeInOut(duration: 0.4), value: isIdle)

                if isIdle {
                    IdleAmbientOverlay(book: book, screen: screen)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.4), value: isIdle)
                }
            }
        }
        .frame(width: screen.frame.width, height: screen.frame.height)
        .onAppear(perform: startIdleWatcher)
        .onDisappear(perform: stopIdleWatcher)
        .onChange(of: idleTimeoutSeconds) { _, _ in restartIdleWatcher() }
    }

    private func startIdleWatcher() {
        idleWatcher = IdleWatcher(
            idleThreshold: idleTimeoutSeconds,
            tickInterval: 10,
            onIdle: { isIdle = true },
            onWake: { isIdle = false }
        )
        idleWatcher?.start()
    }

    private func stopIdleWatcher() {
        idleWatcher?.stop()
        idleWatcher = nil
    }

    private func restartIdleWatcher() {
        stopIdleWatcher()
        startIdleWatcher()
    }

    private var currentBook: Book? {
        guard let hash = state.currentBookHash else { return nil }
        return allBooks.first { $0.sha256 == hash }
    }

    private var placement: SafeColumnPlacement {
        SafeColumnPlacement(rawValue: placementRaw) ?? .center
    }

    private var column: CGRect {
        SafeColumn.frame(
            for: CGRect(origin: .zero, size: screen.frame.size),
            placement: placement,
            width: CGFloat(columnWidth)
        )
    }

    private var bodyPointSize: CGFloat {
        PhysicalTypeMetrics(screen: screen).recommendedBodyPointSize
    }

    private var isDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    @ViewBuilder
    private func content(for book: Book) -> some View {
        switch book.format {
        case .pdf:
            let pageIndex = decodedPDFPageIndex(book.position?.anchor ?? "1:0")
            PageModePDFView(book: book,
                            pageIndex: pageIndex,
                            isDark: isDark)

        case .epub:
            PageModeEPUBView(
                book: book,
                safeColumnWidth: column.width,
                bodyPointSize: bodyPointSize,
                pendingScrollDirection: book.position?.pendingScrollDirection,
                onPendingConsumed: { clearPending(on: book) }
            )

        case .txt:
            PageModeTXTView(
                book: book,
                charOffset: Int(book.position?.anchor ?? "0") ?? 0,
                safeColumnWidth: column.width,
                bodyPointSize: bodyPointSize,
                pendingScrollDirection: book.position?.pendingScrollDirection,
                onPendingConsumed: { clearPending(on: book) }
            )
        }
    }

    private func decodedPDFPageIndex(_ anchor: String) -> Int {
        let parts = anchor.split(separator: ":")
        let oneBased = Int(parts.first ?? "1") ?? 1
        return max(0, oneBased - 1)
    }

    private func clearPending(on book: Book) {
        book.position?.pendingScrollDirection = nil
        try? modelContext.save()
    }
}

/// Overlay shown after the idle threshold trips. Reuses Plan 5's
/// `AmbientCornerCard` minus the chapter line.
private struct IdleAmbientOverlay: View {
    let book: Book
    let screen: NSScreen

    var body: some View {
        // AmbientCornerCard is provided by Plan 5. We hide the chapter line
        // via its `chapterVisible` parameter.
        AmbientCornerCard(book: book, chapterVisible: false)
            .frame(width: screen.frame.width, height: screen.frame.height,
                   alignment: .bottomLeading)
            .padding([.bottom, .leading], 64)
    }
}
```

This assumes Plan 5's `AmbientCornerCard` exposes a `chapterVisible: Bool = true` parameter. If Plan 5 named it differently (likely candidates: `showsChapter`, `includesChapter`), the executing agent must update the call site to match — the spec is firm that the idle overlay drops the chapter line.

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`. If `AmbientCornerCard` doesn't accept the `chapterVisible:` parameter, pause and patch Plan 5's component first.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/PageMode/PageModeRouter.swift && \
  git commit -m "feat(mac/page): idle crossfade from page mode to ambient overlay"
```

---

## Task 21: Manual smoke test instructions

**Files:**
- Modify: `book-reader-mac/README.md`

- [ ] **Step 1: Append a "Page mode smoke test" section to the README**

Append to `book-reader-mac/README.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/README.md && \
  git commit -m "docs(mac/page): smoke test checklist for page mode"
```

---

## Task 22: Full test suite pass

- [ ] **Step 1: Run every page-mode test**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' \
    -only-testing:InstantBookReaderTests/PhysicalTypeMetricsTests \
    -only-testing:InstantBookReaderTests/SafeColumnTests \
    -only-testing:InstantBookReaderTests/PageModeEPUBCSSTests \
    -only-testing:InstantBookReaderTests/PageModeEPUBPaginationTests \
    -only-testing:InstantBookReaderTests/PDFDarkModeTests \
    -only-testing:InstantBookReaderTests/IdleWatcherTests 2>&1 | tail -20
```
Expected: all six suites pass.

- [ ] **Step 2: Run the full suite to confirm no regressions in Plans 1–5**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: no failures.

- [ ] **Step 3: Final commit if any fixups landed**

If the runs were clean, no commit is needed. Otherwise commit fix-ups under `fix(mac/page): …`.

---

## Spec coverage

| Spec section | Tasks |
|---|---|
| §6.1 Advance model (static + ⌃⌥→ / ⌃⌥←) | Tasks 6, 7, 17 |
| §6.2 Typography (22pt physical, log curve 13→27→32) | Tasks 2, 3 |
| §6.3 Safe column (720pt, L/C/R, 200pt right reserve) | Tasks 4, 5 |
| §6.4 PDF page mode (light live, dark CI invert + hue) | Tasks 8, 9, 10 |
| §6.5 EPUB page mode (reuse extension flatten, inject CSS, height-paginate) | Tasks 11, 12, 13, 14 |
| §6.6 Idle behavior (10min → crossfade to ambient, mouse → back) | Tasks 18, 19, 20 |
| §6 multi-monitor (same page every screen) | Task 16 — `PageModeRouter` is per-window; no cross-screen state |
| TXT branch (implied by Book.format coverage) | Task 15 |
| Coexistence with Plan 5 (atomic vs page in same coordinator) | Task 16 step 2 |

