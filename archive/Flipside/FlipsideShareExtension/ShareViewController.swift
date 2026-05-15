import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        handleSharedFiles()
    }

    private func handleSharedFiles() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeRequest()
            return
        }

        let supportedTypes: [UTType] = [.epub, .pdf, .plainText]

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                for type in supportedTypes {
                    if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [weak self] url, error in
                            guard let url, error == nil else {
                                self?.completeRequest()
                                return
                            }
                            self?.copyToAppGroup(url: url)
                        }
                        return
                    }
                }
            }
        }

        completeRequest()
    }

    private func copyToAppGroup(url: URL) {
        let manager = FileManager.default
        guard let containerURL = manager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.flipside.reader"
        ) else {
            completeRequest()
            return
        }

        let booksDir = containerURL.appendingPathComponent("SharedImports", isDirectory: true)
        try? manager.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let destURL = booksDir.appendingPathComponent(url.lastPathComponent)
        try? manager.removeItem(at: destURL)

        do {
            try manager.copyItem(at: url, to: destURL)

            let defaults = UserDefaults(suiteName: "group.com.flipside.reader")
            var pending = defaults?.stringArray(forKey: "pendingImports") ?? []
            pending.append(destURL.lastPathComponent)
            defaults?.set(pending, forKey: "pendingImports")
        } catch {
            // File copy failed silently — main app will handle missing files
        }

        completeRequest()
    }

    private func completeRequest() {
        DispatchQueue.main.async {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
