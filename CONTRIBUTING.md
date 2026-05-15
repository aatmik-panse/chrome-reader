# Contributing to Instant Book Reader

Thanks for considering a contribution - this project started as a personal tool and only became "a project" because a few friends asked for it. The bar for opening a PR is low. The bar for being kind in comments is high.

## Ways to help

- Pick up an issue labeled [`good first issue`](https://github.com/aatmik-panse/chrome-reader/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) - these are scoped to be doable in an afternoon.
- File a bug. Please include: Chrome version, OS, the file format that triggered it (EPUB / PDF / TXT), a short reproduction, and **a screenshot or short screen recording** of the broken state. Visual bugs without a screenshot are very hard to triage. A 4 MB sample file is fine; please don't attach copyrighted books.
- Suggest a feature. Open an issue with the **problem** first ("I wanted X but couldn't"), the solution second.
- Improve docs, themes, or test coverage. All of these are first-class contributions.

## Development setup

```bash
git clone https://github.com/aatmik-panse/chrome-reader
cd chrome-reader/book-reader-extension
npm install
npm run build
```

Then load `book-reader-extension/dist` as an unpacked extension at `chrome://extensions` with **Developer mode** enabled. After code changes, run `npm run build` and click the reload icon on the extension card.

`npm run dev` exists but isn't useful most of the time - the extension runs as a New Tab override, not a regular Vite page.

### Tests

```bash
npm test                                       # full run
npm run test:watch                             # watch mode
npx vitest run tests/themes/cascade.test.ts    # single file
npx vitest run -t "preset name"                # filter by test name
```

Tests use `jsdom` + `fake-indexeddb`, so storage-layer tests exercise the real `idb` API. Tests are colocated by domain under `tests/` (not next to source). Convention: `tests/<domain>/<file>.test.ts(x)`.

If you change anything in `lib/parsers/`, `lib/highlights/`, `lib/vocab/`, `lib/themes/`, or `lib/ai/`, please add or update a test.

## Project tour (read this before changing anything non-trivial)

The extension is a single-page React app rendered into the New Tab override. State is owned by hooks under `src/newtab/hooks/`, one per domain - `useBook`, `usePosition`, `useHighlights`, `useVocab`, `useTheme`, `useAI`, `usePanelState`, `useSelection`, `useByok`. `App.tsx` composes them.

Books are content-addressed by **SHA-256 of the file bytes** (see `computeFileHash` in `src/newtab/lib/storage.ts`). The hash is the primary key everywhere: positions, highlights, vocab, AI cache. If you're adding any persisted data tied to a book, key it by hash.

The three formats render through three separate paths on purpose:

- **EPUB** → `epubjs` → flattened chapters → rendered as React-managed HTML inside `.prose-reader`. TOC fallbacks in `lib/parsers/epub-toc-fallback.ts` + `toc-quality.ts`.
- **PDF** → `pdfjs-dist` 3.x → its own viewer under `components/pdf/` with single / continuous / spread modes and a thumbnail strip. The worker ships as a static file in `public/` (CSP forbids `unsafe-eval`).
- **TXT** → chunked in-memory. Trivial.

Highlights use a **content-addressed anchor scheme** (`lib/highlights/anchor.ts`) - they store the surrounding text + offset, not DOM ranges, so they survive re-renders and reflows. PDF highlights anchor against the per-page `.textLayer`; EPUB/TXT anchor against `.prose-reader`. See the PDF branch of `handleSelectionAction` in `App.tsx`.

Themes are CSS variables applied by `lib/themes/apply.ts`. Presets live in `lib/themes/presets.ts`. Custom themes go through `components/settings/ThemeBuilder.tsx`.

## Design system

UI must follow the **Clay** design system: warm cream background, oat borders, hard-offset hover shadows, no cool grays, no blurred shadows. Full spec at `.cursor/rules/clay-design-system.mdc`.

Use the existing primitives:

- Buttons: `.clay-btn-solid`, `.clay-btn-white`
- Cards: `.clay-card`
- Uppercase labels: `.clay-label`

If a theme needs to extend variables, add them to `src/newtab/themes.css` and the corresponding entry in `lib/themes/presets.ts`.

## Code style

- TypeScript everywhere. No `any` unless you leave a one-line comment explaining why.
- Hooks own state. Components stay presentational where possible.
- Prefer composition over abstraction. Three similar lines is better than a premature helper.
- No comments that just describe what the code does - only comments that explain a non-obvious _why_.
- Don't add features the issue didn't ask for. Smaller PRs merge faster.

## Commit + PR conventions

- One logical change per PR. Don't bundle unrelated fixes.
- Branch from `main`. Rebase, don't merge `main` back in.
- Commit messages: short imperative subject (`fix: epub spine with empty hrefs`), optional body for the _why_.
- PR description should answer three questions: **what changed**, **why**, and **how you tested it**.
- **If your PR touches the UI, you must attach a screenshot — and a before/after pair if you're changing existing UI.** A short screen recording (GIF or MP4) is even better for anything animated or interactive. PRs that change UI without visual evidence will be sent back for one.
- All checks (typecheck + tests) must pass before review.

## Privacy & data

This is a non-negotiable: **the extension does not phone home**, and contributions must preserve that.

- No analytics. No telemetry. No "anonymous usage stats."
- BYOK AI requests must go from the user's browser directly to the provider. No proxy, no logging.
- Don't add a backend dependency. The legacy `book-reader-api/` folder is reference-only.
- New permissions must be justified in the PR description. Minimum-viable scope only.

## Reporting security issues

Please **don't** open public issues for security problems. Email the maintainer (see GitHub profile) and we'll respond within a week.

## Code of conduct

Be kind. Assume good faith. Reviewing other people's code is a gift; receiving review is also a gift. If a conversation gets heated, step away for a day. Disrespectful comments will be removed without warning.

## License

By contributing, you agree your contributions are licensed under the project's ISC license.
