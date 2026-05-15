import { Hono } from "hono";
import { authMiddleware } from "../middleware/auth.js";
import {
  summarizeChapter,
  askAboutBook,
  extractHighlights,
  explainPassage,
  isAIAvailable,
} from "../services/ai.js";
import { translateText } from "../services/translate.js";
import type { AppVariables } from "../types.js";

const ai = new Hono<{ Variables: AppVariables }>();

ai.use("/*", authMiddleware);

ai.use("/*", async (c, next) => {
  if (!isAIAvailable()) {
    return c.json(
      { error: "AI features are not configured on this server" },
      503
    );
  }
  await next();
});

ai.post("/summarize", async (c) => {
  const userId = c.get("userId") as string;
  const { bookHash, text } = await c.req.json<{
    bookHash: string;
    text: string;
  }>();

  if (!bookHash || !text) {
    return c.json({ error: "bookHash and text are required" }, 400);
  }

  try {
    const summary = await summarizeChapter(userId, bookHash, text);
    return c.json({ summary });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Summarization failed";
    return c.json({ error: msg }, 500);
  }
});

ai.post("/ask", async (c) => {
  const userId = c.get("userId") as string;
  const { bookHash, question, context } = await c.req.json<{
    bookHash: string;
    question: string;
    context: string;
  }>();

  if (!bookHash || !question) {
    return c.json({ error: "bookHash and question are required" }, 400);
  }

  try {
    const answer = await askAboutBook(userId, bookHash, question, context || "");
    return c.json({ answer });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Question failed";
    return c.json({ error: msg }, 500);
  }
});

ai.post("/highlights", async (c) => {
  const userId = c.get("userId") as string;
  const { bookHash, text } = await c.req.json<{
    bookHash: string;
    text: string;
  }>();

  if (!bookHash || !text) {
    return c.json({ error: "bookHash and text are required" }, 400);
  }

  try {
    const highlights = await extractHighlights(userId, bookHash, text);
    return c.json({ highlights });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Highlights extraction failed";
    return c.json({ error: msg }, 500);
  }
});

ai.post("/explain", async (c) => {
  const userId = c.get("userId") as string;
  const { bookHash, selection, context } = await c.req.json<{
    bookHash: string;
    selection: string;
    context: string;
  }>();

  if (!bookHash || !selection) {
    return c.json({ error: "bookHash and selection are required" }, 400);
  }

  try {
    const explanation = await explainPassage(
      userId,
      bookHash,
      selection,
      context || ""
    );
    return c.json({ explanation });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Explanation failed";
    return c.json({ error: msg }, 500);
  }
});

ai.post("/translate", async (c) => {
  const userId = c.get("userId") as string;
  const { bookHash, text, targetLang } = await c.req.json<{
    bookHash: string;
    text: string;
    targetLang: string;
  }>();

  if (!bookHash || !text || !targetLang) {
    return c.json({ error: "bookHash, text, and targetLang are required" }, 400);
  }

  try {
    const result = await translateText(userId, bookHash, text, targetLang);
    return c.json(result);
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Translation failed";
    return c.json({ error: msg }, 500);
  }
});

export default ai;
