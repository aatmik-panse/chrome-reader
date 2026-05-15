import { chat, anthropic } from "../lib/anthropic.js";
import { db } from "../db/index.js";
import { aiCache } from "../db/schema.js";
import { eq, and } from "drizzle-orm";
import crypto from "crypto";

export function isAIAvailable(): boolean {
  return anthropic !== null;
}

function hashRequest(...parts: string[]): string {
  return crypto.createHash("sha256").update(parts.join("::")).digest("hex");
}

export async function translateText(
  userId: string,
  bookHash: string,
  text: string,
  targetLang: string
): Promise<{ translation: string; detectedLang?: string }> {
  const reqHash = hashRequest("translate", targetLang, text.slice(0, 4000));

  const cached = await db
    .select()
    .from(aiCache)
    .where(
      and(
        eq(aiCache.userId, userId),
        eq(aiCache.bookHash, bookHash),
        eq(aiCache.requestType, "translate"),
        eq(aiCache.requestHash, reqHash)
      )
    )
    .limit(1)
    .then((rows) => rows[0] ?? null);

  if (cached) return cached.response as { translation: string; detectedLang?: string };

  const raw = await chat(
    "You are a precise translator. Reply with ONLY a single JSON object of shape {\"detectedLang\":\"<bcp47>\",\"translation\":\"...\"}. No prose, no code fences.",
    `Translate the following text to ${targetLang}:\n\n${text.slice(0, 4000)}`
  );

  let parsed: { translation: string; detectedLang?: string };
  try {
    const cleaned = raw.trim().replace(/^```(?:json)?\s*/i, "").replace(/```$/, "").trim();
    parsed = JSON.parse(cleaned);
    if (typeof parsed.translation !== "string") throw new Error("missing translation");
  } catch {
    parsed = { translation: raw.trim() };
  }

  await db.insert(aiCache).values({
    userId,
    bookHash,
    requestType: "translate",
    requestHash: reqHash,
    response: parsed,
  });
  return parsed;
}
