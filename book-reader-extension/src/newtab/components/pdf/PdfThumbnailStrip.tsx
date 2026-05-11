import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { usePdfThumbnails, type PdfDocumentProxyLike } from "./usePdfThumbnails";

interface PdfThumbnailStripProps {
  pdfDoc: PdfDocumentProxyLike;
  currentPage: number;
  totalPages: number;
  onJumpToPage: (page: number) => void;
  /** Set of bookmarked spineIndices (== pageNumber - 1). Optional — strip works without it. */
  bookmarkedPages?: ReadonlySet<number>;
}

// Thumbnail layout constants — derived from spec §7.2 (~120px tall strip, ~120x160 thumbs).
const THUMBNAIL_WIDTH_PX = 96;
const THUMBNAIL_HEIGHT_PX = 128;
const ACTIVE_THUMBNAIL_SCALE = 1.15;
// Strip taller than the un-zoomed thumbnail so dock-style cursor zoom has
// headroom — see DOCK_ZOOM_MAX_BOOST below. The active baseline (1.15) plus
// max boost (0.3) caps peak scale at 1.45, extending the thumbnail upward by
// 0.45 * 128 ≈ 58px; strip height 200 leaves ≈50px above the baseline
// thumbnail which absorbs almost all of that extension.
const STRIP_HEIGHT_PX = 200;
const LOOKAHEAD_PAGES = 4;
// Drag movement under this threshold counts as a click (jump-to-page) instead
// of a scrub. Was 4 — too aggressive with trackpads (jitter on tap fired drag
// and suppressed the click), so we widened it to a more conventional value.
const DRAG_CLICK_THRESHOLD_PX = 8;
// IntersectionObserver lookahead — keep ~2 thumbnails worth of pixels rendered ahead.
const INTERSECTION_OBSERVER_ROOT_MARGIN = "0px 220px";

// Dock-zoom tuning. The lens scales each thumbnail by `baseline + boost`,
// where `boost = MAX_BOOST * exp(-(distance^2) / (2 * SIGMA^2))`. SIGMA is in
// CSS px and controls how many neighbors zoom; MAX_BOOST is the peak boost on
// direct hover. Picked so on hover the centered thumbnail reaches ~1.45 and
// each immediate neighbor sits around ~1.2.
const DOCK_ZOOM_SIGMA_PX = 110;
const DOCK_ZOOM_MAX_BOOST = 0.3;

type ObserveSlotFn = (slot: HTMLDivElement, onVisible: () => void) => () => void;

interface ThumbnailItemProps {
  pageNumber: number;
  isActive: boolean;
  isWithinLookahead: boolean;
  isBookmarked: boolean;
  ensureThumbnailRendered: (pageNumber: number) => Promise<HTMLCanvasElement | null>;
  getCachedThumbnail: (pageNumber: number) => HTMLCanvasElement | null;
  observeSlot: ObserveSlotFn;
  onClickThumbnail: (pageNumber: number) => void;
  /**
   * Register the outer button element with the parent so it can drive the
   * dock-zoom transform via direct DOM. We avoid round-tripping the cursor
   * position through React state — at ~60Hz with N thumbnails the renders
   * would dominate the frame.
   */
  registerButtonElement: (pageNumber: number, element: HTMLButtonElement | null) => void;
}

function attachCanvasToSlot(slot: HTMLDivElement, canvas: HTMLCanvasElement): void {
  if (slot.firstChild === canvas) return;
  while (slot.firstChild) slot.removeChild(slot.firstChild);
  slot.appendChild(canvas);
  canvas.style.width = "100%";
  canvas.style.height = "100%";
  canvas.style.display = "block";
}

function ThumbnailItem({
  pageNumber,
  isActive,
  isWithinLookahead,
  isBookmarked,
  ensureThumbnailRendered,
  getCachedThumbnail,
  observeSlot,
  onClickThumbnail,
  registerButtonElement,
}: ThumbnailItemProps): React.ReactElement {
  const slotRef = useRef<HTMLDivElement | null>(null);
  const buttonRefCallback = useCallback(
    (element: HTMLButtonElement | null) => registerButtonElement(pageNumber, element),
    [pageNumber, registerButtonElement],
  );
  const [renderRequestTick, setRenderRequestTick] = useState<number>(0);

  // Subscribe to visibility — parent's observer bumps renderRequestTick which kicks off render.
  useEffect(() => {
    const slot = slotRef.current;
    if (!slot) return;
    const unobserve = observeSlot(slot, () => {
      setRenderRequestTick((tick) => tick + 1);
    });
    return unobserve;
  }, [observeSlot]);

  // Attach the cached canvas if one already exists. This covers both initial mount
  // (when a sibling lookahead has already populated the cache) and re-renders after
  // pageNumber changes. Does NOT trigger a render on its own — that only happens
  // via the visibility callback or via the strip's lookahead prime.
  useEffect(() => {
    const slot = slotRef.current;
    if (!slot) return;
    const cached = getCachedThumbnail(pageNumber);
    if (cached) attachCanvasToSlot(slot, cached);
  }, [pageNumber, getCachedThumbnail]);

  // Trigger a render when (a) the visibility callback fires (renderRequestTick bumps)
  // or (b) this thumbnail sits within the current page's lookahead window. Re-running
  // ensureThumbnailRendered for an already-cached page is cheap (the hook dedupes).
  useEffect(() => {
    if (renderRequestTick === 0 && !isWithinLookahead) return;
    let cancelled = false;
    void ensureThumbnailRendered(pageNumber).then((canvas) => {
      if (cancelled || !canvas) return;
      const currentSlot = slotRef.current;
      if (!currentSlot) return;
      attachCanvasToSlot(currentSlot, canvas);
    });
    return () => {
      cancelled = true;
    };
  }, [pageNumber, ensureThumbnailRendered, renderRequestTick, isWithinLookahead]);

  const handleClick = useCallback(() => {
    onClickThumbnail(pageNumber);
  }, [onClickThumbnail, pageNumber]);

  // The transform is owned by the parent's dock-zoom logic (applyTransforms),
  // not React, so we only set the baseline layout here. transformOrigin keeps
  // the bottom edge anchored so growth from cursor zoom always extends
  // upward into the strip's headroom, never below the strip's bottom border.
  const wrapperStyle: React.CSSProperties = {
    width: THUMBNAIL_WIDTH_PX,
    height: THUMBNAIL_HEIGHT_PX,
    transformOrigin: "center bottom",
    // Fast linear transition so the cursor-driven transform feels glued to
    // the mouse but still smooths a tiny bit; slow easing here would lag.
    transition: "transform 90ms linear",
    willChange: "transform",
  };

  return (
    <button
      ref={buttonRefCallback}
      type="button"
      onClick={handleClick}
      data-page-number={pageNumber}
      className={`relative flex-none flex flex-col items-center justify-end mx-1 group focus:outline-none ${
        isActive ? "z-10" : ""
      }`}
      style={wrapperStyle}
      aria-label={`Jump to page ${pageNumber}`}
      aria-current={isActive ? "page" : undefined}
    >
      <div
        ref={slotRef}
        data-thumbnail-slot="true"
        className={`relative w-full h-full bg-clay-white rounded-[4px] overflow-hidden border-2 transition-colors ${
          isActive ? "border-matcha-600 ring-2 ring-matcha-600/40" : "border-oat group-hover:border-charcoal"
        }`}
      />
      {isBookmarked && (
        // Positioned outside the slot so attachCanvasToSlot's child-replacement
        // never wipes it out. Sits at the top-right of the thumbnail.
        <span
          aria-hidden
          className="absolute top-0 right-0 text-pomegranate-400 drop-shadow-[0_1px_1px_rgba(0,0,0,0.25)] pointer-events-none"
          style={{ transform: "translate(20%, -20%)" }}
        >
          <ThumbnailBookmarkIcon />
        </span>
      )}
      <span
        className={`mt-1 text-[10px] tabular-nums ${
          isActive ? "text-matcha-600 font-semibold" : "text-silver"
        }`}
      >
        {pageNumber}
      </span>
    </button>
  );
}

function ThumbnailBookmarkIcon(): React.ReactElement {
  return (
    <svg
      width="14"
      height="14"
      viewBox="0 0 14 14"
      fill="currentColor"
      stroke="currentColor"
      strokeWidth="1.2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M3.5 1.5h7v11l-3.5-2.5-3.5 2.5v-11z" />
    </svg>
  );
}

function clampScrollPosition(value: number, max: number): number {
  if (value < 0) return 0;
  if (value > max) return max;
  return value;
}

function scrollStripToCurrentPage(
  stripContainerEl: HTMLDivElement,
  currentPage: number,
  smooth: boolean
): void {
  const target = stripContainerEl.querySelector<HTMLElement>(
    `[data-page-number="${currentPage}"]`
  );
  if (!target) return;
  const containerRect = stripContainerEl.getBoundingClientRect();
  const targetRect = target.getBoundingClientRect();
  const targetCenter = targetRect.left + targetRect.width / 2;
  const containerCenter = containerRect.left + containerRect.width / 2;
  const desiredScrollLeft = stripContainerEl.scrollLeft + (targetCenter - containerCenter);
  const maxScrollLeft = stripContainerEl.scrollWidth - stripContainerEl.clientWidth;
  const clamped = clampScrollPosition(desiredScrollLeft, maxScrollLeft);
  stripContainerEl.scrollTo({ left: clamped, behavior: smooth ? "smooth" : "auto" });
}

export default function PdfThumbnailStrip({
  pdfDoc,
  currentPage,
  totalPages,
  onJumpToPage,
  bookmarkedPages,
}: PdfThumbnailStripProps): React.ReactElement {
  const stripContainerRef = useRef<HTMLDivElement | null>(null);
  const observerRef = useRef<IntersectionObserver | null>(null);
  const visibilityCallbacksByElement = useRef<Map<Element, () => void>>(new Map());
  const dragStateRef = useRef<{
    pointerId: number;
    startX: number;
    startScrollLeft: number;
    moved: boolean;
  } | null>(null);
  // Set true at pointerup if the pointer moved past DRAG_CLICK_THRESHOLD_PX. The click
  // event fires after pointerup, so we use this flag to suppress the jump-to-page action
  // for that one synthetic click. Cleared on the next pointerdown.
  const suppressNextClickRef = useRef<boolean>(false);
  // Each ThumbnailItem registers its outer button here so the strip can drive
  // dock-zoom transforms directly without React re-renders.
  const thumbnailButtonsRef = useRef<Map<number, HTMLButtonElement>>(new Map());
  const currentPageRef = useRef<number>(currentPage);
  currentPageRef.current = currentPage;

  const { ensureThumbnailRendered, getCachedThumbnail, documentGeneration } =
    usePdfThumbnails(pdfDoc);

  const pageNumbers = useMemo(() => {
    const result: number[] = [];
    for (let pageNumber = 1; pageNumber <= totalPages; pageNumber++) {
      result.push(pageNumber);
    }
    return result;
  }, [totalPages]);

  // Set up the IntersectionObserver once. Each ThumbnailItem registers its own
  // callback via observeSlot — when the observer reports an intersection for that
  // slot, we invoke the registered callback. Child effects fire before parent
  // effects in React, so child callbacks may already be registered by the time
  // this runs; we observe each one retroactively.
  useEffect(() => {
    const stripContainerEl = stripContainerRef.current;
    if (!stripContainerEl) return;
    const callbacks = visibilityCallbacksByElement.current;
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          const callback = callbacks.get(entry.target);
          if (callback) callback();
        }
      },
      { root: stripContainerEl, rootMargin: INTERSECTION_OBSERVER_ROOT_MARGIN }
    );
    observerRef.current = observer;
    callbacks.forEach((_callback, element) => observer.observe(element));
    return () => {
      observer.disconnect();
      observerRef.current = null;
    };
  }, []);

  const observeSlot = useCallback<ObserveSlotFn>((slot, onVisible) => {
    const callbacks = visibilityCallbacksByElement.current;
    callbacks.set(slot, onVisible);
    const observer = observerRef.current;
    if (observer) observer.observe(slot);
    return () => {
      callbacks.delete(slot);
      const currentObserver = observerRef.current;
      if (currentObserver) currentObserver.unobserve(slot);
    };
  }, []);

  const registerThumbnailButton = useCallback(
    (pageNumber: number, element: HTMLButtonElement | null) => {
      if (element) {
        thumbnailButtonsRef.current.set(pageNumber, element);
        // Apply baseline scale immediately so newly mounted thumbnails don't
        // pop in at 1.0 then jump to the active scale after the next effect.
        const baseline =
          pageNumber === currentPageRef.current ? ACTIVE_THUMBNAIL_SCALE : 1;
        element.style.transform = `scale(${baseline})`;
      } else {
        thumbnailButtonsRef.current.delete(pageNumber);
      }
    },
    [],
  );

  // Recompute and write every thumbnail's transform. When `cursorClientX` is
  // null we paint the baseline (active page bigger, rest 1×); otherwise we
  // add the Gaussian lens boost so the thumbnail closest to the cursor pops
  // and its neighbors taper off. Runs in a rAF so a burst of mousemove
  // events collapses into one paint per frame.
  const rafIdRef = useRef<number | null>(null);
  const pendingCursorXRef = useRef<number | null | typeof undefined>(undefined);
  const applyTransforms = useCallback((cursorClientX: number | null) => {
    pendingCursorXRef.current = cursorClientX;
    if (rafIdRef.current !== null) return;
    rafIdRef.current = requestAnimationFrame(() => {
      rafIdRef.current = null;
      const nextCursor = pendingCursorXRef.current;
      pendingCursorXRef.current = undefined;
      const buttons = thumbnailButtonsRef.current;
      const activePage = currentPageRef.current;
      buttons.forEach((button, pageNumber) => {
        const baseline = pageNumber === activePage ? ACTIVE_THUMBNAIL_SCALE : 1;
        let scale = baseline;
        if (typeof nextCursor === "number") {
          const rect = button.getBoundingClientRect();
          const center = rect.left + rect.width / 2;
          const distance = nextCursor - center;
          const boost =
            DOCK_ZOOM_MAX_BOOST *
            Math.exp(-(distance * distance) / (2 * DOCK_ZOOM_SIGMA_PX * DOCK_ZOOM_SIGMA_PX));
          scale = baseline + boost;
        }
        button.style.transform = `scale(${scale})`;
      });
    });
  }, []);

  useEffect(() => {
    return () => {
      if (rafIdRef.current !== null) cancelAnimationFrame(rafIdRef.current);
    };
  }, []);

  // Whenever the active page changes externally (toolbar nav, scroll-driven
  // detection), repaint baselines so the previous active thumbnail shrinks
  // back to 1× and the new one pops to ACTIVE_THUMBNAIL_SCALE.
  useEffect(() => {
    applyTransforms(null);
  }, [currentPage, applyTransforms]);

  const handleStripMouseMove = useCallback(
    (event: React.MouseEvent<HTMLDivElement>) => {
      applyTransforms(event.clientX);
    },
    [applyTransforms],
  );

  const handleStripMouseLeave = useCallback(() => {
    applyTransforms(null);
  }, [applyTransforms]);

  // Auto-scroll the strip to keep the current page centered when it changes externally.
  useEffect(() => {
    const stripContainerEl = stripContainerRef.current;
    if (!stripContainerEl) return;
    scrollStripToCurrentPage(stripContainerEl, currentPage, true);
  }, [currentPage]);

  // Mousewheel-horizontal: translate vertical wheel deltas into horizontal scroll.
  useEffect(() => {
    const stripContainerEl = stripContainerRef.current;
    if (!stripContainerEl) return;
    const handleWheel = (event: WheelEvent) => {
      if (event.deltaY === 0) return;
      if (Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return;
      event.preventDefault();
      stripContainerEl.scrollLeft += event.deltaY;
    };
    stripContainerEl.addEventListener("wheel", handleWheel, { passive: false });
    return () => stripContainerEl.removeEventListener("wheel", handleWheel);
  }, []);

  // Drag-scrub: pointer down records start; move updates scrollLeft; up
  // releases. Crucially we DON'T setPointerCapture on pointerdown — capturing
  // the pointer to the strip container redirects the subsequent click event
  // away from the thumbnail button, swallowing the jump-to-page intent. We
  // only escalate to setPointerCapture once movement exceeds the drag
  // threshold, by which point we're committed to a scrub, not a tap.
  const handlePointerDown = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    const stripContainerEl = stripContainerRef.current;
    if (!stripContainerEl) return;
    if (event.button !== 0) return;
    suppressNextClickRef.current = false;
    dragStateRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startScrollLeft: stripContainerEl.scrollLeft,
      moved: false,
    };
  }, []);

  const handlePointerMove = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    const dragState = dragStateRef.current;
    const stripContainerEl = stripContainerRef.current;
    if (!dragState || !stripContainerEl) return;
    if (dragState.pointerId !== event.pointerId) return;
    const deltaX = event.clientX - dragState.startX;
    if (!dragState.moved && Math.abs(deltaX) > DRAG_CLICK_THRESHOLD_PX) {
      dragState.moved = true;
      // Only now claim the pointer so the scrub keeps tracking even if the
      // cursor leaves the strip vertically. Wrapped in try/catch because
      // browsers throw if the pointer is already released (rare).
      try {
        stripContainerEl.setPointerCapture(event.pointerId);
      } catch {
        // setPointerCapture can throw if the pointer was already released or
        // the element was detached; either way, drag-scrub still works while
        // the cursor stays inside the strip.
      }
    }
    if (dragState.moved) {
      const maxScrollLeft = stripContainerEl.scrollWidth - stripContainerEl.clientWidth;
      stripContainerEl.scrollLeft = clampScrollPosition(
        dragState.startScrollLeft - deltaX,
        maxScrollLeft
      );
    }
  }, []);

  const handlePointerUp = useCallback((event: React.PointerEvent<HTMLDivElement>) => {
    const dragState = dragStateRef.current;
    const stripContainerEl = stripContainerRef.current;
    if (!dragState || !stripContainerEl) return;
    if (dragState.pointerId !== event.pointerId) return;
    if (dragState.moved) suppressNextClickRef.current = true;
    if (stripContainerEl.hasPointerCapture(event.pointerId)) {
      stripContainerEl.releasePointerCapture(event.pointerId);
    }
    dragStateRef.current = null;
  }, []);

  const handleClickThumbnail = useCallback(
    (pageNumber: number) => {
      if (suppressNextClickRef.current) {
        suppressNextClickRef.current = false;
        return;
      }
      onJumpToPage(pageNumber);
    },
    [onJumpToPage]
  );

  return (
    <div
      className="flex-none border-t border-oat bg-cream"
      style={{ height: STRIP_HEIGHT_PX }}
      data-pdf-thumbnail-strip="true"
    >
      <div
        ref={stripContainerRef}
        className="relative h-full overflow-x-auto overflow-y-hidden flex items-end px-2 pb-2 pt-3 select-none cursor-grab active:cursor-grabbing"
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerCancel={handlePointerUp}
        onMouseMove={handleStripMouseMove}
        onMouseLeave={handleStripMouseLeave}
        role="listbox"
        aria-label="PDF page thumbnails"
      >
        {pageNumbers.map((pageNumber) => (
          // documentGeneration is part of the key so a pdfDoc swap forces every
          // ThumbnailItem to remount and re-bind against the new document — the
          // stable ensure/getCached callbacks would otherwise leave us with stale
          // (zeroed) canvases from the prior doc.
          <ThumbnailItem
            key={`${documentGeneration}-${pageNumber}`}
            pageNumber={pageNumber}
            isActive={pageNumber === currentPage}
            isWithinLookahead={Math.abs(pageNumber - currentPage) <= LOOKAHEAD_PAGES}
            isBookmarked={bookmarkedPages?.has(pageNumber - 1) ?? false}
            ensureThumbnailRendered={ensureThumbnailRendered}
            getCachedThumbnail={getCachedThumbnail}
            observeSlot={observeSlot}
            onClickThumbnail={handleClickThumbnail}
            registerButtonElement={registerThumbnailButton}
          />
        ))}
      </div>
    </div>
  );
}
