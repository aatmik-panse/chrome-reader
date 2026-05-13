import Foundation

public enum SummarizePrompt {
    public static let system =
        "You are a helpful reading assistant. Provide concise, insightful chapter summaries that capture the key themes, events, and character developments. Keep summaries to 3-5 paragraphs."

    public static let maxChapterTextLength = 8000

    public static func user(chapterText: String) -> String {
        "Please summarize the following chapter:\n\n\(String(chapterText.prefix(maxChapterTextLength)))"
    }
}
