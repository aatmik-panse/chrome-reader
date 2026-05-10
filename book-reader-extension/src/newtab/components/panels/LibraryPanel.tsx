import React, { useCallback, useMemo, useRef, useState } from "react";
import { BookMetadata } from "../../lib/storage";
import Tooltip from "../Tooltip";
import { useBookThumbnail } from "../../hooks/useBookThumbnail";
import {
  buildLibraryEntries,
  filterBySearch,
  groupForDisplay,
  sortEntries,
  LibraryEntry,
  LibrarySort,
  timeAgo,
} from "./library-helpers";

type LibraryView = "active" | "archived";

interface LibraryPanelProps {
  books: ReadonlyArray<BookMetadata>;
  currentHash: string | null;
  progressByHash: Record<string, number>;
  onSelect: (hash: string) => void;
  onUpload: (file: File) => void;
  onDelete: (hash: string) => void;
  onArchive: (hash: string) => void;
  onUnarchive: (hash: string) => void;
}

const FORMAT_BADGE: Record<BookMetadata["format"], { bg: string; text: string }> = {
  epub: { bg: "bg-matcha-300", text: "text-matcha-800" },
  pdf: { bg: "bg-pomegranate-400", text: "text-white" },
  txt: { bg: "bg-slushie-500", text: "text-white" },
};

export default function LibraryPanel({
  books,
  currentHash,
  progressByHash,
  onSelect,
  onUpload,
  onDelete,
  onArchive,
  onUnarchive,
}: LibraryPanelProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [searchQuery, setSearchQuery] = useState("");
  const [sortKey, setSortKey] = useState<LibrarySort>("recent");
  const [view, setView] = useState<LibraryView>("active");
  const [draggingFile, setDraggingFile] = useState(false);
  const [confirmDeleteHash, setConfirmDeleteHash] = useState<string | null>(null);

  const { activeBooks, archivedBooks } = useMemo(() => {
    const active: BookMetadata[] = [];
    const archived: BookMetadata[] = [];
    for (const meta of books) {
      if (meta.archived) archived.push(meta);
      else active.push(meta);
    }
    return { activeBooks: active, archivedBooks: archived };
  }, [books]);

  const grouped = useMemo(() => {
    const all = buildLibraryEntries(activeBooks, progressByHash);
    const filtered = filterBySearch(all, searchQuery);
    return groupForDisplay(filtered, sortKey);
  }, [activeBooks, progressByHash, searchQuery, sortKey]);

  const archivedEntries = useMemo(() => {
    const all = buildLibraryEntries(archivedBooks, progressByHash);
    const filtered = filterBySearch(all, searchQuery);
    return sortEntries(filtered, sortKey);
  }, [archivedBooks, progressByHash, searchQuery, sortKey]);

  const handleDropFile = useCallback(
    (event: React.DragEvent) => {
      event.preventDefault();
      setDraggingFile(false);
      const file = event.dataTransfer.files[0];
      if (file) onUpload(file);
    },
    [onUpload],
  );

  const handleFileInputChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const file = event.target.files?.[0];
      if (file) onUpload(file);
      event.target.value = "";
    },
    [onUpload],
  );

  return (
    <div
      className="flex flex-col h-full"
      onDragOver={(event) => {
        event.preventDefault();
        setDraggingFile(true);
      }}
      onDragLeave={() => setDraggingFile(false)}
      onDrop={handleDropFile}
    >
      <div className="px-4 py-3 border-b border-oat space-y-2">
        <div className="flex items-center gap-1 p-0.5 rounded-[10px] bg-frost/60 text-[11px]">
          <ViewTabButton active={view === "active"} onClick={() => setView("active")}>
            Active ({activeBooks.length})
          </ViewTabButton>
          <ViewTabButton active={view === "archived"} onClick={() => setView("archived")}>
            Archived ({archivedBooks.length})
          </ViewTabButton>
        </div>
        <input
          type="search"
          value={searchQuery}
          onChange={(event) => setSearchQuery(event.target.value)}
          placeholder="Search title or author"
          className="w-full px-3 py-1.5 text-xs rounded-[8px] border border-oat bg-clay-white text-clay-black placeholder:text-silver focus:outline-2 focus:outline-matcha-600"
          aria-label="Search library"
        />
        <div className="flex items-center justify-between text-[11px] text-silver">
          <span>{books.length} book{books.length === 1 ? "" : "s"}</span>
          <select
            value={sortKey}
            onChange={(event) => setSortKey(event.target.value as LibrarySort)}
            className="px-2 py-1 rounded-[6px] border border-oat bg-clay-white text-clay-black"
            aria-label="Sort library"
          >
            <option value="recent">Recent</option>
            <option value="title">Title</option>
            <option value="author">Author</option>
          </select>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto px-3 py-3 space-y-4">
        {view === "active" ? (
          <>
            <LibraryGroup
              label="Recent"
              entries={grouped.recent}
              currentHash={currentHash}
              confirmDeleteHash={confirmDeleteHash}
              onSelect={onSelect}
              onDelete={onDelete}
              onConfirmDelete={setConfirmDeleteHash}
              onArchive={onArchive}
              onUnarchive={onUnarchive}
            />
            <LibraryGroup
              label={`Reading (${grouped.reading.length})`}
              entries={grouped.reading}
              currentHash={currentHash}
              confirmDeleteHash={confirmDeleteHash}
              onSelect={onSelect}
              onDelete={onDelete}
              onConfirmDelete={setConfirmDeleteHash}
              onArchive={onArchive}
              onUnarchive={onUnarchive}
            />
            <LibraryGroup
              label={`Unstarted (${grouped.unstarted.length})`}
              entries={grouped.unstarted}
              currentHash={currentHash}
              confirmDeleteHash={confirmDeleteHash}
              onSelect={onSelect}
              onDelete={onDelete}
              onConfirmDelete={setConfirmDeleteHash}
              onArchive={onArchive}
              onUnarchive={onUnarchive}
            />
            <LibraryGroup
              label={`Finished (${grouped.finished.length})`}
              entries={grouped.finished}
              currentHash={currentHash}
              confirmDeleteHash={confirmDeleteHash}
              onSelect={onSelect}
              onDelete={onDelete}
              onConfirmDelete={setConfirmDeleteHash}
              onArchive={onArchive}
              onUnarchive={onUnarchive}
            />
            {activeBooks.length === 0 && (
              <p className="text-xs text-silver text-center py-12">
                Your library is empty. Drop a book below to start reading.
              </p>
            )}
          </>
        ) : (
          <>
            <LibraryGroup
              label="Archived"
              entries={archivedEntries}
              currentHash={currentHash}
              confirmDeleteHash={confirmDeleteHash}
              onSelect={onSelect}
              onDelete={onDelete}
              onConfirmDelete={setConfirmDeleteHash}
              onArchive={onArchive}
              onUnarchive={onUnarchive}
            />
            {archivedEntries.length === 0 && (
              <p className="text-xs text-silver text-center py-12">
                No archived books. Archive a book from the Active tab to move it here.
              </p>
            )}
          </>
        )}
      </div>

      <button
        type="button"
        onClick={() => fileInputRef.current?.click()}
        className={`m-3 p-3 border border-dashed rounded-[16px] text-center transition-all ${
          draggingFile
            ? "border-matcha-600 bg-matcha-300/10"
            : "border-oat hover:border-charcoal"
        }`}
      >
        <p className="text-xs font-medium">Drop or click to add a book</p>
        <p className="text-[10px] text-silver mt-0.5">EPUB, PDF, or TXT</p>
      </button>
      <input
        ref={fileInputRef}
        type="file"
        accept=".epub,.pdf,.txt,.text"
        onChange={handleFileInputChange}
        className="hidden"
      />
    </div>
  );
}

interface ViewTabButtonProps {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}

function ViewTabButton({ active, onClick, children }: ViewTabButtonProps) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={`flex-1 px-3 py-1.5 rounded-[8px] transition-colors ${
        active ? "bg-clay-white text-clay-black shadow-sm" : "text-silver hover:text-clay-black"
      }`}
    >
      {children}
    </button>
  );
}

interface LibraryGroupProps {
  label: string;
  entries: ReadonlyArray<LibraryEntry>;
  currentHash: string | null;
  confirmDeleteHash: string | null;
  onSelect: (hash: string) => void;
  onDelete: (hash: string) => void;
  onConfirmDelete: (hash: string | null) => void;
  onArchive: (hash: string) => void;
  onUnarchive: (hash: string) => void;
}

function LibraryGroup({
  label,
  entries,
  currentHash,
  confirmDeleteHash,
  onSelect,
  onDelete,
  onConfirmDelete,
  onArchive,
  onUnarchive,
}: LibraryGroupProps) {
  if (entries.length === 0) return null;
  return (
    <section>
      <h4 className="clay-label mb-1 px-1">{label}</h4>
      <ul className="space-y-1.5">
        {entries.map((entry) => (
          <LibraryRow
            key={entry.meta.hash}
            entry={entry}
            isActive={entry.meta.hash === currentHash}
            isConfirmingDelete={confirmDeleteHash === entry.meta.hash}
            onSelect={onSelect}
            onDelete={onDelete}
            onConfirmDelete={onConfirmDelete}
            onArchive={onArchive}
            onUnarchive={onUnarchive}
          />
        ))}
      </ul>
    </section>
  );
}

interface LibraryRowProps {
  entry: LibraryEntry;
  isActive: boolean;
  isConfirmingDelete: boolean;
  onSelect: (hash: string) => void;
  onDelete: (hash: string) => void;
  onConfirmDelete: (hash: string | null) => void;
  onArchive: (hash: string) => void;
  onUnarchive: (hash: string) => void;
}

function LibraryRow({
  entry,
  isActive,
  isConfirmingDelete,
  onSelect,
  onDelete,
  onConfirmDelete,
  onArchive,
  onUnarchive,
}: LibraryRowProps) {
  const { meta, progressPercent, status } = entry;
  const badge = FORMAT_BADGE[meta.format] ?? { bg: "bg-frost", text: "text-charcoal" };
  const progressLabel =
    status === "finished"
      ? "Done"
      : progressPercent > 0
        ? `${Math.round(progressPercent)}%`
        : "—";
  const isArchived = meta.archived === true;
  return (
    <li>
      <div
        className={`flex items-center gap-2 p-2 rounded-[10px] cursor-pointer group transition-all ${
          isActive ? "ring-1 ring-matcha-600 bg-matcha-300/10" : "hover:bg-frost/60"
        }`}
        onClick={() => onSelect(meta.hash)}
      >
        <BookCover meta={meta} />
        <div className="flex-1 min-w-0">
          <p className="text-xs font-medium truncate">{meta.title}</p>
          <p className="text-[11px] text-silver truncate">
            {meta.author} &middot; {timeAgo(meta.lastOpenedAt)}
          </p>
          <div className="mt-1 h-0.5 bg-oat/60 rounded-full overflow-hidden">
            <div
              className="h-full bg-matcha-600"
              style={{ width: `${Math.min(100, Math.max(0, progressPercent))}%` }}
            />
          </div>
        </div>
        {isConfirmingDelete ? (
          <div className="flex items-center gap-1 flex-shrink-0" onClick={(event) => event.stopPropagation()}>
            <button
              type="button"
              onClick={() => {
                onDelete(meta.hash);
                onConfirmDelete(null);
              }}
              className="clay-btn-ghost danger !text-[10px] !py-1 !px-2 bg-pomegranate-400 !text-white !rounded-[8px]"
            >
              Delete
            </button>
            <button
              type="button"
              onClick={() => onConfirmDelete(null)}
              className="clay-btn-ghost !text-[10px] !py-1 !px-2"
            >
              Cancel
            </button>
          </div>
        ) : (
          <div className="relative flex-shrink-0 w-12 h-9">
            {/*
              Two layers occupying the same slot: the metadata badge column
              (default) and the action buttons (hover/focus). The slot has a
              fixed width so the title column doesn't reflow when they swap;
              we cross-fade with a small slide so the transition reads as
              motion instead of a flash.
            */}
            <div
              aria-hidden={false}
              className="absolute inset-0 flex flex-col items-end justify-center gap-1 transition-all duration-150 ease-out group-hover:opacity-0 group-hover:translate-x-1 group-hover:pointer-events-none group-focus-within:opacity-0 group-focus-within:translate-x-1 group-focus-within:pointer-events-none"
            >
              <span className={`clay-badge ${badge.bg} ${badge.text} uppercase text-[9px]`}>
                {meta.format}
              </span>
              <span className="text-[10px] tabular-nums text-silver">{progressLabel}</span>
            </div>
            <div
              className="absolute inset-0 flex items-center justify-end gap-0.5 opacity-0 -translate-x-1 pointer-events-none transition-all duration-150 ease-out group-hover:opacity-100 group-hover:translate-x-0 group-hover:pointer-events-auto group-focus-within:opacity-100 group-focus-within:translate-x-0 group-focus-within:pointer-events-auto"
            >
              <Tooltip label={isArchived ? "Move back to active" : "Archive book"} position="left">
                <button
                  type="button"
                  aria-label={isArchived ? `Unarchive ${meta.title}` : `Archive ${meta.title}`}
                  onClick={(event) => {
                    event.stopPropagation();
                    if (isArchived) onUnarchive(meta.hash);
                    else onArchive(meta.hash);
                  }}
                  className="clay-btn-icon !p-1.5"
                >
                  {isArchived ? (
                    <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                      <path d="M2 4.5h8M3 4.5v5a1 1 0 0 0 1 1h4a1 1 0 0 0 1-1v-5M5 6.5l1 1 1-1M6 7.5V3" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  ) : (
                    <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                      <path d="M2 4.5h8M3 4.5v5a1 1 0 0 0 1 1h4a1 1 0 0 0 1-1v-5M2 2h8v2H2zM5 7h2" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  )}
                </button>
              </Tooltip>
              <Tooltip label="Delete book" position="left">
                <button
                  type="button"
                  aria-label={`Delete ${meta.title}`}
                  onClick={(event) => {
                    event.stopPropagation();
                    onConfirmDelete(meta.hash);
                  }}
                  className="clay-btn-icon !p-1.5"
                >
                  <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                    <path d="M2.5 3h7M4.5 3V2a1 1 0 011-1h1a1 1 0 011 1v1M8 5v4.5a1 1 0 01-1 1H5a1 1 0 01-1-1V5" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
                  </svg>
                </button>
              </Tooltip>
            </div>
          </div>
        )}
      </div>
    </li>
  );
}

interface BookCoverProps {
  meta: BookMetadata;
}

function BookCover({ meta }: BookCoverProps) {
  const { url, status } = useBookThumbnail(meta);
  const initial = meta.title?.trim().charAt(0).toUpperCase() || "?";
  return (
    <div className="flex-shrink-0 w-9 h-12 rounded-[6px] overflow-hidden bg-oat/40 flex items-center justify-center">
      {url ? (
        <img
          src={url}
          alt=""
          className="w-full h-full object-cover"
          draggable={false}
        />
      ) : status === "loading" ? (
        <div className="w-3 h-3 border border-silver/40 border-t-transparent rounded-full animate-spin" />
      ) : (
        <span className="text-[14px] font-semibold text-silver">{initial}</span>
      )}
    </div>
  );
}
