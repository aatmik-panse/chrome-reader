import { db } from "../db/index.js";
import { highlights } from "../db/schema.js";
import { and, eq, isNull } from "drizzle-orm";

export interface HighlightInput {
  clientId: string;
  bookHash: string;
  chapterIndex: number;
  startOffset: number;
  length: number;
  contextBefore: string;
  contextAfter: string;
  text: string;
  color: string;
  note?: string | null;
}

export async function listHighlightsForBook(userId: string, bookHash: string) {
  return db
    .select()
    .from(highlights)
    .where(
      and(
        eq(highlights.userId, userId),
        eq(highlights.bookHash, bookHash),
        isNull(highlights.deletedAt)
      )
    );
}

export async function upsertHighlight(userId: string, input: HighlightInput) {
  const existing = await db
    .select()
    .from(highlights)
    .where(and(eq(highlights.userId, userId), eq(highlights.clientId, input.clientId)))
    .limit(1)
    .then((rows) => rows[0] ?? null);

  if (existing) {
    await db
      .update(highlights)
      .set({
        chapterIndex: input.chapterIndex,
        startOffset: input.startOffset,
        length: input.length,
        contextBefore: input.contextBefore,
        contextAfter: input.contextAfter,
        text: input.text,
        color: input.color,
        note: input.note ?? null,
        updatedAt: new Date(),
        deletedAt: null,
      })
      .where(eq(highlights.id, existing.id));
    return { id: existing.id, clientId: input.clientId };
  }

  const inserted = await db
    .insert(highlights)
    .values({
      userId,
      clientId: input.clientId,
      bookHash: input.bookHash,
      chapterIndex: input.chapterIndex,
      startOffset: input.startOffset,
      length: input.length,
      contextBefore: input.contextBefore,
      contextAfter: input.contextAfter,
      text: input.text,
      color: input.color,
      note: input.note ?? null,
    })
    .returning({ id: highlights.id });
  return { id: inserted[0].id, clientId: input.clientId };
}

export async function softDeleteHighlight(userId: string, clientId: string) {
  await db
    .update(highlights)
    .set({ deletedAt: new Date(), updatedAt: new Date() })
    .where(and(eq(highlights.userId, userId), eq(highlights.clientId, clientId)));
}
