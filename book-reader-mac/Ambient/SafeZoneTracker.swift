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
