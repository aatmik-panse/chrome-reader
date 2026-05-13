import Foundation
import SwiftData

/// Debounced position writer. Coalesces 500 ms of rapid scroll/page-change
/// events into a single SwiftData save.
@MainActor
final class PositionRecorder {
    private struct Pending {
        let bookHash: String
        let anchor: String
        let percentage: Double
        let chapterTitle: String?
    }

    private let modelContainer: ModelContainer
    private let debounce: TimeInterval
    private var task: Task<Void, Never>?
    private var pending: Pending?

    init(modelContainer: ModelContainer, debounce: TimeInterval = 0.5) {
        self.modelContainer = modelContainer
        self.debounce = debounce
    }

    func record(bookHash: String, anchor: String, percentage: Double, chapterTitle: String?) {
        pending = Pending(bookHash: bookHash,
                          anchor: anchor,
                          percentage: percentage,
                          chapterTitle: chapterTitle)
        task?.cancel()
        let interval = debounce
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if Task.isCancelled { return }
            await self?.flush()
        }
    }

    func flush() async {
        task?.cancel()
        task = nil
        guard let p = pending else { return }
        pending = nil
        let context = ModelContext(modelContainer)
        let hash = p.bookHash
        let descriptor = FetchDescriptor<Position>(
            predicate: #Predicate { $0.bookHash == hash }
        )
        do {
            let existing = try context.fetch(descriptor)
            if let position = existing.first {
                position.anchor = p.anchor
                position.percentage = p.percentage
                position.chapterTitle = p.chapterTitle
                position.updatedAt = .now
            } else {
                context.insert(Position(bookHash: p.bookHash,
                                        anchor: p.anchor,
                                        percentage: p.percentage,
                                        chapterTitle: p.chapterTitle))
            }
            try context.save()
        } catch {
            // Surfacing this through a UI banner is a Plan 7 concern.
            // For now, silently drop — re-recording will retry within debounce.
            _ = error
        }
    }
}
