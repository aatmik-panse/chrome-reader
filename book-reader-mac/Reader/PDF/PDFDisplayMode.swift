import PDFKit

enum PDFDisplayModeOption: String, CaseIterable, Identifiable, Sendable {
    case singlePage
    case singlePageContinuous
    case twoUp
    case twoUpContinuous

    var id: String { rawValue }

    var pdfKit: PDFDisplayMode {
        switch self {
        case .singlePage:           return .singlePage
        case .singlePageContinuous: return .singlePageContinuous
        case .twoUp:                return .twoUp
        case .twoUpContinuous:      return .twoUpContinuous
        }
    }

    var label: String {
        switch self {
        case .singlePage:           return "Single page"
        case .singlePageContinuous: return "Continuous"
        case .twoUp:                return "Spread"
        case .twoUpContinuous:      return "Continuous spread"
        }
    }
}
