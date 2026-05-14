import React, { useState } from "react";
import type { AiProvider } from "../../lib/ai/types";
import { useByok } from "../../hooks/useByok";
import {
  ANTHROPIC_DEFAULT_MODEL,
  createAnthropicClient,
} from "../../lib/ai/anthropic";
import { OPENAI_DEFAULT_MODEL, createOpenAiClient } from "../../lib/ai/openai";
import { GOOGLE_DEFAULT_MODEL, createGoogleClient } from "../../lib/ai/google";
import {
  OPENROUTER_DEFAULT_MODEL,
  createOpenRouterClient,
} from "../../lib/ai/openrouter";
import type { AiClient } from "../../lib/ai/types";

interface ProviderDescriptor {
  id: AiProvider;
  label: string;
  defaultModel: string;
  modelOptions: ReadonlyArray<string>;
  buildClient: (apiKey: string, model: string | undefined) => AiClient;
  apiKeyPlaceholder: string;
}

const PROVIDER_DESCRIPTORS: ReadonlyArray<ProviderDescriptor> = [
  {
    id: "anthropic",
    label: "Anthropic",
    defaultModel: ANTHROPIC_DEFAULT_MODEL,
    modelOptions: [
      ANTHROPIC_DEFAULT_MODEL,
      "claude-opus-4-5",
      "claude-haiku-4-5",
    ],
    buildClient: (apiKey, model) => createAnthropicClient(apiKey, model),
    apiKeyPlaceholder: "sk-ant-…",
  },
  {
    id: "openai",
    label: "OpenAI",
    defaultModel: OPENAI_DEFAULT_MODEL,
    modelOptions: [OPENAI_DEFAULT_MODEL, "gpt-5.5-mini", "gpt-4.1"],
    buildClient: (apiKey, model) => createOpenAiClient(apiKey, model),
    apiKeyPlaceholder: "sk-…",
  },
  {
    id: "google",
    label: "Google Gemini",
    defaultModel: GOOGLE_DEFAULT_MODEL,
    modelOptions: [
      GOOGLE_DEFAULT_MODEL,
      "gemini-3.1-flash",
      "gemini-2.5-pro",
    ],
    buildClient: (apiKey, model) => createGoogleClient(apiKey, model),
    apiKeyPlaceholder: "AIza…",
  },
  {
    id: "openrouter",
    label: "OpenRouter",
    defaultModel: OPENROUTER_DEFAULT_MODEL,
    modelOptions: [
      OPENROUTER_DEFAULT_MODEL,
      "openai/gpt-5.5",
      "google/gemini-3.1-pro",
      "meta-llama/llama-4-405b-instruct",
    ],
    buildClient: (apiKey, model) => createOpenRouterClient(apiKey, model),
    apiKeyPlaceholder: "sk-or-…",
  },
];

const PING_PROMPT = "ping";

function maskKeyForDisplay(apiKey: string | undefined): string {
  if (!apiKey || apiKey.length === 0) return "";
  if (apiKey.length <= 8) return apiKey;
  return `${apiKey.slice(0, 4)}…${apiKey.slice(-4)}`;
}

interface ProviderTestState {
  status: "idle" | "running" | "ok" | "error";
  message: string | null;
  latencyMs: number | null;
}

const INITIAL_TEST_STATE: ProviderTestState = {
  status: "idle",
  message: null,
  latencyMs: null,
};

export default function ByokSettings() {
  const { byok, setActiveProvider, setKey, setModel, clearAllKeys } = useByok();
  const [revealKey, setRevealKey] = useState<Partial<Record<AiProvider, boolean>>>({});
  const [testState, setTestState] = useState<Partial<Record<AiProvider, ProviderTestState>>>({});

  const toggleRevealKey = (provider: AiProvider) =>
    setRevealKey((prev) => ({ ...prev, [provider]: !prev[provider] }));

  const handleTest = async (descriptor: ProviderDescriptor): Promise<void> => {
    const apiKey = byok.keys[descriptor.id];
    if (!apiKey || apiKey.length === 0) {
      setTestState((prev) => ({
        ...prev,
        [descriptor.id]: { status: "error", message: "Enter an API key first.", latencyMs: null },
      }));
      return;
    }
    const modelOverride = byok.models[descriptor.id];
    const client = descriptor.buildClient(apiKey, modelOverride);
    setTestState((prev) => ({
      ...prev,
      [descriptor.id]: { status: "running", message: null, latencyMs: null },
    }));
    const startedAt = performance.now();
    try {
      await client.summarize(PING_PROMPT);
      const latencyMs = Math.round(performance.now() - startedAt);
      setTestState((prev) => ({
        ...prev,
        [descriptor.id]: { status: "ok", message: "Connected", latencyMs },
      }));
    } catch (err) {
      setTestState((prev) => ({
        ...prev,
        [descriptor.id]: {
          status: "error",
          message: err instanceof Error ? err.message : "Test failed",
          latencyMs: null,
        },
      }));
    }
  };

  return (
    <div className="space-y-6">
      <ActiveProviderRadioGroup
        activeProvider={byok.activeProvider}
        onSelectProvider={setActiveProvider}
      />

      <div className="space-y-5 border-t border-oat pt-5">
        {PROVIDER_DESCRIPTORS.map((descriptor) => (
          <ProviderSection
            key={descriptor.id}
            descriptor={descriptor}
            apiKey={byok.keys[descriptor.id] ?? ""}
            modelOverride={byok.models[descriptor.id]}
            isKeyRevealed={!!revealKey[descriptor.id]}
            onToggleReveal={() => toggleRevealKey(descriptor.id)}
            onChangeKey={(value) => setKey(descriptor.id, value)}
            onChangeModel={(value) => setModel(descriptor.id, value)}
            onTest={() => handleTest(descriptor)}
            testState={testState[descriptor.id] ?? INITIAL_TEST_STATE}
          />
        ))}
      </div>

      <div className="border-t border-oat pt-5 flex items-center justify-between">
        <p className="text-xs text-silver">
          Keys are stored locally only. They are sent directly to the provider you select; never to our backend.
        </p>
        <button
          onClick={clearAllKeys}
          className="clay-btn-white text-xs text-pomegranate-400 hover:text-pomegranate-400"
          disabled={Object.keys(byok.keys).length === 0}
        >
          Clear all keys
        </button>
      </div>
    </div>
  );
}

interface ActiveProviderRadioGroupProps {
  activeProvider: AiProvider | null;
  onSelectProvider: (provider: AiProvider) => void;
}

function ActiveProviderRadioGroup({
  activeProvider,
  onSelectProvider,
}: ActiveProviderRadioGroupProps) {
  return (
    <div>
      <p className="clay-label mb-2">Active Provider</p>
      <div className="grid grid-cols-1 gap-2">
        {PROVIDER_DESCRIPTORS.map((descriptor) => (
          <RadioRow
            key={descriptor.id}
            label={descriptor.label}
            checked={activeProvider === descriptor.id}
            onSelect={() => onSelectProvider(descriptor.id)}
          />
        ))}
      </div>
    </div>
  );
}

interface RadioRowProps {
  label: string;
  checked: boolean;
  onSelect: () => void;
}

function RadioRow({ label, checked, onSelect }: RadioRowProps) {
  return (
    <button
      type="button"
      onClick={onSelect}
      className={`flex items-center gap-3 px-3 py-2 rounded-[8px] border text-left transition-all ${
        checked
          ? "border-clay-black bg-clay-white clay-shadow"
          : "border-oat hover:border-charcoal"
      }`}
    >
      <span
        className={`w-3.5 h-3.5 rounded-full border-2 flex-shrink-0 ${
          checked ? "border-matcha-600 bg-matcha-600" : "border-silver"
        }`}
      />
      <span className="text-sm text-clay-black">{label}</span>
    </button>
  );
}

interface ProviderSectionProps {
  descriptor: ProviderDescriptor;
  apiKey: string;
  modelOverride: string | undefined;
  isKeyRevealed: boolean;
  onToggleReveal: () => void;
  onChangeKey: (apiKey: string) => void;
  onChangeModel: (model: string | null) => void;
  onTest: () => void;
  testState: ProviderTestState;
}

function ProviderSection({
  descriptor,
  apiKey,
  modelOverride,
  isKeyRevealed,
  onToggleReveal,
  onChangeKey,
  onChangeModel,
  onTest,
  testState,
}: ProviderSectionProps) {
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium text-clay-black">{descriptor.label}</p>
        <p className="text-[10px] uppercase tracking-wide text-silver">
          Default: {descriptor.defaultModel}
        </p>
      </div>

      <div className="flex items-stretch gap-2">
        <input
          type={isKeyRevealed ? "text" : "password"}
          value={apiKey}
          onChange={(e) => onChangeKey(e.target.value)}
          placeholder={descriptor.apiKeyPlaceholder}
          className="flex-1 min-w-0 px-3 py-2 text-sm rounded-[8px] border border-oat bg-clay-white text-clay-black"
        />
        <button
          type="button"
          onClick={onToggleReveal}
          className="clay-btn-white text-xs px-3"
        >
          {isKeyRevealed ? "Hide" : "Show"}
        </button>
      </div>

      {!isKeyRevealed && apiKey.length > 0 && (
        <p className="text-[10px] text-silver">Stored: {maskKeyForDisplay(apiKey)}</p>
      )}

      <div className="flex items-stretch gap-2">
        <select
          value={modelOverride ?? ""}
          onChange={(e) =>
            onChangeModel(e.target.value === "" ? null : e.target.value)
          }
          className="flex-1 px-3 py-2 text-sm rounded-[8px] border border-oat bg-clay-white text-clay-black"
        >
          <option value="">Default ({descriptor.defaultModel})</option>
          {descriptor.modelOptions.map((option) => (
            <option key={option} value={option}>
              {option}
            </option>
          ))}
        </select>
        <button
          type="button"
          onClick={onTest}
          className="clay-btn-white text-xs px-3"
          disabled={apiKey.length === 0 || testState.status === "running"}
        >
          {testState.status === "running" ? "Testing…" : "Test"}
        </button>
      </div>

      <TestStatusLine state={testState} />
    </div>
  );
}

function TestStatusLine({ state }: { state: ProviderTestState }) {
  if (state.status === "idle") return null;
  if (state.status === "running") {
    return <p className="text-xs text-silver">Testing…</p>;
  }
  if (state.status === "ok") {
    return (
      <p className="text-xs text-matcha-600">
        ✓ {state.message ?? "Connected"}
        {state.latencyMs !== null ? ` (${state.latencyMs}ms)` : ""}
      </p>
    );
  }
  return <p className="text-xs text-pomegranate-400">{state.message ?? "Test failed"}</p>;
}
