/**
 * Thin wrappers over the AI router so React components can call AI features
 * via the same shape regardless of which BYOK provider is active.
 *
 * All keys are stored locally in `chrome.storage.local` and requests go
 * directly from the extension to the user's chosen provider. No backend.
 */

import { getAiClient } from "./ai/router";

export async function aiSummarize(
  bookHash: string,
  chapterText: string,
): Promise<{ summary: string }> {
  return { summary: await getAiClient(bookHash).summarize(chapterText) };
}

export async function aiAsk(
  bookHash: string,
  question: string,
  context: string,
): Promise<{ answer: string }> {
  return { answer: await getAiClient(bookHash).ask(question, context) };
}

export async function aiHighlights(
  bookHash: string,
  chapterText: string,
): Promise<{ highlights: string[] }> {
  return { highlights: await getAiClient(bookHash).highlights(chapterText) };
}

export async function aiExplain(
  bookHash: string,
  selection: string,
  context: string,
): Promise<{ explanation: string }> {
  return { explanation: await getAiClient(bookHash).explain(selection, context) };
}

export async function aiTranslate(
  bookHash: string,
  text: string,
  targetLang: string,
): Promise<{ translation: string; detectedLang?: string }> {
  const result = await getAiClient(bookHash).translate(text, targetLang);
  return { translation: result.text, detectedLang: result.detectedLang };
}
