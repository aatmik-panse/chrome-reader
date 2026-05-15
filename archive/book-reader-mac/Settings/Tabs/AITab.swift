import SwiftUI

/// Thin wrapper that exposes Plan 4's `AISettingsTab` under the name
/// `AITab` so `SettingsRootView` can reference all ten tabs uniformly.
/// Keeping the existing `AISettingsTab` file under `Settings/AI/` avoids
/// churning imports across the AI submodule.
struct AITab: View {
    var body: some View {
        AISettingsTab()
    }
}
