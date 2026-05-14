import { useCallback, useEffect, useMemo, useState } from "react";
import { VocabWord, VocabContext, VocabDefinition, LeitnerRating } from "../lib/vocab/types";
import {
  listVocab,
  upsertVocab,
  deleteVocab,
  getVocabByWord,
} from "../lib/vocab/storage";
import { applyRating } from "../lib/vocab/leitner";

export function useVocab() {
  const [items, setItems] = useState<VocabWord[]>([]);

  const refresh = useCallback(async () => {
    setItems(await listVocab());
  }, []);

  useEffect(() => {
    listVocab().then(setItems);
  }, []);

  const dueCount = useMemo(() => {
    const now = Date.now();
    return items.filter((w) => !w.mastered && w.nextReviewAt <= now).length;
  }, [items]);

  const save = useCallback(
    async (input: {
      word: string;
      phonetic?: string;
      audioUrl?: string;
      definitions: VocabDefinition[];
      context: VocabContext;
    }): Promise<VocabWord> => {
      const now = Date.now();
      const fresh: VocabWord = {
        id: crypto.randomUUID(),
        word: input.word.trim().toLowerCase(),
        phonetic: input.phonetic,
        audioUrl: input.audioUrl,
        definitions: input.definitions,
        contexts: [input.context],
        stage: 0,
        mastered: false,
        nextReviewAt: now,
        correctStreak: 0,
        createdAt: now,
        updatedAt: now,
      };
      const persisted = await upsertVocab(fresh);
      await refresh();
      return persisted;
    },
    [refresh]
  );

  const unsave = useCallback(
    async (id: string) => {
      await deleteVocab(id);
      await refresh();
    },
    [refresh]
  );

  const findByWord = useCallback(async (word: string): Promise<VocabWord | null> => {
    return getVocabByWord(word);
  }, []);

  const applyReview = useCallback(
    async (id: string, rating: LeitnerRating): Promise<VocabWord | null> => {
      const all = await listVocab();
      const found = all.find((w) => w.id === id);
      if (!found) return null;
      const newState = applyRating(found, rating, Date.now());
      const updated: VocabWord = {
        ...found,
        ...newState,
        updatedAt: Date.now(),
      };
      await upsertVocab(updated);
      await refresh();
      return updated;
    },
    [refresh]
  );

  const resetStage = useCallback(
    async (id: string) => {
      const all = await listVocab();
      const found = all.find((w) => w.id === id);
      if (!found) return;
      const reset: VocabWord = {
        ...found,
        stage: 0,
        mastered: false,
        nextReviewAt: Date.now(),
        correctStreak: 0,
        updatedAt: Date.now(),
      };
      await upsertVocab(reset);
      await refresh();
    },
    [refresh]
  );

  return { items, dueCount, save, unsave, findByWord, applyReview, resetStage, refresh };
}
