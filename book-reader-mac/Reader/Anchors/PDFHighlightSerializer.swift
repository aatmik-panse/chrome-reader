import Foundation

/// Serializes a PDFAnchorResolver.Anchor into the `surroundingText: String`
/// column of the SwiftData Highlight model. JSON-encoded so we don't depend
/// on schema migrations to widen the model.
struct PDFHighlightSerializer {
    enum Error: Swift.Error { case malformed }

    func encode(_ anchor: PDFAnchorResolver.Anchor) -> String {
        let payload: [String: Any] = [
            "pageIndex": anchor.pageIndex,
            "text": anchor.text,
            "inner": [
                "startOffset": anchor.inner.startOffset,
                "length": anchor.inner.length,
                "contextBefore": anchor.inner.contextBefore,
                "contextAfter": anchor.inner.contextAfter
            ]
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func decode(_ string: String) throws -> PDFAnchorResolver.Anchor {
        guard let data = string.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pageIndex = obj["pageIndex"] as? Int,
              let text = obj["text"] as? String,
              let inner = obj["inner"] as? [String: Any],
              let startOffset = inner["startOffset"] as? Int,
              let length = inner["length"] as? Int,
              let contextBefore = inner["contextBefore"] as? String,
              let contextAfter = inner["contextAfter"] as? String
        else { throw Error.malformed }
        return PDFAnchorResolver.Anchor(
            pageIndex: pageIndex,
            text: text,
            inner: HighlightAnchor(startOffset: startOffset,
                                   length: length,
                                   contextBefore: contextBefore,
                                   contextAfter: contextAfter)
        )
    }
}
