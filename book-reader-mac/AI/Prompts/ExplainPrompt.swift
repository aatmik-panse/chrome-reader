import Foundation

public enum ExplainPrompt {
    public static let system =
        "You are a thoughtful reading assistant. When asked to explain a passage, provide context about its meaning, literary significance, vocabulary, or historical references as appropriate. Be concise but insightful."

    public static let maxContextLength = 4000

    public static func user(selection: String, context: String) -> String {
        "Surrounding context:\n\(String(context.prefix(maxContextLength)))\n\nPlease explain this passage:\n\"\(selection)\""
    }
}
