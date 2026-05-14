import { describe, it, expect, beforeEach } from "vitest";
import "fake-indexeddb/auto";
import {
  upsertVocab,
  getVocabByWord,
  listVocab,
  deleteVocab,
  listDueWords,
} from "../../../src/newtab/lib/vocab/storage";
import { VocabWord, VocabContext } from "../../../src/newtab/lib/vocab/types";

const NOW = 1_700_000_000_000;
const DAY = 24 * 3600 * 1000;

function ctx(overrides: Partial<VocabContext> = {}): VocabContext {
  return {
    bookHash: "bookA",
    bookTitle: "Book A",
    chapterIndex: 0,
    sentence: "an example sentence with the word",
    savedAt: NOW,
    ...overrides,
  };
}

function fixture(overrides: Partial<VocabWord> = {}): VocabWord {
  return {
    id: crypto.randomUUID(),
    word: "elucidate",
    definitions: [{ partOfSpeech: "verb", definition: "make clear" }],
    contexts: [ctx()],
    stage: 0,
    mastered: false,
    nextReviewAt: NOW,
    correctStreak: 0,
    createdAt: NOW,
    updatedAt: NOW,
    ...overrides,
  };
}

describe("vocab storage", () => {
  beforeEach(async () => {
    await new Promise<void>((resolve) => {
      const req = indexedDB.deleteDatabase("book-reader-vocab");
      req.onsuccess = () => resolve();
      req.onerror = () => resolve();
      req.onblocked = () => resolve();
    });
  });

  it("inserts a new word and lists it", async () => {
    const w = fixture();
    await upsertVocab(w);
    const list = await listVocab();
    expect(list).toHaveLength(1);
    expect(list[0].word).toBe("elucidate");
  });

  it("dedupes by word: defining same word twice merges contexts", async () => {
    const a = fixture({ word: "elucidate", contexts: [ctx({ bookHash: "bookA" })] });
    await upsertVocab(a);
    const b = fixture({ id: crypto.randomUUID(), word: "elucidate", contexts: [ctx({ bookHash: "bookB" })] });
    await upsertVocab(b);
    const found = await getVocabByWord("elucidate");
    expect(found).not.toBeNull();
    expect(found!.contexts).toHaveLength(2);
    expect(found!.contexts.map((c) => c.bookHash)).toEqual(["bookA", "bookB"]);
  });

  it("dedupe is case-insensitive", async () => {
    await upsertVocab(fixture({ word: "Elucidate" }));
    const found = await getVocabByWord("elucidate");
    expect(found).not.toBeNull();
    expect(found!.word).toBe("elucidate");
  });

  it("deletes a word and excludes from listVocab", async () => {
    const w = fixture();
    await upsertVocab(w);
    await deleteVocab(w.id);
    const list = await listVocab();
    expect(list).toHaveLength(0);
  });

  it("listDueWords returns words with nextReviewAt <= now and not mastered", async () => {
    const due = fixture({ word: "due", nextReviewAt: NOW - 1 });
    const future = fixture({ word: "future", nextReviewAt: NOW + 7 * DAY });
    const mastered = fixture({ word: "done", nextReviewAt: NOW - 1, mastered: true });
    await upsertVocab(due);
    await upsertVocab(future);
    await upsertVocab(mastered);
    const list = await listDueWords(NOW);
    expect(list.map((w) => w.word).sort()).toEqual(["due"]);
  });
});
