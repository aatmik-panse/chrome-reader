import { Hono } from "hono";
import { authMiddleware } from "../middleware/auth.js";
import {
  listHighlightsForBook,
  upsertHighlight,
  softDeleteHighlight,
  HighlightInput,
} from "../services/highlights.js";
import type { AppVariables } from "../types.js";

const r = new Hono<{ Variables: AppVariables }>();
r.use("/*", authMiddleware);

r.get("/:bookHash", async (c) => {
  const userId = c.get("userId") as string;
  const bookHash = c.req.param("bookHash");
  const rows = await listHighlightsForBook(userId, bookHash);
  return c.json({ highlights: rows });
});

r.put("/:bookHash/:clientId", async (c) => {
  const userId = c.get("userId") as string;
  const bookHash = c.req.param("bookHash");
  const clientId = c.req.param("clientId");
  const body = await c.req.json<Omit<HighlightInput, "clientId" | "bookHash">>();
  const result = await upsertHighlight(userId, { ...body, clientId, bookHash });
  return c.json(result);
});

r.delete("/:bookHash/:clientId", async (c) => {
  const userId = c.get("userId") as string;
  const clientId = c.req.param("clientId");
  await softDeleteHighlight(userId, clientId);
  return c.json({ ok: true });
});

export default r;
