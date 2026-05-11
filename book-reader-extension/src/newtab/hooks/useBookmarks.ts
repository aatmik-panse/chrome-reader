import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { getBookmarks, toggleBookmark } from "../lib/bookmarks/storage";

/**
 * Reactive bookmark state for a single book.
 *
 * Returns `bookmarks` as a Set for O(1) membership tests in render paths
 * (thumbnail strip, TOC) and `toggle` for the toolbar / context-menu calls.
 *
 * The hook owns the optimistic update so the UI flips instantly on click —
 * the storage write happens in the background, and `getBookmarks` is re-run
 * once on mount to hydrate from disk.
 */
export function useBookmarks(bookHash: string | null) {
  const [bookmarks, setBookmarks] = useState<Set<number>>(() => new Set());
  const bookHashRef = useRef<string | null>(null);
  bookHashRef.current = bookHash;

  useEffect(() => {
    if (!bookHash) {
      setBookmarks(new Set());
      return;
    }
    let cancelled = false;
    void getBookmarks(bookHash).then((indices) => {
      // Late hydration could otherwise overwrite a toggle that happened while
      // the read was in flight; bail if the book switched out from under us.
      if (cancelled || bookHashRef.current !== bookHash) return;
      setBookmarks(new Set(indices));
    });
    return () => {
      cancelled = true;
    };
  }, [bookHash]);

  const toggle = useCallback(
    (spineIndex: number) => {
      if (!bookHash || spineIndex < 0) return;
      setBookmarks((prev) => {
        const next = new Set(prev);
        if (next.has(spineIndex)) next.delete(spineIndex);
        else next.add(spineIndex);
        return next;
      });
      // Fire-and-forget — storage is the source of truth on next mount, but
      // the in-memory Set is the source of truth during this session.
      void toggleBookmark(bookHash, spineIndex);
    },
    [bookHash],
  );

  const isBookmarked = useCallback(
    (spineIndex: number) => bookmarks.has(spineIndex),
    [bookmarks],
  );

  // Sorted list for any UI that wants to iterate (e.g. a future "Bookmarks"
  // section). Memoised so we only re-sort when the Set actually changes.
  const sortedIndices = useMemo(
    () => Array.from(bookmarks).sort((a, b) => a - b),
    [bookmarks],
  );

  return { bookmarks, sortedIndices, toggle, isBookmarked };
}

export type UseBookmarksReturn = ReturnType<typeof useBookmarks>;
