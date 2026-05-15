import Anthropic from "@anthropic-ai/sdk";

const apiKey = process.env.ANTHROPIC_API_KEY;
if (!apiKey) {
  console.warn("ANTHROPIC_API_KEY not set — AI features will be unavailable");
}

export const anthropic = apiKey ? new Anthropic({ apiKey }) : null;

export async function chat(
  systemPrompt: string,
  userMessage: string
): Promise<string> {
  if (!anthropic) {
    throw new Error("AI features are not configured. Set ANTHROPIC_API_KEY.");
  }

  const response = await anthropic.messages.create({
    model: "claude-sonnet-4-20250514",
    max_tokens: 2048,
    system: systemPrompt,
    messages: [{ role: "user", content: userMessage }],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  return textBlock?.text ?? "";
}
