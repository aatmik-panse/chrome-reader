/**
 * Bookmarks (a.k.a. favourite pages / chapters) live in `chrome.storage.local`
 * under `bookmarks_<bookHash>` and are stored as a sorted unique number[] of
 * spine indices (0-based). For PDFs spineIndex === pageNumber - 1; for EPUBs
 * it's the chapter index; for TXT books it's the chunk index. The reader code
 * already treats those uniformly, so a single storage shape works for every
 * format.
 *
 * We deliberately keep this out of the IndexedDB books schema because:
 *   - it's tiny (a handful of integers per book),
 *   - chrome.storage.local lets the (future) cloud-sync layer treat bookmarks
 *     the same way it already treats `pos_*` keys, and
 *   - it lets us read/write without spinning up the books DB on every toggle.
 */

const BOOKMARKS_KEY_PREFIX = "bookmarks_";

function storageKeyFor(bookHash: string): string {
  return `${BOOKMARKS_KEY_PREFIX}${bookHash}`;
}

function normalize(indices: Iterable<number>): number[] {
  // Strip non-finite + negative entries, dedupe, sort ascending so the UI can
  // iterate in a stable order without touching this module's invariants.
  const cleaned = new Set<number>();
  for (const value of indices) {
    if (!Number.isFinite(value)) continue;
    const intValue = Math.trunc(value);
    if (intValue < 0) continue;
    cleaned.add(intValue);
  }
  return Array.from(cleaned).sort((a, b) => a - b);
}

export async function getBookmarks(bookHash: string): Promise<number[]> {
  const key = storageKeyFor(bookHash);
  const result = await chrome.storage.local.get(key);
  const stored = result[key];
  if (!Array.isArray(stored)) return [];
  return normalize(stored as number[]);
}

export async function setBookmarks(bookHash: string, indices: Iterable<number>): Promise<number[]> {
  const next = normalize(indices);
  await chrome.storage.local.set({ [storageKeyFor(bookHash)]: next });
  return next;
}

export async function toggleBookmark(bookHash: string, spineIndex: number): Promise<number[]> {
  const current = await getBookmarks(bookHash);
  const idx = current.indexOf(spineIndex);
  const next = idx >= 0
    ? current.filter((_, i) => i !== idx)
    : normalize([...current, spineIndex]);
  await chrome.storage.local.set({ [storageKeyFor(bookHash)]: next });
  return next;
}

export async function clearBookmarks(bookHash: string): Promise<void> {
  await chrome.storage.local.remove(storageKeyFor(bookHash));
}
