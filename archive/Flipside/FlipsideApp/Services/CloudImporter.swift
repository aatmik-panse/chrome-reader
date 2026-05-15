import Foundation
import UniformTypeIdentifiers

// MARK: - Cloud Provider

enum CloudProvider: String, CaseIterable, Identifiable, Sendable {
    case iCloud
    case dropbox
    case googleDrive

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iCloud: "iCloud Drive"
        case .dropbox: "Dropbox"
        case .googleDrive: "Google Drive"
        }
    }

    var iconSystemName: String {
        switch self {
        case .iCloud: "icloud"
        case .dropbox: "arrow.down.doc"
        case .googleDrive: "externaldrive"
        }
    }

    var supportedTypes: [UTType] {
        [.pdf, .plainText, .epub].compactMap { $0 }
    }
}

// MARK: - CloudImporter

struct CloudImporter: Sendable {

    func isAvailable(_ provider: CloudProvider) -> Bool {
        switch provider {
        case .iCloud:
            return true
        case .dropbox:
            return false
        case .googleDrive:
            return false
        }
    }

    func presentPicker(for provider: CloudProvider) -> URL? {
        switch provider {
        case .iCloud:
            return nil
        case .dropbox:
            return nil
        case .googleDrive:
            return nil
        }
    }

    func availableProviders() -> [CloudProvider] {
        CloudProvider.allCases.filter { isAvailable($0) }
    }

    func allProviders() -> [(provider: CloudProvider, available: Bool)] {
        CloudProvider.allCases.map { ($0, isAvailable($0)) }
    }
}

// MARK: - UTType EPUB

private extension UTType {
    static let epub = UTType("org.idpf.epub-container")
}
