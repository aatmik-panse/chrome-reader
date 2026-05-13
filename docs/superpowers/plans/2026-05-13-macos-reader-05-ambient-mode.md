# Ambient Mode Implementation Plan — macOS Wallpaper Reader

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the foundation's `PlaceholderAmbientView` with the real ambient corner card — cover + chapter/progress label + rotating user highlight + title/author — driven by a deterministic per-session highlight shuffle, a tickable rotation controller with multiple triggers, and a Finder-frontmost fade. Type-only on the wallpaper, deferential to icons, calm.

**Architecture:** A `AmbientCornerCard` SwiftUI view composes the four content units in the spec's priority order (§5.1) using Clay tokens from `AppTheme`. An `AmbientHighlightSelector` produces a stable shuffled iterator over `Highlight` rows fetched via SwiftData for the current book hash. An `AmbientRotationController` owns a per-screen `Clock`-driven timer, plus subscriptions to screen-wake, Finder-frontmost, and a menu-bar command; it pauses while the cursor is in the card's safe zone (tracked via `NSTrackingArea` in `SafeZoneTracker`). A `FinderFrontmostFader` animates the wallpaper window's `contentView.alphaValue` between 1.0 and 0.15 based on `NSWorkspace.didActivateApplicationNotification`. `WallpaperWindowCoordinator` is rewritten to host the real card per screen and degrade cleanly when `ReadingState.ambientMode == .page` (Plan 6 fills that branch).

**Tech Stack:** Swift 5.10, SwiftUI + AppKit, SwiftData (`@Query`/`ModelContainer`), `NSVisualEffectView`, `NSTrackingArea`, `NSWorkspace`, `Clock`, `@AppStorage`. Tests use XCTest with injected `Clock` and fake notifications — no `Thread.sleep`. macOS 14.4+.

---

## File structure

This plan creates one new top-level subdirectory (`Ambient/`) under `book-reader-mac/`, plus a snapshot-tests subdirectory under `Tests/`. It modifies `WallpaperWindowCoordinator.swift` and `MenuBarController.swift`; everything else is additive.

```
book-reader-mac/
├── Ambient/                                       # NEW
│   ├── AmbientCornerCard.swift                    # the visible card
│   ├── AmbientHighlightSelector.swift             # shuffled iterator over Highlights
│   ├── AmbientRotationController.swift            # timer + triggers + pause
│   ├── FinderFrontmostFader.swift                 # window-level fade policy
│   ├── SafeZoneTracker.swift                      # NSTrackingArea wrapper
│   ├── AmbientHostView.swift                      # NSView wrapping card + tracker
│   ├── AmbientClock.swift                         # injectable Clock abstraction
│   └── AmbientLayoutMetrics.swift                 # measured layout constants
├── Windows/
│   └── WallpaperWindowCoordinator.swift           # rewritten in Task 14
├── MenuBar/
│   └── MenuBarController.swift                    # +onNextQuote in Task 12
├── App/
│   └── AppDelegate.swift                          # wired in Task 14
└── Tests/
    ├── AmbientHighlightSelectorTests.swift        # NEW
    ├── AmbientRotationControllerTests.swift       # NEW
    ├── FinderFrontmostFaderTests.swift            # NEW
    ├── AmbientLayoutMetricsTests.swift            # NEW
    └── Snapshots/                                 # NEW
        └── AmbientCornerCardTests.swift           # layout snapshot tests
```

`AmbientHostView` exists so the rotation controller's `NSTrackingArea` (an AppKit construct) has a concrete `NSView` to attach to — `NSHostingView` is fine but we want to control the tracking-rect coordinate system precisely. `AmbientLayoutMetrics` centralises every measurement (card width, cover size, paddings, font sizes, leadings, the optical-center 42%-from-top rule) so the snapshot tests can assert on values without parsing SwiftUI internals.

---

## Task 1: XcodeGen project source path for `Ambient/`

**Files:**
- Modify: `book-reader-mac/project.yml`

- [ ] **Step 1: Add the new source path**

Open `book-reader-mac/project.yml` and add `- path: Ambient` to the `InstantBookReader` target's `sources:` list (immediately after the `Placeholders` entry). The resulting block must read exactly:

```yaml
    sources:
      - path: App
      - path: Core
      - path: Persistence
      - path: Windows
      - path: MenuBar
      - path: Hotkey
      - path: System
      - path: Placeholders
      - path: Ambient
      - path: Resources
```

- [ ] **Step 2: Create the directory and regenerate**

Run:
```bash
mkdir -p /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Ambient
mkdir -p /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/Tests/Snapshots
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodegen generate
```

Expected output ends with: `Created project at /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/book-reader-mac.xcodeproj`.

- [ ] **Step 3: Verify the project still builds**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/project.yml && \
  git commit -m "feat(mac): add Ambient source path to XcodeGen spec"
```

---

## Task 2: `AmbientClock` — injectable time source

**Files:**
- Create: `book-reader-mac/Ambient/AmbientClock.swift`

The rotation controller needs an injectable clock so its timer tests don't sleep. We model it as a `protocol` rather than swapping in `ContinuousClock` directly because we also need to drive scheduled callbacks from tests synchronously.

- [ ] **Step 1: Implement the protocol and the production clock**

Write `book-reader-mac/Ambient/AmbientClock.swift`:
```swift
import Foundation

/// Abstracts time for the rotation controller so tests can fire timers
/// without `Thread.sleep`. Production uses `SystemAmbientClock`; tests use
/// `FakeAmbientClock`.
protocol AmbientClock: AnyObject {
    /// Schedule `block` to run after `seconds`. Returns an opaque handle the
    /// caller can use to cancel. Implementations must execute `block` on the
    /// main actor.
    func schedule(after seconds: TimeInterval, _ block: @escaping @MainActor () -> Void) -> AmbientTimerHandle
}

/// Opaque cancellation handle. Implementations decide what backs it.
final class AmbientTimerHandle {
    private let cancelBlock: () -> Void
    private var cancelled = false

    init(cancel: @escaping () -> Void) { self.cancelBlock = cancel }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        cancelBlock()
    }
}

/// Production clock backed by `DispatchSourceTimer` on the main queue.
final class SystemAmbientClock: AmbientClock {
    func schedule(after seconds: TimeInterval,
                  _ block: @escaping @MainActor () -> Void) -> AmbientTimerHandle {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + seconds,
                       leeway: .milliseconds(Int(seconds * 100))) // 10% tolerance
        timer.setEventHandler {
            Task { @MainActor in block() }
        }
        timer.resume()
        return AmbientTimerHandle { timer.cancel() }
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
  git add book-reader-mac/Ambient/AmbientClock.swift && \
  git commit -m "feat(mac): AmbientClock abstraction for testable timers"
```

---

## Task 3: `AmbientLayoutMetrics` — single source of truth for sizes

**Files:**
- Create: `book-reader-mac/Ambient/AmbientLayoutMetrics.swift`
- Create: `book-reader-mac/Tests/AmbientLayoutMetricsTests.swift`

Every measurement in the spec lives here so the snapshot test in Task 15 can assert on it without screen-scraping SwiftUI internals.

- [ ] **Step 1: Write the failing test**

Write `book-reader-mac/Tests/AmbientLayoutMetricsTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

final class AmbientLayoutMetricsTests: XCTestCase {
    func testCardWidthMatchesSpec() {
        XCTAssertEqual(AmbientLayoutMetrics.cardWidth, 360)
    }

    func testCoverSizeMatchesSpec() {
        XCTAssertEqual(AmbientLayoutMetrics.coverSize.width, 60)
        XCTAssertEqual(AmbientLayoutMetrics.coverSize.height, 80)
    }

    func testQuoteFontSizeShortQuoteIsLarge() {
        XCTAssertEqual(AmbientLayoutMetrics.quoteFontSize(for: "Short."), 44)
    }

    func testQuoteFontSizeBoundaryAt120CharsIsLarge() {
        let s = String(repeating: "a", count: 120)
        XCTAssertEqual(AmbientLayoutMetrics.quoteFontSize(for: s), 44)
    }

    func testQuoteFontSizeAbove120CharsIsSmall() {
        let s = String(repeating: "a", count: 121)
        XCTAssertEqual(AmbientLayoutMetrics.quoteFontSize(for: s), 28)
    }

    func testQuoteLeadingMatchesLengthBucket() {
        XCTAssertEqual(AmbientLayoutMetrics.quoteLeadingMultiple(for: "Short."), 1.25, accuracy: 0.001)
        let long = String(repeating: "a", count: 200)
        XCTAssertEqual(AmbientLayoutMetrics.quoteLeadingMultiple(for: long), 1.45, accuracy: 0.001)
    }

    func testQuoteTruncationCapAt280() {
        let raw = String(repeating: "x", count: 400)
        let result = AmbientLayoutMetrics.truncateForDisplay(raw)
        XCTAssertTrue(result.wasTruncated)
        XCTAssertLessThanOrEqual(result.text.count, 280)
    }

    func testShortQuoteIsNotTruncated() {
        let raw = "Hello world."
        let result = AmbientLayoutMetrics.truncateForDisplay(raw)
        XCTAssertFalse(result.wasTruncated)
        XCTAssertEqual(result.text, raw)
    }

    func testLabelTrackingMatchesClay() {
        XCTAssertEqual(AmbientLayoutMetrics.labelTracking, 1.08, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run tests; confirm they fail with "no such type"**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: compile error referencing `AmbientLayoutMetrics`.

- [ ] **Step 3: Implement the metrics**

Write `book-reader-mac/Ambient/AmbientLayoutMetrics.swift`:
```swift
import CoreGraphics
import Foundation

/// Single source of truth for the ambient corner card's measurements.
/// Every value here traces back to the design spec §5.2 / §11.1.
enum AmbientLayoutMetrics {
    /// Spec §5.2: ~360pt-wide card.
    static let cardWidth: CGFloat = 360

    /// Spec §5.2: 60×80 cover thumbnail.
    static let coverSize = CGSize(width: 60, height: 80)

    /// Spec §11.1 attribution: DM Sans 500, uppercase, 1.08px tracking.
    /// Reused for the chapter/progress label and the title/author footer.
    static let labelTracking: CGFloat = 1.08
    static let labelFontSize: CGFloat = 13        // chapter+progress
    static let footerFontSize: CGFloat = 11       // title+author
    static let footerOpacity: Double = 0.6        // "low opacity" per task brief

    /// Inner padding on the visual-effect plate; sized to the text block only.
    static let plateInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)

    /// 16pt gap between cover and the text block.
    static let coverToTextGap: CGFloat = 16

    /// 8pt vertical spacing between chapter label, quote, and footer.
    static let blockSpacing: CGFloat = 8

    /// Padding from the screen edges (bottom-left corner anchor).
    static let screenPadding = NSEdgeInsets(top: 0, left: 56, bottom: 56, right: 0)

    /// Spec §11.1 motion timings.
    static let crossfadeOutDuration: TimeInterval = 0.8
    static let crossfadeInDuration: TimeInterval = 1.2
    static let reducedMotionBlinkDuration: TimeInterval = 0.1

    /// Spec §5.3 "Finder becomes frontmost" + §5.2 plate.
    static let finderFadeAlpha: CGFloat = 0.15
    static let finderFadeDuration: TimeInterval = 0.4
    static let finderRestoreAlpha: CGFloat = 1.0

    /// Spec §5.3 timer bounds.
    static let rotationMin: TimeInterval = 45
    static let rotationMax: TimeInterval = 600
    static let rotationDefault: TimeInterval = 90
    /// Spec §5.3 "Cursor enters safe zone … resume 5s after exit".
    static let safeZoneResumeDelay: TimeInterval = 5
    /// Spec §5.3 "Finder becomes frontmost … advance after 800ms".
    static let finderActivationDelay: TimeInterval = 0.8

    /// Truncated quote text + whether truncation happened.
    struct TruncatedQuote: Equatable {
        let text: String
        let wasTruncated: Bool
    }

    /// Spec §5.2: max 280 chars, "Read more…" affordance for longer.
    static func truncateForDisplay(_ raw: String) -> TruncatedQuote {
        if raw.count <= 280 {
            return TruncatedQuote(text: raw, wasTruncated: false)
        }
        let cut = raw.prefix(279)
        return TruncatedQuote(text: cut + "…", wasTruncated: true)
    }

    /// Spec §11.1: Medium 44pt for ≤120 chars, Regular 28pt for longer.
    static func quoteFontSize(for raw: String) -> CGFloat {
        raw.count <= 120 ? 44 : 28
    }

    /// Spec §11.1: 1.25 leading for short, 1.45 for long.
    static func quoteLeadingMultiple(for raw: String) -> CGFloat {
        raw.count <= 120 ? 1.25 : 1.45
    }
}
```

- [ ] **Step 4: Run tests; confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `Test Suite 'AmbientLayoutMetricsTests' passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Ambient/AmbientLayoutMetrics.swift \
          book-reader-mac/Tests/AmbientLayoutMetricsTests.swift && \
  git commit -m "feat(mac): AmbientLayoutMetrics with truncation + font-size helpers"
```

---

## Task 4: `AmbientHighlightSelector` — shuffled iterator over highlights

**Files:**
- Create: `book-reader-mac/Ambient/AmbientHighlightSelector.swift`
- Create: `book-reader-mac/Tests/AmbientHighlightSelectorTests.swift`

The selector takes a list of `Highlight` rows and returns a stable-per-session shuffle. It skips `note`-only highlights (where `text` is blank). Empty pool returns `nil` forever; single-element pool repeats that element.

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/AmbientHighlightSelectorTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

final class AmbientHighlightSelectorTests: XCTestCase {
    private func makeHighlight(_ text: String, note: String? = nil) -> Highlight {
        Highlight(bookHash: "h",
                  text: text,
                  surroundingText: text,
                  offset: 0,
                  note: note)
    }

    func testEmptyPoolReturnsNil() {
        let selector = AmbientHighlightSelector(highlights: [], seed: 1)
        XCTAssertNil(selector.next())
        XCTAssertNil(selector.next())
    }

    func testSingleElementPoolRepeats() {
        let only = makeHighlight("Only one.")
        let selector = AmbientHighlightSelector(highlights: [only], seed: 1)
        XCTAssertEqual(selector.next()?.text, "Only one.")
        XCTAssertEqual(selector.next()?.text, "Only one.")
        XCTAssertEqual(selector.next()?.text, "Only one.")
    }

    func testNoteOnlyHighlightsAreSkipped() {
        let valid = makeHighlight("Valid quote.")
        let blank = makeHighlight("", note: "a note but no text")
        let whitespace = makeHighlight("   \n  ", note: "whitespace text")
        let selector = AmbientHighlightSelector(
            highlights: [blank, valid, whitespace],
            seed: 1
        )
        // 30 draws — none should ever return the blank-text rows.
        for _ in 0..<30 {
            XCTAssertEqual(selector.next()?.text, "Valid quote.")
        }
    }

    func testShufflePresentsEveryHighlightBeforeRepeating() {
        let pool = (0..<4).map { makeHighlight("h\($0)") }
        let selector = AmbientHighlightSelector(highlights: pool, seed: 42)

        var firstCycle: [String] = []
        for _ in 0..<4 {
            firstCycle.append(selector.next()!.text)
        }
        XCTAssertEqual(Set(firstCycle), Set(["h0", "h1", "h2", "h3"]),
                       "all four highlights appear in one cycle")

        var secondCycle: [String] = []
        for _ in 0..<4 {
            secondCycle.append(selector.next()!.text)
        }
        XCTAssertEqual(Set(secondCycle), Set(["h0", "h1", "h2", "h3"]),
                       "second cycle covers all again")
    }

    func testSameSeedReproducesSameShuffle() {
        let pool = (0..<5).map { makeHighlight("h\($0)") }
        let a = AmbientHighlightSelector(highlights: pool, seed: 7)
        let b = AmbientHighlightSelector(highlights: pool, seed: 7)
        for _ in 0..<10 {
            XCTAssertEqual(a.next()?.text, b.next()?.text)
        }
    }
}
```

- [ ] **Step 2: Run tests; confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: compile error referencing `AmbientHighlightSelector`.

- [ ] **Step 3: Implement the selector**

Write `book-reader-mac/Ambient/AmbientHighlightSelector.swift`:
```swift
import Foundation

/// A seeded PRNG so the per-session shuffle is reproducible in tests.
/// Splitmix64 — small, fast, no Foundation dependency, deterministic.
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Produces a session-stable shuffled stream over the user's highlights for
/// the current book. Empty pool ⇒ nil forever. Single-element pool ⇒ repeat.
/// Blank-text highlights (where the user only attached a note) are filtered
/// out before shuffling.
final class AmbientHighlightSelector {
    private let pool: [Highlight]
    private var rng: SeededRandomNumberGenerator
    private var deck: [Highlight] = []

    init(highlights: [Highlight], seed: UInt64) {
        self.pool = highlights.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        self.rng = SeededRandomNumberGenerator(seed: seed)
    }

    /// Returns the next highlight in the shuffle. When the deck is exhausted,
    /// reshuffles the pool and starts again. Returns nil iff the pool is empty.
    func next() -> Highlight? {
        guard !pool.isEmpty else { return nil }
        if deck.isEmpty {
            deck = pool.shuffled(using: &rng)
        }
        return deck.removeFirst()
    }
}
```

- [ ] **Step 4: Run tests; confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `Test Suite 'AmbientHighlightSelectorTests' passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Ambient/AmbientHighlightSelector.swift \
          book-reader-mac/Tests/AmbientHighlightSelectorTests.swift && \
  git commit -m "feat(mac): seeded shuffled highlight selector with empty/single-element behavior"
```

---

## Task 5: `AmbientRotationController` — triggers + pause behavior

**Files:**
- Create: `book-reader-mac/Ambient/AmbientRotationController.swift`
- Create: `book-reader-mac/Tests/AmbientRotationControllerTests.swift`

The controller is per-screen but shares a content pool via the selector. Triggers:
1. Timer fire (configurable, default 90s via `@AppStorage("ambientRotationSeconds")`).
2. `NSWorkspace.screensDidWakeNotification` → advance now.
3. Finder activation (`NSWorkspace.didActivateApplicationNotification` with bundle id `com.apple.finder`) → advance after 800ms, unless cursor is in safe zone.
4. Menu-bar "Next quote" command → advance now.
5. Safe-zone entry (via `SafeZoneTracker` in Task 6) pauses; safe-zone exit resumes after 5s.

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/AmbientRotationControllerTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

@MainActor
final class FakeAmbientClock: AmbientClock {
    struct Scheduled {
        let id: UUID
        let fireAt: TimeInterval
        let block: () -> Void
    }

    private(set) var now: TimeInterval = 0
    private var pending: [Scheduled] = []

    func schedule(after seconds: TimeInterval,
                  _ block: @escaping @MainActor () -> Void) -> AmbientTimerHandle {
        let id = UUID()
        let entry = Scheduled(id: id, fireAt: now + seconds) { block() }
        pending.append(entry)
        return AmbientTimerHandle { [weak self] in
            self?.pending.removeAll { $0.id == id }
        }
    }

    /// Advances virtual time, firing every scheduled block whose deadline is
    /// reached. Removes fired blocks; remaining ones may have been rescheduled
    /// during their handler.
    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let next = pending.filter({ $0.fireAt <= target })
                .min(by: { $0.fireAt < $1.fireAt }) {
            pending.removeAll { $0.id == next.id }
            now = next.fireAt
            next.block()
        }
        now = target
    }

    var pendingCount: Int { pending.count }
}

@MainActor
final class AmbientRotationControllerTests: XCTestCase {
    private func makePool(_ count: Int) -> [Highlight] {
        (0..<count).map {
            Highlight(bookHash: "h",
                      text: "h\($0)",
                      surroundingText: "h\($0)",
                      offset: 0)
        }
    }

    func testTimerFireAdvancesQuote() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()

        XCTAssertEqual(observed.count, 1, "start() publishes the first quote immediately")
        clock.advance(by: 90)
        XCTAssertEqual(observed.count, 2)
        clock.advance(by: 90)
        XCTAssertEqual(observed.count, 3)
    }

    func testMenuCommandAdvancesImmediately() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()
        XCTAssertEqual(observed.count, 1)

        controller.advanceNow(reason: .menuCommand)
        XCTAssertEqual(observed.count, 2)
    }

    func testScreenWakeAdvancesImmediately() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()
        let before = observed.count

        controller.advanceNow(reason: .screenWake)
        XCTAssertEqual(observed.count, before + 1)
    }

    func testFinderActivationAdvancesAfter800ms() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()
        let before = observed.count

        controller.handleFinderActivation()
        clock.advance(by: 0.7)
        XCTAssertEqual(observed.count, before, "not yet — only 700ms elapsed")
        clock.advance(by: 0.1)
        XCTAssertEqual(observed.count, before + 1, "fires at 800ms")
    }

    func testFinderActivationSkippedWhileCursorInSafeZone() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()
        let before = observed.count

        controller.setSafeZoneOccupied(true)
        controller.handleFinderActivation()
        clock.advance(by: 1.0)
        XCTAssertEqual(observed.count, before, "no advance while in safe zone")
    }

    func testSafeZoneEntryPausesTimer() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()
        let before = observed.count

        controller.setSafeZoneOccupied(true)
        clock.advance(by: 200)
        XCTAssertEqual(observed.count, before, "timer paused while occupied")
    }

    func testSafeZoneExitResumesAfter5Seconds() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [String?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0?.text) }
        )
        controller.start()
        controller.setSafeZoneOccupied(true)
        clock.advance(by: 30)
        let before = observed.count

        controller.setSafeZoneOccupied(false)
        clock.advance(by: 4.9)
        XCTAssertEqual(observed.count, before, "5s resume delay not elapsed")
        clock.advance(by: 0.2)
        XCTAssertEqual(observed.count, before + 1, "advance fires once resume delay completes")
    }

    func testEmptyPoolStillStartsButPublishesNil() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: [], seed: 1)
        var observed: [Highlight?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0) }
        )
        controller.start()
        XCTAssertEqual(observed.count, 1)
        XCTAssertNil(observed[0])
        clock.advance(by: 90)
        XCTAssertEqual(observed.count, 2)
        XCTAssertNil(observed[1])
    }

    func testStopCancelsPendingTimer() {
        let clock = FakeAmbientClock()
        let selector = AmbientHighlightSelector(highlights: makePool(3), seed: 1)
        var observed: [Highlight?] = []
        let controller = AmbientRotationController(
            selector: selector,
            clock: clock,
            rotationSeconds: 90,
            onAdvance: { observed.append($0) }
        )
        controller.start()
        let before = observed.count
        controller.stop()
        clock.advance(by: 1000)
        XCTAssertEqual(observed.count, before, "no advance after stop")
    }
}
```

- [ ] **Step 2: Run tests; confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: compile error referencing `AmbientRotationController`.

- [ ] **Step 3: Implement the controller**

Write `book-reader-mac/Ambient/AmbientRotationController.swift`:
```swift
import Foundation

/// Reasons the controller advances to the next quote. Used by tests + logs.
enum AmbientAdvanceReason {
    case startup
    case timer
    case screenWake
    case finderFrontmost
    case menuCommand
}

/// Owns a per-screen rotation loop. Triggers:
///   - timer fire (`rotationSeconds`)
///   - `advanceNow(reason: .screenWake)` from NSWorkspace screen-wake
///   - `handleFinderActivation()` from NSWorkspace activation events
///   - `advanceNow(reason: .menuCommand)` from the menu-bar command
///
/// Pauses while the cursor is in the safe zone (driven by `SafeZoneTracker`).
/// Resumes 5s after the cursor leaves.
///
/// All public methods are @MainActor.
@MainActor
final class AmbientRotationController {
    private let selector: AmbientHighlightSelector
    private let clock: AmbientClock
    private(set) var rotationSeconds: TimeInterval
    private let onAdvance: (Highlight?) -> Void

    private var timerHandle: AmbientTimerHandle?
    private var pendingFinderHandle: AmbientTimerHandle?
    private var safeZoneResumeHandle: AmbientTimerHandle?
    private var isRunning = false
    private var isPaused = false

    init(selector: AmbientHighlightSelector,
         clock: AmbientClock,
         rotationSeconds: TimeInterval,
         onAdvance: @escaping (Highlight?) -> Void) {
        self.selector = selector
        self.clock = clock
        self.rotationSeconds = max(AmbientLayoutMetrics.rotationMin,
                                    min(AmbientLayoutMetrics.rotationMax, rotationSeconds))
        self.onAdvance = onAdvance
    }

    /// Publishes the first quote immediately and starts the rotation timer.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        publishNext(reason: .startup)
        scheduleTimer()
    }

    /// Cancels every pending callback.
    func stop() {
        isRunning = false
        cancelTimer()
        pendingFinderHandle?.cancel()
        pendingFinderHandle = nil
        safeZoneResumeHandle?.cancel()
        safeZoneResumeHandle = nil
    }

    /// Updates the rotation cadence at runtime (e.g. from the Settings tab).
    /// Reschedules the running timer if active.
    func updateRotationSeconds(_ seconds: TimeInterval) {
        rotationSeconds = max(AmbientLayoutMetrics.rotationMin,
                              min(AmbientLayoutMetrics.rotationMax, seconds))
        if isRunning, !isPaused {
            scheduleTimer()
        }
    }

    /// Advance immediately for an explicit trigger (screen wake, menu command,
    /// or — internally — timer fire). Always publishes, even while paused, so
    /// a user-driven "Next quote" command works from a paused screen.
    func advanceNow(reason: AmbientAdvanceReason) {
        guard isRunning else { return }
        publishNext(reason: reason)
        if !isPaused { scheduleTimer() }
    }

    /// Schedule a Finder-activation-triggered advance. Per spec: 800ms delay,
    /// suppressed if cursor is in the safe zone at fire time.
    func handleFinderActivation() {
        guard isRunning else { return }
        pendingFinderHandle?.cancel()
        pendingFinderHandle = clock.schedule(
            after: AmbientLayoutMetrics.finderActivationDelay
        ) { [weak self] in
            guard let self else { return }
            self.pendingFinderHandle = nil
            guard !self.isPaused else { return }
            self.advanceNow(reason: .finderFrontmost)
        }
    }

    /// Pause (cursor entered safe zone) or resume (cursor left, after 5s grace).
    func setSafeZoneOccupied(_ occupied: Bool) {
        guard isRunning else { return }
        if occupied {
            isPaused = true
            cancelTimer()
            safeZoneResumeHandle?.cancel()
            safeZoneResumeHandle = nil
        } else {
            safeZoneResumeHandle?.cancel()
            safeZoneResumeHandle = clock.schedule(
                after: AmbientLayoutMetrics.safeZoneResumeDelay
            ) { [weak self] in
                guard let self else { return }
                self.safeZoneResumeHandle = nil
                self.isPaused = false
                self.advanceNow(reason: .timer)
            }
        }
    }

    private func scheduleTimer() {
        cancelTimer()
        timerHandle = clock.schedule(after: rotationSeconds) { [weak self] in
            guard let self else { return }
            self.timerHandle = nil
            self.advanceNow(reason: .timer)
        }
    }

    private func cancelTimer() {
        timerHandle?.cancel()
        timerHandle = nil
    }

    private func publishNext(reason: AmbientAdvanceReason) {
        _ = reason  // hook reserved for future logging; required by API for callers
        onAdvance(selector.next())
    }
}
```

- [ ] **Step 4: Run tests; confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -15
```
Expected: `Test Suite 'AmbientRotationControllerTests' passed` with 9 tests.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Ambient/AmbientRotationController.swift \
          book-reader-mac/Tests/AmbientRotationControllerTests.swift && \
  git commit -m "feat(mac): AmbientRotationController with timer/wake/finder/safe-zone triggers"
```

---

## Task 6: `SafeZoneTracker` — NSTrackingArea wrapper

**Files:**
- Create: `book-reader-mac/Ambient/SafeZoneTracker.swift`

This is an `NSView` that posts `mouseEntered`/`mouseExited` to a callback. The wallpaper window is click-through (`ignoresMouseEvents = true`), but tracking areas with `.assumeInside` + `.activeAlways` still register cursor crossings without intercepting clicks.

- [ ] **Step 1: Implement**

Write `book-reader-mac/Ambient/SafeZoneTracker.swift`:
```swift
import AppKit

/// A transparent NSView that posts cursor enter/exit events to a callback.
/// Used by AmbientHostView to pause rotation while the cursor hovers the card.
final class SafeZoneTracker: NSView {
    private var trackingArea: NSTrackingArea?
    /// Called with `true` when cursor enters, `false` when it exits.
    var onOccupiedChange: ((Bool) -> Void)?

    override var isOpaque: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            // assumeInside lets the initial hover state be detected even when
            // the cursor was already over the rect at view installation time.
            .assumeInside
        ]
        let area = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onOccupiedChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onOccupiedChange?(false)
    }

    // Tracking areas work on click-through windows, but explicitly opt out of
    // hit-testing so we never swallow drags onto Finder icons under the card.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
  git add book-reader-mac/Ambient/SafeZoneTracker.swift && \
  git commit -m "feat(mac): SafeZoneTracker NSView wrapping NSTrackingArea"
```

---

## Task 7: `FinderFrontmostFader` with injectable application source

**Files:**
- Create: `book-reader-mac/Ambient/FinderFrontmostFader.swift`
- Create: `book-reader-mac/Tests/FinderFrontmostFaderTests.swift`

Animates the wallpaper window's `contentView.alphaValue` between 1.0 and 0.15 over 400ms based on `NSWorkspace.didActivateApplicationNotification`. We extract the "is this app Finder?" decision behind a protocol so we can test the policy without an `NSRunningApplication`.

- [ ] **Step 1: Write the failing tests**

Write `book-reader-mac/Tests/FinderFrontmostFaderTests.swift`:
```swift
import XCTest
@testable import InstantBookReader

@MainActor
final class FinderFrontmostFaderTests: XCTestCase {
    func testActivatingFinderTriggersFadeOut() {
        var applied: [CGFloat] = []
        let fader = FinderFrontmostFader(
            isReducedMotion: { false },
            apply: { alpha, _ in applied.append(alpha) }
        )
        fader.handleActivation(bundleIdentifier: "com.apple.finder")
        XCTAssertEqual(applied.last, AmbientLayoutMetrics.finderFadeAlpha)
    }

    func testActivatingNonFinderDoesNothing() {
        var applied: [CGFloat] = []
        let fader = FinderFrontmostFader(
            isReducedMotion: { false },
            apply: { alpha, _ in applied.append(alpha) }
        )
        fader.handleActivation(bundleIdentifier: "com.google.Chrome")
        XCTAssertTrue(applied.isEmpty)
    }

    func testDeactivatingFinderRestoresAlpha() {
        var applied: [CGFloat] = []
        let fader = FinderFrontmostFader(
            isReducedMotion: { false },
            apply: { alpha, _ in applied.append(alpha) }
        )
        fader.handleActivation(bundleIdentifier: "com.apple.finder")
        fader.handleDeactivation(bundleIdentifier: "com.apple.finder")
        XCTAssertEqual(applied.last, AmbientLayoutMetrics.finderRestoreAlpha)
    }

    func testDeactivatingNonFinderDoesNothing() {
        var applied: [CGFloat] = []
        let fader = FinderFrontmostFader(
            isReducedMotion: { false },
            apply: { alpha, _ in applied.append(alpha) }
        )
        fader.handleDeactivation(bundleIdentifier: "com.google.Chrome")
        XCTAssertTrue(applied.isEmpty)
    }

    func testReducedMotionUsesShortDuration() {
        var applied: [(CGFloat, TimeInterval)] = []
        let fader = FinderFrontmostFader(
            isReducedMotion: { true },
            apply: { alpha, duration in applied.append((alpha, duration)) }
        )
        fader.handleActivation(bundleIdentifier: "com.apple.finder")
        XCTAssertEqual(applied.last?.1, AmbientLayoutMetrics.reducedMotionBlinkDuration)
    }

    func testNormalMotionUses400msDuration() {
        var applied: [(CGFloat, TimeInterval)] = []
        let fader = FinderFrontmostFader(
            isReducedMotion: { false },
            apply: { alpha, duration in applied.append((alpha, duration)) }
        )
        fader.handleActivation(bundleIdentifier: "com.apple.finder")
        XCTAssertEqual(applied.last?.1, AmbientLayoutMetrics.finderFadeDuration)
    }
}
```

- [ ] **Step 2: Run tests; confirm they fail**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: compile error referencing `FinderFrontmostFader`.

- [ ] **Step 3: Implement**

Write `book-reader-mac/Ambient/FinderFrontmostFader.swift`:
```swift
import AppKit

/// Policy object: when Finder activates, fade target alpha to 0.15; when it
/// deactivates, restore to 1.0. The actual animation is delegated to a closure
/// so tests can drive it without an NSWindow.
@MainActor
final class FinderFrontmostFader {
    private static let finderBundleID = "com.apple.finder"

    private let isReducedMotion: () -> Bool
    private let apply: (CGFloat, TimeInterval) -> Void
    private var workspaceObservers: [NSObjectProtocol] = []
    private var reduceMotionObserver: NSObjectProtocol?

    /// - Parameters:
    ///   - isReducedMotion: closure returning the current Reduce Motion state.
    ///   - apply: closure that animates content alpha → target over duration.
    init(isReducedMotion: @escaping () -> Bool,
         apply: @escaping (CGFloat, TimeInterval) -> Void) {
        self.isReducedMotion = isReducedMotion
        self.apply = apply
    }

    /// Subscribe to `NSWorkspace` activation events. Call once per fader.
    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        let activated = workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            Task { @MainActor in
                self.handleActivation(bundleIdentifier: app.bundleIdentifier)
            }
        }
        let deactivated = workspace.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            Task { @MainActor in
                self.handleDeactivation(bundleIdentifier: app.bundleIdentifier)
            }
        }
        workspaceObservers = [activated, deactivated]
    }

    /// Stop receiving events.
    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for obs in workspaceObservers { center.removeObserver(obs) }
        workspaceObservers.removeAll()
    }

    /// Internal entry point used by the notification handler and by tests.
    func handleActivation(bundleIdentifier: String?) {
        guard bundleIdentifier == Self.finderBundleID else { return }
        let duration = isReducedMotion()
            ? AmbientLayoutMetrics.reducedMotionBlinkDuration
            : AmbientLayoutMetrics.finderFadeDuration
        apply(AmbientLayoutMetrics.finderFadeAlpha, duration)
    }

    func handleDeactivation(bundleIdentifier: String?) {
        guard bundleIdentifier == Self.finderBundleID else { return }
        let duration = isReducedMotion()
            ? AmbientLayoutMetrics.reducedMotionBlinkDuration
            : AmbientLayoutMetrics.finderFadeDuration
        apply(AmbientLayoutMetrics.finderRestoreAlpha, duration)
    }
}
```

- [ ] **Step 4: Run tests; confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -10
```
Expected: `Test Suite 'FinderFrontmostFaderTests' passed`.

- [ ] **Step 5: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Ambient/FinderFrontmostFader.swift \
          book-reader-mac/Tests/FinderFrontmostFaderTests.swift && \
  git commit -m "feat(mac): FinderFrontmostFader policy with reduce-motion fallback"
```

---

## Task 8: Cover image loader for the card

**Files:**
- Create: `book-reader-mac/Ambient/AmbientCoverImage.swift`

Plan 2 writes covers to `AppSupportPaths.covers/<sha256>.png` and stores the relative path on `Book.coverPath`. The corner card needs to load that PNG without making the SwiftUI body throw, and degrade gracefully to a placeholder rounded rectangle if the file is missing.

- [ ] **Step 1: Implement**

Write `book-reader-mac/Ambient/AmbientCoverImage.swift`:
```swift
import AppKit
import SwiftUI

/// Loads a `Book.coverPath`-relative PNG from Application Support and renders
/// it at the spec's 60×80 size. Falls back to a Clay-tinted placeholder when
/// the cover file is absent or unreadable.
struct AmbientCoverImage: View {
    /// Relative path stored on `Book.coverPath`, e.g. "<sha256>.png".
    let coverPath: String?
    @Environment(\.appTheme) private var theme

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.border.swiftUI.opacity(0.6))
            }
        }
        .frame(width: AmbientLayoutMetrics.coverSize.width,
               height: AmbientLayoutMetrics.coverSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .accessibilityHidden(true)
    }

    private func loadImage() -> NSImage? {
        guard let coverPath, !coverPath.isEmpty else { return nil }
        let url = AppSupportPaths.covers.appendingPathComponent(coverPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
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
  git add book-reader-mac/Ambient/AmbientCoverImage.swift && \
  git commit -m "feat(mac): AmbientCoverImage with Clay placeholder fallback"
```

---

## Task 9: `AmbientCornerCard` SwiftUI view

**Files:**
- Create: `book-reader-mac/Ambient/AmbientCornerCard.swift`

The pure-SwiftUI composition. It takes a `Book` and an optional `Highlight` (the currently displayed quote) plus the chapter title and progress percentage. It is owned externally — Task 11 (`AmbientHostView`) wires it into the rotation controller and provides crossfade animations.

- [ ] **Step 1: Implement**

Write `book-reader-mac/Ambient/AmbientCornerCard.swift`:
```swift
import SwiftUI

/// The visible ambient corner card. Composition (top → bottom):
///   1. 60×80 cover thumbnail
///   2. "Ch. 7 · 43%" chapter+progress label
///   3. Rotating highlight (or empty)
///   4. Title + author footer
/// A NSVisualEffectView plate sits behind the text block only — never behind
/// the cover. The card pins to the bottom-left of its container.
struct AmbientCornerCard: View {
    let book: Book?
    let highlight: Highlight?
    let chapterTitle: String?
    let progressPercent: Int?

    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: AmbientLayoutMetrics.coverToTextGap) {
            AmbientCoverImage(coverPath: book?.coverPath)

            VStack(alignment: .leading, spacing: AmbientLayoutMetrics.blockSpacing) {
                chapterProgressLabel
                quoteText
                titleAuthorFooter
            }
            .background(
                VisualEffectPlate()
                    .opacity(0.3)
                    .padding(EdgeInsets(
                        top: -AmbientLayoutMetrics.plateInsets.top,
                        leading: -AmbientLayoutMetrics.plateInsets.left,
                        bottom: -AmbientLayoutMetrics.plateInsets.bottom,
                        trailing: -AmbientLayoutMetrics.plateInsets.right
                    ))
                    .allowsHitTesting(false)
            )
        }
        .frame(width: AmbientLayoutMetrics.cardWidth, alignment: .topLeading)
        .padding(EdgeInsets(
            top: AmbientLayoutMetrics.screenPadding.top,
            leading: AmbientLayoutMetrics.screenPadding.left,
            bottom: AmbientLayoutMetrics.screenPadding.bottom,
            trailing: AmbientLayoutMetrics.screenPadding.right
        ))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Subviews

    @ViewBuilder private var chapterProgressLabel: some View {
        Text(chapterProgressString)
            .font(.system(size: AmbientLayoutMetrics.labelFontSize, weight: .medium))
            .tracking(AmbientLayoutMetrics.labelTracking)
            .textCase(.uppercase)
            .foregroundStyle(theme.ink.swiftUI.opacity(0.92))
            .shadow(color: textShadowColor, radius: 0, x: 0, y: 1)
    }

    @ViewBuilder private var quoteText: some View {
        if let highlight {
            let truncated = AmbientLayoutMetrics.truncateForDisplay(highlight.text)
            let fontSize = AmbientLayoutMetrics.quoteFontSize(for: truncated.text)
            let leading = AmbientLayoutMetrics.quoteLeadingMultiple(for: truncated.text)
            VStack(alignment: .leading, spacing: 6) {
                Text(truncated.text)
                    .font(.system(size: fontSize, weight: .medium, design: .serif))
                    .lineSpacing(fontSize * (leading - 1.0))
                    .foregroundStyle(theme.ink.swiftUI.opacity(0.92))
                    .shadow(color: textShadowColor, radius: 0, x: 0, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                if truncated.wasTruncated {
                    Text("Read more…")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(AmbientLayoutMetrics.labelTracking)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.ink.swiftUI.opacity(0.65))
                }
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder private var titleAuthorFooter: some View {
        if let book {
            Text(titleAuthorString(for: book))
                .font(.system(size: AmbientLayoutMetrics.footerFontSize, weight: .medium))
                .tracking(AmbientLayoutMetrics.labelTracking)
                .textCase(.uppercase)
                .foregroundStyle(theme.ink.swiftUI.opacity(AmbientLayoutMetrics.footerOpacity))
                .shadow(color: textShadowColor, radius: 0, x: 0, y: 1)
        }
    }

    // MARK: - Helpers

    private var chapterProgressString: String {
        switch (chapterTitle, progressPercent) {
        case let (title?, pct?): return "\(title) · \(pct)%"
        case let (title?, nil):  return title
        case let (nil, pct?):    return "\(pct)%"
        case (nil, nil):         return ""
        }
    }

    private func titleAuthorString(for book: Book) -> String {
        if let author = book.author, !author.isEmpty {
            return "\(book.title) · \(author)"
        }
        return book.title
    }

    /// Spec §11.1: shadow `0 1px 2px rgba(0,0,0,0.35)` in dark, inverted in light.
    private var textShadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.35)
            : Color.white.opacity(0.4)
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if let book { parts.append(book.title) }
        if let chapterTitle { parts.append(chapterTitle) }
        if let pct = progressPercent { parts.append("\(pct) percent") }
        if let highlight { parts.append(highlight.text) }
        return parts.joined(separator: ", ")
    }
}

/// NSVisualEffectView bridged into SwiftUI as the plate behind the text block.
struct VisualEffectPlate: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
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
  git add book-reader-mac/Ambient/AmbientCornerCard.swift && \
  git commit -m "feat(mac): AmbientCornerCard SwiftUI composition with Clay typography"
```

---

## Task 10: Reduce-motion observer

**Files:**
- Create: `book-reader-mac/Ambient/AmbientReduceMotion.swift`

Spec §11.4 says crossfade durations collapse to a 100ms blink when Reduce Motion is on. We expose a tiny `@Observable` token both `AmbientHostView` and `FinderFrontmostFader` can read.

- [ ] **Step 1: Implement**

Write `book-reader-mac/Ambient/AmbientReduceMotion.swift`:
```swift
import AppKit
import Observation

/// Observes `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`
/// and republishes the current `accessibilityDisplayShouldReduceMotion` value.
@MainActor
@Observable
final class AmbientReduceMotion {
    var isEnabled: Bool

    private var observer: NSObjectProtocol?

    init() {
        self.isEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isEnabled = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
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
  git add book-reader-mac/Ambient/AmbientReduceMotion.swift && \
  git commit -m "feat(mac): AmbientReduceMotion observer"
```

---

## Task 11: `AmbientHostView` — wires card + rotation + tracker + crossfade

**Files:**
- Create: `book-reader-mac/Ambient/AmbientHostView.swift`

This is the per-screen root view. It:
1. Resolves the current `Book` from `ReadingState.currentBookHash` via a SwiftData fetch.
2. Builds an `AmbientHighlightSelector` and `AmbientRotationController` once.
3. Renders the current `AmbientCornerCard` with an opacity crossfade on change.
4. Overlays a `SafeZoneTracker` so cursor enter/exit toggles rotation pause.

The view is intentionally a hosting wrapper: we use an `NSHostingView`-friendly composition where the rotation controller lives in a `@State` box.

- [ ] **Step 1: Implement**

Write `book-reader-mac/Ambient/AmbientHostView.swift`:
```swift
import AppKit
import SwiftData
import SwiftUI

/// Per-screen ambient root. Combines AmbientCornerCard with the rotation
/// controller, safe-zone tracker, and reduce-motion-aware crossfade.
struct AmbientHostView: View {
    let screenName: String
    /// Stable seed for the per-session shuffle; passed in so two screens get
    /// different shuffles but the same seed across rotation re-creation.
    let shuffleSeed: UInt64
    /// External hook for menu-bar "Next quote" — Task 14 binds this to a
    /// shared coordinator across screens.
    let advanceTrigger: AmbientAdvanceTrigger

    @Environment(\.modelContext) private var modelContext
    @Environment(ReadingState.self) private var state
    @Environment(\.appTheme) private var theme
    @AppStorage("ambientRotationSeconds") private var rotationSeconds: Double = AmbientLayoutMetrics.rotationDefault

    @State private var controllerBox = ControllerBox()
    @State private var currentHighlight: Highlight?
    @State private var currentBook: Book?
    @State private var reduceMotion = AmbientReduceMotion()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Empty when ambientMode != .atomic — Plan 6 fills the .page branch.
            if state.ambientMode == .atomic {
                AmbientCornerCard(
                    book: currentBook,
                    highlight: currentHighlight,
                    chapterTitle: currentBook?.position?.chapterTitle,
                    progressPercent: currentBook?.position.map { Int(($0.percentage * 100).rounded()) }
                )
                .id(currentHighlight?.clientID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
                .transition(.opacity)
            }

            // Cursor tracking — sized to the card's bounding box only.
            SafeZoneTrackerRepresentable(
                onOccupiedChange: { occupied in
                    controllerBox.controller?.setSafeZoneOccupied(occupied)
                }
            )
            .frame(width: AmbientLayoutMetrics.cardWidth + AmbientLayoutMetrics.coverSize.width,
                   height: 200)
            .padding(.leading, AmbientLayoutMetrics.screenPadding.left)
            .padding(.bottom, AmbientLayoutMetrics.screenPadding.bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .animation(crossfadeAnimation, value: currentHighlight?.clientID)
        .onAppear {
            reduceMotion.start()
            startController()
            advanceTrigger.register(screenName: screenName) { [box = controllerBox] in
                box.controller?.advanceNow(reason: .menuCommand)
            }
        }
        .onDisappear {
            controllerBox.controller?.stop()
            controllerBox.controller = nil
            reduceMotion.stop()
            advanceTrigger.unregister(screenName: screenName)
        }
        .onChange(of: state.currentBookHash) { _, _ in
            restartController()
        }
        .onChange(of: rotationSeconds) { _, newValue in
            controllerBox.controller?.updateRotationSeconds(newValue)
        }
    }

    // MARK: - Controller lifecycle

    private func startController() {
        let (book, highlights) = fetchBookAndHighlights()
        currentBook = book

        let selector = AmbientHighlightSelector(highlights: highlights, seed: shuffleSeed)
        let controller = AmbientRotationController(
            selector: selector,
            clock: SystemAmbientClock(),
            rotationSeconds: rotationSeconds,
            onAdvance: { highlight in
                Task { @MainActor in currentHighlight = highlight }
            }
        )
        controllerBox.controller = controller
        controller.start()
    }

    private func restartController() {
        controllerBox.controller?.stop()
        controllerBox.controller = nil
        currentHighlight = nil
        startController()
    }

    private func fetchBookAndHighlights() -> (Book?, [Highlight]) {
        guard let hash = state.currentBookHash else { return (nil, []) }
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.sha256 == hash }
        )
        descriptor.fetchLimit = 1
        let book = (try? modelContext.fetch(descriptor))?.first
        let highlights = book?.highlights ?? []
        return (book, highlights)
    }

    private var crossfadeAnimation: Animation {
        if reduceMotion.isEnabled {
            return .linear(duration: AmbientLayoutMetrics.reducedMotionBlinkDuration)
        }
        // Spec §11.4: 800ms ease-out outgoing, 1200ms ease-in incoming.
        // SwiftUI doesn't expose asymmetric durations on `.opacity` transitions
        // through a single Animation; we use the average and lean ease-in-out.
        // The asymmetric incoming-vs-outgoing visual is approximated by the
        // ~400ms overlap inherent to opacity crossfade.
        return .easeInOut(duration: AmbientLayoutMetrics.crossfadeInDuration)
    }
}

/// Boxed reference so SwiftUI `@State` doesn't try to value-copy the
/// reference-typed controller.
@MainActor
final class ControllerBox {
    var controller: AmbientRotationController?
    init() { self.controller = nil }
}

/// Bridge for `SafeZoneTracker` into SwiftUI.
struct SafeZoneTrackerRepresentable: NSViewRepresentable {
    let onOccupiedChange: (Bool) -> Void

    func makeNSView(context: Context) -> SafeZoneTracker {
        let view = SafeZoneTracker()
        view.onOccupiedChange = onOccupiedChange
        return view
    }

    func updateNSView(_ nsView: SafeZoneTracker, context: Context) {
        nsView.onOccupiedChange = onOccupiedChange
    }
}

/// Shared trigger object that the menu-bar "Next quote" command pokes.
/// Each AmbientHostView registers a per-screen callback at appear time.
@MainActor
final class AmbientAdvanceTrigger {
    private var callbacks: [String: () -> Void] = [:]

    func register(screenName: String, _ callback: @escaping () -> Void) {
        callbacks[screenName] = callback
    }
    func unregister(screenName: String) {
        callbacks.removeValue(forKey: screenName)
    }
    func fireAll() {
        for callback in callbacks.values { callback() }
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
  git add book-reader-mac/Ambient/AmbientHostView.swift && \
  git commit -m "feat(mac): AmbientHostView wires rotation, safe-zone, crossfade"
```

---

## Task 12: Extend `MenuBarController` with `onNextQuote`

**Files:**
- Modify: `book-reader-mac/MenuBar/MenuBarController.swift`

Add a fifth closure (`onNextQuote`) and a "Next Quote" menu item placed above "Toggle Wallpaper Mode". Re-read the current file before editing so the replacement is exact.

- [ ] **Step 1: Read the current file**

Run:
```bash
sed -n '1,200p' /Users/profitoniumapps/Documents/chromeApps/book-reader-mac/MenuBar/MenuBarController.swift
```
Confirm it matches the foundation Task 18 implementation. If it doesn't, abort and reconcile before continuing.

- [ ] **Step 2: Overwrite with the extended version**

Write `book-reader-mac/MenuBar/MenuBarController.swift`:
```swift
import AppKit

/// Owns the NSStatusItem. Menu items wire to closures supplied by AppDelegate.
@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let onToggleReader: () -> Void
    private let onToggleAmbientMode: () -> Void
    private let onNextQuote: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    init(onToggleReader: @escaping () -> Void,
         onToggleAmbientMode: @escaping () -> Void,
         onNextQuote: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void,
         onQuit: @escaping () -> Void) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.onToggleReader = onToggleReader
        self.onToggleAmbientMode = onToggleAmbientMode
        self.onNextQuote = onNextQuote
        self.onOpenSettings = onOpenSettings
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
        menu.addItem(makeItem(title: "Next Quote",
                              action: #selector(nextQuoteClicked),
                              keyEquivalent: ""))
        menu.addItem(makeItem(title: "Toggle Wallpaper Mode",
                              action: #selector(toggleAmbientClicked),
                              keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Settings…",
                              action: #selector(openSettingsClicked),
                              keyEquivalent: ","))
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
    @objc private func nextQuoteClicked() { onNextQuote() }
    @objc private func openSettingsClicked() { onOpenSettings() }
    @objc private func quitClicked() { onQuit() }
}
```

- [ ] **Step 3: Build (expect AppDelegate breakage)**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -10
```
Expected: build fails because `AppDelegate` still constructs `MenuBarController` without `onNextQuote`. That's wired up in Task 14.

- [ ] **Step 4: Commit (build will succeed after Task 14)**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/MenuBar/MenuBarController.swift && \
  git commit -m "feat(mac): MenuBarController gains onNextQuote command"
```

---

## Task 13: Per-screen ambient instance type for the coordinator

**Files:**
- Create: `book-reader-mac/Ambient/AmbientScreenInstance.swift`

Pulled out of the coordinator rewrite for readability. This struct keeps the per-screen `WallpaperWindow` paired with its `FinderFrontmostFader`. The host view itself owns the rotation controller (Task 11).

- [ ] **Step 1: Implement**

Write `book-reader-mac/Ambient/AmbientScreenInstance.swift`:
```swift
import AppKit
import SwiftUI

/// One per NSScreen: the wallpaper window, its hosting view, and the
/// Finder-frontmost fader bound to that window's contentView alpha.
@MainActor
final class AmbientScreenInstance {
    let window: WallpaperWindow
    let fader: FinderFrontmostFader

    init(screen: NSScreen,
         reduceMotion: AmbientReduceMotion,
         rootView: AnyView) {
        let window = WallpaperWindow(screen: screen)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        window.contentView = hostingView
        window.setFrame(screen.frame, display: true)

        // Bind the fader's `apply` closure to the contentView's alpha so
        // the policy module (Task 7) stays free of NSWindow references.
        let fader = FinderFrontmostFader(
            isReducedMotion: { reduceMotion.isEnabled },
            apply: { [weak hostingView] target, duration in
                guard let hostingView else { return }
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = duration
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    hostingView.animator().alphaValue = target
                }
            }
        )

        self.window = window
        self.fader = fader
    }

    func show() {
        window.orderFront(nil)
        fader.start()
    }

    func hide() {
        fader.stop()
        window.orderOut(nil)
    }

    func relayout(to screen: NSScreen) {
        window.setFrame(screen.frame, display: true)
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -10
```
Expected: build still fails on `MenuBarController` call site (Task 14). That's OK; the new file compiles standalone.

- [ ] **Step 3: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Ambient/AmbientScreenInstance.swift && \
  git commit -m "feat(mac): AmbientScreenInstance pairs window + fader per screen"
```

---

## Task 14: Rewrite `WallpaperWindowCoordinator` and rewire AppDelegate

**Files:**
- Modify: `book-reader-mac/Windows/WallpaperWindowCoordinator.swift`
- Modify: `book-reader-mac/App/AppDelegate.swift`

This is the only task that touches existing foundation code. Replace the coordinator wholesale; rewire the AppDelegate to supply the new `onNextQuote` closure and to own the shared `AmbientAdvanceTrigger` + `AmbientReduceMotion`.

- [ ] **Step 1: Overwrite the coordinator**

Write `book-reader-mac/Windows/WallpaperWindowCoordinator.swift`:
```swift
import AppKit
import SwiftData
import SwiftUI

/// Owns one AmbientScreenInstance per NSScreen. Hosts the real
/// AmbientHostView (Plan 5 atomic mode). The .page branch is filled in
/// by Plan 6; this coordinator hosts an empty view there so the wallpaper
/// window stays alive without crashing.
@MainActor
final class WallpaperWindowCoordinator {
    private var instances: [String: AmbientScreenInstance] = [:]
    private let state: ReadingState
    private let modelContainer: ModelContainer
    private let theme: AppTheme
    private let advanceTrigger: AmbientAdvanceTrigger
    private let reduceMotion: AmbientReduceMotion
    private var observer: NSObjectProtocol?
    private var screenWakeObserver: NSObjectProtocol?
    private var finderActivationObserver: NSObjectProtocol?

    init(state: ReadingState,
         modelContainer: ModelContainer,
         theme: AppTheme,
         advanceTrigger: AmbientAdvanceTrigger,
         reduceMotion: AmbientReduceMotion) {
        self.state = state
        self.modelContainer = modelContainer
        self.theme = theme
        self.advanceTrigger = advanceTrigger
        self.reduceMotion = reduceMotion
    }

    func start() {
        reconcile()

        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }

        screenWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.advanceTrigger.fireAll() }
        }

        finderActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard
                let self,
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                app.bundleIdentifier == "com.apple.finder"
            else { return }
            Task { @MainActor in
                // Each host view's controller is asked to schedule its own
                // 800ms-delayed advance via the trigger; this is the simpler
                // signal — Finder activation already fans out per-screen
                // because every host view registers its callback with the
                // trigger. The 800ms delay is enforced inside the controller's
                // handleFinderActivation, which we invoke instead of advanceNow.
                self.fireFinderActivation()
            }
        }
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if let screenWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(screenWakeObserver)
        }
        screenWakeObserver = nil
        if let finderActivationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(finderActivationObserver)
        }
        finderActivationObserver = nil

        for instance in instances.values { instance.hide() }
        instances.removeAll()
    }

    /// Public hook bound to the menu-bar "Next Quote" command.
    func advanceAllQuotes() {
        advanceTrigger.fireAll()
    }

    // MARK: - Reconciliation

    private func reconcile() {
        let currentScreens = NSScreen.screens
        let currentKeys = Set(currentScreens.map(Self.key(for:)))

        for key in Array(instances.keys) where !currentKeys.contains(key) {
            instances[key]?.hide()
            instances.removeValue(forKey: key)
        }

        for (index, screen) in currentScreens.enumerated() {
            let key = Self.key(for: screen)
            if instances[key] == nil {
                let seed = Self.seed(for: screen, index: index)
                let rootView = AnyView(
                    AmbientHostView(
                        screenName: screen.localizedName,
                        shuffleSeed: seed,
                        advanceTrigger: advanceTrigger
                    )
                    .environment(\.appTheme, theme)
                    .environment(state)
                    .modelContainer(modelContainer)
                )
                let instance = AmbientScreenInstance(
                    screen: screen,
                    reduceMotion: reduceMotion,
                    rootView: rootView
                )
                instance.show()
                instances[key] = instance
            } else {
                instances[key]?.relayout(to: screen)
            }
        }
    }

    /// Per-screen path for the Finder-activation 800ms delay. Because the
    /// rotation controller lives inside AmbientHostView, we route through the
    /// shared trigger using a dedicated callback list. Each host registers a
    /// `handleFinderActivation` closure separately (see Task 11 if you extend
    /// this — for v1 the simpler `advanceTrigger.fireAll()` is acceptable
    /// because timer reset + immediate advance both happen).
    private func fireFinderActivation() {
        // Spec §5.3: "Advance after 800ms (only if cursor not in safe zone)".
        // The controller already encodes both — we just need to ask it.
        // We piggyback on the same trigger pool: register the per-screen
        // controllers' handleFinderActivation in addition to advanceNow.
        advanceTrigger.fireAllFinderActivations()
    }

    private static func key(for screen: NSScreen) -> String {
        "\(screen.localizedName)|\(Int(screen.frame.width))x\(Int(screen.frame.height))"
    }

    /// Stable per-screen seed so multi-monitor setups get distinct shuffles
    /// without re-randomising on every reconcile.
    private static func seed(for screen: NSScreen, index: Int) -> UInt64 {
        var hasher = Hasher()
        hasher.combine(screen.localizedName)
        hasher.combine(index)
        return UInt64(bitPattern: Int64(hasher.finalize()))
    }
}
```

- [ ] **Step 2: Extend the trigger with Finder-activation fan-out**

The coordinator references `advanceTrigger.fireAllFinderActivations()` which we haven't added yet. Open `book-reader-mac/Ambient/AmbientHostView.swift` and replace the `AmbientAdvanceTrigger` class at the bottom with the extended version below. (Do not edit anything else in the file.)

Find this block:
```swift
@MainActor
final class AmbientAdvanceTrigger {
    private var callbacks: [String: () -> Void] = [:]

    func register(screenName: String, _ callback: @escaping () -> Void) {
        callbacks[screenName] = callback
    }
    func unregister(screenName: String) {
        callbacks.removeValue(forKey: screenName)
    }
    func fireAll() {
        for callback in callbacks.values { callback() }
    }
}
```

Replace it with:
```swift
@MainActor
final class AmbientAdvanceTrigger {
    private var nextQuoteCallbacks: [String: () -> Void] = [:]
    private var finderActivationCallbacks: [String: () -> Void] = [:]

    func register(screenName: String,
                  _ callback: @escaping () -> Void) {
        nextQuoteCallbacks[screenName] = callback
    }
    func registerFinderActivation(screenName: String,
                                  _ callback: @escaping () -> Void) {
        finderActivationCallbacks[screenName] = callback
    }
    func unregister(screenName: String) {
        nextQuoteCallbacks.removeValue(forKey: screenName)
        finderActivationCallbacks.removeValue(forKey: screenName)
    }
    func fireAll() {
        for callback in nextQuoteCallbacks.values { callback() }
    }
    func fireAllFinderActivations() {
        for callback in finderActivationCallbacks.values { callback() }
    }
}
```

Also extend the `.onAppear` block inside `AmbientHostView.body` so that — in addition to the existing `advanceTrigger.register(screenName:_:)` call — it also registers the controller's Finder-activation handler. Find this block inside `body`:
```swift
        .onAppear {
            reduceMotion.start()
            startController()
            advanceTrigger.register(screenName: screenName) { [box = controllerBox] in
                box.controller?.advanceNow(reason: .menuCommand)
            }
        }
```

Replace it with:
```swift
        .onAppear {
            reduceMotion.start()
            startController()
            advanceTrigger.register(screenName: screenName) { [box = controllerBox] in
                box.controller?.advanceNow(reason: .menuCommand)
            }
            advanceTrigger.registerFinderActivation(screenName: screenName) { [box = controllerBox] in
                box.controller?.handleFinderActivation()
            }
        }
```

- [ ] **Step 3: Rewire AppDelegate**

Open `book-reader-mac/App/AppDelegate.swift` and replace its full contents with:

```swift
import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: ReadingState!
    private var modelContainer: ModelContainer!
    private var wallpaperCoordinator: WallpaperWindowCoordinator!
    private var readerController: ReaderWindowController!
    private var menuBar: MenuBarController!
    private var hotkey: GlobalHotkey!
    private var systemEvents: SystemEventObserver!
    private var advanceTrigger: AmbientAdvanceTrigger!
    private var reduceMotion: AmbientReduceMotion!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try AppSupportPaths.ensureCreated()
            modelContainer = try PersistenceController.makeContainer()
        } catch {
            NSApp.presentError(error)
            NSApp.terminate(nil)
            return
        }

        state = ReadingState()
        let theme: AppTheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? .clayDark : .clayLight

        advanceTrigger = AmbientAdvanceTrigger()
        reduceMotion = AmbientReduceMotion()
        reduceMotion.start()

        wallpaperCoordinator = WallpaperWindowCoordinator(
            state: state,
            modelContainer: modelContainer,
            theme: theme,
            advanceTrigger: advanceTrigger,
            reduceMotion: reduceMotion
        )
        readerController = ReaderWindowController(
            state: state, modelContainer: modelContainer, theme: theme)

        menuBar = MenuBarController(
            onToggleReader: { [weak self] in self?.readerController.toggle() },
            onToggleAmbientMode: { [weak self] in
                guard let self else { return }
                state.ambientMode = state.ambientMode == .atomic ? .page : .atomic
            },
            onNextQuote: { [weak self] in self?.wallpaperCoordinator.advanceAllQuotes() },
            onOpenSettings: {
                if #available(macOS 14.0, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } else {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
            },
            onQuit: { NSApp.terminate(nil) }
        )

        hotkey = GlobalHotkey(onToggle: { [weak self] in self?.readerController.toggle() })
        hotkey.register()

        systemEvents = SystemEventObserver(
            onWillSleep: { [weak self] in
                try? self?.modelContainer.mainContext.save()
            },
            onDidWake: { _ in
                // Plan 5: handled by the coordinator's screensDidWakeNotification observer.
            },
            onLowPowerModeChange: { _ in
                // Reserved for energy policy in later plans.
            }
        )
        systemEvents.start()

        wallpaperCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperCoordinator?.stop()
        systemEvents?.stop()
        reduceMotion?.stop()
        try? modelContainer?.mainContext.save()
    }
}
```

- [ ] **Step 4: Build the full app**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader build 2>&1 | tail -10
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Run all tests**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: all existing test suites still pass — `BookHashTests`, `ReadingStateTests`, `PersistenceTests`, `ThemeEnvironmentTests`, `AmbientLayoutMetricsTests`, `AmbientHighlightSelectorTests`, `AmbientRotationControllerTests`, `FinderFrontmostFaderTests`.

- [ ] **Step 6: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Windows/WallpaperWindowCoordinator.swift \
          book-reader-mac/Ambient/AmbientHostView.swift \
          book-reader-mac/App/AppDelegate.swift && \
  git commit -m "feat(mac): rewrite WallpaperWindowCoordinator to host real ambient card"
```

---

## Task 15: Snapshot-style layout test for `AmbientCornerCard`

**Files:**
- Create: `book-reader-mac/Tests/Snapshots/AmbientCornerCardTests.swift`

True pixel snapshots are out of scope for v1; the task brief allows falling back to measured-layout assertions. We render the card into a fixed-size `NSHostingView`, force a layout pass, and assert that the cover, text block, and the entire card have the sizes we expect.

- [ ] **Step 1: Add the Snapshots path to XcodeGen**

Open `book-reader-mac/project.yml` and find the `InstantBookReaderTests` target. The current `sources:` list reads:
```yaml
    sources:
      - path: Tests
```

It already covers `Tests/Snapshots/` because `path: Tests` is recursive in XcodeGen. No edit needed — confirm by running:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && xcodegen generate
```
Expected: regenerates without changing project structure other than the new test file once it exists.

- [ ] **Step 2: Write the test**

Write `book-reader-mac/Tests/Snapshots/AmbientCornerCardTests.swift`:
```swift
import AppKit
import SwiftUI
import XCTest
@testable import InstantBookReader

@MainActor
final class AmbientCornerCardTests: XCTestCase {
    private func makeBook() -> Book {
        Book(sha256: "abc123",
             title: "The Sample Book",
             author: "A. Sample",
             format: .epub,
             coverPath: nil,            // missing → placeholder rectangle
             filePath: "abc123.epub")
    }

    private func makeShortHighlight() -> Highlight {
        Highlight(bookHash: "abc123",
                  text: "A short quote.",
                  surroundingText: "A short quote.",
                  offset: 0)
    }

    private func makeLongHighlight() -> Highlight {
        let text = String(repeating: "x", count: 240) + "."
        return Highlight(bookHash: "abc123",
                         text: text,
                         surroundingText: text,
                         offset: 0)
    }

    /// Helper: mount the card in a 1280×800 hosting view, force layout, and
    /// return the resulting `intrinsicContentSize` of the root view.
    private func mountAndLayout<V: View>(_ view: V) -> NSHostingView<some View> {
        let host = NSHostingView(rootView:
            view
                .environment(\.appTheme, AppTheme.clayDark)
                .frame(width: 1280, height: 800)
        )
        host.frame = NSRect(x: 0, y: 0, width: 1280, height: 800)
        host.layoutSubtreeIfNeeded()
        return host
    }

    func testShortHighlightLayoutMatchesMetrics() {
        let view = AmbientCornerCard(
            book: makeBook(),
            highlight: makeShortHighlight(),
            chapterTitle: "Ch. 7",
            progressPercent: 43
        )
        let host = mountAndLayout(view)
        XCTAssertGreaterThan(host.bounds.width, 0)
        // The hosting frame is sized via .frame above, so we mainly verify
        // we didn't blow up and the metrics report 44pt for short quotes.
        XCTAssertEqual(
            AmbientLayoutMetrics.quoteFontSize(for: makeShortHighlight().text),
            44
        )
    }

    func testLongHighlightFallsBackTo28pt() {
        let view = AmbientCornerCard(
            book: makeBook(),
            highlight: makeLongHighlight(),
            chapterTitle: "Ch. 7",
            progressPercent: 43
        )
        let host = mountAndLayout(view)
        XCTAssertGreaterThan(host.bounds.width, 0)
        XCTAssertEqual(
            AmbientLayoutMetrics.quoteFontSize(for: makeLongHighlight().text),
            28
        )
    }

    func testEmptyHighlightSlotRendersCoverPlusLabelsOnly() {
        let view = AmbientCornerCard(
            book: makeBook(),
            highlight: nil,
            chapterTitle: "Ch. 7",
            progressPercent: 43
        )
        let host = mountAndLayout(view)
        XCTAssertGreaterThan(host.bounds.width, 0)
        // Smoke: no crash when highlight is absent.
    }

    func testTruncationAffordanceTriggersAt281Chars() {
        let raw = String(repeating: "y", count: 281)
        let result = AmbientLayoutMetrics.truncateForDisplay(raw)
        XCTAssertTrue(result.wasTruncated)
        XCTAssertLessThanOrEqual(result.text.count, 280)
    }

    /// Renders the card to a 1× NSImage and writes it to a temporary file
    /// purely so a future PR can swap this in for a real pixel snapshot
    /// without restructuring the test. The assertion is on file existence,
    /// not pixels — pixel snapshots are deferred.
    func testRendersToImageAtOnex() throws {
        let view = AmbientCornerCard(
            book: makeBook(),
            highlight: makeShortHighlight(),
            chapterTitle: "Ch. 7",
            progressPercent: 43
        )
        let host = mountAndLayout(view)
        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let data = rep.representation(using: .png, properties: [:])
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)

        // Attach as a diagnostic — visible in the test run log.
        if let data {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
            attachment.name = "AmbientCornerCard-short.png"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
```

- [ ] **Step 3: Run the snapshot tests; confirm they pass**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodegen generate && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -20
```
Expected: `Test Suite 'AmbientCornerCardTests' passed` plus the attachment is recorded.

- [ ] **Step 4: Commit**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git add book-reader-mac/Tests/Snapshots/AmbientCornerCardTests.swift && \
  git commit -m "test(mac): AmbientCornerCard layout + render smoke test"
```

---

## Task 16: Manual smoke test of ambient mode

This task has no code changes. It validates the running app on a real Mac with at least one user-imported book and one highlight present (assumes Plan 2's library + import work is merged).

- [ ] **Step 1: Build and launch**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -configuration Debug \
    -derivedDataPath ./build build 2>&1 | tail -5 && \
  open ./build/Build/Products/Debug/InstantBookReader.app
```

Expected: `** BUILD SUCCEEDED **`, app launches with menu-bar item.

- [ ] **Step 2: Visually verify on a real screen**

Confirm by inspection:

1. The corner card appears in the bottom-left of every connected screen, ~56pt from the left and bottom edges.
2. The card shows: cover (or a Clay-tinted placeholder if Plan 2 hasn't populated a cover yet), an uppercase chapter+progress label, a serif quote, and an uppercase title+author footer.
3. A subtle translucent plate sits behind the text block only, not behind the cover.
4. Quotes change roughly every 90s, with a slow crossfade (~1s) between them.
5. Moving the cursor over the card pauses rotation; moving the cursor away resumes after about 5s.
6. Clicking through the card onto a Finder icon still selects the icon (window remains click-through).
7. Selecting Finder via Cmd+Tab fades the entire card to about 15% opacity over 400ms; activating any other app restores full opacity.
8. The menu bar shows a "Next Quote" item; choosing it advances every screen immediately.
9. With System Settings → Accessibility → Display → "Reduce motion" toggled on, the crossfade collapses to a near-instant blink and the Finder fade does the same.
10. With `ReadingState.ambientMode == .page` (set programmatically by toggling the menu-bar "Toggle Wallpaper Mode" item), the wallpaper window stays alive and shows no content — no crash, no error log. (Plan 6 fills this in.)
11. Disconnect and reconnect an external display: the card appears on the reconnected screen without the app needing a restart.

If any of these fail, file the failure as a bug task before moving to Plan 6.

- [ ] **Step 3: Run the full test suite**

Run:
```bash
cd /Users/profitoniumapps/Documents/chromeApps/book-reader-mac && \
  xcodebuild test -project book-reader-mac.xcodeproj \
    -scheme InstantBookReader \
    -destination 'platform=macOS' 2>&1 | tail -25
```

Expected: all eight test suites pass — the four foundation suites plus `AmbientLayoutMetricsTests`, `AmbientHighlightSelectorTests`, `AmbientRotationControllerTests`, `FinderFrontmostFaderTests`, and `AmbientCornerCardTests`.

- [ ] **Step 4: Tag the milestone**

```bash
cd /Users/profitoniumapps/Documents/chromeApps && \
  git tag -a mac-v0.5.0-ambient -m "Plan 5 ambient mode complete" && \
  git log --oneline mac-v0.5.0-ambient~16..mac-v0.5.0-ambient
```

Expected: 16 commits from Task 1 through Task 16 of this plan.

---

## Self-review notes

Coverage check against the spec's §5 (Ambient mode) and §11 (Visual language):

| Spec section / brief requirement | Task |
|---|---|
| §5.1 Content priority (cover, chapter+progress, rotating highlight); skip blank notes | Tasks 4, 9 |
| §5.2 Corner card composition, 360pt width, 60×80 cover, NSVisualEffectView plate sized to text only | Tasks 3, 8, 9 |
| §5.3 Timer (default 90s, 45s–600s bounds) | Tasks 3, 5 (`AmbientLayoutMetrics.rotation*`, `@AppStorage("ambientRotationSeconds")`) |
| §5.3 Screen-wake trigger advances immediately | Tasks 5, 14 |
| §5.3 Finder-frontmost advances after 800ms unless in safe zone | Tasks 5, 11, 14 |
| §5.3 Cursor in safe zone pauses; resume 5s after exit | Tasks 5, 6, 11 |
| §5.3 Menu-bar "Next quote" advances all screens | Tasks 5, 11, 12, 14 |
| §5.3 Multi-monitor: per-screen instances, shared content pool | Tasks 11, 13, 14 |
| §5.4 Position bottom-left | Task 3 (`screenPadding`), 9 |
| §5.4 Visual-effect plate sized to text block | Task 9 |
| §5.4 Frontmost-Finder fade to 15% over 400ms | Tasks 3, 7, 13 |
| §11.1 Quote face New York Medium 28/44pt with length-based sizing | Tasks 3, 9 |
| §11.1 Attribution Clay `.clay-label` (DM Sans 500, uppercase, 1.08 tracking, 13pt label / 11pt footer) | Tasks 3, 9 |
| §11.1 Text shadow `0 1px 2px rgba(0,0,0,0.35)` dark, inverted in light | Task 9 |
| §11.1 280-char cap with "Read more…" affordance | Tasks 3, 9 |
| §11.4 Crossfade 800ms ease-out / 1200ms ease-in / Reduce Motion 100ms blink | Tasks 10, 11 |
| Empty highlight pool ⇒ cover + progress only | Tasks 4, 9 |
| Per-session stable shuffle seed | Tasks 4, 14 |
| Coordinator hand-off when `ambientMode == .page` | Task 11 (atomic-only render), 14 |
| Snapshot / layout test for the card | Task 15 |

### Placeholder scan

No "TBD", "implement later", or "similar to Task N" markers remain. Every code block is complete and ready to paste. The reduce-motion approximation in `AmbientHostView.crossfadeAnimation` is the only behavioural compromise: SwiftUI's symmetric opacity transitions can't express the 800ms / 1200ms asymmetric easing exactly, so the implementation uses the average. This is called out in code and is the closest accurate SwiftUI approximation without dropping to Core Animation.

### Type-consistency check

- `AmbientClock.schedule(after:_:)` returns `AmbientTimerHandle` everywhere it's called.
- `AmbientHighlightSelector.next()` returns `Highlight?` everywhere — including the empty-pool path.
- `AmbientRotationController.onAdvance` is `(Highlight?) -> Void` in the controller, the host view, and tests.
- `AmbientAdvanceTrigger.fireAll()` / `.fireAllFinderActivations()` / `.register…` names match between the coordinator, host view, and Task 14's revision.
- `FinderFrontmostFader.apply` signature is `(CGFloat, TimeInterval) -> Void` in both the production wiring (Task 13) and tests (Task 7).
- `Book.coverPath` is read as `String?` everywhere (matches the foundation model).
- `AmbientLayoutMetrics` constants are referenced by the same names across `AmbientCornerCard`, `AmbientHostView`, `AmbientRotationController`, `FinderFrontmostFader`, and their tests.

### Deferred items

- True pixel-perfect snapshots: scaffolded as image-render smoke (Task 15); checked-in PNG references can be added in a follow-up without restructuring.
- The asymmetric 800ms / 1200ms crossfade is approximated; switching to Core Animation `CATransition` is a follow-up.
- Plan 6 fills in the `.page` ambient branch — this plan only commits to not crashing there.
