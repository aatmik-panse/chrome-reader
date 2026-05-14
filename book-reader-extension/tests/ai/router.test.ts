import { describe, it, expect, beforeEach, vi } from "vitest";
import { setCachedByok, getEmptyByokConfig } from "../../src/newtab/lib/ai/byok-cache";
import { getAiClient, AI_NOT_CONFIGURED_MESSAGE } from "../../src/newtab/lib/ai/router";

beforeEach(() => {
  setCachedByok(getEmptyByokConfig());
});

describe("getAiClient (router)", () => {
  it("usesAnthropicDirectClientWhenByokKeyIsSet", () => {
    setCachedByok({
      activeProvider: "anthropic",
      keys: { anthropic: "sk-ant-XXXX" },
      models: {},
    });

    const client = getAiClient("book-1");

    expect(client).toBeDefined();
    expect(typeof client.summarize).toBe("function");
  });

  it("throwsWhenActiveProviderHasNoKey", () => {
    setCachedByok({
      activeProvider: "openai",
      keys: {},
      models: {},
    });

    expect(() => getAiClient("book-1")).toThrow(AI_NOT_CONFIGURED_MESSAGE);
  });

  it("throwsWhenNoActiveProviderConfigured", () => {
    expect(() => getAiClient("book-1")).toThrow(AI_NOT_CONFIGURED_MESSAGE);
  });

  it("routesToTheSelectedProvider", async () => {
    setCachedByok({
      activeProvider: "anthropic",
      keys: { anthropic: "sk-ant-X" },
      models: {},
    });

    const original = globalThis.fetch;
    let urlSeen = "";
    globalThis.fetch = vi.fn(async (input: RequestInfo | URL) => {
      urlSeen = String(input);
      return new Response(JSON.stringify({ content: [{ type: "text", text: "ok" }] }), { status: 200 });
    }) as typeof fetch;

    const client = getAiClient("book-1");
    await client.summarize("hi");

    expect(urlSeen).toContain("api.anthropic.com");
    globalThis.fetch = original;
  });
});
