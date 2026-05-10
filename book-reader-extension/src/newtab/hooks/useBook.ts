import { useState, useCallback, useEffect, useRef } from "react";
import { parseEpub, ParsedEpub } from "../lib/parsers/epub";
import { parsePdf, ParsedPdf } from "../lib/parsers/pdf";
import { parseTxt, ParsedTxt } from "../lib/parsers/txt";
import {
  saveBook,
  getBook,
  saveBookMeta,
  getBookMeta,
  getAllBookMetas,
  deleteBook as deleteBookFromStorage,
  computeFileHash,
  getCurrentBook,
  setCurrentBook,
  saveThumbnail,
  BookMetadata,
  POSITION_KEY_PREFIX,
} from "../lib/storage";
import { generateThumbnail } from "../lib/thumbnails";

export type BookFormat = "epub" | "pdf" | "txt";

export interface LoadedBook {
  hash: string;
  format: BookFormat;
  metadata: BookMetadata;
  epub?: ParsedEpub;
  pdf?: ParsedPdf;
  txt?: ParsedTxt;
}

function detectFormat(file: File): BookFormat | null {
  const ext = file.name.split(".").pop()?.toLowerCase();
  if (ext === "epub") return "epub";
  if (ext === "pdf") return "pdf";
  if (ext === "txt" || ext === "text") return "txt";

  if (file.type === "application/epub+zip") return "epub";
  if (file.type === "application/pdf") return "pdf";
  if (file.type.startsWith("text/")) return "txt";

  return null;
}

async function loadProgressByHashFromStorage(): Promise<Record<string, number>> {
  // Passing null asks chrome to return every key in the area. The stub
  // honours this; the real chrome typings accept it via the union signature.
  const all = (await (chrome.storage.local as unknown as {
    get(key: null): Promise<Record<string, unknown>>;
  }).get(null)) as Record<string, unknown>;
  const progress: Record<string, number> = {};
  for (const [key, value] of Object.entries(all)) {
    if (!key.startsWith(POSITION_KEY_PREFIX)) continue;
    const hash = key.slice(POSITION_KEY_PREFIX.length);
    const position = value as { percentage?: number } | null | undefined;
    if (position && typeof position.percentage === "number") {
      progress[hash] = position.percentage;
    }
  }
  return progress;
}

function shouldPublishProgress(previous: number | undefined, next: number): boolean {
  return typeof previous !== "number" || Math.round(previous) !== Math.round(next);
}

export function useBook() {
  const [currentBook, setCurrentBookState] = useState<LoadedBook | null>(null);
  const [library, setLibrary] = useState<BookMetadata[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [progressByHash, setProgressByHash] = useState<Record<string, number>>({});

  const loadLibrary = useCallback(async () => {
    const metas = await getAllBookMetas();
    setLibrary(metas.sort((a, b) => b.addedAt - a.addedAt));
  }, []);

  // Hold the previous book so we can dispose its parser-owned resources
  // (epubjs blob URLs, archive bookkeeping) once the next one is ready.
  const previousBookRef = useRef<LoadedBook | null>(null);

  const loadBookFromHash = useCallback(async (hash: string) => {
    setLoading(true);
    setError(null);

    try {
      const meta = await getBookMeta(hash);
      if (!meta) throw new Error("Book metadata not found");

      const data = await getBook(hash);
      if (!data) throw new Error("Book data not found");

      const loaded: LoadedBook = { hash, format: meta.format, metadata: meta };

      switch (meta.format) {
        case "epub": {
          loaded.epub = await parseEpub(data);
          break;
        }
        case "pdf": {
          loaded.pdf = await parsePdf(data);
          break;
        }
        case "txt": {
          loaded.txt = await parseTxt(data);
          break;
        }
      }

      const prior = previousBookRef.current;
      previousBookRef.current = loaded;
      if (prior?.epub) prior.epub.dispose();

      setCurrentBookState(loaded);
      await setCurrentBook(hash);

      // Stamp lastOpenedAt so the LibraryPanel can sort by recency.
      const updatedMeta: BookMetadata = { ...meta, lastOpenedAt: Date.now() };
      await saveBookMeta(updatedMeta);
      setLibrary((prev) =>
        prev.map((entry) => (entry.hash === hash ? updatedMeta : entry)),
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "Failed to load book");
    } finally {
      setLoading(false);
    }
  }, []);

  const uploadBook = useCallback(
    async (file: File) => {
      setLoading(true);
      setError(null);

      try {
        const format = detectFormat(file);
        if (!format) throw new Error("Unsupported file format. Use EPUB, PDF, or TXT.");

        const arrayBuffer = await file.arrayBuffer();
        const hash = computeFileHash(arrayBuffer);

        const existing = await getBookMeta(hash);
        if (existing) {
          await loadBookFromHash(hash);
          return;
        }

        const meta: BookMetadata = {
          hash,
          title: file.name.replace(/\.[^.]+$/, ""),
          author: "Unknown Author",
          format,
          addedAt: Date.now(),
          fileSize: file.size,
        };

        switch (format) {
          case "epub": {
            const parsed = await parseEpub(arrayBuffer);
            meta.title = parsed.title;
            meta.author = parsed.author;
            meta.totalChapters = parsed.chapters.length;
            break;
          }
          case "pdf": {
            const pdfInfo = await parsePdf(arrayBuffer);
            if (pdfInfo.title && pdfInfo.title !== "PDF Document") meta.title = pdfInfo.title;
            meta.author = pdfInfo.author;
            meta.totalPages = pdfInfo.totalPages;
            break;
          }
          case "txt": {
            const parsed = await parseTxt(arrayBuffer);
            meta.title = parsed.title;
            break;
          }
        }

        await saveBook(hash, arrayBuffer);
        await saveBookMeta(meta);

        // Best-effort cover generation. We don't block library refresh on it
        // because the lazy hook will retry per-row anyway, and a thumbnail
        // failure must never make a successful upload look broken.
        void generateThumbnail(meta, arrayBuffer)
          .then((blob) => (blob ? saveThumbnail(hash, blob) : undefined))
          .catch(() => undefined);

        await loadLibrary();
        await loadBookFromHash(hash);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Failed to upload book");
        setLoading(false);
      }
    },
    [loadBookFromHash, loadLibrary]
  );

  const removeBook = useCallback(
    async (hash: string) => {
      await deleteBookFromStorage(hash);
      if (currentBook?.hash === hash) {
        if (previousBookRef.current?.epub) previousBookRef.current.epub.dispose();
        previousBookRef.current = null;
        setCurrentBookState(null);
        await setCurrentBook(null);
      }
      await loadLibrary();
    },
    [currentBook, loadLibrary]
  );

  const setArchivedFlag = useCallback(
    async (hash: string, archived: boolean) => {
      const meta = await getBookMeta(hash);
      if (!meta) return;
      const updated: BookMetadata = archived
        ? { ...meta, archived: true, archivedAt: Date.now() }
        : { ...meta, archived: false, archivedAt: undefined };
      await saveBookMeta(updated);
      setLibrary((prev) => prev.map((entry) => (entry.hash === hash ? updated : entry)));
    },
    []
  );

  const archiveBook = useCallback((hash: string) => setArchivedFlag(hash, true), [setArchivedFlag]);
  const unarchiveBook = useCallback((hash: string) => setArchivedFlag(hash, false), [setArchivedFlag]);

  const switchBook = useCallback(
    async (hash: string) => {
      await loadBookFromHash(hash);
    },
    [loadBookFromHash]
  );

  useEffect(() => {
    (async () => {
      await loadLibrary();
      const lastHash = await getCurrentBook();
      if (lastHash) {
        await loadBookFromHash(lastHash);
      } else {
        setLoading(false);
      }
    })();
  }, [loadLibrary, loadBookFromHash]);

  // Initial progress load — read every `pos_*` key once on mount.
  useEffect(() => {
    loadProgressByHashFromStorage().then(setProgressByHash);
  }, []);

  // Keep progress map in sync with cross-tab writes / within-session updates.
  useEffect(() => {
    const handleStorageChanged = (
      changes: Record<string, { newValue?: unknown }>,
      areaName: string,
    ): void => {
      if (areaName !== "local") return;
      let touched = false;
      let next: Record<string, number> | null = null;
      const draftProgress = (): Record<string, number> => {
        if (!next) next = { ...progressByHashRef.current };
        return next;
      };
      for (const [key, change] of Object.entries(changes)) {
        if (!key.startsWith(POSITION_KEY_PREFIX)) continue;
        const hash = key.slice(POSITION_KEY_PREFIX.length);
        const position = change.newValue as { percentage?: number } | undefined;
        if (position && typeof position.percentage === "number") {
          const previous = progressByHashRef.current[hash];
          draftProgress()[hash] = position.percentage;
          if (shouldPublishProgress(previous, position.percentage)) {
            touched = true;
          }
        } else if (change.newValue === undefined && hash in progressByHashRef.current) {
          delete draftProgress()[hash];
          touched = true;
        }
      }
      if (next) {
        // Keep the ref exact for future comparisons, but publish React state
        // only when rounded display progress changes.
        progressByHashRef.current = next;
      }
      if (touched && next) {
        setProgressByHash(next);
      }
    };
    chrome.storage.onChanged.addListener(handleStorageChanged);
    return () => chrome.storage.onChanged.removeListener(handleStorageChanged);
  }, []);

  const progressByHashRef = useRef<Record<string, number>>({});
  useEffect(() => {
    progressByHashRef.current = progressByHash;
  }, [progressByHash]);

  return {
    currentBook,
    library,
    loading,
    error,
    progressByHash,
    uploadBook,
    removeBook,
    switchBook,
    loadLibrary,
    archiveBook,
    unarchiveBook,
  };
}
