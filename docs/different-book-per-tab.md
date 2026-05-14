# Different Book Per Tab — Plan

> Status: **Deferred** — kept as reference, not currently scheduled for implementation. See "Honest tradeoffs" below.

## Context

Today the extension stores a single global "current book" in `chrome.storage.local.current_book`. Every new tab reads the same value, so opening multiple new tabs in the same window all land on the same book.

The user wants to **manually assign books to specific tab slots** — e.g. *Tab 1 → Book A, Tab 2 → Book B, Tab 3 → Book C* — so they can read three books in parallel by opening three new tabs. UX must stay simple: no toasts, no extra chrome, no rotation algorithms. The TopBar already shows the current book title, which is enough confirmation.

## Behavior

- **Toggle in Settings**, default off. When off, behavior is identical to today (single global book).
- **User configures slots** 1..N in Settings. Each slot is one row: `Slot 1 → [book picker]`. Add/remove slots. Slot N+1 etc. fall back to today's behavior (last opened book).
- **On new tab open**: the page asks the service worker for its `tab.id`, then claims the **lowest unused slot** among open tabs and loads that slot's book.
- **Sticky per tab**: assignment lives in `chrome.storage.session` keyed by `tab.id`. Reloading the tab keeps the same book. Closing the tab frees the slot (service worker listens to `tabs.onRemoved`).
- **Manual book switch** inside a tab (via LibraryPanel) overrides the slot's book *for that tab only* until close. The configured slot mapping is untouched.
- **Browser restart** clears `chrome.storage.session`, so slot allocation restarts from slot 1 on the next session — by design.
- **No toast.** TopBar at `src/newtab/components/shell/TopBar.tsx` already shows the title.

## Files to modify

### New files
- `src/newtab/lib/tab-slots.ts` — slot allocation + lookup. Exports:
  - `getMyTabId(): Promise<number | null>` — wraps `chrome.tabs.getCurrent()`.
  - `claimSlotForTab(tabId, configuredSlots): Promise<{ slot, bookHash } | null>` — reads `chrome.storage.session.tab_slot_map`, finds lowest unused slot, writes back atomically.
  - `getAssignmentForTab(tabId): Promise<{ slot, bookHash } | null>`.
  - `setAssignmentForTab(tabId, bookHash)` — used when user manually switches book inside an assigned tab.

- `src/newtab/components/settings/TabSlotsSettings.tsx` — Clay-styled list of slot rows. Each row: slot number badge (`.clay-label`), book cover thumbnail + title selector (reuses `useBookThumbnail` from `src/newtab/hooks/useBookThumbnail.ts` and the cover render pattern from `LibraryPanel.tsx`), remove (×) button. Footer: `+ Add slot` (`.clay-btn-white`). Top: master toggle "Different book per tab" using the existing `Toggle` component from `Settings.tsx` (lines 80–93).

### Edits
- `src/newtab/lib/storage.ts` — extend `ReaderSettings` (around lines 146–274) with:
  ```ts
  tabSlotsEnabled?: boolean;       // default false
  tabSlots?: { slot: number; bookHash: string }[];  // ordered by slot asc
  ```
  No migration needed (optional fields).

- `src/newtab/hooks/useBook.ts` (lines 237–247, the bootstrap `useEffect`):
  - If `settings.tabSlotsEnabled && settings.tabSlots?.length`:
    1. `const tabId = await getMyTabId()`
    2. `const existing = await getAssignmentForTab(tabId)` — reload of an already-assigned tab.
    3. If none, `const claim = await claimSlotForTab(tabId, settings.tabSlots)`.
    4. If a claim exists, call `loadBookFromHash(claim.bookHash)` instead of `getCurrentBook()`.
    5. Else fall back to current `getCurrentBook()` flow (slot exhausted).
  - When `switchBook(hash)` is called and the tab has an assignment, update `setAssignmentForTab(tabId, hash)` so reload stays on the manually chosen book.

- `src/newtab/components/Settings.tsx` — add a section to the `SECTIONS` array (around lines 31–78): `{ key: 'tabs', label: 'New Tab', icon: ... }`, render `<TabSlotsSettings />` in the body.

- `src/background/service-worker.ts` — register `chrome.tabs.onRemoved.addListener(tabId => removeFromSession(tabId))` so closed tabs free their slot. Uses `chrome.storage.session` directly; no new permission required (no `tab.url` access needed).

### No changes needed
- `public/manifest.json` — `chrome.tabs.getCurrent()` and `chrome.tabs.onRemoved` do not require the `tabs` permission (no URL/title access).
- Position/highlights/vocab — they're keyed by book hash, not by tab. Reading two books in parallel just writes to two different `pos_<hash>` entries. Already works.

## UI/UX details

- Settings section visual: matches existing Reader section pattern. Slot rows are `.clay-card` with 12–16px padding; cover thumb is the 9×12 style used in `LibraryPanel.tsx`; the picker is a native `<select>` styled with Clay tokens (consistent with rest of Settings — no popup picker complexity in v1).
- Empty configured list: shows a one-line hint "Pick a book for each tab slot." inside the section. Add-slot button below.
- If a referenced book was deleted from the library: row shows `Slot N → (missing book)` with a remove button. New tabs claiming that slot fall through to the next slot.
- The toggle being off hides the slot list entirely to keep the section quiet.

## Honest tradeoffs (added after review)

Reasons this feature may not be worth building:

- **Low coverage**: only the first N tabs of a browser session get unique books; tab N+1 onward is identical to today. Most users open many more than 3 new tabs per session.
- **Invisible mapping**: there is no visible link between a Chrome tab and "slot 2." The lowest-unused-slot rule is implicit. Users can't deliberately put Book B in a specific tab.
- **Setup cost vs payoff**: the user must configure each slot in Settings. The Library panel is already a 2-click switch, so the saving is small unless the user reads ≥2 books in strict parallel and re-opens the tabs daily.
- **Edge-case surprise**: closing a tab silently frees its slot; the next new tab claims it. That's correct by design but can feel arbitrary.
- **Maintenance**: a new Settings section, a new storage shape, a service-worker listener, and a per-tab session map — non-trivial surface area for a niche feature.

### Lighter alternatives to consider first

- **Library cycle shortcut**: `Cmd+]` / `Cmd+[` to jump to next/previous book in the library. Zero config, scales past 3 books, works in any tab.
- **Quick switcher (`Cmd+K`)**: type to fuzzy-find a book and switch. Faster than the Library panel for users with many books.
- **"Recent books" strip** in the empty state or TopBar overflow: one-click switch to the last 3–5 read books.

These deliver most of the practical value ("read multiple books, switch fast") without per-tab state or configuration.

## Verification

1. `cd book-reader-extension && npm run build`, then reload the unpacked extension at `chrome://extensions`.
2. Library must have ≥3 books. Open Settings → New Tab → enable toggle → assign Slot 1, 2, 3 to three different books.
3. Open three new tabs in succession; each TopBar should show a distinct title (slots claimed in order). Order independence: closing tab 2, then opening a new tab, should reuse slot 2 (lowest free).
4. Reload tab 2 — title must stay the same (sticky).
5. In tab 2, open Library panel and switch to a fourth book — reload should keep that fourth book (per-tab override).
6. Disable the toggle — new tabs revert to the global `current_book` behavior.
7. Restart Chrome — slots reallocate from slot 1 on next session (`chrome.storage.session` cleared by design).
8. Run `npm test` — no existing tests touch this path, but new logic in `tab-slots.ts` should get unit tests under `tests/tab-slots/` using `fake-indexeddb` setup (chrome.storage mock may need a small stub; check `tests/setup.ts`).
</content>
</invoke>