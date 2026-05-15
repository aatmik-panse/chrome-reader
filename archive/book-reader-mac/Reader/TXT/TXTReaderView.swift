import SwiftUI

/// Plain text reader. Splits the document into ~4 KB chunks rendered as
/// separate `Text` views inside a ScrollView, so SwiftUI's diffing stays
/// cheap on long files. Position anchor is the leading UTF-16 offset of the
/// chunk most visible in the scroll viewport.
struct TXTReaderView: View {
    let book: Book
    let plainText: String
    @Environment(\.appTheme) private var theme
    @Binding var currentOffset: Int
    @Binding var selectedRange: NSRange?
    let onSelectionRect: (CGRect?, String) -> Void

    private static let chunkSize = 4_096

    private struct Chunk: Identifiable {
        let id: Int      // chunk index
        let startOffset: Int
        let text: String
    }

    private var chunks: [Chunk] {
        let ns = plainText as NSString
        let total = ns.length
        var out: [Chunk] = []
        var i = 0
        var idx = 0
        while i < total {
            let len = min(Self.chunkSize, total - i)
            out.append(Chunk(id: idx, startOffset: i, text: ns.substring(with: NSRange(location: i, length: len))))
            i += len
            idx += 1
        }
        return out
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(chunks) { chunk in
                        Text(chunk.text)
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .foregroundStyle(theme.ink.swiftUI)
                            .textSelection(.enabled)
                            .frame(maxWidth: 720, alignment: .leading)
                            .padding(.horizontal, 48)
                            .id(chunk.id)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: TXTVisibleChunkKey.self,
                                        value: geo.frame(in: .named("txt-scroll")).minY < 200
                                            ? chunk.startOffset
                                            : Int.max
                                    )
                                }
                            )
                    }
                }
                .padding(.vertical, 48)
            }
            .coordinateSpace(name: "txt-scroll")
            .onPreferenceChange(TXTVisibleChunkKey.self) { offset in
                if offset != Int.max && offset != currentOffset {
                    currentOffset = offset
                }
            }
        }
    }
}

private struct TXTVisibleChunkKey: PreferenceKey {
    static var defaultValue: Int = Int.max
    static func reduce(value: inout Int, nextValue: () -> Int) {
        value = min(value, nextValue())
    }
}
