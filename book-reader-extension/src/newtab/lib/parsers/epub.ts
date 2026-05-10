import ePub, { Book, NavItem, Rendition } from "epubjs";
import {
  parseTocFromNavXhtml,
  parseTocFromNcx,
} from "./epub-toc-fallback";
import {
  cleanTocLabel,
  isTocGoodEnough,
  tocQualityScore,
} from "./toc-quality";

export interface EpubChapter {
  href: string;
  label: string;
  content: string;
}

/**
 * Single TOC entry. Tree is built via `children`.
 *
 * `id` is the recursive index path (e.g. "0", "0.1", "0.1.2") so it's
 * guaranteed unique even when multiple TOC nodes point to the same href.
 *
 * `spineIndex` is the index in `ParsedEpub.chapters[]` (the flat spine the
 * reader scrolls through) when the href can be resolved; `-1` otherwise.
 *
 * `fragment` is the URL-decoded anchor id without a leading "#"; `null`
 * when the href contains no fragment.
 */
export interface TocNode {
  id: string;
  label: string;
  href: string;
  spineIndex: number;
  fragment: string | null;
  children: TocNode[];
}

/**
 * Result of resolving an in-chapter `<a href>` against the spine. `spineIndex`
 * is `-1` when the link points outside the spine (a stylesheet, an unknown
 * resource, etc.) so the caller can fall back to no-op or external-open
 * behavior.
 */
export interface ResolvedSpineLink {
  spineIndex: number;
  fragment: string | null;
}

export interface ParsedEpub {
  title: string;
  author: string;
  chapters: EpubChapter[];
  toc: TocNode[];
  book: Book;
  /**
   * Resolves an `<a href>` value found inside a chapter to a spine index +
   * optional fragment. `fromHref` is the chapter href that contained the
   * link (the `chapters[i].href` for the active chapter). Returns `null`
   * when the link is absolute (http/https/mailto/blob/...) so the caller
   * can decide whether to open it externally.
   */
  resolveLink: (fromHref: string, linkHref: string) => ResolvedSpineLink | null;
  /**
   * Releases blob URLs created for inlined chapter images and tears down
   * epubjs's internal archive bookkeeping. Call when the book is unloaded
   * to avoid leaking resources across book switches.
   */
  dispose: () => void;
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

export async function parseEpub(arrayBuffer: ArrayBuffer): Promise<ParsedEpub> {
  const book = ePub(arrayBuffer);
  await book.ready;

  const metadata = await book.loaded.metadata;
  const navigation = await book.loaded.navigation;
  const spineItems = readSpineItems(book);

  // Rewrite every manifest item (images, css, fonts) to a blob: URL so the
  // serialized chapter HTML can render them without a same-origin fetch.
  // Without this step, `<img src="../images/foo.jpg">` injected into the
  // newtab page resolves against `chrome-extension://.../newtab.html` and
  // 404s, leaving every figure broken.
  await runResourceReplacements(book);

  const chapters = await loadAllChapters(book, spineItems, navigation.toc);

  const spineHrefMap = buildSpineHrefMap(spineItems);
  const primaryToc = buildPrimaryToc(
    navigation.toc,
    spineHrefMap,
    chapters,
  );
  const fallbackToc = await buildFallbackToc(book, spineItems, chapters);
  const finalToc = pickWinningToc(primaryToc, fallbackToc);

  const dispose = (): void => {
    try {
      book.destroy();
    } catch {
      // epubjs occasionally throws when destroying a partially-initialized
      // book; the URLs are revoked by destroy() best-effort and that's the
      // important part.
    }
  };

  const resolveLink = (fromHref: string, linkHref: string): ResolvedSpineLink | null =>
    resolveInChapterLink(spineHrefMap, fromHref, linkHref);

  return {
    title: metadata.title || "Untitled",
    author: metadata.creator || "Unknown Author",
    chapters,
    toc: finalToc,
    book,
    resolveLink,
    dispose,
  };
}

interface SubstituteFn {
  (content: string, url?: string): string;
}

interface ResourcesLike {
  replacements?: () => Promise<unknown>;
  substitute?: SubstituteFn;
}

function getResources(book: Book): ResourcesLike | null {
  const resources = (book as unknown as { resources?: ResourcesLike }).resources;
  return resources ?? null;
}

async function runResourceReplacements(book: Book): Promise<void> {
  const resources = getResources(book);
  if (!resources || typeof resources.replacements !== "function") return;
  try {
    await resources.replacements();
  } catch {
    // Best-effort. A partial replacement is still applied; broken images
    // are preferable to a fully non-rendering chapter.
  }
}

export function createRendition(book: Book, element: HTMLElement): Rendition {
  return book.renderTo(element, {
    width: "100%",
    height: "100%",
    spread: "none",
  });
}

// ---------------------------------------------------------------------------
// Spine + chapter loading
// ---------------------------------------------------------------------------

interface SpineItemRef {
  href: string;
  /**
   * Resolved URL produced by epubjs's spine resolver (e.g. `/OEBPS/Text/cover.xhtml`).
   * `Resources.substitute` uses this as the anchor for `relativeTo()`, so
   * passing the raw manifest `href` here would produce mismatched relative
   * paths and silently leave images broken.
   */
  url?: string;
}

/**
 * `book.spine` isn't precisely typed by epubjs; cast at this single boundary
 * and pull only the fields we actually consume.
 */
function readSpineItems(book: Book): SpineItemRef[] {
  const spine = (book as unknown as { spine: { items: Array<{ href?: string; url?: string }> } })
    .spine;
  return spine.items
    .filter((item): item is { href: string; url?: string } => typeof item.href === "string" && item.href.length > 0)
    .map((item) => ({ href: item.href, url: typeof item.url === "string" ? item.url : undefined }));
}

async function loadAllChapters(
  book: Book,
  spineItems: SpineItemRef[],
  navigationToc: NavItem[],
): Promise<EpubChapter[]> {
  const labelByHref = buildNavLabelMap(navigationToc);
  const chapters: EpubChapter[] = [];
  const resources = getResources(book);
  const substitute: SubstituteFn | null =
    resources && typeof resources.substitute === "function" ? resources.substitute.bind(resources) : null;

  for (const item of spineItems) {
    try {
      const doc = await book.load(item.href);
      if (!doc) continue;
      const rawHtml = new XMLSerializer().serializeToString(doc as Node);
      const html = applyResourceSubstitution(substitute, rawHtml, item);
      chapters.push({
        href: item.href,
        label: labelByHref.get(item.href) || item.href,
        content: html,
      });
    } catch {
      // Skip chapters that fail to load — keep going so the rest of the
      // spine still renders.
    }
  }

  return chapters;
}

/**
 * `resources.substitute(content, url)` does a regex replace of every
 * manifest URL (relative to `url`) with its blob: replacement. The "url" we
 * feed it has to match what `Resources.relativeTo` produces internally, or
 * the relative paths won't line up with the literal strings in the chapter.
 *
 * Empirically, the resolved spine `url` is the right anchor — the same one
 * epubjs's own serialize hook passes when rendering through `book.replacements()`.
 * We try the resolved url first, then fall back to the raw href, then to no
 * anchor (which uses the absolute manifest URLs as-is). Whichever pass mutates
 * the html wins; subsequent passes are cheap no-ops because the relative
 * paths no longer appear.
 */
function applyResourceSubstitution(
  substitute: SubstituteFn | null,
  rawHtml: string,
  item: SpineItemRef,
): string {
  if (!substitute) return rawHtml;
  let html = rawHtml;
  if (item.url) html = substitute(html, item.url);
  if (item.href && item.href !== item.url) html = substitute(html, item.href);
  html = substitute(html);
  return html;
}

function buildNavLabelMap(navigationToc: NavItem[]): Map<string, string> {
  const labelByHref = new Map<string, string>();
  const walk = (items: NavItem[]): void => {
    for (const item of items) {
      if (item.href && item.label) labelByHref.set(item.href, item.label);
      const subitems = item.subitems ?? [];
      if (subitems.length > 0) walk(subitems);
    }
  };
  walk(navigationToc);
  return labelByHref;
}

// ---------------------------------------------------------------------------
// Spine href map shared between primary + fallback resolution
// ---------------------------------------------------------------------------

function buildSpineHrefMap(spineItems: SpineItemRef[]): Map<string, number> {
  const map = new Map<string, number>();
  spineItems.forEach((item, index) => {
    for (const variant of hrefVariants(item.href)) {
      if (!map.has(variant)) map.set(variant, index);
    }
  });
  return map;
}

function hrefVariants(href: string): string[] {
  const variants = new Set<string>();
  variants.add(href);
  const noLeadingDot = href.replace(/^\.\//, "");
  variants.add(noLeadingDot);
  const lastSlash = noLeadingDot.lastIndexOf("/");
  if (lastSlash >= 0) variants.add(noLeadingDot.slice(lastSlash + 1));
  return Array.from(variants);
}

/**
 * Resolve an `<a href>` value found inside a chapter to a spine index +
 * fragment. Returns `null` when the link is absolute (http/mailto/blob) so
 * the caller can decide whether to open it externally.
 *
 * `fromHref` is the chapter href containing the link; the link's relative
 * path is rebased against it so `<a href="../ch2.xhtml#sec">` from
 * `OEBPS/Text/ch1.xhtml` correctly maps to spine `OEBPS/ch2.xhtml`.
 */
function resolveInChapterLink(
  spineHrefMap: Map<string, number>,
  fromHref: string,
  linkHref: string,
): ResolvedSpineLink | null {
  if (!linkHref) return null;
  if (/^[a-z][a-z0-9+.-]*:/i.test(linkHref)) return null; // http:, mailto:, blob:, data:, ...
  if (linkHref.startsWith("#")) {
    const fragment = decodeFragment(linkHref.slice(1));
    return { spineIndex: -1, fragment };
  }
  const { pathPart, fragment } = splitHrefAndFragment(linkHref);
  const resolvedPath = rebasePath(fromHref, pathPart);
  if (!resolvedPath) return { spineIndex: -1, fragment };
  const spineIndex = resolveSpineIndex(resolvedPath, spineHrefMap);
  return { spineIndex, fragment };
}

function rebasePath(fromHref: string, relativePath: string): string {
  if (!relativePath) return "";
  if (relativePath.startsWith("/")) return relativePath.replace(/^\/+/, "");
  // Use a synthetic origin so the URL parser does standard relative-path
  // resolution. The origin is discarded; we only keep the pathname.
  try {
    const synthetic = new URL(relativePath, `https://x.invalid/${fromHref}`);
    return synthetic.pathname.replace(/^\/+/, "");
  } catch {
    return relativePath;
  }
}

function decodeFragment(rawFragment: string): string | null {
  if (!rawFragment) return null;
  try {
    return decodeURIComponent(rawFragment);
  } catch {
    return rawFragment;
  }
}

function resolveSpineIndex(
  rawPath: string,
  spineHrefMap: Map<string, number>,
): number {
  if (!rawPath) return -1;
  for (const candidate of hrefVariants(rawPath)) {
    const index = spineHrefMap.get(candidate);
    if (index !== undefined) return index;
  }
  return -1;
}

interface HrefParts {
  pathPart: string;
  fragment: string | null;
}

function splitHrefAndFragment(rawHref: string): HrefParts {
  if (!rawHref) return { pathPart: "", fragment: null };
  const hashIndex = rawHref.indexOf("#");
  if (hashIndex < 0) return { pathPart: rawHref, fragment: null };
  const pathPart = rawHref.slice(0, hashIndex);
  const rawFragment = rawHref.slice(hashIndex + 1);
  if (!rawFragment) return { pathPart, fragment: null };
  let urlDecodedFragment: string;
  try {
    urlDecodedFragment = decodeURIComponent(rawFragment);
  } catch {
    urlDecodedFragment = rawFragment;
  }
  return { pathPart, fragment: urlDecodedFragment };
}

// ---------------------------------------------------------------------------
// Primary walker — recursive descent over book.loaded.navigation.toc
// ---------------------------------------------------------------------------

function buildPrimaryToc(
  navigationToc: NavItem[],
  spineHrefMap: Map<string, number>,
  chapters: EpubChapter[],
): TocNode[] {
  return navigationToc.map((navItem, index) =>
    buildPrimaryNode(navItem, String(index), spineHrefMap, chapters),
  );
}

function buildPrimaryNode(
  navItem: NavItem,
  nodeId: string,
  spineHrefMap: Map<string, number>,
  chapters: EpubChapter[],
): TocNode {
  const rawHref = navItem.href ?? "";
  const { pathPart, fragment } = splitHrefAndFragment(rawHref);
  const spineIndex = resolveSpineIndex(pathPart, spineHrefMap);
  const label = resolveDisplayLabel(navItem.label ?? "", nodeId, spineIndex, chapters);

  const subitems = navItem.subitems ?? [];
  const children = subitems.map((child, childIndex) =>
    buildPrimaryNode(
      child,
      childTreePathId(nodeId, childIndex),
      spineHrefMap,
      chapters,
    ),
  );

  return {
    id: nodeId,
    label,
    href: rawHref,
    spineIndex,
    fragment,
    children,
  };
}

function childTreePathId(parentId: string, childIndex: number): string {
  return parentId === "" ? String(childIndex) : `${parentId}.${childIndex}`;
}

/**
 * Pick the best display label for a TOC node. Tries (in order):
 *   1. the cleaned raw label
 *   2. the first <h1>/<h2> text in the chapter HTML
 *   3. `Chapter <N>` (or `Section <id>` when the spine index is unresolved)
 */
function resolveDisplayLabel(
  rawLabel: string,
  nodeId: string,
  spineIndex: number,
  chapters: EpubChapter[],
): string {
  const cleaned = cleanTocLabel(rawLabel);
  if (cleaned) return cleaned;

  const headingLabel = extractFirstHeading(chapters, spineIndex);
  if (headingLabel) return headingLabel;

  if (spineIndex >= 0) return `Chapter ${spineIndex + 1}`;
  return `Section ${nodeId}`;
}

function extractFirstHeading(
  chapters: EpubChapter[],
  spineIndex: number,
): string | null {
  if (spineIndex < 0 || spineIndex >= chapters.length) return null;
  const html = chapters[spineIndex].content;
  if (!html) return null;
  let chapterDocument: Document;
  try {
    chapterDocument = new DOMParser().parseFromString(html, "text/html");
  } catch {
    return null;
  }
  const heading = chapterDocument.querySelector("h1, h2");
  const text = heading?.textContent?.replace(/\s+/g, " ").trim() ?? "";
  if (!text) return null;
  // Run the same cleaning so we don't accept "FOOBARFOOBARFOOBAR..." as a
  // good heading. Returns "" when the heading itself is junk.
  return cleanTocLabel(text) || null;
}

// ---------------------------------------------------------------------------
// Fallback parser — direct nav.xhtml / toc.ncx via book.archive
// ---------------------------------------------------------------------------

interface PackagingPaths {
  navPath?: string;
  ncxPath?: string;
}

function readPackagingPaths(book: Book): PackagingPaths {
  // epubjs's Packaging type isn't exported in a way that lets us narrow
  // here; cast at the boundary.
  const packaging = (book as unknown as { packaging?: PackagingPaths })
    .packaging;
  if (!packaging) return {};
  return {
    navPath: typeof packaging.navPath === "string" && packaging.navPath ? packaging.navPath : undefined,
    ncxPath: typeof packaging.ncxPath === "string" && packaging.ncxPath ? packaging.ncxPath : undefined,
  };
}

interface ArchiveSurface {
  getText(path: string): Promise<string>;
}

function readArchiveSurface(book: Book): ArchiveSurface | null {
  const archive = (book as unknown as { archive?: ArchiveSurface }).archive;
  if (!archive || typeof archive.getText !== "function") return null;
  return archive;
}

async function buildFallbackToc(
  book: Book,
  spineItems: SpineItemRef[],
  chapters: EpubChapter[],
): Promise<TocNode[] | null> {
  const { navPath, ncxPath } = readPackagingPaths(book);
  if (!navPath && !ncxPath) return null;

  const archive = readArchiveSurface(book);
  if (!archive) return null;

  const spineHrefs = spineItems.map((item) => item.href);

  if (navPath) {
    const fallback = await tryFallbackNav(archive, navPath, spineHrefs);
    if (fallback) return refineLabels(fallback, chapters);
  }
  if (ncxPath) {
    const fallback = await tryFallbackNcx(archive, ncxPath, spineHrefs);
    if (fallback) return refineLabels(fallback, chapters);
  }
  return null;
}

async function tryFallbackNav(
  archive: ArchiveSurface,
  navPath: string,
  spineHrefs: string[],
): Promise<TocNode[] | null> {
  try {
    const navXhtml = await archive.getText(navPath);
    return parseTocFromNavXhtml(navXhtml, spineHrefs);
  } catch {
    return null;
  }
}

async function tryFallbackNcx(
  archive: ArchiveSurface,
  ncxPath: string,
  spineHrefs: string[],
): Promise<TocNode[] | null> {
  try {
    const ncxXml = await archive.getText(ncxPath);
    return parseTocFromNcx(ncxXml, spineHrefs);
  } catch {
    return null;
  }
}

/**
 * The fallback parser does its own first-pass cleaning, but it doesn't have
 * access to chapter HTML for the heading-extraction fallback. Re-run label
 * resolution here so both paths produce equally good labels.
 */
function refineLabels(
  toc: TocNode[],
  chapters: EpubChapter[],
): TocNode[] {
  return toc.map((node) => refineNodeLabel(node, chapters));
}

// Patterns matching ONLY the auto-defaults emitted by `buildResolvedNode`
// in epub-toc-fallback.ts (`Chapter <N>` and `Section <treepath>`). Real
// labels like "Section Five: Conclusions" must NOT match.
const AUTO_DEFAULT_CHAPTER_LABEL = /^Chapter\s+\d+$/;
const AUTO_DEFAULT_SECTION_LABEL = /^Section\s+\d+(?:\.\d+)*$/;

function refineNodeLabel(
  node: TocNode,
  chapters: EpubChapter[],
): TocNode {
  // The fallback parser substitutes `Chapter N` / `Section <id>` defaults;
  // try to lift to a chapter heading where one exists.
  const isDefaultChapterLabel = AUTO_DEFAULT_CHAPTER_LABEL.test(node.label);
  const isDefaultSectionLabel = AUTO_DEFAULT_SECTION_LABEL.test(node.label);
  if (isDefaultChapterLabel || isDefaultSectionLabel) {
    const heading = extractFirstHeading(chapters, node.spineIndex);
    if (heading) {
      return {
        ...node,
        label: heading,
        children: node.children.map((child) =>
          refineNodeLabel(child, chapters),
        ),
      };
    }
  }
  return {
    ...node,
    children: node.children.map((child) =>
      refineNodeLabel(child, chapters),
    ),
  };
}

// ---------------------------------------------------------------------------
// Picker — choose between primary + fallback per spec §2.3
// ---------------------------------------------------------------------------

function pickWinningToc(
  primaryToc: TocNode[],
  fallbackToc: TocNode[] | null,
): TocNode[] {
  if (fallbackToc === null) return primaryToc;

  const primaryGoodEnough = isTocGoodEnough(primaryToc);
  const fallbackGoodEnough = isTocGoodEnough(fallbackToc);

  if (primaryGoodEnough && !fallbackGoodEnough) return primaryToc;
  if (!primaryGoodEnough && fallbackGoodEnough) return fallbackToc;
  if (primaryGoodEnough && fallbackGoodEnough) return fallbackToc;

  // Neither passes the bar: prefer higher score; tie → primary.
  const primaryScore = tocQualityScore(primaryToc);
  const fallbackScore = tocQualityScore(fallbackToc);
  return fallbackScore > primaryScore ? fallbackToc : primaryToc;
}
