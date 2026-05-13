import Foundation

public enum ExtractHighlightsPrompt {
    public static let system =
        "You are a literary analyst. Extract the 5-8 most important or memorable passages from the text. Return each passage as a direct quote on its own line, prefixed with a dash (-)."

    public static let maxChapterTextLength = 8000

    public static func user(chapterText: String) -> String {
        "Extract key passages from:\n\n\(String(chapterText.prefix(maxChapterTextLength)))"
    }

    /// Parse a model response of `- quote one\n- quote two` into ["quote one","quote two"].
    public static func parseLines(_ raw: String) -> [String] {
        raw.split(separator: "\n", omittingEmptySubsequences: true)
            .map { line -> String in
                var s = String(line)
                if s.hasPrefix("-") { s.removeFirst() }
                return s.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }
}
