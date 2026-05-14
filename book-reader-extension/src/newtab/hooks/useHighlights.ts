import { useCallback, useEffect, useState } from "react";
import { Highlight, HighlightAnchor, HighlightColor } from "../lib/highlights/types";
import {
  listHighlights,
  putHighlight,
  deleteHighlight,
  getHighlight,
} from "../lib/highlights/storage";

export function useHighlights(bookHash: string | null) {
  const [items, setItems] = useState<Highlight[]>([]);

  const refresh = useCallback(async () => {
    if (!bookHash) return setItems([]);
    setItems(await listHighlights(bookHash));
  }, [bookHash]);

  useEffect(() => {
    if (!bookHash) {
      setItems([]);
      return;
    }
    listHighlights(bookHash).then(setItems);
  }, [bookHash]);

  const create = useCallback(
    async (text: string, color: HighlightColor, anchor: HighlightAnchor): Promise<Highlight> => {
      if (!bookHash) throw new Error("no book");
      const now = Date.now();
      const h: Highlight = {
        id: crypto.randomUUID(),
        bookHash,
        anchor,
        text,
        color,
        createdAt: now,
        updatedAt: now,
      };
      await putHighlight(h);
      await refresh();
      return h;
    },
    [bookHash, refresh]
  );

  const update = useCallback(
    async (id: string, patch: Partial<Pick<Highlight, "color" | "note">>) => {
      const found = await getHighlight(id);
      if (!found) return;
      const updated: Highlight = { ...found, ...patch, updatedAt: Date.now() };
      await putHighlight(updated);
      await refresh();
    },
    [refresh]
  );

  const remove = useCallback(
    async (id: string) => {
      await deleteHighlight(id);
      await refresh();
    },
    [refresh]
  );

  return { items, create, update, remove, refresh };
}
