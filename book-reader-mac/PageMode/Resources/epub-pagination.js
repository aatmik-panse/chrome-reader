/**
 * Page-mode pagination harness, injected by PageModeEPUBView into the
 * WKWebView that hosts the existing extension reader. The extension reader
 * renders the entire flattened spine into `.prose-reader`; we add a
 * single-screen scrolling paginator on top.
 *
 * Exposed API (window.__pageMode):
 *   measure()           → { scrollHeight, viewportHeight, currentTop }
 *   advance(direction)  → scrolls one viewport height, returns new state
 *   scrollTo(top)       → absolute scroll
 */
(function () {
  const reader = () => document.querySelector('.prose-reader') || document.scrollingElement;

  function measure() {
    const el = reader();
    const viewport = window.innerHeight;
    return {
      scrollHeight: el.scrollHeight,
      viewportHeight: viewport,
      currentTop: el.scrollTop || window.scrollY || 0
    };
  }

  function advance(direction) {
    const el = reader();
    const viewport = window.innerHeight;
    const current = el.scrollTop || window.scrollY || 0;
    const max = Math.max(0, el.scrollHeight - viewport);
    const delta = direction === 'previous' ? -viewport : viewport;
    const next = Math.max(0, Math.min(max, current + delta));
    if (el === document.scrollingElement) {
      window.scrollTo({ top: next, behavior: 'auto' });
    } else {
      el.scrollTop = next;
    }
    return measure();
  }

  function scrollTo(top) {
    const el = reader();
    if (el === document.scrollingElement) {
      window.scrollTo({ top, behavior: 'auto' });
    } else {
      el.scrollTop = top;
    }
    return measure();
  }

  window.__pageMode = { measure, advance, scrollTo };
})();
