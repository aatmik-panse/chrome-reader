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
            advanceTrigger.registerFinderActivation(screenName: screenName) { [box = controllerBox] in
                box.controller?.handleFinderActivation()
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

/// Shared trigger object that the menu-bar "Next quote" command and the
/// Finder-activation observer poke. Each AmbientHostView registers a
/// per-screen callback at appear time.
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
