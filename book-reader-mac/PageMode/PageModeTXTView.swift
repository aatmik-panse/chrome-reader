import SwiftUI

/// Page-mode TXT renderer. Native SwiftUI — no WKWebView. Chunks the file
/// by paragraphs and shows the slice that fits inside the safe column at
/// the current `Position.anchor` character offset.
struct PageModeTXTView: View {

    let book: Book
    let charOffset: Int
    let safeColumnWidth: CGFloat
    let bodyPointSize: CGFloat
    let pendingScrollDirection: String?
    let onPendingConsumed: () -> Void

    @State private var chunkText: String = ""
    @State private var currentOffset: Int = 0

    var body: some View {
        GeometryReader { geo in
            let column = SafeColumn.frame(
                for: CGRect(origin: .zero, size: geo.size),
                placement: .center,
                width: safeColumnWidth
            )
            HStack(spacing: 0) {
                Spacer(minLength: column.minX)
                Text(chunkText)
                    .font(.system(size: bodyPointSize, design: .serif))
                    .lineSpacing(bodyPointSize * 0.5)
                    .multilineTextAlignment(.leading)
                    .frame(width: column.width, alignment: .topLeading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 48)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onAppear { load(at: charOffset, viewportSize: nil) }
        .onChange(of: charOffset) { _, newValue in
            currentOffset = newValue
            load(at: newValue, viewportSize: nil)
        }
        .onChange(of: pendingScrollDirection) { _, direction in
            guard let direction else { return }
            advance(direction: direction)
            onPendingConsumed()
        }
    }

    private func load(at offset: Int, viewportSize: CGSize?) {
        let url = AppSupportPaths.books.appendingPathComponent(book.filePath)
        guard let data = try? Data(contentsOf: url),
              let full = String(data: data, encoding: .utf8) else {
            chunkText = ""
            return
        }
        let start = max(0, min(offset, full.count))
        let length = chunkLength(forPointSize: bodyPointSize)
        let endIdx = min(full.count, start + length)
        let lower = full.index(full.startIndex, offsetBy: start)
        let upper = full.index(full.startIndex, offsetBy: endIdx)
        chunkText = String(full[lower..<upper])
        currentOffset = start
    }

    private func advance(direction: String) {
        let url = AppSupportPaths.books.appendingPathComponent(book.filePath)
        guard let data = try? Data(contentsOf: url),
              let full = String(data: data, encoding: .utf8) else { return }
        let length = chunkLength(forPointSize: bodyPointSize)
        let delta = direction == "previous" ? -length : length
        let next = max(0, min(full.count - 1, currentOffset + delta))
        let endIdx = min(full.count, next + length)
        let lower = full.index(full.startIndex, offsetBy: next)
        let upper = full.index(full.startIndex, offsetBy: endIdx)
        chunkText = String(full[lower..<upper])
        currentOffset = next
    }

    /// Character window per screen. A 13" MBP at 22pt fits ~1800 chars; we
    /// scale linearly with the inverse of point size so 30pt fits ~1300.
    private func chunkLength(forPointSize size: CGFloat) -> Int {
        let base: CGFloat = 1800
        let baseSize: CGFloat = 22
        let scaled = base * (baseSize / max(size, 1))
        return max(400, Int(scaled))
    }
}
