# Instant Book Reader

<p align="center">
  <img src="book-reader-extension/public/BookFlipSmall.jpg" alt="Instant Book Reader" width="120" height="120" style="border-radius: 24px;" />
</p>

<p align="center">
  <strong>Your reading space, always one tab away.</strong><br/>
  A Chrome Extension that replaces your New Tab with a distraction-free book reader.
</p>

<p align="center">
  <a href="https://chromewebstore.google.com/detail/instant-book-reader/beconkamchfbjkplbapbkhmjdmpjfeni"><strong>Install from Chrome Web Store</strong></a>
  &nbsp;&middot;&nbsp;
  <a href="https://github.com/aatmik-panse/chrome-reader/releases/latest">Download Latest Release</a>
</p>

---

## What It Does

Drop an EPUB, PDF, or TXT file into the extension once — every new tab takes you back to where you left off. No app to launch, no website to load, no account required.

Everything stays on your device. The AI assistant is **bring-your-own-key**: when you add a provider API key in Settings, the extension talks directly to that provider from your browser. There is no backend.

## Features

### Reader
- **Multi-format** — EPUB, PDF, and TXT with clean rendering
- **15+ themes** — Light, dark, sepia, and more, plus a custom theme builder
- **Adjustable typography** — Font family, size, and line spacing controls
- **PDF view modes** — Single page, continuous scroll, two-page spread
- **PDF thumbnails** — Bottom strip with page previews for quick navigation
- **Table of Contents** — Nested chapter navigation for EPUBs with one-click jump
- **Resizable panels** — Drag-to-resize sidebars for Library, TOC, AI, Highlights, and Words

### AI Assistant (BYOK only)
- **Summarize** chapters in a few paragraphs
- **Explain** any selected text — auto-fires from the selection toolbar
- **Key highlights** extraction from the current chapter
- **Ask questions** about what you're reading
- **Bring Your Own Key** — Anthropic, OpenAI, Google Gemini, or OpenRouter
- Keys are stored locally and sent **directly** to the provider you choose. No backend, no proxy, no telemetry.
- **Markdown rendering** — AI responses display with proper formatting

### Vocabulary & Learning
- **One-click define** — definitions, phonetics, and pronunciation audio inline
- **Inline translation** — translate selections into 10 languages
- **Vocabulary builder** — auto-saves every word you define with context
- **Spaced repetition** — Leitner box flashcards (1d → 3d → 7d → 14d → 30d → mastered)
- **Quiz mode** — fill-in-the-blank using your own saved sentences
- **CSV export** — for Anki, Notion, or anywhere else

### Highlights
- **5 colors** with optional notes
- **Sidebar list** — click any highlight to jump back to it
- **One-click remove** — re-select a highlighted passage to remove it

### Privacy
- **Local-first** — books, highlights, vocabulary, and reading positions live in your browser (IndexedDB + `chrome.storage.local`).
- **No accounts, no sign-in, no cloud sync.**
- **No analytics, no telemetry, no ads.**
- **No backend** — AI requests go from your browser directly to the provider you chose.

## Project Structure

```
chromeApps/
  book-reader-extension/   Chrome Extension (React + Tailwind + Vite)
  book-reader-api/         Legacy backend (not used by v1.0.5; kept for reference)
```

> **Note on the API:** Earlier 1.0.x releases supported Google sign-in and a server-side AI fallback through `book-reader-api/`. Starting with **v1.0.5** the extension is BYOK-only and ships without sign-in or sync. The `book-reader-api/` folder is preserved for historical reference but is no longer required to run the extension.

## Quick Start

### Install from Release

1. Download `instant-book-reader-1.0.5.zip` from [Releases](https://github.com/aatmik-panse/chrome-reader/releases/latest)
2. Unzip the file
3. Go to `chrome://extensions`
4. Enable **Developer mode**
5. Click **Load unpacked**
6. Select the unzipped folder

### Build from Source

```bash
cd book-reader-extension
npm install
npm run build
```

Then load `book-reader-extension/dist` as an unpacked extension.

### Run Tests

```bash
cd book-reader-extension
npm test
```

## AI Configuration

Open **Settings → AI Keys**, paste a key for any supported provider, then select that provider as the active one. Click **Test** to verify the key works.

| Provider | Models |
|---|---|
| Anthropic | Claude Sonnet, Claude Haiku, Claude Opus |
| OpenAI | GPT-4.1, GPT-5.5-mini, etc. |
| Google Gemini | Gemini 2.5 Pro, Gemini 3.1 Flash |
| OpenRouter | Any model on OpenRouter |

Keys are stored locally in `chrome.storage.local` (AES-wrapped) and are sent directly to the provider's API. If no key is configured, the AI panel shows an "Add an API key" affordance that deep-links into Settings → AI Keys.

## Permissions

| Permission | Why |
|---|---|
| `storage` | Saves books, highlights, vocabulary, reading positions, settings, and (encrypted) BYOK keys locally |
| `api.dictionaryapi.dev` | Fetches word definitions for the dictionary popup |
| `translate.google.com` | Pronunciation audio fallback |
| `api.anthropic.com` / `api.openai.com` / `generativelanguage.googleapis.com` / `openrouter.ai` | Only used when you add your own AI key for that provider |

No `identity` permission, no `alarms` permission, no background service worker.

## Tech Stack

- **Frontend:** React 19, TypeScript, Tailwind CSS 4, Vite 8
- **PDF:** pdf.js
- **EPUB:** epub.js
- **Local storage:** IndexedDB (via `idb`) + `chrome.storage.local`
- **Testing:** Vitest, Testing Library, fake-indexeddb
- **Design System:** Custom Clay-inspired system with tilt+shadow hover animations

## License

ISC
