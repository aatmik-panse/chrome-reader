import Foundation

enum BookFormat: String, Codable, CaseIterable, Sendable {
    case epub
    case pdf
    case txt

    var displayName: String {
        switch self {
        case .epub: "EPUB"
        case .pdf: "PDF"
        case .txt: "TXT"
        }
    }

    var fileExtension: String { rawValue }
}
