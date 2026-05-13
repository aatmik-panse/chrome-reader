import Foundation

/// The named features that route through `AIRouter`. Each has its own
/// per-feature provider+model preference key.
public enum AIFeature: String, CaseIterable, Sendable {
    case summarize
    case ask
    case explain
    case translate
    case extractHighlights

    public var displayName: String {
        switch self {
        case .summarize:         return "Summarize"
        case .ask:               return "Ask"
        case .explain:           return "Explain"
        case .translate:         return "Translate"
        case .extractHighlights: return "Extract highlights"
        }
    }

    public var providerDefaultsKey: String { "ai.feature.\(rawValue).provider" }
    public var modelDefaultsKey: String    { "ai.feature.\(rawValue).model" }
}
