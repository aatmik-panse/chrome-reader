import { Hono } from "hono";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { serve } from "@hono/node-server";
import authRoutes from "./routes/auth.js";
import positionRoutes from "./routes/position.js";
import aiRoutes from "./routes/ai.js";
import highlightRoutes from "./routes/highlights.js";
import vocabularyRoutes from "./routes/vocabulary.js";

const app = new Hono();

app.use("*", logger());
app.use(
  "*",
  cors({
    origin: (origin) => {
      if (!origin) return "http://localhost:3000";
      if (origin.startsWith("chrome-extension://")) return origin;
      const allowed = [
        "http://localhost:5173",
        "http://localhost:3000",
      ];
      if (allowed.includes(origin)) return origin;
      return null as unknown as string;
    },
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allowHeaders: ["Content-Type", "Authorization"],
  })
);

app.get("/", (c) => {
  return c.json({
    name: "Instant Book Reader API",
    version: "1.0.0",
    status: "ok",
  });
});

app.get("/health", (c) => {
  return c.json({ status: "healthy", timestamp: new Date().toISOString() });
});

app.route("/auth", authRoutes);
app.route("/position", positionRoutes);
app.route("/ai", aiRoutes);
app.route("/highlights", highlightRoutes);
app.route("/vocabulary", vocabularyRoutes);

const port = Number(process.env.PORT) || 3000;

serve({ fetch: app.fetch, port }, () => {
  console.log(`Book Reader API running on http://localhost:${port}`);
});

export default app;
