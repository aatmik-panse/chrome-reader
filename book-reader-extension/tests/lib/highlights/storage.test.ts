import { describe, it, expect, beforeEach } from "vitest";
import "fake-indexeddb/auto";
import {
  putHighlight,
  listHighlights,
  deleteHighlight,
} from "../../../src/newtab/lib/highlights/storage";
import { Highlight } from "../../../src/newtab/lib/highlights/types";

function fixture(overrides: Partial<Highlight> = {}): Highlight {
  const now = Date.now();
  return {
    id: crypto.randomUUID(),
    bookHash: "bookA",
    anchor: { chapterIndex: 0, startOffset: 0, length: 4, contextBefore: "", contextAfter: "" },
    text: "test",
    color: "yellow",
    createdAt: now,
    updatedAt: now,
    ...overrides,
  };
}

describe("highlights storage", () => {
  beforeEach(async () => {
    await new Promise<void>((resolve) => {
      const req = indexedDB.deleteDatabase("book-reader-highlights");
      req.onsuccess = () => resolve();
      req.onerror = () => resolve();
      req.onblocked = () => resolve();
    });
  });

  it("persists and lists highlights by book", async () => {
    const a = fixture({ bookHash: "bookA" });
    const b = fixture({ bookHash: "bookB" });
    await putHighlight(a);
    await putHighlight(b);
    const list = await listHighlights("bookA");
    expect(list).toHaveLength(1);
    expect(list[0].id).toBe(a.id);
  });

  it("deletes a highlight", async () => {
    const h = fixture();
    await putHighlight(h);
    await deleteHighlight(h.id);
    const list = await listHighlights(h.bookHash);
    expect(list).toHaveLength(0);
  });
});
