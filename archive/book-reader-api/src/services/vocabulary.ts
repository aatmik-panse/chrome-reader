import { db } from "../db/index.js";
import { vocabulary } from "../db/schema.js";
import { and, eq, isNull } from "drizzle-orm";

export interface VocabularyInput {
  clientId: string;
  word: string;
  phonetic?: string | null;
  audioUrl?: string | null;
  definitions: unknown;
  contexts: unknown;
  stage: number;
  mastered: boolean;
  nextReviewAt: Date;
  lastReviewAt?: Date | null;
  correctStreak: number;
}

export async function listVocabularyForUser(userId: string) {
  return db
    .select()
    .from(vocabulary)
    .where(and(eq(vocabulary.userId, userId), isNull(vocabulary.deletedAt)));
}

export async function upsertVocabulary(userId: string, input: VocabularyInput) {
  const existing = await db
    .select()
    .from(vocabulary)
    .where(and(eq(vocabulary.userId, userId), eq(vocabulary.clientId, input.clientId)))
    .limit(1)
    .then((rows) => rows[0] ?? null);

  if (existing) {
    await db
      .update(vocabulary)
      .set({
        word: input.word,
        phonetic: input.phonetic ?? null,
        audioUrl: input.audioUrl ?? null,
        definitions: input.definitions,
        contexts: input.contexts,
        stage: input.stage,
        mastered: input.mastered,
        nextReviewAt: input.nextReviewAt,
        lastReviewAt: input.lastReviewAt ?? null,
        correctStreak: input.correctStreak,
        updatedAt: new Date(),
        deletedAt: null,
      })
      .where(eq(vocabulary.id, existing.id));
    return { id: existing.id, clientId: input.clientId };
  }

  const inserted = await db
    .insert(vocabulary)
    .values({
      userId,
      clientId: input.clientId,
      word: input.word,
      phonetic: input.phonetic ?? null,
      audioUrl: input.audioUrl ?? null,
      definitions: input.definitions,
      contexts: input.contexts,
      stage: input.stage,
      mastered: input.mastered,
      nextReviewAt: input.nextReviewAt,
      lastReviewAt: input.lastReviewAt ?? null,
      correctStreak: input.correctStreak,
    })
    .returning({ id: vocabulary.id });
  return { id: inserted[0].id, clientId: input.clientId };
}

export async function softDeleteVocabulary(userId: string, clientId: string) {
  await db
    .update(vocabulary)
    .set({ deletedAt: new Date(), updatedAt: new Date() })
    .where(and(eq(vocabulary.userId, userId), eq(vocabulary.clientId, clientId)));
}
