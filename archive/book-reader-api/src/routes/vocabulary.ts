import { Hono } from "hono";
import { authMiddleware } from "../middleware/auth.js";
import {
  listVocabularyForUser,
  upsertVocabulary,
  softDeleteVocabulary,
  VocabularyInput,
} from "../services/vocabulary.js";
import type { AppVariables } from "../types.js";

const r = new Hono<{ Variables: AppVariables }>();
r.use("/*", authMiddleware);

r.get("/", async (c) => {
  const userId = c.get("userId") as string;
  const rows = await listVocabularyForUser(userId);
  return c.json({ words: rows });
});

r.put("/:clientId", async (c) => {
  const userId = c.get("userId") as string;
  const clientId = c.req.param("clientId");
  const body = await c.req.json<Omit<VocabularyInput, "clientId" | "nextReviewAt" | "lastReviewAt"> & {
    nextReviewAt: number;
    lastReviewAt?: number | null;
  }>();
  const input: VocabularyInput = {
    ...body,
    clientId,
    nextReviewAt: new Date(body.nextReviewAt),
    lastReviewAt: body.lastReviewAt ? new Date(body.lastReviewAt) : null,
  };
  const result = await upsertVocabulary(userId, input);
  return c.json(result);
});

r.delete("/:clientId", async (c) => {
  const userId = c.get("userId") as string;
  const clientId = c.req.param("clientId");
  await softDeleteVocabulary(userId, clientId);
  return c.json({ ok: true });
});

export default r;
