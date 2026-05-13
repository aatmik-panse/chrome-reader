import SwiftUI
import AppKit

/// Wallpaper root view that switches between atomic (Plan 5 `AmbientHostView`)
/// and page (Plan 6 `PageModeRouter`) based on `ReadingState.ambientMode`.
struct WallpaperRootView: View {
    let screen: NSScreen
    let shuffleSeed: UInt64
    let advanceTrigger: AmbientAdvanceTrigger

    @Environment(ReadingState.self) private var state

    var body: some View {
        Group {
            switch state.ambientMode {
            case .atomic:
                AmbientHostView(
                    screenName: screen.localizedName,
                    shuffleSeed: shuffleSeed,
                    advanceTrigger: advanceTrigger
                )
            case .page:
                PageModeRouter(screen: screen)
            }
        }
    }
}
