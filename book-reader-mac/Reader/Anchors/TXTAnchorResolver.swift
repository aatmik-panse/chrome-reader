import Foundation

/// Thin wrapper around HighlightAnchor for plain-text bodies. Adds the
/// selected `text` for convenience so the UI can display it without
/// re-slicing the document.
struct TXTAnchorResolver {
    struct Anchor: Equatable {
        let text: String
        let inner: HighlightAnchor
    }

    func makeAnchor(in plainText: String, startOffset: Int, length: Int) -> Anchor {
        let ns = plainText as NSString
        let safeRange = NSRange(location: max(0, startOffset),
                                length: min(length, ns.length - max(0, startOffset)))
        let selected = ns.substring(with: safeRange)
        let inner = HighlightAnchor.build(plainText: plainText,
                                          startOffset: safeRange.location,
                                          length: safeRange.length)
        return Anchor(text: selected, inner: inner)
    }

    func resolve(anchor: Anchor, in plainText: String) -> (startOffset: Int, length: Int)? {
        HighlightAnchor.resolve(plainText: plainText, anchor: anchor.inner)
    }
}
