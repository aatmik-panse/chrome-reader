import { Hono } from "hono";
import { db } from "../db/index.js";
import { users } from "../db/schema.js";
import { eq } from "drizzle-orm";
import { signToken } from "../middleware/auth.js";

const auth = new Hono();

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;

interface GoogleUserInfo {
  sub: string;
  email: string;
  name?: string;
  picture?: string;
}

async function verifyGoogleToken(token: string): Promise<GoogleUserInfo> {
  // chrome.identity.getAuthToken() returns an OAuth2 access token.
  // Verify it and fetch the user profile in one call via the userinfo endpoint.
  const res = await fetch("https://www.googleapis.com/oauth2/v3/userinfo", {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (!res.ok) {
    // Fallback: maybe it's an ID token from a web-based flow
    const idRes = await fetch(
      `https://oauth2.googleapis.com/tokeninfo?id_token=${token}`
    );
    if (!idRes.ok) throw new Error("Invalid token");
    return (await idRes.json()) as GoogleUserInfo;
  }

  const profile = (await res.json()) as GoogleUserInfo;

  if (GOOGLE_CLIENT_ID) {
    // Verify the access token was issued for our app
    const tokenInfo = await fetch(
      `https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=${token}`
    );
    if (tokenInfo.ok) {
      const info = (await tokenInfo.json()) as { aud?: string; azp?: string };
      const audience = info.aud || info.azp;
      if (audience && audience !== GOOGLE_CLIENT_ID) {
        throw new Error("Token was not issued for this application");
      }
    }
  }

  return profile;
}

auth.post("/google", async (c) => {
  const { idToken } = await c.req.json<{ idToken: string }>();

  if (!idToken) {
    return c.json({ error: "idToken is required" }, 400);
  }

  let googleUser: GoogleUserInfo;
  try {
    googleUser = await verifyGoogleToken(idToken);
  } catch {
    return c.json({ error: "Failed to verify Google token" }, 401);
  }

  if (!googleUser.sub || !googleUser.email) {
    return c.json({ error: "Invalid token: missing user info" }, 401);
  }

  let user = await db
    .select()
    .from(users)
    .where(eq(users.googleId, googleUser.sub))
    .limit(1)
    .then((rows) => rows[0] ?? null);

  if (!user) {
    const [newUser] = await db
      .insert(users)
      .values({
        googleId: googleUser.sub,
        email: googleUser.email,
        name: googleUser.name || googleUser.email,
      })
      .returning();
    user = newUser;
  } else if (googleUser.name && user.name === user.email) {
    // Backfill name if it was missing on first auth
    const [updated] = await db
      .update(users)
      .set({ name: googleUser.name })
      .where(eq(users.id, user.id))
      .returning();
    user = updated;
  }

  const token = signToken({ userId: user.id, email: user.email });

  return c.json({
    token,
    user: {
      id: user.id,
      email: user.email,
      name: user.name,
    },
  });
});

export default auth;
