# Instant Book Reader — Privacy Policy

**Last updated:** 14 May 2026
**Applies to:** Instant Book Reader for Chrome (extension ID `beconkamchfbjkplbapbkhmjdmpjfeni`), version 1.1.0 and later.

## Summary

Instant Book Reader does not collect, store, or transmit any personal data to its developer or to any service operated by its developer. It has no accounts, no sign-in, no cloud sync, and no backend. All of your reading data stays on your device.

The extension contacts third-party services only when **you** trigger a feature that requires them (defining a word, playing pronunciation audio, or using the optional AI assistant with your own API key). When that happens, the request goes directly from your browser to the third party — the developer does not sit in the middle and does not see the request.

## What stays on your device

The following data is stored exclusively in your browser, using `chrome.storage.local` and IndexedDB, and is never transmitted to the developer:

- Uploaded book files (EPUB, PDF, TXT)
- Reading position for each book
- Highlights (text, color, optional note)
- Saved vocabulary words and their context sentences
- Spaced-repetition review state for each saved word
- Reader preferences (theme, font, line spacing, layout, translate target language, PDF view mode)
- Custom themes you create
- AI provider API keys you choose to add in Settings → AI Keys

When you uninstall the extension, Chrome deletes this data along with it.

## What we do not collect

Instant Book Reader does **not** collect, log, infer, or transmit any of the following:

- Personally identifiable information (no name, email, address, age, or identifier)
- Authentication credentials (the extension has no sign-in)
- Health, financial, or payment information
- Personal communications
- Location data, IP address, or GPS
- Web browsing history
- User activity logs, clicks, mouse position, scroll, or keystroke data
- The text of your books, your highlights, or your saved vocabulary

The extension contains no analytics SDK, no telemetry, no crash reporter, and no advertising code.

## Third-party services you opt into

The extension makes outbound network requests only in the following circumstances. In each case, the request is made directly from your browser to the third party using their public API; the developer does not receive, proxy, or log it.

### 1. Dictionary lookups (`api.dictionaryapi.dev`)

When you use the **Define** action on a selected word, that single word is sent to `api.dictionaryapi.dev`, a free public dictionary API, to retrieve its definition, part of speech, and phonetic transcription. Only the selected word is included in the request. No identifier, no token, no other information about you or your book is sent.

### 2. Pronunciation audio (`translate.google.com`)

When a dictionary definition does not include a human-recorded pronunciation, the **Listen** button fetches a text-to-speech audio clip from `translate.google.com`. Only the word being pronounced appears in the URL. No identifier is attached.

### 3. AI assistant (bring-your-own-key)

The AI assistant is opt-in. It is disabled until you go to **Settings → AI Keys**, paste an API key for one of the supported providers, and select that provider as the active one. Once configured, when you click **Summarize**, **Highlights**, **Explain**, **Ask**, or **Translate**, the relevant text excerpt (and your question, if any) is sent **directly from your browser** to the API of the provider you selected, authenticated with the API key you stored locally. Supported providers and the endpoints they use:

- **Anthropic** — `https://api.anthropic.com/`
- **OpenAI** — `https://api.openai.com/`
- **Google Gemini** — `https://generativelanguage.googleapis.com/`
- **OpenRouter** — `https://openrouter.ai/`

The developer does **not** operate a proxy, relay, or fallback endpoint for these requests. The developer cannot read them, log them, or bill for them. Your API key never leaves your device except as the standard `Authorization` header on the call your browser makes to your chosen provider.

Each provider has its own privacy policy governing how they handle the prompts you send. Refer to the policy of the provider you choose:

- Anthropic: https://www.anthropic.com/legal/privacy
- OpenAI: https://openai.com/policies/privacy-policy
- Google: https://policies.google.com/privacy
- OpenRouter: https://openrouter.ai/privacy

### 4. Web search shortcut

The **Search** action on the selection toolbar opens a new tab pointed at `https://www.google.com/search?q=<your selection>`. This is a normal browser tab navigation; the extension itself does not transmit anything. Google's privacy policy applies to that tab the same way it would for any Google search.

## Permissions and why we request them

Instant Book Reader requests the smallest set of permissions needed for its features.

| Permission | Reason |
|---|---|
| `storage` | Persist your books, reading positions, highlights, vocabulary, settings, and (if you add one) your AI API key on this device. |
| Host: `api.dictionaryapi.dev` | Dictionary definitions when you use **Define**. |
| Host: `translate.google.com` | Pronunciation audio when no other recording is available. |
| Host: `api.anthropic.com` | Only when you have configured an Anthropic key and trigger an AI action. |
| Host: `api.openai.com` | Only when you have configured an OpenAI key and trigger an AI action. |
| Host: `generativelanguage.googleapis.com` | Only when you have configured a Google Gemini key and trigger an AI action. |
| Host: `openrouter.ai` | Only when you have configured an OpenRouter key and trigger an AI action. |

The extension does **not** request `identity`, `alarms`, `activeTab`, `tabs`, `cookies`, `webRequest`, or any other permission. It does not run content scripts on any web page. It does not run a background service worker.

## What changed from earlier versions (1.0.x → 1.1.0)

Versions 1.0.4 and earlier offered an optional Google Sign-In used to enable cloud sync of reading positions, highlights, and vocabulary across devices, plus a server-side AI fallback. Starting with **version 1.1.0**, these features have been removed entirely. The extension no longer requests the `identity` or `alarms` permissions, no longer runs a background service worker, and no longer communicates with any backend operated by the developer.

## Data retention and deletion

Because no data is collected or stored on the developer's infrastructure, there is nothing on our side to retain or delete. To erase all data the extension has stored locally, remove the extension from `chrome://extensions` (or use **Clear all keys** in Settings → AI Keys to remove only AI keys while keeping your library).

## Children

Instant Book Reader is a general-audience reading tool and is not directed at children under 13. It does not knowingly collect any data from anyone.

## Changes to this policy

If the extension's data-handling behavior ever changes, this policy will be updated and a notice will be included in the release notes for the corresponding version. The "Last updated" date at the top of this document reflects the most recent revision.

## Contact

For questions about this policy or this extension's privacy practices, open an issue at:

https://github.com/aatmik-panse/chrome-reader/issues
