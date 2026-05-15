import AppKit
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` as a MainActor singleton.
/// The "Check for updates…" menu item in the SwiftUI `MenuBarExtra` calls
/// `UpdateController.shared.checkForUpdates(_:)`. The feed URL and
/// EdDSA public key are set in Info.plist (Task 1).
@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate {
    static let shared = UpdateController()

    let updater: SPUUpdater
    private let controller: SPUStandardUpdaterController

    private override init() {
        // Hold a forwarding ref so the delegate is in place before
        // SPUStandardUpdaterController spins up the updater. Sparkle 2
        // wires the delegate via this init parameter; it has no
        // `delegate` setter on SPUUpdater.
        let delegateBox = UpdateControllerDelegateBox()
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegateBox,
            userDriverDelegate: nil
        )
        self.updater = controller.updater
        super.init()
        delegateBox.owner = self
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

/// Forwards SPUUpdater delegate callbacks to `UpdateController.shared`.
/// Required because `SPUStandardUpdaterController` only accepts the delegate
/// at init time and there is no setter on `SPUUpdater.delegate` in Sparkle 2.
private final class UpdateControllerDelegateBox: NSObject, SPUUpdaterDelegate {
    weak var owner: UpdateController?
    func feedURLString(for updater: SPUUpdater) -> String? {
        owner?.feedURLString(for: updater)
    }
}
