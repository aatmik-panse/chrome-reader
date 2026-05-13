import Foundation
import Observation

enum PageDirection: Int, Sendable { case next = 1, previous = -1 }

/// In-process page-advance bus. Intents and global hotkeys post here;
/// the active reader and page-mode windows observe `sequence` to react.
/// Pure singleton, MainActor-confined.
@Observable
@MainActor
final class PageAdvanceBus {
    static let shared = PageAdvanceBus()
    private init() {}

    /// Monotonically increasing on every post — views observe this to fire effects.
    private(set) var sequence: Int = 0
    private(set) var lastDirection: PageDirection = .next

    func post(_ direction: PageDirection) {
        lastDirection = direction
        sequence &+= 1
    }
}
