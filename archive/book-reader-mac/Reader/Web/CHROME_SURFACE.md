# chrome.* APIs the extension calls

Sourced from a grep over `book-reader-extension/src/newtab/`. The WKWebView
bridge in `WebReaderBridge.swift` must support the read paths; write paths
delegate to UserDefaults keyed by `wk_<name>`. Anything not listed here is a
no-op stub that logs to `os_log` and returns `undefined`.

## chrome.storage.local

- `chrome.storage.local.get(keys)` — keys is string | string[] | Record<string, unknown>.
  Returns `{ [key]: value }`. Bridge to UserDefaults keys prefixed `wk_`.
- `chrome.storage.local.set(items)` — items is `Record<string, unknown>`.
  Bridge to UserDefaults; emit synthetic onChanged events.
- `chrome.storage.local.remove(keys)` — keys is string | string[].
- `chrome.storage.onChanged.addListener(cb)` — cb receives
  `(changes: Record<string, {oldValue?: any, newValue?: any}>, areaName: 'local')`.

## chrome.runtime

- `chrome.runtime.getURL(path)` — returns `bookreader://app/<path>` so the web
  app can load assets via the same WKURLSchemeHandler that serves the book file.
- `chrome.runtime.openOptionsPage()` — stub. Opens the macOS Settings scene
  (Plan 7); for v1 of Plan 3 logs `os_log` and posts a Notification.

## chrome.identity (unused in offline reader path)

- `chrome.identity.getAuthToken(opts, cb)` — stub: returns
  `cb(undefined, chrome.runtime.lastError = { message: "not signed in" })`.
- `chrome.identity.clearAllCachedAuthTokens(cb)` — stub: `cb()`.

The Mac app does not call `book-reader-api` (spec §14). The extension's hooks
that depend on identity short-circuit when no token is returned, which is the
desired path here.

## chrome.alarms (background-only)

The new-tab page never registers chrome.alarms — only the service worker does.
The Mac shell never executes the service worker. No bridge needed.

## chrome.tabs

Not referenced in `src/newtab/`. Confirm with:

    grep -r "chrome.tabs" book-reader-extension/src/newtab

Expected: no matches. If matches appear, extend this file before changing the bridge.
