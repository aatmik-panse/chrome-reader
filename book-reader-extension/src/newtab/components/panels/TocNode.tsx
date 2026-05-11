import React from "react";
import type { TocNode as TocNodeData } from "../../lib/parsers/epub";
import type { ChapterStatus } from "../../lib/parsers/toc-progress";

interface TocNodeViewProps {
  node: TocNodeData;
  depth: number;
  isExpanded: boolean;
  status: ChapterStatus;
  isCurrent: boolean;
  toggleExpand: (nodeId: string) => void;
  onJump: (node: TocNodeData) => void;
  resolveStatus: (node: TocNodeData) => ChapterStatus;
  isNodeExpanded: (nodeId: string) => boolean;
  registerNodeElement: (nodeId: string, element: HTMLElement | null) => void;
  isNodeCurrent: (node: TocNodeData) => boolean;
  /** True when this node's spineIndex is in the book's bookmark set. */
  isBookmarked: (node: TocNodeData) => boolean;
  /** Toggle bookmark for this node. Omit to hide the bookmark control. */
  onToggleBookmark?: (node: TocNodeData) => void;
}

const INDENT_PER_DEPTH_PX = 12;

/**
 * One row in the TOC tree. Renders its own status dot, label, optional
 * expand chevron, and recurses for children when expanded.
 */
export default function TocNodeView({
  node,
  depth,
  isExpanded,
  status,
  isCurrent,
  toggleExpand,
  onJump,
  resolveStatus,
  isNodeExpanded,
  registerNodeElement,
  isNodeCurrent,
  isBookmarked,
  onToggleBookmark,
}: TocNodeViewProps) {
  const hasChildren = node.children.length > 0;
  const isUnresolved = node.spineIndex < 0;
  const bookmarked = isBookmarked(node);
  return (
    <li>
      <div
        ref={(element) => registerNodeElement(node.id, element)}
        className={`flex items-center gap-1 py-1 pr-1 rounded-[8px] transition-colors group/toc ${
          isCurrent ? "bg-matcha-300/20" : "hover:bg-frost/60"
        }`}
        style={{ paddingLeft: 4 + depth * INDENT_PER_DEPTH_PX }}
      >
        {hasChildren ? (
          <button
            type="button"
            onClick={() => toggleExpand(node.id)}
            aria-label={isExpanded ? "Collapse section" : "Expand section"}
            aria-expanded={isExpanded}
            className="w-4 h-4 flex items-center justify-center text-silver hover:text-clay-black"
          >
            <ChevronIcon expanded={isExpanded} />
          </button>
        ) : (
          <span className="w-4 h-4" aria-hidden />
        )}
        <StatusDot status={status} isCurrent={isCurrent} />
        <button
          type="button"
          disabled={isUnresolved}
          onClick={() => !isUnresolved && onJump(node)}
          title={node.label}
          className={`flex-1 text-left text-xs truncate py-0.5 ${
            isUnresolved
              ? "text-silver/60 cursor-not-allowed"
              : isCurrent
                ? "text-clay-black font-medium"
                : "text-charcoal hover:text-clay-black"
          }`}
        >
          {node.label}
        </button>
        {onToggleBookmark && !isUnresolved && (
          <button
            type="button"
            onClick={(event) => {
              event.stopPropagation();
              onToggleBookmark(node);
            }}
            aria-pressed={bookmarked}
            aria-label={bookmarked ? "Remove bookmark" : "Add bookmark"}
            title={bookmarked ? "Remove bookmark" : "Add bookmark"}
            // Always render the bookmarked icon visible; show the empty
            // outline only on hover/focus so the panel stays calm.
            className={`flex-shrink-0 w-5 h-5 flex items-center justify-center rounded-[6px] transition-opacity ${
              bookmarked
                ? "text-pomegranate-400 opacity-100"
                : "text-silver opacity-0 group-hover/toc:opacity-100 focus:opacity-100 hover:text-clay-black"
            }`}
          >
            <BookmarkIcon filled={bookmarked} />
          </button>
        )}
      </div>
      {hasChildren && isExpanded && (
        <ul>
          {node.children.map((child) => (
            <TocNodeView
              key={child.id}
              node={child}
              depth={depth + 1}
              isExpanded={isNodeExpanded(child.id)}
              status={resolveStatus(child)}
              isCurrent={isNodeCurrent(child)}
              toggleExpand={toggleExpand}
              onJump={onJump}
              resolveStatus={resolveStatus}
              isNodeExpanded={isNodeExpanded}
              registerNodeElement={registerNodeElement}
              isNodeCurrent={isNodeCurrent}
              isBookmarked={isBookmarked}
              onToggleBookmark={onToggleBookmark}
            />
          ))}
        </ul>
      )}
    </li>
  );
}

function BookmarkIcon({ filled }: { filled: boolean }) {
  return (
    <svg
      width="11"
      height="11"
      viewBox="0 0 14 14"
      fill={filled ? "currentColor" : "none"}
      stroke="currentColor"
      strokeWidth="1.4"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M3.5 1.5h7v11l-3.5-2.5-3.5 2.5v-11z" />
    </svg>
  );
}

function ChevronIcon({ expanded }: { expanded: boolean }) {
  return (
    <svg
      width="10"
      height="10"
      viewBox="0 0 10 10"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      style={{ transform: expanded ? "rotate(90deg)" : "rotate(0deg)", transition: "transform 0.15s" }}
    >
      <path d="M3 2l3 3-3 3" />
    </svg>
  );
}

function StatusDot({ status, isCurrent }: { status: ChapterStatus; isCurrent: boolean }) {
  const baseClass = "w-2 h-2 rounded-full flex-shrink-0";
  if (isCurrent || status === "current") {
    return <span className={`${baseClass} bg-matcha-600 ring-2 ring-matcha-300`} />;
  }
  if (status === "read") {
    return <span className={`${baseClass} bg-charcoal`} />;
  }
  return <span className={`${baseClass} border border-silver`} />;
}
