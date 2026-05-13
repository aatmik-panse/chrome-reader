import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bootstrap is wired up in later tasks.
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Hook for synchronous flushes.
    }
}
