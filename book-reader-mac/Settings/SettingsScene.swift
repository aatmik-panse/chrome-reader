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
