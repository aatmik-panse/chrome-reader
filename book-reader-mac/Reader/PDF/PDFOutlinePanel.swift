import SwiftUI
import PDFKit

/// Recursive disclosure tree for `PDFDocument.outlineRoot`. Clicking an
/// entry navigates the supplied PDFView to the entry's destination.
struct PDFOutlinePanel: View {
    let document: PDFDocument
    weak var pdfView: PDFView?

    var body: some View {
        if let root = document.outlineRoot, root.numberOfChildren > 0 {
            List {
                outlineRows(node: root)
            }
            .listStyle(.sidebar)
        } else {
            Text("No outline available")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding()
        }
    }

    private func outlineRows(node: PDFOutline) -> AnyView {
        AnyView(
            ForEach(0..<node.numberOfChildren, id: \.self) { i in
                let child = node.child(at: i)!
                if child.numberOfChildren == 0 {
                    Button(action: { go(to: child) }) {
                        Text(child.label ?? "Untitled")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                } else {
                    DisclosureGroup(child.label ?? "Untitled") {
                        outlineRows(node: child)
                    }
                }
            }
        )
    }

    private func go(to entry: PDFOutline) {
        guard let pdfView, let destination = entry.destination else { return }
        pdfView.go(to: destination)
    }
}
