import { chat, anthropic } from "../lib/anthropic.js";
import { db } from "../db/index.js";
import { aiCache } from "../db/schema.js";
import { eq, and } from "drizzle-orm";
import crypto from "crypto";

export function isAIAvailable(): boolean {
  return anthropic !== null;
}

function hashRequest(type: string, ...parts: string[]): string {
  return crypto
    .createHash("sha256")
    .update([type, ...parts].join("::"))
    .digest("hex");
}

async function getCachedResponse(
  userId: string,
  bookHash: string,
  requestType: string,
  requestHash: string
): Promise<any | null> {
  const cached = await db
    .select()
    .from(aiCache)
    .where(
      and(
        eq(aiCache.userId, userId),
        eq(aiCache.bookHash, bookHash),
        eq(aiCache.requestType, requestType),
        eq(aiCache.requestHash, requestHash)
      )
    )
    .limit(1)
    .then((rows) => rows[0] ?? null);

  return cached?.response ?? null;
}

async function cacheResponse(
  userId: string,
  bookHash: string,
  requestType: string,
  requestHash: string,
  response: any
): Promise<void> {
  await db.insert(aiCache).values({
    userId,
    bookHash,
    requestType,
    requestHash,
    response,
  });
}

export async function summarizeChapter(
  userId: string,
  bookHash: string,
  text: string
): Promise<string> {
  const reqHash = hashRequest("summarize", text.slice(0, 5000));

  const cached = await getCachedResponse(userId, bookHash, "summarize", reqHash);
  if (cached) return cached.summary;

  const summary = await chat(
    "You are a helpful reading assistant. Provide concise, insightful chapter summaries that capture the key themes, events, and character developments. Keep summaries to 3-5 paragraphs.",
    `Please summarize the following chapter:\n\n${text.slice(0, 8000)}`
  );

  await cacheResponse(userId, bookHash, "summarize", reqHash, { summary });
  return summary;
}

export async function askAboutBook(
  userId: string,
  bookHash: string,
  question: string,
  context: string
): Promise<string> {
  const reqHash = hashRequest("ask", question, context.slice(0, 2000));

  const cached = await getCachedResponse(userId, bookHash, "ask", reqHash);
  if (cached) return cached.answer;

  const answer = await chat(
    "You are a knowledgeable reading companion. Answer questions about books thoughtfully and accurately based on the provided context. If the answer isn't in the context, say so honestly.",
    `Context from the book:\n${context.slice(0, 6000)}\n\nQuestion: ${question}`
  );

  await cacheResponse(userId, bookHash, "ask", reqHash, { answer });
  return answer;
}

export async function extractHighlights(
  userId: string,
  bookHash: string,
  text: string
): Promise<string[]> {
  const reqHash = hashRequest("highlights", text.slice(0, 5000));

  const cached = await getCachedResponse(userId, bookHash, "highlights", reqHash);
  if (cached) return cached.highlights;

  const response = await chat(
    "You are a literary analyst. Extract the 5-8 most important or memorable passages from the text. Return each passage as a direct quote on its own line, prefixed with a dash (-).",
    `Extract key passages from:\n\n${text.slice(0, 8000)}`
  );

  const highlights = response
    .split("\n")
    .map((l) => l.replace(/^-\s*/, "").trim())
    .filter((l) => l.length > 0);

  await cacheResponse(userId, bookHash, "highlights", reqHash, { highlights });
  return highlights;
}

export async function explainPassage(
  userId: string,
  bookHash: string,
  selection: string,
  context: string
): Promise<string> {
  const reqHash = hashRequest("explain", selection, context.slice(0, 2000));

  const cached = await getCachedResponse(userId, bookHash, "explain", reqHash);
  if (cached) return cached.explanation;

  const explanation = await chat(
    "You are a thoughtful reading assistant. When asked to explain a passage, provide context about its meaning, literary significance, vocabulary, or historical references as appropriate. Be concise but insightful.",
    `Surrounding context:\n${context.slice(0, 4000)}\n\nPlease explain this passage:\n"${selection}"`
  );

  await cacheResponse(userId, bookHash, "explain", reqHash, { explanation });
  return explanation;
}
