import Foundation
import WebKit
import os

/// Backing store for chrome.storage.local. Keys are namespaced `wk_` in
/// UserDefaults so they don't collide with native preferences.
///
/// Supported `chrome.*` surface (see Reader/Web/CHROME_SURFACE.md):
///   - chrome.storage.local.{get,set,remove}
///   - chrome.storage.onChanged.addListener
///   - chrome.runtime.getURL
///   - chrome.runtime.openOptionsPage (stubbed to a notification)
///   - chrome.identity.{getAuthToken,clearAllCachedAuthTokens} (no-op stubs)
///
/// Anything else logs once and returns undefined.
final class WebReaderStorage {
    enum Query {
        case array([String])
        case object([String: Any])    // keys → defaults
        case allKeys
    }

    struct Change {
        let oldValue: Any?
        let newValue: Any?
    }

    private static let prefix = "wk_"
    private let defaults: UserDefaults
    private var listeners: [(([String: Change]) -> Void)] = []
    private let queue = DispatchQueue(label: "WebReaderStorage", attributes: .concurrent)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func get(_ query: Query) -> [String: Any] {
        switch query {
        case .array(let keys):
            var out: [String: Any] = [:]
            for k in keys {
                if let v = defaults.object(forKey: Self.prefix + k) { out[k] = v }
            }
            return out
        case .object(let defaultsMap):
            var out: [String: Any] = [:]
            for (k, def) in defaultsMap {
                out[k] = defaults.object(forKey: Self.prefix + k) ?? def
            }
            return out
        case .allKeys:
            var out: [String: Any] = [:]
            for (k, v) in defaults.dictionaryRepresentation() where k.hasPrefix(Self.prefix) {
                out[String(k.dropFirst(Self.prefix.count))] = v
            }
            return out
        }
    }

    func set(_ items: [String: Any]) {
        var changes: [String: Change] = [:]
        for (k, newValue) in items {
            let storageKey = Self.prefix + k
            let oldValue = defaults.object(forKey: storageKey)
            defaults.set(newValue, forKey: storageKey)
            changes[k] = Change(oldValue: oldValue, newValue: newValue)
        }
        notify(changes: changes)
    }

    func remove(_ query: Query) {
        var changes: [String: Change] = [:]
        let keys: [String]
        switch query {
        case .array(let arr): keys = arr
        case .object(let obj): keys = Array(obj.keys)
        case .allKeys:
            keys = defaults.dictionaryRepresentation().keys
                .filter { $0.hasPrefix(Self.prefix) }
                .map { String($0.dropFirst(Self.prefix.count)) }
        }
        for k in keys {
            let storageKey = Self.prefix + k
            let oldValue = defaults.object(forKey: storageKey)
            defaults.removeObject(forKey: storageKey)
            changes[k] = Change(oldValue: oldValue, newValue: nil)
        }
        notify(changes: changes)
    }

    func onChange(_ listener: @escaping ([String: Change]) -> Void) {
        queue.async(flags: .barrier) { self.listeners.append(listener) }
    }

    private func notify(changes: [String: Change]) {
        queue.sync {
            for l in listeners { l(changes) }
        }
    }
}

/// Routes `window.webkit.messageHandlers.bridge.postMessage(...)` calls from
/// the embedded React reader to native handlers.
///
/// Wire protocol (JSON):
///   { id: string, api: "storage.get"|"storage.set"|"storage.remove"
///                    | "storage.allKeys"|"runtime.openOptionsPage"
///                    | "identity.getAuthToken"|"identity.clearAllCachedAuthTokens"
///                    | "ai.stream",
///     args: <api-specific> }
///
/// Replies posted to JS by evaluating `window.__wkBridgeReply(id, payload)`.
@MainActor
final class WebReaderBridge: NSObject, WKScriptMessageHandler {
    static let messageName = "bridge"
    static let logger = Logger(subsystem: "com.profitoniumapps.instantbookreader",
                               category: "WebReaderBridge")

    private weak var webView: WKWebView?
    private let storage: WebReaderStorage

    init(storage: WebReaderStorage) {
        self.storage = storage
        super.init()
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
        storage.onChange { [weak self] changes in
            Task { @MainActor in self?.emitStorageChanged(changes) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let payload = message.body as? [String: Any],
              let id = payload["id"] as? String,
              let api = payload["api"] as? String else {
            Self.logger.error("dropped malformed bridge message")
            return
        }
        let args = payload["args"] as? [String: Any] ?? [:]
        handle(api: api, args: args, id: id)
    }

    private func handle(api: String, args: [String: Any], id: String) {
        switch api {
        case "storage.get":
            let query = parseQuery(args["keys"])
            reply(id: id, payload: storage.get(query))
        case "storage.set":
            if let items = args["items"] as? [String: Any] { storage.set(items) }
            reply(id: id, payload: [String: Any]())
        case "storage.remove":
            storage.remove(parseQuery(args["keys"]))
            reply(id: id, payload: [String: Any]())
        case "storage.allKeys":
            reply(id: id, payload: storage.get(.allKeys))
        case "runtime.openOptionsPage":
            NotificationCenter.default.post(name: .openSettingsRequested, object: nil)
            reply(id: id, payload: [String: Any]())
        case "identity.getAuthToken":
            reply(id: id, payload: ["error": "not signed in"])
        case "identity.clearAllCachedAuthTokens":
            reply(id: id, payload: [String: Any]())
        case "ai.stream":
            // Plan 4 fills this in. For now respond with an explicit stub.
            reply(id: id, payload: ["error": "ai-not-configured"])
        default:
            Self.logger.notice("unhandled bridge api: \(api, privacy: .public)")
            reply(id: id, payload: ["error": "unsupported"])
        }
    }

    private func parseQuery(_ raw: Any?) -> WebReaderStorage.Query {
        if raw == nil { return .allKeys }
        if let s = raw as? String { return .array([s]) }
        if let arr = raw as? [String] { return .array(arr) }
        if let obj = raw as? [String: Any] { return .object(obj) }
        return .allKeys
    }

    private func reply(id: String, payload: [String: Any]) {
        guard let webView else { return }
        let json = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let js = "window.__wkBridgeReply && window.__wkBridgeReply(\(jsString(id)), \(json));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func emitStorageChanged(_ changes: [String: WebReaderStorage.Change]) {
        guard let webView else { return }
        var dict: [String: [String: Any]] = [:]
        for (k, c) in changes {
            var inner: [String: Any] = [:]
            if let o = c.oldValue { inner["oldValue"] = o }
            if let n = c.newValue { inner["newValue"] = n }
            dict[k] = inner
        }
        let json = (try? JSONSerialization.data(withJSONObject: dict))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let js = "window.__wkStorageChanged && window.__wkStorageChanged(\(json), 'local');"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    private func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
        let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(str.dropFirst().dropLast())
    }
}

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("InstantBookReader.openSettingsRequested")
}
