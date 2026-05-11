import React, { useState, useCallback, useEffect, useRef, useMemo } from "react";
import { usePdfDocument } from "./usePdfDocument";
import PdfToolbar from "./PdfToolbar";
import PdfThumbnailStrip from "./PdfThumbnailStrip";
import PdfSingleView from "./PdfSingleView";
import PdfContinuousView from "./PdfContinuousView";
import PdfSpreadView from "./PdfSpreadView";
import { ReaderSettings } from "../../lib/storage";
import { useSelection, type SelectionOffsets } from "../../hooks/useSelection";
import SelectionToolbar, { ToolbarAction, HighlightColor } from "../SelectionToolbar";
import { findOverlappingHighlights, offsetsFromRange } from "../../lib/highlights/anchor";
import { useActiveThemePdfTint } from "../../hooks/useActiveThemePdfTint";

export type PdfViewMode = "single" | "continuous" | "spread";
export type PdfColorMode = "normal" | "dark" | "sepia";

interface PdfViewerProps {
  bookHash: string;
  initialPage: number;
  initialScrollOffset: number;
  settings: ReaderSettings;
  onSettingsChange: (next: ReaderSettings) => void;
  onPositionChange: (chapterIndex: number, scrollOffset: number, percentage: number) => void;
  onSelectionAction?: (
    action: ToolbarAction,
    payload: { text: string; range: Range; rect: DOMRect; offsets?: SelectionOffsets; color?: HighlightColor; highlightIds?: string[]; chapterIndex: number; chapterText: string }
  ) => void;
  hasExplain?: boolean;
  aiAvailable?: boolean;
  highlights?: import("../../lib/highlights/types").Highlight[];
  onHighlightClick?: (id: string, rect: DOMRect) => void;
  /** Set of bookmarked spineIndices (== pageNumber - 1) for the current book. */
  bookmarkedPages?: ReadonlySet<number>;
  /** Toggle the bookmark for the given spineIndex (pageNumber - 1). */
  onToggleBookmark?: (spineIndex: number) => void;
}

const ZOOM_MIN = 0.25;
const ZOOM_MAX = 3;
const ZOOM_STEP = 0.05;

export default function PdfViewer({ bookHash, initialPage, initialScrollOffset, settings, onSettingsChange, onPositionChange, onSelectionAction, hasExplain = false, aiAvailable = false, highlights = [], onHighlightClick, bookmarkedPages, onToggleBookmark }: PdfViewerProps) {
  const { pdfDoc, totalPages, loading, error } = usePdfDocument(bookHash);

  const startPage = Math.max(1, initialPage);
  const [currentPage, setCurrentPage] = useState(startPage);
  const [zoom, setZoom] = useState(1);

  // View mode and thumbnail visibility are derived directly from the settings prop.
  // Persisted state lives in App; this component never mutates settings without going
  // through onSettingsChange, so the prop is always the single source of truth.
  const viewMode: PdfViewMode = settings.pdfViewMode ?? "continuous";
  const showThumbnailStrip: boolean = settings.pdfShowThumbnailStrip ?? false;

  // PDF tint resolution per spec §1.6:
  //   effectiveTint = settings.pdfTintOverride ?? activeTheme.pdfTint
  // The active theme's pdfTint is exposed via the `--pdf-tint` CSS var (set by applyTheme);
  // useActiveThemePdfTint reads it and re-reads when the html element's data-theme/style/class changes.
  const activeThemePdfTint = useActiveThemePdfTint();
  const colorMode: PdfColorMode = settings.pdfTintOverride ?? activeThemePdfTint;

  const containerRef = useRef<HTMLDivElement>(null);
  const [containerEl, setContainerEl] = useState<HTMLDivElement | null>(null);
  const attachContainerRef = useCallback((el: HTMLDivElement | null) => {
    containerRef.current = el;
    setContainerEl(el);
  }, []);
  const currentPageRef = useRef(startPage);
  const currentScrollRatioRef = useRef(initialScrollOffset);
  const settingsRef = useRef(settings);
  settingsRef.current = settings;

  const savePage = useCallback(
    (page: number, scrollRatio?: number) => {
      currentPageRef.current = page;
      const ratio = scrollRatio ?? currentScrollRatioRef.current;
      currentScrollRatioRef.current = ratio;
      const pct = totalPages > 0 ? ((page - 1 + ratio) / totalPages) * 100 : 0;
      onPositionChange(page - 1, ratio, pct);
    },
    [totalPages, onPositionChange]
  );

  const goToPage = useCallback(
    (page: number) => {
      const clamped = Math.max(1, Math.min(page, totalPages || 1));
      setCurrentPage(clamped);
      currentPageRef.current = clamped;
      currentScrollRatioRef.current = 0;
      savePage(clamped, 0);
    },
    [totalPages, savePage]
  );

  const handlePageChange = useCallback(
    (page: number, scrollRatio: number = 0) => {
      currentScrollRatioRef.current = scrollRatio;
      if (page !== currentPageRef.current) {
        setCurrentPage(page);
        currentPageRef.current = page;
      }
      savePage(page, scrollRatio);
    },
    [savePage]
  );

  const zoomIn = useCallback(() => setZoom((z) => Math.min(ZOOM_MAX, +(z + ZOOM_STEP).toFixed(2))), []);
  const zoomOut = useCallback(() => setZoom((z) => Math.max(ZOOM_MIN, +(z - ZOOM_STEP).toFixed(2))), []);
  const zoomReset = useCallback(() => setZoom(1), []);

  const handleViewModeChange = useCallback((mode: PdfViewMode) => {
    onSettingsChange({ ...settingsRef.current, pdfViewMode: mode });
  }, [onSettingsChange]);

  const handleColorModeChange = useCallback((mode: PdfColorMode) => {
    // Per spec §1.6 the in-PDF toolbar persists an EXPLICIT override — including "normal".
    // The "Override theme PDF tint" toggle in Settings → PDF tab owns the null state
    // (toggle off → null → use active theme's tint). Collapsing "normal" to null here
    // would mean a user who picks Normal in the toolbar under a Sepia theme can never
    // actually force normal pages.
    onSettingsChange({ ...settingsRef.current, pdfTintOverride: mode });
  }, [onSettingsChange]);

  const handleToggleThumbnailStrip = useCallback(() => {
    const nextValue = !settingsRef.current.pdfShowThumbnailStrip;
    onSettingsChange({ ...settingsRef.current, pdfShowThumbnailStrip: nextValue });
  }, [onSettingsChange]);

  const isCurrentPageBookmarked = bookmarkedPages?.has(currentPage - 1) ?? false;
  const handleToggleBookmarkForCurrentPage = useCallback(() => {
    if (!onToggleBookmark) return;
    onToggleBookmark(currentPageRef.current - 1);
  }, [onToggleBookmark]);

  // PDF.js renders text on a canvas with an absolutely-positioned text layer
  // of `color: transparent` spans on top. CSS Custom Highlight forces those
  // spans visible inside the highlighted range and ghosts over the canvas
  // glyphs. Disable the visual swap and rely on native ::selection, which
  // matches how the canvas renders the text underneath.
  const { selection, clearSelection } = useSelection(containerEl, { persistentVisual: "none" });

  const overlappingHighlightIds = useMemo(() => {
    if (!selection) return [];
    const node = selection.range.commonAncestorContainer;
    const startNode = node.nodeType === Node.ELEMENT_NODE ? (node as Element) : node.parentElement;
    if (!startNode) return [];
    const pageWrapper = startNode.closest("[data-page]") as HTMLElement | null;
    if (!pageWrapper) return [];
    const textLayer = pageWrapper.querySelector(".textLayer") as HTMLElement | null;
    if (!textLayer) return [];
    const pageIndex = Number(pageWrapper.getAttribute("data-page")) - 1;
    const offs = offsetsFromRange(textLayer, selection.range);
    if (!offs) return [];
    return findOverlappingHighlights(highlights, pageIndex, offs.startOffset, offs.length);
  }, [selection, highlights]);

  const dispatchAction = useCallback(
    (action: ToolbarAction, payload?: { color?: HighlightColor; highlightIds?: string[] }) => {
      if (!selection || !onSelectionAction) return;
      const currentSelection = selection;
      onSelectionAction(action, {
        text: currentSelection.text,
        range: currentSelection.range,
        rect: currentSelection.rect,
        color: payload?.color,
        highlightIds: payload?.highlightIds,
        chapterIndex: currentPageRef.current - 1,
        chapterText: "",
      });
      if (action === "highlight" || action === "remove_highlight") clearSelection();
    },
    [selection, onSelectionAction, clearSelection]
  );

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement).tagName === "INPUT") return;

      if (viewMode === "single") {
        if (e.key === "ArrowLeft" || e.key === "ArrowUp") { e.preventDefault(); goToPage(currentPageRef.current - 1); }
        if (e.key === "ArrowRight" || e.key === "ArrowDown" || e.key === " ") { e.preventDefault(); goToPage(currentPageRef.current + 1); }
      }

      if ((e.ctrlKey || e.metaKey) && (e.key === "=" || e.key === "+")) { e.preventDefault(); zoomIn(); }
      if ((e.ctrlKey || e.metaKey) && e.key === "-") { e.preventDefault(); zoomOut(); }
      if ((e.ctrlKey || e.metaKey) && e.key === "0") { e.preventDefault(); zoomReset(); }
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [viewMode, goToPage, zoomIn, zoomOut, zoomReset]);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const handler = (e: WheelEvent) => {
      if (e.ctrlKey || e.metaKey) {
        e.preventDefault();
        if (e.deltaY < 0) zoomIn();
        else if (e.deltaY > 0) zoomOut();
      }
    };
    el.addEventListener("wheel", handler, { passive: false });
    return () => el.removeEventListener("wheel", handler);
  }, [zoomIn, zoomOut]);

  useEffect(() => {
    if (pdfDoc && startPage > totalPages && totalPages > 0) {
      setCurrentPage(1);
      currentPageRef.current = 1;
    }
  }, [pdfDoc, totalPages, startPage]);

  // Sync currentPage when initialPage changes from outside (TOC click, thumbnail
  // jump in another book, library switch). Without this the prop only seeds the
  // initial useState and external navigations to a different page are dropped.
  // Guarded by currentPageRef so the scroll → onPositionChange → updated position
  // round-trip doesn't cause a redundant setState/scroll.
  useEffect(() => {
    if (!pdfDoc) return;
    const ceiling = totalPages > 0 ? totalPages : initialPage;
    const target = Math.max(1, Math.min(initialPage, ceiling));
    if (target === currentPageRef.current) return;
    setCurrentPage(target);
    currentPageRef.current = target;
    currentScrollRatioRef.current = 0;
  }, [initialPage, totalPages, pdfDoc]);

  if (loading) {
    return (
      <div className="flex flex-col h-full bg-cream items-center justify-center">
        <div className="w-6 h-6 border-2 border-clay-black border-t-transparent rounded-full animate-spin" />
        <p className="text-xs text-silver mt-3">Loading PDF&hellip;</p>
      </div>
    );
  }

  if (error || !pdfDoc) {
    return (
      <div className="flex flex-col h-full bg-cream items-center justify-center px-6">
        <p className="text-sm text-pomegranate-400 mb-2">{error || "Failed to load PDF"}</p>
        <p className="text-xs text-silver text-center">Try reloading the extension or re-importing the PDF.</p>
      </div>
    );
  }

  const viewProps = {
    pdfDoc,
    totalPages,
    currentPage,
    zoom,
    colorMode,
    onPageChange: handlePageChange,
    initialScrollOffset,
    highlights,
    onHighlightClick,
  };

  return (
    <div ref={attachContainerRef} className="flex flex-col h-full bg-cream">
      <PdfToolbar
        currentPage={currentPage}
        totalPages={totalPages}
        zoom={zoom}
        viewMode={viewMode}
        colorMode={colorMode}
        showThumbnailStrip={showThumbnailStrip}
        showViewMode={settings.pdfShowViewMode ?? true}
        showPageNav={settings.pdfShowPageNav ?? true}
        showColorMode={settings.pdfShowColorMode ?? true}
        showZoom={settings.pdfShowZoom ?? true}
        isCurrentPageBookmarked={isCurrentPageBookmarked}
        onToggleBookmark={onToggleBookmark ? handleToggleBookmarkForCurrentPage : undefined}
        onGoToPage={goToPage}
        onZoomIn={zoomIn}
        onZoomOut={zoomOut}
        onZoomReset={zoomReset}
        onViewModeChange={handleViewModeChange}
        onColorModeChange={handleColorModeChange}
        onToggleThumbnailStrip={handleToggleThumbnailStrip}
        zoomMin={ZOOM_MIN}
        zoomMax={ZOOM_MAX}
      />

      <div className="flex flex-1 overflow-hidden">
        {viewMode === "single" && <PdfSingleView {...viewProps} />}
        {viewMode === "continuous" && <PdfContinuousView {...viewProps} />}
        {viewMode === "spread" && <PdfSpreadView {...viewProps} />}
      </div>

      {showThumbnailStrip && (
        <PdfThumbnailStrip
          pdfDoc={pdfDoc}
          currentPage={currentPage}
          totalPages={totalPages}
          onJumpToPage={goToPage}
          bookmarkedPages={bookmarkedPages}
        />
      )}

      {selection && (
        <SelectionToolbar
          overlappingHighlightIds={overlappingHighlightIds}
          rect={selection.rect}
          hasExplain={hasExplain}
          aiAvailable={aiAvailable}
          isPdf={true}
          onAction={dispatchAction}
        />
      )}
    </div>
  );
}
