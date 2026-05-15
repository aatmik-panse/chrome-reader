import Foundation
import SwiftData

@MainActor
@Observable
public final class SelectionAIController {
    public enum State: Equatable {
        case idle
        case streaming
        case finished
        case needsKey(ProviderID)
        case error(String)
    }

    public var state: State = .idle
    public var outputText: String = ""

    private let router: AIRouter
    private let cache: AICache
    private let bookHash: () -> String
    private var task: Task<Void, Never>?

    public init(router: AIRouter = AIRouter(),
                container: ModelContainer,
                bookHash: @escaping () -> String) {
        self.router = router
        self.cache = AICache(container: container)
        self.bookHash = bookHash
    }

    public func reset() {
        task?.cancel()
        task = nil
        outputText = ""
        state = .idle
    }

    public func run(feature: AIFeature,
                    selection: String,
                    context: String = "",
                    chapterText: String = "",
                    question: String = "",
                    targetLang: String = "English") {
        task?.cancel()
        outputText = ""
        state = .streaming

        do {
            let (request, resolved) = try router.request(for: feature,
                                                         selection: selection,
                                                         context: context,
                                                         chapterText: chapterText,
                                                         question: question,
                                                         targetLang: targetLang)
            let promptString = (request.system ?? "") + "\n---\n" + (request.messages.last?.content ?? "")
            let cacheKey = AICache.makeKey(provider: resolved.provider.id,
                                           model: resolved.model,
                                           prompt: promptString,
                                           bookHash: bookHash())
            if let cached = cache.read(key: cacheKey) {
                outputText = cached
                state = .finished
                return
            }
            task = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    for try await chunk in resolved.provider.stream(request) {
                        if Task.isCancelled { return }
                        switch chunk {
                        case .textDelta(let s):
                            self.outputText.append(s)
                        case .done:
                            self.cache.write(key: cacheKey, response: self.outputText)
                            self.state = .finished
                            return
                        case .error(let msg):
                            self.state = .error(msg)
                            return
                        }
                    }
                    self.cache.write(key: cacheKey, response: self.outputText)
                    self.state = .finished
                } catch {
                    self.state = .error(String(describing: error))
                }
            }
        } catch let AIRouterError.noKeyForProvider(id) {
            state = .needsKey(id)
        } catch {
            state = .error(String(describing: error))
        }
    }
}
