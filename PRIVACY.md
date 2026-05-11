# Instant Book Reader — Privacy Policy

Last updated: May 11, 2026.

This Privacy Policy explains what data the Instant Book Reader Chrome extension ("the extension", "we") collects, how it is handled, where it is stored, and with whom it is shared. The extension is designed to work fully offline — every feature that transmits data does so only in direct response to an explicit user action, and most users will never sign in or send any data off their device.

If you do not agree with this policy, do not install or use the extension.

---

## 1. Summary

- **Default behavior:** all reading data (books, positions, highlights, vocabulary, preferences) is stored **only on your device** in your browser's IndexedDB and `chrome.storage.local`. Nothing is sent to any server.
- **Optional Google Sign-In** unlocks cloud sync of reading progress, highlights, and vocabulary across your devices, plus AI-powered features. Sign-in is entirely optional.
- **Optional AI features** can either use your own API key (your data is sent directly from your browser to the provider you choose) or our hosted fallback (your data is sent to our server, which forwards the request to Anthropic).
- **Two unauthenticated lookups** — dictionary definitions and text-to-speech audio — are sent to third-party services only when you explicitly click the corresponding button on a selected word.
- We do **not** sell user data. We do **not** use user data for advertising. We do **not** use user data to train AI models. We do **not** share user data with third parties except to deliver the feature you invoked.

---

## 2. Data we handle

The categories below list every type of data the extension may handle. Anything not listed here is not collected.

### 2.1 Data stored only on your device

The following data is stored locally in your browser (IndexedDB and `chrome.storage.local`) and never leaves your device unless you opt into sync (Section 2.2) or AI features (Section 2.3):

- **Book files** you import (EPUB, PDF, TXT) and their extracted text and table of contents. Stored in IndexedDB, keyed by a SHA-256 hash of the file bytes.
- **Reading position** for each book (current chapter, scroll offset, page number).
- **Highlights and notes** you create on text inside your books.
- **Vocabulary entries** (words you save), associated definitions, and spaced-repetition review state.
- **Reader preferences**: theme, font, font size, line spacing, layout, translation target language, panel sizes, last opened book.
- **Encrypted API keys**: if you enable Bring-Your-Own-Key (BYOK) AI, the API keys you enter are stored in `chrome.storage.local`, AES-encrypted with a key derived inside the extension. They are never transmitted to our servers.
- **Authentication token cache**: if you sign in, the JWT issued by our backend (Section 4) is stored locally so you don't have to sign in on every new tab.

You can delete all locally stored data at any time by removing the extension from `chrome://extensions` (Chrome will clear its IndexedDB and `chrome.storage.local`) or by using "Clear data" inside the extension's settings.

### 2.2 Data sent to our backend, only if you sign in

If — and only if — you sign in with Google, the following data is transmitted to and stored on our backend server (Section 4):

- **Your Google account identifiers**: Google ID (`sub`), email address, display name, and profile picture URL, obtained from the Google ID token. Used solely to create and identify your account.
- **Reading position** for each book: the hash of the book, the current location identifier (chapter id, page number, or character offset), and a timestamp. Used to resume reading on another device.
- **Highlights**: the hash of the book, the selected text, surrounding anchor text, an optional note, color, and timestamps.
- **Vocabulary entries**: the saved word, the sentence it appeared in, its definition, the book hash, and review state.

We do **not** receive your book files, your full reading content, or your highlights' position within the file beyond what is needed to anchor a highlight back to its passage. Books themselves never leave your device.

If you sign out or delete your account, this server-side data is deleted (Section 6).

### 2.3 Data sent to AI providers, only when you invoke an AI feature

When you click an AI action (e.g., "Summarize", "Explain", "Translate"), the extension sends a prompt to an AI provider. The prompt typically includes the text you selected and a short instruction, and may include a small amount of surrounding context from the same book to make the answer useful.

You choose which provider handles the request:

- **Bring-Your-Own-Key (BYOK) mode** (preferred): the request is sent **directly from your browser** to the provider you configured — OpenAI, Anthropic, Google (Gemini), or OpenRouter — using your own API key. Our servers do not see the request. Each provider's own privacy policy governs that traffic.
- **Hosted fallback mode**: if you are signed in and have not configured a BYOK provider, the request is sent to our backend, which forwards it to Anthropic's API. We do not store prompt content or responses beyond a short-lived response cache; see Section 4.

The extension does **not** send AI prompts unless you explicitly trigger an AI action.

### 2.4 Data sent to other third parties, only when you click a button

- **Dictionary lookup** ("Define"): the single word you selected is sent over HTTPS to `https://api.dictionaryapi.dev` to fetch a definition. No identifiers, no book content, no account info are sent. See the Free Dictionary API's terms at [dictionaryapi.dev](https://dictionaryapi.dev).
- **Text-to-speech** (the 🔊 audio button, only when the dictionary did not include a pronunciation): the single word is sent over HTTPS to `https://translate.google.com/translate_tts` to retrieve an audio file. Google's privacy policy applies: [policies.google.com/privacy](https://policies.google.com/privacy).

These two requests are anonymous — they contain only the selected word, not your identity, and they are not associated with your account.

---

## 3. What we do **not** collect

- We do **not** collect personally identifiable information beyond what you provide via Google Sign-In (email, name, profile picture).
- We do **not** collect health, financial, payment, location, web-browsing-history, or device-identifier data.
- We do **not** use analytics, telemetry, tracking pixels, advertising IDs, fingerprinting, or session-recording tools.
- We do **not** read the content of any other website you visit. The extension only activates on the New Tab page and on book files you explicitly open inside it.
- We do **not** sell, rent, or transfer your data to data brokers, advertisers, or any other third party for their own purposes.
- We do **not** use your data, prompts, highlights, or reading content to train any AI model — ours or anyone else's.

---

## 4. How and where data is stored

- **Local data** (Section 2.1) lives in Chrome's IndexedDB and `chrome.storage.local` on your device. It is subject to Chrome's own storage protections.
- **Backend data** (Section 2.2) is stored in a PostgreSQL database hosted on Railway (operated by Railway Corp., United States). The connection is encrypted in transit (TLS). Database access is restricted to the extension developer.
- **AI hosted fallback** (Section 2.3): requests are proxied to Anthropic's API ([anthropic.com/privacy](https://www.anthropic.com/privacy)). Anthropic processes the request and returns a response. Anthropic states that API inputs and outputs are not used to train their models by default. We do not log prompt content; only minimal request metadata (timestamp, user id, token counts) is recorded for abuse prevention and is retained for at most 30 days.
- **BYOK AI traffic** (Section 2.3): your browser talks directly to the chosen provider. Their policies apply: [OpenAI](https://openai.com/policies/privacy-policy), [Anthropic](https://www.anthropic.com/privacy), [Google AI](https://policies.google.com/privacy), [OpenRouter](https://openrouter.ai/privacy).
- **Authentication**: Google Sign-In is performed via `chrome.identity.getAuthToken`. The Google ID token is exchanged for a JWT issued by our backend. We do not see, store, or have access to your Google password.

All transmissions between the extension and our backend, and between the extension and third-party services listed above, occur over HTTPS/TLS.

---

## 5. Permissions used

The extension declares these Chrome permissions, used only for the purposes below:

- `storage` — to persist preferences, the last-opened-book pointer, and the most recent reading position locally on your device.
- `identity` — to enable optional Google Sign-In via `chrome.identity.getAuthToken`. Not used unless you click "Sign in".
- `alarms` — to schedule a low-frequency background tick (at most once per minute) that flushes your current reading position from memory into `chrome.storage.local`, so a crash or unexpected tab close does not lose your place. The alarm performs only local writes and, separately, when you are signed in, periodically POSTs your latest position to our backend.
- Host permissions for `googleapis.com`, `api.dictionaryapi.dev`, `translate.google.com`, `api.anthropic.com`, `api.openai.com`, `generativelanguage.googleapis.com`, `openrouter.ai` — only to send the specific requests described in Sections 2.3 and 2.4, in direct response to user action.

The extension does **not** request `tabs`, `activeTab`, `webNavigation`, `cookies`, `history`, `bookmarks`, content-script injection on arbitrary sites, or any other broad permission.

---

## 6. Data retention and deletion

- **Local data**: retained on your device until you delete a book, clear data from settings, or uninstall the extension. Uninstalling the extension causes Chrome to delete all of its IndexedDB and `chrome.storage.local` data.
- **Backend data** (only present if you signed in): retained for as long as your account exists. You can delete your account from inside the extension's settings; this permanently deletes your reading positions, highlights, and vocabulary entries from our database. You can also request deletion by emailing the contact address in Section 9.
- **AI request metadata**: retained for at most 30 days for abuse prevention, then deleted.
- We do not retain backups beyond what is operationally necessary, and backups roll off within 30 days.

---

## 7. Children's privacy

The extension is not directed to children under 13. We do not knowingly collect data from children under 13. If you believe a child has provided data, contact us (Section 9) and we will delete it.

---

## 8. Changes to this policy

If we make material changes to this policy, we will update the "Last updated" date at the top and post a notice in the extension's release notes and on the Chrome Web Store listing. Continued use of the extension after a change indicates acceptance of the updated policy.

---

## 9. Contact

For privacy questions, data-deletion requests, or to report a concern, open an issue or contact the developer at:

- GitHub issues: <https://github.com/aatmik-panse/chrome-reader/issues>
- Email: aatmik.panse@gmail.com

We aim to respond within 14 days.

---

## 10. Your rights

Depending on where you live (e.g., EEA, UK, California), you may have rights to access, correct, delete, or port your personal data, and to object to or restrict its processing. To exercise these rights, contact us using the details in Section 9. We will not discriminate against you for exercising any of these rights.
