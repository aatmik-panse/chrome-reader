import { useEffect, useState } from "react";
import { BookMetadata } from "../lib/storage";
import { ensureThumbnail } from "../lib/thumbnails";

interface ThumbnailState {
  status: "idle" | "loading" | "ready" | "missing";
  url: string | null;
}

const INITIAL_STATE: ThumbnailState = { status: "idle", url: null };

/**
 * Lazy-loads (and caches) a per-book thumbnail object URL. The URL is created
 * here and revoked on unmount or when the book hash changes, so callers can
 * pass it directly to an <img> tag without leaking blob references.
 */
export function useBookThumbnail(meta: BookMetadata): ThumbnailState {
  const [state, setState] = useState<ThumbnailState>(INITIAL_STATE);

  useEffect(() => {
    let cancelled = false;
    let createdObjectUrl: string | null = null;

    setState({ status: "loading", url: null });

    ensureThumbnail(meta)
      .then((blob) => {
        if (cancelled) return;
        if (!blob) {
          setState({ status: "missing", url: null });
          return;
        }
        createdObjectUrl = URL.createObjectURL(blob);
        setState({ status: "ready", url: createdObjectUrl });
      })
      .catch(() => {
        if (cancelled) return;
        setState({ status: "missing", url: null });
      });

    return () => {
      cancelled = true;
      if (createdObjectUrl) URL.revokeObjectURL(createdObjectUrl);
    };
    // Re-fetch only when the book identity changes — every other meta field
    // is irrelevant to the rendered cover bytes.
  }, [meta.hash, meta.format]);

  return state;
}
