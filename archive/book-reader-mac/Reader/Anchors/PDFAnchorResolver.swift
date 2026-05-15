import Foundation
import PDFKit

/// Anchors PDF text selections using surrounding-text + offset, the same
/// scheme as the EPUB/TXT reader. Offsets are measured in UTF-16 units within
/// the page's `string` property.
struct PDFAnchorResolver {
    struct Anchor: Equatable {
        let pageIndex: Int
        let text: String
        let inner: HighlightAnchor
    }

    struct Resolved {
        let selection: PDFSelection
        let pageIndex: Int
    }

    func makeAnchor(from selection: PDFSelection, on page: PDFPage, pageIndex: Int) -> Anchor {
        let pageString = page.string ?? ""
        let selText = selection.string ?? ""
        let nsPage = pageString as NSString

        // Locate selection within page string. PDFSelection doesn't expose the
        // index directly; characterBounds(at:) lets us reverse-engineer it.
        let startOffset = offsetOfFirstCharacter(of: selection, in: page, pageString: pageString)
            ?? nsPage.range(of: selText).location
        let length = selText.utf16.count

        let inner = HighlightAnchor.build(plainText: pageString,
                                          startOffset: startOffset,
                                          length: length)
        return Anchor(pageIndex: pageIndex, text: selText, inner: inner)
    }

    func resolve(anchor: Anchor, in document: PDFDocument) -> Resolved? {
        guard let page = document.page(at: anchor.pageIndex) else { return nil }
        let pageString = page.string ?? ""
        guard let resolved = HighlightAnchor.resolve(plainText: pageString, anchor: anchor.inner) else {
            return nil
        }
        let range = NSRange(location: resolved.startOffset, length: resolved.length)
        guard let selection = page.selection(for: range) else { return nil }
        return Resolved(selection: selection, pageIndex: anchor.pageIndex)
    }

    /// Probes the first character's bounds and walks the page string for a
    /// match. Returns the UTF-16 offset of the first selected char.
    private func offsetOfFirstCharacter(of selection: PDFSelection,
                                        in page: PDFPage,
                                        pageString: String) -> Int? {
        let selText = selection.string ?? ""
        guard !selText.isEmpty else { return nil }
        let bounds = selection.bounds(for: page)
        let probePoint = CGPoint(x: bounds.minX + 1, y: bounds.midY)
        let charIndex = page.characterIndex(at: probePoint)
        if charIndex >= 0 { return charIndex }
        // Fallback: substring search.
        let ns = pageString as NSString
        let r = ns.range(of: selText)
        return r.location == NSNotFound ? nil : r.location
    }
}
