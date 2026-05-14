/**
 * Synchronous AI client factory.
 *
 * The extension is BYOK-only: the user supplies an API key for one of the
 * supported providers (Anthropic, OpenAI, Google, OpenRouter) and the
 * router builds a direct client for that provider. If no key is
 * configured, callers get a user-facing error pointing them at Settings.
 *
 * The router relies on `byok-cache` being populated before the first call
 * — `useAppBootstrap` invokes `loadByokIntoCache()` during mount.
 */

import type { AiClient, AiProvider } from "./types";
import { getCachedByok } from "./byok-cache";
import { getConfiguredProvider } from "./byok-helpers";
import { createAnthropicClient } from "./anthropic";
import { createOpenAiClient } from "./openai";
import { createGoogleClient } from "./google";
import { createOpenRouterClient } from "./openrouter";

export const AI_NOT_CONFIGURED_MESSAGE =
  "AI not configured. Add an API key in Settings → AI Keys.";

function createDirectClient(
  provider: AiProvider,
  apiKey: string,
  modelOverride: string | undefined,
): AiClient {
  switch (provider) {
    case "anthropic":
      return createAnthropicClient(apiKey, modelOverride);
    case "openai":
      return createOpenAiClient(apiKey, modelOverride);
    case "google":
      return createGoogleClient(apiKey, modelOverride);
    case "openrouter":
      return createOpenRouterClient(apiKey, modelOverride);
  }
}

export function getAiClient(_bookHash: string | null): AiClient {
  const byok = getCachedByok();
  const configuredProvider = getConfiguredProvider(byok);

  if (!configuredProvider) {
    throw new Error(AI_NOT_CONFIGURED_MESSAGE);
  }

  const apiKey = byok.keys[configuredProvider];
  if (typeof apiKey !== "string" || apiKey.length === 0) {
    throw new Error(AI_NOT_CONFIGURED_MESSAGE);
  }

  const modelOverride = byok.models[configuredProvider];
  return createDirectClient(configuredProvider, apiKey, modelOverride);
}
