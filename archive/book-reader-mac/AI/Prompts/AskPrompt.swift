import Foundation

public enum AskPrompt {
    public static let system =
        "You are a knowledgeable reading companion. Answer questions about books thoughtfully and accurately based on the provided context. If the answer isn't in the context, say so honestly."

    public static let maxContextLength = 6000

    public static func user(question: String, context: String) -> String {
        "Context from the book:\n\(String(context.prefix(maxContextLength)))\n\nQuestion: \(question)"
    }
}
