import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { LoadedBook } from "../../hooks/useBook";
import type { TocNode } from "../../lib/parsers/epub";
import {
  flattenToc,
  getChapterStatus,
  type ChapterStatus,
} from "../../lib/parsers/toc-progress";
import TocNodeView from "./TocNode";

interface TocPanelProps {
  book: LoadedBook;
  currentChapterIndex: number;
  onJump: (node: TocNode) => void;
  /** Set of bookmarked spineIndices for the current book. */
  bookmarkedIndices?: ReadonlySet<number>;
  /** Toggle bookmark for a given spineIndex. Omit to hide the bookmark control. */
  onToggleBookmark?: (spineIndex: number) => void;
}

const TOC_STATE_KEY_PREFIX = "toc_state_";

function tocStateKeyFor(bookHash: string): string {
  return `${TOC_STATE_KEY_PREFIX}${bookHash}`;
}

async function loadExpandedNodeIds(bookHash: string): Promise<string[] | null> {
  const key = tocStateKeyFor(bookHash);
  const result = await chrome.storage.local.get(key);
  const stored = result[key];
  if (Array.isArray(stored)) return stored.filter((id): id is string => typeof id === "string");
  return null;
}

async function persistExpandedNodeIds(bookHash: string, ids: string[]): Promise<void> {
  await chrome.storage.local.set({ [tocStateKeyFor(bookHash)]: ids });
}

function ancestorIdsFor(nodeId: string): string[] {
  // Tree-path id "0.1.2" → ["0", "0.1"] (parents along the chain).
  const segments = nodeId.split(".");
  const ancestors: string[] = [];
  for (let i = 1; i < segments.length; i++) {
    ancestors.push(segments.slice(0, i).join("."));
  }
  return ancestors;
}

function findCurrentNode(toc: ReadonlyArray<TocNode>, currentChapterIndex: number): TocNode | null {
  const flat = flattenToc(toc as TocNode[]);
  // Prefer the deepest match — more specific TOC entries win over their parents.
  let bestMatch: TocNode | null = null;
  for (const node of flat) {
    if (node.spineIndex === currentChapterIndex) {
      bestMatch = node;
    }
  }
  return bestMatch;
}

function filterTocBySearch(
  toc: ReadonlyArray<TocNode>,
  searchQuery: string,
): { nodes: TocNode[]; matchedIds: Set<string> } {
  const trimmed = searchQuery.trim().toLowerCase();
  if (!trimmed) return { nodes: toc as TocNode[], matchedIds: new Set() };

  const matchedIds = new Set<string>();

  const visit = (nodes: ReadonlyArray<TocNode>): TocNode[] => {
    const kept: TocNode[] = [];
    for (const node of nodes) {
      const childMatches = visit(node.children);
      const labelMatches = node.label.toLowerCase().includes(trimmed);
      if (labelMatches || childMatches.length > 0) {
        kept.push({ ...node, children: childMatches });
        if (labelMatches) {
          matchedIds.add(node.id);
          for (const ancestor of ancestorIdsFor(node.id)) matchedIds.add(ancestor);
        }
      }
    }
    return kept;
  };

  return { nodes: visit(toc), matchedIds };
}

function buildFlatChapterToc(book: LoadedBook): TocNode[] {
  if (book.format === "txt" && book.txt) {
    return book.txt.chunks.map((_, index) => ({
      id: String(index),
      label: `Section ${index + 1}`,
      href: "",
      spineIndex: index,
      fragment: null,
      children: [],
    }));
  }
  if (book.format === "pdf" && book.pdf) {
    // Prefer the PDF's embedded outline (bookmarks). PDFs with no outline
    // fall through to a flat page list so the user still has a way to jump
    // around. Unresolved entries (spineIndex < 0) are kept so the user
    // sees the structure, but TocNode renders them disabled.
    if (book.pdf.outline && book.pdf.outline.length > 0) {
      return book.pdf.outline;
    }
    return Array.from({ length: book.pdf.totalPages }, (_, index) => ({
      id: String(index),
      label: `Page ${index + 1}`,
      href: "",
      spineIndex: index,
      fragment: null,
      children: [],
    }));
  }
  if (book.format === "epub" && book.epub) {
    return book.epub.chapters.map((chapter, index) => ({
      id: String(index),
      label: chapter.label?.trim() || `Chapter ${index + 1}`,
      href: chapter.href,
      spineIndex: index,
      fragment: null,
      children: [],
    }));
  }
  return [];
}

export default function TocPanel({
  book,
  currentChapterIndex,
  onJump,
  bookmarkedIndices,
  onToggleBookmark,
}: TocPanelProps) {
  const [searchQuery, setSearchQuery] = useState("");
  const [expandedNodeIds, setExpandedNodeIds] = useState<Set<string>>(new Set());
  const [hydrated, setHydrated] = useState(false);
  const nodeElementsRef = useRef<Map<string, HTMLElement>>(new Map());
  const containerRef = useRef<HTMLDivElement>(null);

  const tocSource: TocNode[] = useMemo(() => {
    if (book.format === "epub" && book.epub && book.epub.toc.length > 0) {
      return book.epub.toc;
    }
    return buildFlatChapterToc(book);
  }, [book]);

  const { nodes: visibleToc, matchedIds } = useMemo(
    () => filterTocBySearch(tocSource, searchQuery),
    [tocSource, searchQuery],
  );

  const currentNode = useMemo(
    () => findCurrentNode(tocSource, currentChapterIndex),
    [tocSource, currentChapterIndex],
  );

  // Initial load of expanded ids: persisted state, plus expand path to current.
  useEffect(() => {
    let cancelled = false;
    loadExpandedNodeIds(book.hash).then((stored) => {
      if (cancelled) return;
      const initial = new Set<string>(stored ?? []);
      if (currentNode) {
        for (const ancestorId of ancestorIdsFor(currentNode.id)) initial.add(ancestorId);
      }
      setExpandedNodeIds(initial);
      setHydrated(true);
    });
    return () => {
      cancelled = true;
    };
  }, [book.hash, currentNode]);

  // Search auto-expands every ancestor of a match.
  useEffect(() => {
    if (matchedIds.size === 0) return;
    setExpandedNodeIds((prev) => {
      const next = new Set(prev);
      for (const id of matchedIds) next.add(id);
      return next;
    });
  }, [matchedIds]);

  // Persist after hydration so we don't stomp the stored set with empty initial.
  useEffect(() => {
    if (!hydrated) return;
    void persistExpandedNodeIds(book.hash, Array.from(expandedNodeIds));
  }, [hydrated, book.hash, expandedNodeIds]);

  // Scroll-spy: keep the active node in view when it changes.
  useEffect(() => {
    if (!currentNode) return;
    const element = nodeElementsRef.current.get(currentNode.id);
    if (!element || !containerRef.current) return;
    const containerRect = containerRef.current.getBoundingClientRect();
    const elementRect = element.getBoundingClientRect();
    const isInView =
      elementRect.top >= containerRect.top && elementRect.bottom <= containerRect.bottom;
    if (!isInView) {
      element.scrollIntoView({ block: "center", behavior: "smooth" });
    }
  }, [currentNode]);

  const toggleExpand = useCallback((nodeId: string) => {
    setExpandedNodeIds((prev) => {
      const next = new Set(prev);
      if (next.has(nodeId)) next.delete(nodeId);
      else next.add(nodeId);
      return next;
    });
  }, []);

  const isNodeExpanded = useCallback(
    (nodeId: string): boolean => expandedNodeIds.has(nodeId),
    [expandedNodeIds],
  );

  const resolveStatus = useCallback(
    (node: TocNode): ChapterStatus => getChapterStatus(node.spineIndex, currentChapterIndex),
    [currentChapterIndex],
  );

  const isNodeCurrent = useCallback(
    (node: TocNode): boolean => currentNode?.id === node.id,
    [currentNode],
  );

  const isNodeBookmarked = useCallback(
    (node: TocNode): boolean =>
      node.spineIndex >= 0 && (bookmarkedIndices?.has(node.spineIndex) ?? false),
    [bookmarkedIndices],
  );

  const handleToggleNodeBookmark = useCallback(
    (node: TocNode) => {
      if (!onToggleBookmark) return;
      if (node.spineIndex < 0) return;
      onToggleBookmark(node.spineIndex);
    },
    [onToggleBookmark],
  );

  const registerNodeElement = useCallback((nodeId: string, element: HTMLElement | null) => {
    if (element) nodeElementsRef.current.set(nodeId, element);
    else nodeElementsRef.current.delete(nodeId);
  }, []);

  return (
    <div className="flex flex-col h-full">
      <div className="px-3 py-2 border-b border-oat">
        <input
          type="search"
          value={searchQuery}
          onChange={(event) => setSearchQuery(event.target.value)}
          placeholder="Search chapters"
          aria-label="Search chapters"
          className="w-full px-3 py-1.5 text-xs rounded-[8px] border border-oat bg-clay-white text-clay-black placeholder:text-silver focus:outline-2 focus:outline-matcha-600"
        />
      </div>
      <div ref={containerRef} className="flex-1 overflow-y-auto px-2 py-2">
        {visibleToc.length === 0 ? (
          <p className="text-xs text-silver text-center py-12">
            {searchQuery ? "No chapters match." : "No table of contents available."}
          </p>
        ) : (
          <ul>
            {visibleToc.map((node) => (
              <TocNodeView
                key={node.id}
                node={node}
                depth={0}
                isExpanded={isNodeExpanded(node.id)}
                status={resolveStatus(node)}
                isCurrent={isNodeCurrent(node)}
                toggleExpand={toggleExpand}
                onJump={onJump}
                resolveStatus={resolveStatus}
                isNodeExpanded={isNodeExpanded}
                registerNodeElement={registerNodeElement}
                isNodeCurrent={isNodeCurrent}
                isBookmarked={isNodeBookmarked}
                onToggleBookmark={onToggleBookmark ? handleToggleNodeBookmark : undefined}
              />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
