import React, { useRef, useEffect, useCallback, useMemo, useState } from "react";
import { LoadedBook } from "../hooks/useBook";
import { ReadingPosition, ReaderSettings } from "../lib/storage";
import PdfViewer from "./pdf/PdfViewer";
import { useSelection, type SelectionOffsets } from "../hooks/useSelection";
import SelectionToolbar, { ToolbarAction, HighlightColor } from "./SelectionToolbar";
import { Highlight } from "../lib/highlights/types";
import { renderHighlights, clearHighlights } from "../lib/highlights/render";
import { findOverlappingHighlights, offsetsFromRange } from "../lib/highlights/anchor";

interface ReaderProps {
  book: LoadedBook;
  position: ReadingPosition | null;
  settings: ReaderSettings;
  onSettingsChange: (next: ReaderSettings) => void;
  highlights: Highlight[];
  onPositionChange: (chapterIndex: number, scrollOffset: number, percentage: number) => void;
  onSelectionAction: (
    action: ToolbarAction,
    payload: { text: string; range: Range; rect: DOMRect; offsets?: SelectionOffsets; color?: HighlightColor; highlightIds?: string[]; chapterIndex: number; chapterText: string }
  ) => void;
  onHighlightClick: (id: string, rect: DOMRect) => void;
  hasExplain: boolean;
  aiAvailable: boolean;
  /**
   * Anchor id (no leading "#") to scroll to inside the prose container after
   * the next chapter render. App.tsx owns this state — see `goToTocNode`.
   */
  pendingFragment?: string | null;
  /**
   * Reader calls this after attempting (or skipping) the fragment scroll so
   * App.tsx can null out `pendingFragment` and avoid re-firing.
   */
  onPendingFragmentConsumed?: () => void;
  /**
   * Invoked when the user clicks an in-EPUB `<a href>` that resolves to a
   * different spine section. Reader handles same-chapter fragment scrolling
   * internally; cross-chapter jumps are owned by App.
   */
  onNavigateToSpine?: (spineIndex: number, fragment: string | null) => void;
}

function estimateReadingTime(text: string): number {
  return Math.max(1, Math.ceil(text.split(/\s+/).length / 230));
}

function stripHtml(html: string): string {
  const tmp = document.createElement("div");
  tmp.innerHTML = html;
  return tmp.textContent || tmp.innerText || "";
}

function cleanChapterLabel(label: string): string {
  if (/\.(x?html?|xml|htm)$/i.test(label)) return "";
  if (/^[A-Z0-9!@#$%^&*()\-_=+{}\[\]|\\;:'",.<>?/~`]+$/i.test(label) && label.length > 30) return "";
  return label.trim();
}

function Reader({
  book, position, settings, onSettingsChange, highlights, onPositionChange, onSelectionAction, onHighlightClick, hasExplain, aiAvailable,
  pendingFragment = null, onPendingFragmentConsumed, onNavigateToSpine,
}: ReaderProps) {
  const contentRef = useRef<HTMLDivElement>(null);
  const proseRef = useRef<HTMLDivElement>(null);
  const scrollTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const restoredRef = useRef(false);
  const [showNav, setShowNav] = useState(false);
  const [contentEl, setContentEl] = useState<HTMLDivElement | null>(null);
  const [proseEl, setProseEl] = useState<HTMLDivElement | null>(null);
  const attachContentRef = useCallback((el: HTMLDivElement | null) => {
    contentRef.current = el;
    setContentEl(el);
  }, []);
  const attachProseRef = useCallback((el: HTMLDivElement | null) => {
    proseRef.current = el;
    setProseEl(el);
  }, []);

  const chapterIndex = position?.chapterIndex ?? 0;

  const { content, totalSections, chapterLabel, plainText } = useMemo(() => {
    if (book.format === "epub" && book.epub) {
      const ch = book.epub.chapters[chapterIndex];
      return {
        content: ch?.content ?? "",
        totalSections: book.epub.chapters.length,
        chapterLabel: ch?.label ?? `Chapter ${chapterIndex + 1}`,
        plainText: stripHtml(ch?.content ?? ""),
      };
    }
    if (book.format === "txt" && book.txt) {
      const chunk = book.txt.chunks[chapterIndex];
      return {
        content: `<div style="white-space: pre-wrap;">${(chunk ?? "").replace(/</g, "&lt;")}</div>`,
        totalSections: book.txt.chunks.length,
        chapterLabel: `Section ${chapterIndex + 1} of ${book.txt.chunks.length}`,
        plainText: chunk ?? "",
      };
    }
    return { content: "", totalSections: 0, chapterLabel: "", plainText: "" };
  }, [book, chapterIndex]);

  const readingTime = useMemo(() => estimateReadingTime(plainText), [plainText]);

  useEffect(() => {
    if (!contentRef.current || !position || restoredRef.current) return;
    contentRef.current.scrollTop = position.scrollOffset;
    restoredRef.current = true;
  }, [content, position]);

  useEffect(() => { restoredRef.current = false; }, [chapterIndex]);

  useEffect(() => {
    if (book.format === "pdf") return;
    const el = proseRef.current;
    if (!el) return;
    const handle = requestAnimationFrame(() => {
      if (!proseRef.current) return;
      renderHighlights(proseRef.current, plainText, chapterIndex, highlights, onHighlightClick);
    });
    return () => {
      cancelAnimationFrame(handle);
      if (proseRef.current) clearHighlights(proseRef.current);
    };
  }, [content, highlights, plainText, chapterIndex, book.format, onHighlightClick]);

  // After content renders, scroll to the requested fragment (TOC deep-link).
  useEffect(() => {
    if (book.format === "pdf") return;
    if (!pendingFragment) return;
    if (!onPendingFragmentConsumed) return;
    const handle = requestAnimationFrame(() => {
      const proseElement = proseRef.current;
      if (!proseElement) {
        onPendingFragmentConsumed();
        return;
      }
      let target: Element | null = proseElement.ownerDocument.getElementById(pendingFragment);
      if (target && !proseElement.contains(target)) target = null;
      if (!target) {
        const escaped = (typeof CSS !== "undefined" && CSS.escape)
          ? CSS.escape(pendingFragment)
          : pendingFragment.replace(/[^a-zA-Z0-9_-]/g, "");
        target = proseElement.querySelector(`[name="${escaped}"]`);
      }
      if (target instanceof HTMLElement) {
        target.scrollIntoView({ block: "start" });
      }
      onPendingFragmentConsumed();
    });
    return () => cancelAnimationFrame(handle);
  }, [pendingFragment, content, book.format, onPendingFragmentConsumed]);

  const handleScroll = useCallback(() => {
    if (!contentRef.current) return;
    if (scrollTimeoutRef.current) clearTimeout(scrollTimeoutRef.current);
    scrollTimeoutRef.current = setTimeout(() => {
      const el = contentRef.current!;
      const scrollOffset = el.scrollTop;
      const maxScroll = el.scrollHeight - el.clientHeight;
      const chapterProgress = maxScroll > 0 ? scrollOffset / maxScroll : 0;
      const pct = totalSections > 0 ? ((chapterIndex + chapterProgress) / totalSections) * 100 : 0;
      onPositionChange(chapterIndex, scrollOffset, pct);
    }, 300);
  }, [chapterIndex, totalSections, onPositionChange]);

  const goToChapter = useCallback((index: number) => {
    if (index < 0 || index >= totalSections) return;
    onPositionChange(index, 0, (index / totalSections) * 100);
    restoredRef.current = false;
    if (contentRef.current) contentRef.current.scrollTop = 0;
  }, [totalSections, onPositionChange]);

  // Intercept clicks on in-chapter <a> tags. EPUB content lands in our
  // newtab origin via dangerouslySetInnerHTML, so a raw click would either
  // navigate the whole tab away (for absolute URLs) or fail silently (for
  // intra-spine paths that don't exist as files). We resolve the href via
  // ParsedEpub.resolveLink and route accordingly.
  const handleProseClick = useCallback((event: React.MouseEvent<HTMLDivElement>) => {
    if (book.format !== "epub" || !book.epub) return;
    // Allow modifier-clicks (open in new tab/window) to behave normally for
    // absolute URLs. We still need to prevent default for relative paths
    // since the browser would resolve them against the newtab origin.
    const target = (event.target as Element | null)?.closest("a");
    if (!target) return;
    const rawHref = target.getAttribute("href");
    if (!rawHref) return;

    if (/^[a-z][a-z0-9+.-]*:/i.test(rawHref)) {
      // Absolute external link (http/https/mailto/...). Open externally so
      // the reader tab itself doesn't navigate away.
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      event.preventDefault();
      window.open(rawHref, "_blank", "noopener,noreferrer");
      return;
    }

    const fromHref = book.epub.chapters[chapterIndex]?.href ?? "";
    const resolved = book.epub.resolveLink(fromHref, rawHref);
    if (!resolved) return;

    event.preventDefault();
    if (resolved.spineIndex < 0 || resolved.spineIndex === chapterIndex) {
      // Same chapter (or unknown chapter) — scroll within the prose if the
      // fragment matches an element id.
      const fragment = resolved.fragment;
      if (!fragment) return;
      const proseElement = proseRef.current;
      if (!proseElement) return;
      const escaped = (typeof CSS !== "undefined" && CSS.escape) ? CSS.escape(fragment) : fragment.replace(/[^a-zA-Z0-9_-]/g, "");
      const inDoc = proseElement.ownerDocument.getElementById(fragment);
      const found = inDoc && proseElement.contains(inDoc) ? inDoc : proseElement.querySelector(`[id="${escaped}"], [name="${escaped}"]`);
      if (found instanceof HTMLElement) found.scrollIntoView({ block: "start" });
      return;
    }

    if (onNavigateToSpine) onNavigateToSpine(resolved.spineIndex, resolved.fragment);
  }, [book, chapterIndex, onNavigateToSpine]);

  const { selection, clearSelection } = useSelection(contentEl, { anchorContainer: proseEl });

  const overlappingHighlightIds = useMemo(() => {
    if (!selection || !proseRef.current) return [];
    const offs = selection.offsets ?? offsetsFromRange(proseRef.current, selection.range);
    if (!offs) return [];
    return findOverlappingHighlights(highlights, chapterIndex, offs.startOffset, offs.length);
  }, [selection, highlights, chapterIndex]);

  const dispatchAction = useCallback(
    (action: ToolbarAction, payload?: { color?: HighlightColor; highlightIds?: string[] }) => {
      if (!selection) return;
      const currentSelection = selection;
      onSelectionAction(action, {
        text: currentSelection.text,
        range: currentSelection.range,
        rect: currentSelection.rect,
        offsets: currentSelection.offsets,
        color: payload?.color,
        highlightIds: payload?.highlightIds,
        chapterIndex,
        chapterText: plainText,
      });
      if (action === "highlight" || action === "remove_highlight") clearSelection();
    },
    [selection, onSelectionAction, chapterIndex, plainText, clearSelection]
  );

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "ArrowLeft") goToChapter(chapterIndex - 1);
      if (e.key === "ArrowRight") goToChapter(chapterIndex + 1);
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [chapterIndex, goToChapter]);

  if (book.format === "pdf") {
    if (!position) {
      return (
        <div className="flex flex-col h-full bg-cream items-center justify-center">
          <div className="w-6 h-6 border-2 border-clay-black border-t-transparent rounded-full animate-spin" />
        </div>
      );
    }
    return (
      <PdfViewer
        bookHash={book.hash}
        initialPage={position.chapterIndex + 1}
        initialScrollOffset={position.scrollOffset}
        settings={settings}
        onSettingsChange={onSettingsChange}
        onPositionChange={onPositionChange}
        onSelectionAction={onSelectionAction}
        hasExplain={hasExplain}
        aiAvailable={aiAvailable}
        highlights={highlights}
        onHighlightClick={onHighlightClick}
      />
    );
  }

  const hasPrev = chapterIndex > 0;
  const hasNext = chapterIndex < totalSections - 1;
  const displayLabel = cleanChapterLabel(chapterLabel) || `Chapter ${chapterIndex + 1}`;

  return (
    <div className="flex flex-col h-full bg-cream text-clay-black relative">
      <div
        ref={attachContentRef}
        onScroll={handleScroll}
        className="flex-1 overflow-y-auto"
        style={{ fontSize: `${settings.fontSize}px`, lineHeight: settings.lineHeight, fontFamily: settings.fontFamily }}
      >
        <div className="max-w-2xl mx-auto px-6 pt-12 pb-4">
          <p className="clay-label mb-1">{displayLabel}</p>
          <p className="text-sm text-silver">{readingTime} min read</p>
        </div>

        <div className="max-w-2xl mx-auto px-6 pb-28">
          <div ref={attachProseRef} onClick={handleProseClick} className="prose-reader" dangerouslySetInnerHTML={{ __html: content }} />
        </div>

        {content && (
          <div className="max-w-sm mx-auto px-6 pb-16 text-center">
            <hr className="clay-divider w-16 mx-auto mb-6" />
            <p className="text-xs text-silver mb-4">End of {displayLabel.toLowerCase()}</p>
            {hasNext && (
              <button onClick={() => goToChapter(chapterIndex + 1)} className="clay-btn-solid text-sm">
                Continue reading &rarr;
              </button>
            )}
          </div>
        )}
      </div>

      {hasPrev && (
        <button
          onClick={() => goToChapter(chapterIndex - 1)}
          className="clay-btn-white absolute left-4 top-1/2 -translate-y-1/2 w-10 h-10 !p-0 !rounded-[12px] flex items-center justify-center"
        >
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M11 4L6 9l5 5" />
          </svg>
        </button>
      )}
      {hasNext && (
        <button
          onClick={() => goToChapter(chapterIndex + 1)}
          className="clay-btn-white absolute right-4 top-1/2 -translate-y-1/2 w-10 h-10 !p-0 !rounded-[12px] flex items-center justify-center"
        >
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M7 4l5 5-5 5" />
          </svg>
        </button>
      )}

      <div className="absolute bottom-0 left-0 right-0 flex justify-center pb-5 pointer-events-none">
        <div className="pointer-events-auto">
          {!showNav ? (
            <button
              onClick={() => setShowNav(true)}
              className="clay-btn-white !rounded-[1584px] text-xs !py-2 !px-5"
            >
              {chapterIndex + 1} / {totalSections} &middot; {Math.round(position?.percentage ?? 0)}%
            </button>
          ) : (
            <div
              className="clay-card flex items-center gap-3 px-4 py-2.5 !rounded-[1584px]"
              onMouseLeave={() => setShowNav(false)}
            >
              <button
                onClick={() => goToChapter(chapterIndex - 1)}
                disabled={!hasPrev}
                className="clay-btn-white !p-1.5 !rounded-[8px] disabled:opacity-20"
              >
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M9 3L4 7l5 4" />
                </svg>
              </button>
              <input
                type="range" min={0} max={Math.max(totalSections - 1, 1)} value={chapterIndex}
                onChange={(e) => goToChapter(Number(e.target.value))}
                className="w-44 accent-matcha-600"
              />
              <button
                onClick={() => goToChapter(chapterIndex + 1)}
                disabled={!hasNext}
                className="clay-btn-white !p-1.5 !rounded-[8px] disabled:opacity-20"
              >
                <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M5 3l5 4-5 4" />
                </svg>
              </button>
              <span className="text-xs tabular-nums text-silver min-w-[3rem] text-center">
                {Math.round(position?.percentage ?? 0)}%
              </span>
            </div>
          )}
        </div>
      </div>

      {selection && (
        <SelectionToolbar rect={selection.rect} hasExplain={hasExplain} aiAvailable={aiAvailable} overlappingHighlightIds={overlappingHighlightIds} onAction={dispatchAction} />
      )}
    </div>
  );
}

export default React.memo(Reader);
