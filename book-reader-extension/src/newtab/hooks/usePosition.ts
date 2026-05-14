import { useState, useCallback, useEffect, useRef } from "react";
import {
  savePosition,
  getPosition,
  ReadingPosition,
} from "../lib/storage";

interface UsePositionOptions {
  bookHash: string | null;
  bookTitle: string;
  enabled: boolean;
}

function shouldPublishPosition(prev: ReadingPosition | null, next: ReadingPosition): boolean {
  if (!prev) return true;
  if (prev.bookHash !== next.bookHash) return true;
  if (prev.chapterIndex !== next.chapterIndex) return true;
  return Math.round(prev.percentage) !== Math.round(next.percentage);
}

export function usePosition({ bookHash, enabled }: UsePositionOptions) {
  const [position, setPositionState] = useState<ReadingPosition | null>(null);
  const positionRef = useRef<ReadingPosition | null>(null);
  const saveTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => {
    if (!bookHash || !enabled) return;

    (async () => {
      const local = await getPosition(bookHash);
      if (local) {
        setPositionState(local);
        positionRef.current = local;
      } else {
        const defaultPos: ReadingPosition = {
          bookHash,
          chapterIndex: 0,
          scrollOffset: 0,
          percentage: 0,
          updatedAt: Date.now(),
        };
        setPositionState(defaultPos);
        positionRef.current = defaultPos;
      }
    })();
  }, [bookHash, enabled]);

  const updatePosition = useCallback(
    (chapterIndex: number, scrollOffset: number, percentage: number) => {
      if (!bookHash) return;

      const pos: ReadingPosition = {
        bookHash,
        chapterIndex,
        scrollOffset,
        percentage,
        updatedAt: Date.now(),
      };

      setPositionState((prev) => (shouldPublishPosition(prev, pos) ? pos : prev));
      positionRef.current = pos;

      clearTimeout(saveTimerRef.current);
      saveTimerRef.current = setTimeout(async () => {
        await savePosition(pos);
      }, 300);
    },
    [bookHash]
  );

  // Flush latest position to storage on unload / tab hide
  useEffect(() => {
    const flush = () => {
      clearTimeout(saveTimerRef.current);
      if (positionRef.current) {
        savePosition(positionRef.current);
      }
    };
    const onVisChange = () => { if (document.hidden) flush(); };
    window.addEventListener("beforeunload", flush);
    document.addEventListener("visibilitychange", onVisChange);
    return () => {
      window.removeEventListener("beforeunload", flush);
      document.removeEventListener("visibilitychange", onVisChange);
      clearTimeout(saveTimerRef.current);
    };
  }, []);

  return { position, updatePosition };
}
