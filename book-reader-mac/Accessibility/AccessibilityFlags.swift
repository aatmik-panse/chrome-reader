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
