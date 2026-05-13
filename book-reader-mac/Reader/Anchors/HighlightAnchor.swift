import Foundation

/// Content-addressed highlight anchor. Mirrors the extension's
/// `lib/highlights/anchor.ts`: stores surrounding text + offset rather than
/// DOM ranges, so highlights survive re-renders and reflow.
///
/// The Swift port treats `plainText` as a Swift String (Unicode-scalar safe)
/// but exposes offsets as `Int` measured in UTF-16 code units to match the
/// JS-side semantics used by the WKWebView reader. PDFKit clients convert
/// `String.utf16` offsets when going through `PDFPage.characterBounds(at:)`.
struct HighlightAnchor: Equatable, Sendable {
    var startOffset: Int
    var length: Int
    var contextBefore: String
    var contextAfter: String

    static let contextWindow = 50

    static func build(plainText: String, startOffset: Int, length: Int) -> HighlightAnchor {
        let utf16 = plainText.utf16
        let total = utf16.count
        let clampedStart = max(0, min(startOffset, total))
        let clampedEnd = max(clampedStart, min(startOffset + length, total))
        let beforeStart = max(0, clampedStart - contextWindow)
        let afterEnd = min(total, clampedEnd + contextWindow)
        return HighlightAnchor(
            startOffset: clampedStart,
            length: clampedEnd - clampedStart,
            contextBefore: substring(utf16: utf16, from: beforeStart, to: clampedStart),
            contextAfter: substring(utf16: utf16, from: clampedEnd, to: afterEnd)
        )
    }

    /// Returns the resolved range in `plainText`, or nil if the anchor cannot
    /// be located. Tries the literal offset first; then walks the text looking
    /// for `contextBefore` + (length-wide gap) + `contextAfter`.
    static func resolve(plainText: String, anchor: HighlightAnchor) -> (startOffset: Int, length: Int)? {
        let utf16 = plainText.utf16
        let total = utf16.count

        // Literal offset attempt.
        if anchor.startOffset + anchor.length <= total {
            let beforeStart = max(0, anchor.startOffset - contextWindow)
            let beforeSlice = substring(utf16: utf16, from: beforeStart, to: anchor.startOffset)
            let neededSuffixLen = min(contextWindow, anchor.contextBefore.utf16.count)
            let suffixUnits = Array(anchor.contextBefore.utf16.suffix(neededSuffixLen))
            let suffixString = utf16ToString(suffixUnits)
            if beforeSlice.hasSuffix(suffixString) || anchor.contextBefore.isEmpty {
                return (anchor.startOffset, anchor.length)
            }
        }

        // Both contexts empty → cannot disambiguate.
        if anchor.contextBefore.isEmpty && anchor.contextAfter.isEmpty {
            return nil
        }

        let probe = anchor.contextBefore
        let probeLen = probe.utf16.count
        let afterLen = anchor.contextAfter.utf16.count

        var from = 0
        while from <= total {
            let idx: Int
            if probeLen > 0 {
                guard let found = indexOf(needle: probe, in: utf16, from: from) else { return nil }
                idx = found
            } else {
                idx = 0
            }
            let candidateStart = idx + probeLen
            let candidateEnd = candidateStart + anchor.length
            if candidateEnd > total { return nil }
            let afterEnd = min(total, candidateEnd + afterLen)
            let afterSlice = substring(utf16: utf16, from: candidateEnd, to: afterEnd)
            if afterSlice == anchor.contextAfter || (afterLen == 0 && candidateEnd <= total) {
                return (candidateStart, anchor.length)
            }
            if probeLen == 0 { return nil }
            from = idx + 1
        }
        return nil
    }

    // MARK: - UTF-16 helpers

    private static func substring(utf16: String.UTF16View, from: Int, to: Int) -> String {
        guard from < to else { return "" }
        let start = utf16.index(utf16.startIndex, offsetBy: from)
        let end = utf16.index(utf16.startIndex, offsetBy: to)
        return utf16ToString(Array(utf16[start..<end]))
    }

    private static func utf16ToString(_ units: [UInt16]) -> String {
        var result = ""
        result.reserveCapacity(units.count)
        var decoder = UTF16()
        var iterator = units.makeIterator()
        Decode: while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar):
                result.unicodeScalars.append(scalar)
            case .emptyInput:
                break Decode
            case .error:
                result.unicodeScalars.append(Unicode.Scalar(0xFFFD)!)
            }
        }
        return result
    }

    private static func indexOf(needle: String, in haystack: String.UTF16View, from: Int) -> Int? {
        let needleUnits = Array(needle.utf16)
        if needleUnits.isEmpty { return from }
        let haystackUnits = Array(haystack)
        let n = haystackUnits.count
        let m = needleUnits.count
        if from + m > n { return nil }
        var i = from
        while i + m <= n {
            var k = 0
            while k < m && haystackUnits[i + k] == needleUnits[k] { k += 1 }
            if k == m { return i }
            i += 1
        }
        return nil
    }
}
