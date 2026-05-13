import Foundation

public enum TranslatePrompt {
    public static let system =
        "You are a precise translator. Reply with ONLY a single JSON object of shape {\"detectedLang\":\"<bcp47>\",\"translation\":\"...\"}. No prose, no code fences."

    public static let maxTextLength = 4000

    public static func user(text: String, targetLang: String) -> String {
        "Translate the following text to \(targetLang):\n\n\(String(text.prefix(maxTextLength)))"
    }
}
