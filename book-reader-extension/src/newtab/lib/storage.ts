import { openDB, IDBPDatabase } from "idb";
import SHA256 from "crypto-js/sha256";
import encHex from "crypto-js/enc-hex";
import WordArray from "crypto-js/lib-typedarrays";

const DB_NAME = "book-reader";
const DB_VERSION = 2;
const BOOKS_STORE = "books";
const META_STORE = "metadata";
const THUMBNAILS_STORE = "thumbnails";

export interface BookMetadata {
  hash: string;
  title: string;
  author: string;
  format: "epub" | "pdf" | "txt";
  addedAt: number;
  /**
   * Last time `switchBook` opened this book (epoch ms). Optional because
   * older library entries pre-date the field; LibraryPanel falls back to
   * `addedAt` when missing.
   */
  lastOpenedAt?: number;
  totalChapters?: number;
  totalPages?: number;
  fileSize: number;
  /** When true, the book is hidden from the active library view. */
  archived?: boolean;
  /** Epoch ms the book was archived; used to sort the archived view. */
  archivedAt?: number;
}

export interface ReadingPosition {
  bookHash: string;
  chapterIndex: number;
  scrollOffset: number;
  percentage: number;
  updatedAt: number;
}

async function getDB(): Promise<IDBPDatabase> {
  return openDB(DB_NAME, DB_VERSION, {
    upgrade(db) {
      if (!db.objectStoreNames.contains(BOOKS_STORE)) {
        db.createObjectStore(BOOKS_STORE, { keyPath: "hash" });
      }
      if (!db.objectStoreNames.contains(META_STORE)) {
        db.createObjectStore(META_STORE, { keyPath: "hash" });
      }
      if (!db.objectStoreNames.contains(THUMBNAILS_STORE)) {
        // Keyed by book hash; value is { hash, blob }. A separate store keeps
        // the metadata read path light — listing the library shouldn't pull
        // image bytes off disk.
        db.createObjectStore(THUMBNAILS_STORE, { keyPath: "hash" });
      }
    },
  });
}

export function computeFileHash(arrayBuffer: ArrayBuffer): string {
  const copy = arrayBuffer.slice(0);
  const wordArray = WordArray.create(copy as any);
  return SHA256(wordArray).toString(encHex);
}

export async function saveBook(
  hash: string,
  data: ArrayBuffer
): Promise<void> {
  const db = await getDB();
  const copy = data.slice(0);
  await db.put(BOOKS_STORE, { hash, data: copy });
}

export async function getBook(hash: string): Promise<ArrayBuffer | null> {
  const db = await getDB();
  const record = await db.get(BOOKS_STORE, hash);
  if (!record?.data) return null;
  return (record.data as ArrayBuffer).slice(0);
}

export async function deleteBook(hash: string): Promise<void> {
  const db = await getDB();
  await db.delete(BOOKS_STORE, hash);
  await db.delete(META_STORE, hash);
  await db.delete(THUMBNAILS_STORE, hash);
  await removeBookMeta(hash);
}

export async function saveThumbnail(hash: string, blob: Blob): Promise<void> {
  const db = await getDB();
  await db.put(THUMBNAILS_STORE, { hash, blob });
}

export async function getThumbnail(hash: string): Promise<Blob | null> {
  const db = await getDB();
  const record = await db.get(THUMBNAILS_STORE, hash);
  return (record?.blob as Blob | undefined) ?? null;
}

export async function saveBookMeta(meta: BookMetadata): Promise<void> {
  const db = await getDB();
  await db.put(META_STORE, meta);
}

export async function getBookMeta(hash: string): Promise<BookMetadata | null> {
  const db = await getDB();
  return (await db.get(META_STORE, hash)) ?? null;
}

export async function getAllBookMetas(): Promise<BookMetadata[]> {
  const db = await getDB();
  return db.getAll(META_STORE);
}

async function removeBookMeta(hash: string): Promise<void> {
  const db = await getDB();
  await db.delete(META_STORE, hash);
}

// Reading position — stored in chrome.storage.local for fast sync-compatible access
export const POSITION_KEY_PREFIX = "pos_";
const CURRENT_BOOK_KEY = "current_book";

export async function savePosition(position: ReadingPosition): Promise<void> {
  const key = POSITION_KEY_PREFIX + position.bookHash;
  await chrome.storage.local.set({ [key]: position });
}

export async function getPosition(
  bookHash: string
): Promise<ReadingPosition | null> {
  const key = POSITION_KEY_PREFIX + bookHash;
  const result = await chrome.storage.local.get(key);
  return (result[key] as ReadingPosition | undefined) ?? null;
}

export async function setCurrentBook(hash: string | null): Promise<void> {
  await chrome.storage.local.set({ [CURRENT_BOOK_KEY]: hash });
}

export async function getCurrentBook(): Promise<string | null> {
  const result = await chrome.storage.local.get(CURRENT_BOOK_KEY);
  return (result[CURRENT_BOOK_KEY] as string | undefined) ?? null;
}

// Settings
export type PdfViewMode = "single" | "continuous" | "spread";
export type PdfTint = "normal" | "dark" | "sepia";

/** Default theme id used when nothing is stored or migration cannot resolve one. */
const DEFAULT_THEME_ID = "light";

export interface ReaderSettings {
  themeId: string;
  fontSize: number;
  lineHeight: number;
  fontFamily: string;
  translateTo: string;
  pdfViewMode: PdfViewMode;
  /**
   * `null` means "use the active theme's pdfTint". A non-null value is a
   * per-user override that bypasses theme-coupled tint.
   */
  pdfTintOverride: PdfTint | null;
  pdfShowThumbnailStrip: boolean;
  pdfShowViewMode: boolean;
  pdfShowPageNav: boolean;
  pdfShowColorMode: boolean;
  pdfShowZoom: boolean;
  /** When false the LeftRail collapses entirely (display: none). */
  showLeftRail: boolean;
  /** When false the RightRail collapses entirely (display: none). */
  showRightRail: boolean;
}

export const SETTINGS_STORAGE_KEY = "reader_settings";

export const DEFAULT_SETTINGS: ReaderSettings = {
  themeId: DEFAULT_THEME_ID,
  fontSize: 18,
  lineHeight: 1.8,
  fontFamily: "'DM Sans', Arial, sans-serif",
  translateTo: "en",
  pdfViewMode: "continuous",
  pdfTintOverride: null,
  pdfShowThumbnailStrip: true,
  pdfShowViewMode: true,
  pdfShowPageNav: true,
  pdfShowColorMode: true,
  pdfShowZoom: true,
  showLeftRail: true,
  showRightRail: true,
};

/** Shape of legacy settings we may encounter in storage from prior versions. */
interface LegacySettingsFields {
  theme?: "light" | "dark";
  pinToolbar?: boolean;
  pdfColorMode?: PdfTint;
  pdfShowThumbnails?: boolean;
}

type StoredSettings = Partial<ReaderSettings> & LegacySettingsFields;

function migrateThemeFlag(stored: StoredSettings, working: StoredSettings): void {
  if (typeof stored.theme === "string" && working.themeId === undefined) {
    working.themeId = stored.theme;
  }
  delete working.theme;
}

function migratePinToolbar(working: StoredSettings): void {
  delete working.pinToolbar;
}

function migratePdfColorMode(stored: StoredSettings, working: StoredSettings): void {
  if (!("pdfColorMode" in stored)) return;
  const legacyMode = stored.pdfColorMode;
  working.pdfTintOverride = legacyMode === "normal" ? null : legacyMode ?? null;
  delete working.pdfColorMode;
}

function migratePdfThumbnails(stored: StoredSettings, working: StoredSettings): void {
  if (!("pdfShowThumbnails" in stored)) return;
  const legacyShowThumbnails = stored.pdfShowThumbnails;
  delete working.pdfShowThumbnails;
  if (working.pdfShowThumbnailStrip === undefined) {
    // Preserve the legacy choice. Both flags carry the same intent
    // ("show thumbnails for the PDF"), only the UI placement differs.
    working.pdfShowThumbnailStrip = legacyShowThumbnails ?? true;
  }
}

function migrateLegacySettings(stored: StoredSettings): Partial<ReaderSettings> {
  const working: StoredSettings = { ...stored };
  migrateThemeFlag(stored, working);
  migratePinToolbar(working);
  migratePdfColorMode(stored, working);
  migratePdfThumbnails(stored, working);
  // `working` no longer carries any legacy fields; cast to drop the LegacySettingsFields union.
  return working as Partial<ReaderSettings>;
}

function storedShapeContainsLegacyFields(stored: StoredSettings): boolean {
  return (
    "theme" in stored ||
    "pinToolbar" in stored ||
    "pdfColorMode" in stored ||
    "pdfShowThumbnails" in stored
  );
}

export async function saveSettings(settings: ReaderSettings): Promise<void> {
  await chrome.storage.local.set({ [SETTINGS_STORAGE_KEY]: settings });
}

export async function getSettings(): Promise<ReaderSettings> {
  const result = await chrome.storage.local.get(SETTINGS_STORAGE_KEY);
  const stored = result[SETTINGS_STORAGE_KEY] as StoredSettings | undefined;
  if (!stored) return DEFAULT_SETTINGS;

  const merged: ReaderSettings = { ...DEFAULT_SETTINGS, ...migrateLegacySettings(stored) };

  // Persist the cleaned shape back so legacy fields are physically removed from
  // chrome.storage. Without this every read re-cleans the same legacy keys forever
  // and any direct storage read (background script, devtools) still sees stale data.
  // Fire-and-forget — caller doesn't need to await.
  if (storedShapeContainsLegacyFields(stored)) {
    void saveSettings(merged);
  }

  return merged;
}
