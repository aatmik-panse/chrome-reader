import { Hono } from "hono";
import { db } from "../db/index.js";
import { readingPositions } from "../db/schema.js";
import { eq, and } from "drizzle-orm";
import { authMiddleware } from "../middleware/auth.js";
import type { AppVariables } from "../types.js";

const position = new Hono<{ Variables: AppVariables }>();

position.use("/*", authMiddleware);

function formatPosition(pos: typeof readingPositions.$inferSelect) {
  return {
    bookHash: pos.bookHash,
    bookTitle: pos.bookTitle,
    chapterIndex: pos.chapterIndex,
    scrollOffset: pos.scrollOffset,
    percentage: pos.percentage,
    updatedAt: pos.updatedAt.toISOString(),
  };
}

position.get("/:bookHash", async (c) => {
  const userId = c.get("userId") as string;
  const bookHash = c.req.param("bookHash");

  const pos = await db
    .select()
    .from(readingPositions)
    .where(
      and(
        eq(readingPositions.userId, userId),
        eq(readingPositions.bookHash, bookHash)
      )
    )
    .limit(1)
    .then((rows) => rows[0] ?? null);

  if (!pos) {
    return c.json(null);
  }

  return c.json(formatPosition(pos));
});

position.put("/:bookHash", async (c) => {
  const userId = c.get("userId") as string;
  const bookHash = c.req.param("bookHash");
  const body = await c.req.json<{
    bookTitle?: string;
    chapterIndex?: number;
    scrollOffset?: number;
    percentage?: number;
  }>();

  const chapterIndex = typeof body.chapterIndex === "number" ? body.chapterIndex : 0;
  const scrollOffset = typeof body.scrollOffset === "number" ? body.scrollOffset : 0;
  const percentage = Math.max(0, Math.min(100, typeof body.percentage === "number" ? body.percentage : 0));

  const existing = await db
    .select()
    .from(readingPositions)
    .where(
      and(
        eq(readingPositions.userId, userId),
        eq(readingPositions.bookHash, bookHash)
      )
    )
    .limit(1)
    .then((rows) => rows[0] ?? null);

  if (existing) {
    const [updated] = await db
      .update(readingPositions)
      .set({
        bookTitle: body.bookTitle || existing.bookTitle,
        chapterIndex,
        scrollOffset,
        percentage,
        updatedAt: new Date(),
      })
      .where(eq(readingPositions.id, existing.id))
      .returning();

    return c.json(formatPosition(updated));
  }

  const [created] = await db
    .insert(readingPositions)
    .values({
      userId,
      bookHash,
      bookTitle: body.bookTitle || "",
      chapterIndex,
      scrollOffset,
      percentage,
    })
    .returning();

  return c.json(formatPosition(created));
});

export default position;
