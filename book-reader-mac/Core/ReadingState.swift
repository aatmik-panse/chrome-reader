import Foundation
import Observation
import SwiftUI

enum AmbientMode: String, CaseIterable, Sendable {
    case atomic
    case page
}

/// In-process shared store for the wallpaper layer, active reader, and
/// menu bar. Injected via `.environment(_:)`. Mutations on @MainActor only.
@Observable
@MainActor
final class ReadingState {
    /// SHA-256 of the currently selected book. Persisted via @AppStorage
    /// at the App level; this property is the in-process mirror.
    var currentBookHash: String?

    /// `.atomic` shows cover + chapter + quote on the wallpaper layer.
    /// `.page` renders the current book page itself at desktop level.
    var ambientMode: AmbientMode

    init(currentBookHash: String? = nil,
         ambientMode: AmbientMode = .atomic) {
        self.currentBookHash = currentBookHash
        self.ambientMode = ambientMode
    }
}
