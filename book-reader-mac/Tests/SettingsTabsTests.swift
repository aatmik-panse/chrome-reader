import AppKit
import SwiftData
import SwiftUI
import XCTest
@testable import InstantBookReader

/// Smoke test: every tab's body resolves without crashing. Catches the
/// "I forgot to add this tab to the project sources" regression. We host
/// each view in `NSHostingView` because SwiftUI fatal-errors if `.body`
/// is read directly on a `ModifiedContent` (e.g. `Tab.modelContext(...)`)
/// — the only legal way to evaluate a modified view is through a host.
@MainActor
final class SettingsTabsTests: XCTestCase {
    private func mount<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        // Force a layout pass so the view's body is evaluated. This is
        // enough to catch missing types / crash-on-init regressions.
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        host.layoutSubtreeIfNeeded()
    }

    private func makeContainer() -> ModelContainer {
        try! PersistenceController.makeInMemoryContainer()
    }

    func testRootViewMounts() { mount(SettingsRootView()) }
    func testGeneralTabMounts() { mount(GeneralTab()) }
    func testAppearanceTabMounts() { mount(AppearanceTab()) }
    func testAmbientTabMounts() { mount(AmbientTab()) }
    func testPageModeTabMounts() { mount(PageModeTab()) }
    func testReadingTabMounts() { mount(ReadingTab()) }
    func testLibraryTabMounts() {
        mount(LibraryTab().modelContainer(makeContainer()))
    }
    func testAITabMounts() {
        mount(AITab().modelContainer(makeContainer()))
    }
    func testShortcutsTabMounts() { mount(ShortcutsTab()) }
    func testPrivacyDataTabMounts() {
        mount(PrivacyDataTab().modelContainer(makeContainer()))
    }
    func testAdvancedTabMounts() { mount(AdvancedTab()) }
}
