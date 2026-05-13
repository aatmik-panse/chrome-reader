import Foundation
import WebKit

/// Serves the bookreader:// scheme. Two URL shapes:
///
///   bookreader://current
///       → returns bytes of the currently active book.
///   bookreader://app/<relative-path>
///       → returns a file from the WebReader.bundle resource. Used by the
///         extension's chrome.runtime.getURL() stub for asset loads.
@MainActor
final class BookURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private let loader: BookContentLoader
    private let bundleURL: URL
    private let getCurrent: () -> (hash: String, ext: String)?

    init(loader: BookContentLoader,
         bundleURL: URL,
         getCurrent: @escaping () -> (hash: String, ext: String)?) {
        self.loader = loader
        self.bundleURL = bundleURL
        self.getCurrent = getCurrent
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        switch url.host {
        case "current":
            handleCurrent(task: urlSchemeTask)
        case "app":
            handleApp(url: url, task: urlSchemeTask)
        default:
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        // No-op: synchronous handlers.
    }

    private func handleCurrent(task: any WKURLSchemeTask) {
        guard let current = getCurrent() else {
            task.didFailWithError(URLError(.resourceUnavailable))
            return
        }
        do {
            let data = try loader.read(hash: current.hash, ext: current.ext)
            respond(task: task,
                    url: task.request.url!,
                    data: data,
                    mime: BookContentLoader.mimeType(forExtension: current.ext))
        } catch {
            task.didFailWithError(error)
        }
    }

    private func handleApp(url: URL, task: any WKURLSchemeTask) {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fileURL = bundleURL.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = BookContentLoader.mimeType(forExtension: fileURL.pathExtension)
        respond(task: task, url: url, data: data, mime: mime)
    }

    private func respond(task: any WKURLSchemeTask, url: URL, data: Data, mime: String) {
        let headers = [
            "Content-Type": mime,
            "Content-Length": "\(data.count)",
            "Access-Control-Allow-Origin": "*"
        ]
        let response = HTTPURLResponse(url: url,
                                       statusCode: 200,
                                       httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }
}
