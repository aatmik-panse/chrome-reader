import { useCallback, useState } from "react";
import { aiSummarize, aiAsk, aiHighlights, aiExplain } from "../lib/api";
import { useByok } from "./useByok";
import { getConfiguredProvider } from "../lib/ai/byok-helpers";
import type { ByokConfig } from "../lib/ai/byok-cache";

const OFFLINE_MSG = "AI features require an internet connection.";
const NO_AI_CONFIGURED_MSG =
  "AI is not configured. Add a provider key in Settings → AI Keys.";

function isOnline(): boolean {
  return navigator.onLine;
}

function isAiUsable(byok: ByokConfig): boolean {
  return getConfiguredProvider(byok) !== null;
}

function checkAvailability(byok: ByokConfig): string | null {
  if (!isOnline()) return OFFLINE_MSG;
  if (!isAiUsable(byok)) return NO_AI_CONFIGURED_MSG;
  return null;
}

export function useAI(bookHash: string | null) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { byok } = useByok();

  const available = isOnline() && isAiUsable(byok);

  const guardedCall = useCallback(
    async <T>(action: () => Promise<T>, failureMessage: string): Promise<T | null> => {
      if (!bookHash) return null;
      const unavailable = checkAvailability(byok);
      if (unavailable) {
        setError(unavailable);
        return null;
      }
      setLoading(true);
      setError(null);
      try {
        return await action();
      } catch (e) {
        setError(e instanceof Error ? e.message : failureMessage);
        return null;
      } finally {
        setLoading(false);
      }
    },
    [bookHash, byok],
  );

  const summarize = useCallback(
    (chapterText: string): Promise<string | null> =>
      guardedCall(
        async () => (await aiSummarize(bookHash as string, chapterText)).summary,
        "Summarization failed",
      ),
    [bookHash, guardedCall],
  );

  const ask = useCallback(
    (question: string, context: string): Promise<string | null> =>
      guardedCall(
        async () => (await aiAsk(bookHash as string, question, context)).answer,
        "Question failed",
      ),
    [bookHash, guardedCall],
  );

  const highlights = useCallback(
    (chapterText: string): Promise<string[] | null> =>
      guardedCall(
        async () => (await aiHighlights(bookHash as string, chapterText)).highlights,
        "Highlights failed",
      ),
    [bookHash, guardedCall],
  );

  const explain = useCallback(
    (selection: string, context: string): Promise<string | null> =>
      guardedCall(
        async () => (await aiExplain(bookHash as string, selection, context)).explanation,
        "Explanation failed",
      ),
    [bookHash, guardedCall],
  );

  return { loading, error, available, summarize, ask, highlights, explain };
}
