import { openDB, IDBPDatabase } from "idb";
import { VocabWord } from "./types";

const DB = "book-reader-vocab";
const STORE = "vocab";

let dbPromise: Promise<IDBPDatabase> | null = null;

async function getDB(): Promise<IDBPDatabase> {
  if (!dbPromise) {
    dbPromise = openDB(DB, 1, {
      upgrade(db) {
        if (!db.objectStoreNames.contains(STORE)) {
          const s = db.createObjectStore(STORE, { keyPath: "id" });
          s.createIndex("byWord", "word", { unique: false });
          s.createIndex("byNextReview", "nextReviewAt", { unique: false });
        }
      },
      blocking() {
        dbPromise?.then((d) => d.close()).catch(() => {});
        dbPromise = null;
      },
      terminated() {
        dbPromise = null;
      },
    });
  }
  return dbPromise;
}

function normWord(w: string): string {
  return w.trim().toLowerCase();
}

export async function getVocabByWord(word: string): Promise<VocabWord | null> {
  const db = await getDB();
  const lower = normWord(word);
  const all = (await db.getAllFromIndex(STORE, "byWord", lower)) as VocabWord[];
  return all.find((w) => !w.deleted) ?? null;
}

function dedupeContexts(arr: VocabWord["contexts"]): VocabWord["contexts"] {
  const seen = new Set<string>();
  const out: VocabWord["contexts"] = [];
  for (const c of arr) {
    const k = `${c.bookHash}::${c.chapterIndex}::${c.sentence}`;
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(c);
  }
  return out;
}

export async function upsertVocab(input: VocabWord): Promise<VocabWord> {
  const db = await getDB();
  const lower = normWord(input.word);
  const existing = await getVocabByWord(lower);
  const now = Date.now();
  if (existing) {
    const merged: VocabWord = {
      ...existing,
      contexts: dedupeContexts([...existing.contexts, ...input.contexts]),
      phonetic: existing.phonetic ?? input.phonetic,
      audioUrl: existing.audioUrl ?? input.audioUrl,
      definitions: existing.definitions.length > 0 ? existing.definitions : input.definitions,
      updatedAt: now,
    };
    await db.put(STORE, merged);
    return merged;
  }
  const fresh: VocabWord = { ...input, word: lower };
  await db.put(STORE, fresh);
  return fresh;
}

export async function getVocab(id: string): Promise<VocabWord | null> {
  const db = await getDB();
  return ((await db.get(STORE, id)) as VocabWord | undefined) ?? null;
}

export async function listVocab(): Promise<VocabWord[]> {
  const db = await getDB();
  const all = (await db.getAll(STORE)) as VocabWord[];
  return all.filter((w) => !w.deleted);
}

export async function listDueWords(now: number): Promise<VocabWord[]> {
  const all = await listVocab();
  return all
    .filter((w) => !w.mastered && w.nextReviewAt <= now)
    .sort((a, b) => a.nextReviewAt - b.nextReviewAt);
}

export async function deleteVocab(id: string): Promise<void> {
  const db = await getDB();
  await db.delete(STORE, id);
}
