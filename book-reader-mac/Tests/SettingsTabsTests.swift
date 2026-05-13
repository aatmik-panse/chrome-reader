import SwiftData
import SwiftUI
import XCTest
@testable import InstantBookReader

/// Smoke test: every tab's body resolves without crashing. Catches
/// the "I forgot to add this tab to the project sources" regression.
@MainActor
final class SettingsTabsTests: XCTestCase {
    func testRootViewBodyResolves() {
        _ = SettingsRootView().body
    }
    func testGeneralTabBodyResolves() { _ = GeneralTab().body }
    func testAppearanceTabBodyResolves() { _ = AppearanceTab().body }
    func testAmbientTabBodyResolves() { _ = AmbientTab().body }
    func testPageModeTabBodyResolves() { _ = PageModeTab().body }
    func testReadingTabBodyResolves() { _ = ReadingTab().body }
    func testLibraryTabBodyResolves() {
        let container = try! PersistenceController.makeInMemoryContainer()
        _ = LibraryTab().environment(\.modelContext, ModelContext(container)).body
    }
    func testAITabBodyResolves() { _ = AITab().body }
    func testShortcutsTabBodyResolves() { _ = ShortcutsTab().body }
    func testPrivacyDataTabBodyResolves() {
        let container = try! PersistenceController.makeInMemoryContainer()
        _ = PrivacyDataTab().environment(\.modelContext, ModelContext(container)).body
    }
    func testAdvancedTabBodyResolves() { _ = AdvancedTab().body }
}
