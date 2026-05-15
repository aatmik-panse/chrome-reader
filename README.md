# Instant Book Reader

<p align="center">
  <img src="book-reader-extension/public/BookFlipSmall.jpg" alt="Instant Book Reader" width="120" height="120" style="border-radius: 24px;" />
</p>

<p align="center">
  <strong>Your reading space, always one tab away.</strong><br/>
  A Chrome extension that turns every New Tab into a distraction-free book reader.
</p>

<p align="center">
  <a href="https://chromewebstore.google.com/detail/instant-book-reader/beconkamchfbjkplbapbkhmjdmpjfeni"><strong>Install from Chrome Web Store</strong></a>
  &nbsp;&middot;&nbsp;
  <a href="https://github.com/aatmik-panse/chrome-reader/releases/latest">Download Latest Release</a>
  &nbsp;&middot;&nbsp;
  <a href="#contributing">Contribute</a>
</p>

> _Demo GIF coming soon — drag in an EPUB, close the tab, open a new one, land right back on the same page._

---

## Why this exists

I was fed up of opening Books.app and Preview every time I wanted to read something.

The apps were slow. My fans spun up. My laptop got warm for a 4 MB PDF. And every time I closed one, I'd lose my place and have to fight the UI to get back to it.

Chrome was always already open. New Tab was always empty.

One weekend I thought: _what if my New Tab page was the book?_

A few hundred lines of React later, it was. Drag a file in once. Every new tab takes you back to where you left off. No app to launch, no website to load, no account to create.

I used it quietly for months. Then a friend saw it on a call — _"wait, send me this."_ Then another friend. Then his roommate.

So here we are. Open sourcing it, and building the rest in public.

If you've ever rage-closed Preview, this is probably for you.

## What it does

- Drop an EPUB, PDF, or TXT file into the extension once
- Every new tab takes you back to exactly where you left off
- Highlight, define, translate, and save vocabulary — all locally
- Optional BYOK AI assistant (Claude, GPT, Gemini, OpenRouter) for summaries and explanations
- 15+ reading themes plus a custom theme builder

Everything stays on your device. No account. No backend. No telemetry.

## Quick start

### Install from the Chrome Web Store

[Get it here](https://chromewebstore.google.com/detail/instant-book-reader/beconkamchfbjkplbapbkhmjdmpjfeni) and pin a fresh new tab.

### Install from source

```bash
git clone https://github.com/aatmik-panse/chrome-reader
cd chrome-reader/book-reader-extension
npm install
npm run build
```

Then load `book-reader-extension/dist` as an unpacked extension at `chrome://extensions` with **Developer mode** on.

## Features

**Reader** — EPUB / PDF / TXT, 15+ themes, custom theme builder, adjustable typography, PDF single/continuous/spread modes, thumbnail strip, nested table of contents, resizable side panels.

**AI assistant (BYOK only)** — summarize chapters, explain selected text, extract key highlights, ask questions. Anthropic / OpenAI / Gemini / OpenRouter. Keys live in `chrome.storage.local`, AES-wrapped, and are sent **directly** to the provider you chose. No proxy, no telemetry.

**Vocabulary & learning** — one-click define with phonetics and audio, inline translation in 10 languages, automatic vocabulary list with source sentences, Leitner-box spaced repetition (1d → 3d → 7d → 14d → 30d → mastered), quiz mode, CSV export for Anki or Notion.

**Highlights** — five colors, optional notes, sidebar list, one-click jump-back, one-click remove.

**Privacy** — books, highlights, vocab, and positions live in IndexedDB + `chrome.storage.local`. No accounts, no sign-in, no cloud sync, no analytics, no ads.

## Contributing

This started as a tool I built for myself. The friends who pushed me to open source it deserve a project that's easy to jump into — so I tried to make it that.

- See **[CONTRIBUTING.md](CONTRIBUTING.md)** for setup, conventions, and the design system.
- Browse issues labeled [`good first issue`](https://github.com/aatmik-panse/chrome-reader/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) — themed presets, keyboard shortcuts, small EPUB edge cases, etc.
- Building in public — follow along and roast my code on X: [@aatmik-panse](https://x.com/aatmik_panse).

PRs welcome. Feature suggestions welcome. Bug reports especially welcome.

## Project structure

```
chromeApps/
  book-reader-extension/   Chrome extension (React 19 + Tailwind 4 + Vite 8)
  book-reader-api/         Legacy backend (not used by v1.1.0; kept for reference)
```

> **On the backend:** Earlier 1.0.x releases supported Google sign-in and a server-side AI fallback. Starting with **v1.1.0** the extension is BYOK-only and ships without sign-in or sync. `book-reader-api/` is preserved for historical reference but is no longer required to run anything.

## Tech stack

- **Frontend:** React 19, TypeScript, Tailwind CSS 4, Vite 8
- **PDF:** pdf.js
- **EPUB:** epub.js
- **Local storage:** IndexedDB (via `idb`) + `chrome.storage.local`
- **Testing:** Vitest, Testing Library, fake-indexeddb
- **Design system:** custom Clay-inspired system (warm cream, oat borders, hard-offset hover shadows)

## Permissions

| Permission | Why |
|---|---|
| `storage` | Saves books, highlights, vocabulary, reading positions, settings, and (encrypted) BYOK keys locally |
| `api.dictionaryapi.dev` | Word definitions for the dictionary popup |
| `translate.google.com` | Pronunciation audio fallback |
| `api.anthropic.com` / `api.openai.com` / `generativelanguage.googleapis.com` / `openrouter.ai` | Only used when you add your own key for that provider |

No `identity`, no `alarms`, no background service worker.

## License

ISC
