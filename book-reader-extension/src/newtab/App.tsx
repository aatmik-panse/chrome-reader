import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import Reader from "./components/Reader";
import AppShell from "./components/AppShell";
import AIPanel from "./components/AIPanel";
import ProgressBar from "./components/ProgressBar";
import Settings from "./components/Settings";
import DictionaryPopup from "./components/popups/DictionaryPopup";
import TranslatePopup from "./components/popups/TranslatePopup";
import HighlightEditPopup from "./components/popups/HighlightEditPopup";
import ReviewModal from "./components/ReviewModal";
import QuizModal from "./components/QuizModal";
import HighlightsPanel from "./components/HighlightsPanel";
import WordsPanel from "./components/WordsPanel";
import LibraryPanel from "./components/panels/LibraryPanel";
import TocPanel from "./components/panels/TocPanel";
import type { ToolbarAction, HighlightColor } from "./components/SelectionToolbar";
import { useBook } from "./hooks/useBook";
import { usePosition } from "./hooks/usePosition";
import { useAuth } from "./hooks/useAuth";
import { useAI } from "./hooks/useAI";
import { useTheme } from "./hooks/useTheme";
import { usePanelState } from "./hooks/usePanelState";
import { useAppBootstrap } from "./hooks/useAppBootstrap";
import {
  getSettings,
  saveSettings,
  ReaderSettings,
  DEFAULT_SETTINGS,
} from "./lib/storage";
import { defineWord, DictEntry } from "./lib/dictionary";
import { aiTranslate } from "./lib/api";
import { useHighlights } from "./hooks/useHighlights";
import { buildAnchor, offsetsFromRange } from "./lib/highlights/anchor";
import { useVocab } from "./hooks/useVocab";
import { VocabContext, VocabDefinition } from "./lib/vocab/types";
import type { TocNode } from "./lib/parsers/epub";
import type { SelectionOffsets } from "./hooks/useSelection";

const READING_WORDS_PER_MINUTE = 230;

function estimateReadingMinutes(text: string): number {
  if (!text) return 0;
  return Math.max(1, Math.ceil(text.split(/\s+/).length / READING_WORDS_PER_MINUTE));
}

export default function App() {
  const { bootstrapped } = useAppBootstrap();
  const { currentBook, library, loading, error, progressByHash, uploadBook, removeBook, switchBook, archiveBook, unarchiveBook } =
    useBook();
  const { user, signIn, signOut } = useAuth();
  const [settings, setSettings] = useState<ReaderSettings>(DEFAULT_SETTINGS);
  const [showSettings, setShowSettings] = useState(false);
  const [showReview, setShowReview] = useState(false);
  const [showQuiz, setShowQuiz] = useState(false);
  const [selectedText, setSelectedText] = useState("");
  const [pendingExplainText, setPendingExplainText] = useState<string | null>(null);
  const [topBarExpanded, setTopBarExpanded] = useState(false);
  const [pendingFragment, setPendingFragment] = useState<string | null>(null);
  const theme = useTheme(settings.themeId);
  const panel = usePanelState();
  const [dict, setDict] = useState<{
    loading: boolean;
    entry: DictEntry | null;
    notFoundWord: string | null;
    rect: DOMRect;
    selectionText: string;
    contextSentence: string;
    chapterIndex: number;
  } | null>(null);
  const [savedWordId, setSavedWordId] = useState<string | null>(null);
  const [translate, setTranslate] = useState<{
    loading: boolean;
    source: string;
    translation: string | null;
    error: string | null;
    targetLang: string;
    rect: DOMRect;
  } | null>(null);

  const { position, updatePosition } = usePosition({
    bookHash: currentBook?.hash ?? null,
    bookTitle: currentBook?.metadata.title ?? "",
    enabled: !!currentBook,
  });

  const ai = useAI(currentBook?.hash ?? null);
  const highlights = useHighlights(currentBook?.hash ?? null);
  const vocab = useVocab();
  const [editing, setEditing] = useState<{ id: string; rect: DOMRect } | null>(null);
  const currentChapterIndex = position?.chapterIndex ?? 0;

  /**
   * Tracks whether the persisted-settings load has completed. Until it has,
   * the theme-persist effect must not run — otherwise it would overwrite the
   * stored themeId with the React-state default before we've ever read it.
   */
  const settingsHydratedRef = useRef(false);

  useEffect(() => {
    getSettings().then((loaded) => {
      setSettings(loaded);
      theme.setThemeId(loaded.themeId);
      settingsHydratedRef.current = true;
    });
    // theme.setThemeId is referentially stable (useCallback with no deps)
    // so it does not need to participate in the dependency array.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Persist theme changes back to settings storage so refreshes keep the choice.
  useEffect(() => {
    if (!settingsHydratedRef.current) return;
    if (settings.themeId === theme.activeThemeId) return;
    const next = { ...settings, themeId: theme.activeThemeId };
    setSettings(next);
    saveSettings(next);
  }, [theme.activeThemeId, settings]);

  useEffect(() => {
    if (!user || !currentBook?.hash) return;
    highlights.refresh();
  }, [user, currentBook?.hash]);

  useEffect(() => {
    const onOnline = () => {
      import("./lib/highlights/sync").then((m) => m.pushPendingHighlights());
    };
    window.addEventListener("online", onOnline);
    return () => window.removeEventListener("online", onOnline);
  }, []);

  useEffect(() => {
    if (!user) return;
    vocab.refresh();
  }, [user]);

  useEffect(() => {
    const onOnline = () => {
      import("./lib/vocab/sync").then((m) => m.pushPendingVocab());
    };
    window.addEventListener("online", onOnline);
    return () => window.removeEventListener("online", onOnline);
  }, []);

  const handleSettingsChange = useCallback(async (next: ReaderSettings) => {
    setSettings(next);
    await saveSettings(next);
  }, []);

  const handlePositionChange = useCallback(
    (chapterIndex: number, scrollOffset: number, percentage: number) => {
      updatePosition(chapterIndex, scrollOffset, percentage);
    },
    [updatePosition],
  );

  const totalSections = useMemo(() => {
    if (!currentBook) return 0;
    if (currentBook.format === "epub") return currentBook.epub?.chapters.length ?? 0;
    if (currentBook.format === "txt") return currentBook.txt?.chunks.length ?? 0;
    if (currentBook.format === "pdf") return currentBook.pdf?.totalPages ?? 0;
    return 0;
  }, [currentBook]);

  const jumpToChapter = useCallback(
    (spineIndex: number, fragment: string | null) => {
      if (spineIndex < 0 || totalSections <= 0) return;
      const percentage = (spineIndex / totalSections) * 100;
      handlePositionChange(spineIndex, 0, percentage);
      // PDFs cannot resolve in-page anchors; ignore any fragment for them.
      const isFragmentRoutable = currentBook?.format !== "pdf";
      setPendingFragment(isFragmentRoutable ? fragment : null);
    },
    [handlePositionChange, totalSections, currentBook],
  );

  const goToTocNode = useCallback(
    (node: TocNode) => {
      if (node.spineIndex < 0) return;
      jumpToChapter(node.spineIndex, node.fragment);
      panel.closeLeftPanel();
    },
    [jumpToChapter, panel.closeLeftPanel],
  );

  const onPendingFragmentConsumed = useCallback(() => setPendingFragment(null), []);

  const handleSelectionAction = useCallback(
    (action: ToolbarAction, p: { text: string; range: Range; rect: DOMRect; offsets?: SelectionOffsets; color?: HighlightColor; highlightIds?: string[]; chapterIndex: number; chapterText: string }) => {
      setSelectedText(p.text);
      if (action === "remove_highlight") {
        const ids = p.highlightIds ?? [];
        for (const id of ids) highlights.remove(id);
        window.getSelection()?.removeAllRanges();
        return;
      }
      if (action === "search") {
        const url = `https://www.google.com/search?q=${encodeURIComponent(p.text)}`;
        window.open(url, "_blank", "noopener,noreferrer");
        return;
      }
      if (action === "explain") {
        setPendingExplainText(p.text);
        panel.openRightPanel("ai");
        window.getSelection()?.removeAllRanges();
        return;
      }
      if (action === "define") {
        const ctxText = p.chapterText;
        const idx = ctxText.toLowerCase().indexOf(p.text.toLowerCase());
        const sentence = idx >= 0
          ? ctxText.slice(Math.max(0, idx - 60), Math.min(ctxText.length, idx + p.text.length + 60))
          : p.text;
        setDict({
          loading: true,
          entry: null,
          notFoundWord: null,
          rect: p.rect,
          selectionText: p.text,
          contextSentence: sentence,
          chapterIndex: p.chapterIndex,
        });
        setSavedWordId(null);
        defineWord(p.text).then((entry) => {
          setDict({
            loading: false,
            entry,
            notFoundWord: entry ? null : p.text.split(/\s+/)[0] ?? p.text,
            rect: p.rect,
            selectionText: p.text,
            contextSentence: sentence,
            chapterIndex: p.chapterIndex,
          });
        });
        return;
      }
      if (action === "translate") {
        if (!currentBook) return;
        setTranslate({ loading: true, source: p.text, translation: null, error: null, targetLang: settings.translateTo, rect: p.rect });
        aiTranslate(currentBook.hash, p.text, settings.translateTo)
          .then((r) =>
            setTranslate({ loading: false, source: p.text, translation: r.translation, error: null, targetLang: settings.translateTo, rect: p.rect })
          )
          .catch((e) =>
            setTranslate({ loading: false, source: p.text, translation: null, error: e instanceof Error ? e.message : "Failed", targetLang: settings.translateTo, rect: p.rect })
          );
        return;
      }
      if (action === "highlight") {
        if (!currentBook) return;
        const color = p.color ?? "yellow";

        if (currentBook.format === "pdf") {
          const node = p.range.commonAncestorContainer;
          const startNode = node.nodeType === Node.ELEMENT_NODE ? (node as Element) : node.parentElement;
          if (!startNode) return;
          const pageWrapper = startNode.closest("[data-page]") as HTMLElement | null;
          if (!pageWrapper) return;
          const textLayer = pageWrapper.querySelector(".textLayer") as HTMLElement | null;
          if (!textLayer) return;
          const pageIndex = Number(pageWrapper.getAttribute("data-page")) - 1;
          const pageText = textLayer.textContent ?? "";
          const offs = offsetsFromRange(textLayer, p.range);
          if (!offs) return;
          const anchor = buildAnchor(pageText, offs.startOffset, offs.length, pageIndex);
          highlights.create(p.text, color, anchor);
          window.getSelection()?.removeAllRanges();
          return;
        }

        const proseEl = (p.range.commonAncestorContainer.parentElement?.closest(".prose-reader")
          ?? document.querySelector(".prose-reader")) as HTMLElement | null;
        if (!proseEl) return;
        const offs = p.offsets ?? offsetsFromRange(proseEl, p.range);
        if (!offs) return;
        const anchor = buildAnchor(p.chapterText, offs.startOffset, offs.length, p.chapterIndex);
        highlights.create(p.text, color, anchor);
        window.getSelection()?.removeAllRanges();
        return;
      }
    },
    [currentBook, settings.translateTo, highlights.create, highlights.remove, panel.openRightPanel],
  );

  const hasPosition = position !== null;
  const getCurrentChapterText = useCallback((): string => {
    if (!currentBook || !hasPosition) return "";
    const idx = currentChapterIndex;
    if (currentBook.format === "epub" && currentBook.epub) return currentBook.epub.chapters[idx]?.content ?? "";
    if (currentBook.format === "pdf") {
      const pageWrappers = document.querySelectorAll<HTMLElement>(".pdf-page-wrapper[data-page]");
      const texts: string[] = [];
      pageWrappers.forEach((wrapper) => {
        const tl = wrapper.querySelector(".textLayer");
        if (tl?.textContent) texts.push(tl.textContent);
      });
      return texts.join("\n\n");
    }
    if (currentBook.format === "txt" && currentBook.txt) return currentBook.txt.chunks[idx] ?? "";
    return "";
  }, [currentBook, currentChapterIndex, hasPosition]);

  const currentChapterText = useMemo(() => getCurrentChapterText(), [getCurrentChapterText]);
  const readingTimeMinutes = useMemo(() => {
    if (!currentBook) return null;
    if (!currentChapterText) return null;
    return estimateReadingMinutes(stripHtmlForCount(currentChapterText));
  }, [currentBook, currentChapterText]);

  const closeTopBar = useCallback(() => setTopBarExpanded(false), []);
  const expandTopBar = useCallback(() => setTopBarExpanded(true), []);
  const handleHighlightClick = useCallback((id: string, rect: DOMRect) => {
    setEditing({ id, rect });
  }, []);

  // ── Bootstrap spinner ──
  if (!bootstrapped) {
    return (
      <div className="h-full flex items-center justify-center bg-cream text-clay-black">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 border-2 border-clay-black border-t-transparent rounded-full animate-spin" />
          <p className="text-sm text-silver">Starting up...</p>
        </div>
      </div>
    );
  }

  // ── Empty state ──
  if (!currentBook && !loading) {
    return (
      <EmptyStateHero
        onUploadBook={uploadBook}
        onSignIn={signIn}
        showSignIn={!user}
        error={error}
      />
    );
  }

  // ── Loading ──
  if (loading) {
    return (
      <div className="h-full flex items-center justify-center bg-cream text-clay-black">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 border-2 border-clay-black border-t-transparent rounded-full animate-spin" />
          <p className="text-sm text-silver">Loading your book...</p>
        </div>
      </div>
    );
  }

  // ── Reader ──
  const leftPanelTitle = panel.panelState.left === "toc"
    ? "Table of Contents"
    : panel.panelState.left === "library"
      ? "Library"
      : null;

  const rightPanelTitle = panel.panelState.right === "ai"
    ? "AI Assistant"
    : panel.panelState.right === "highlights"
      ? `Highlights (${highlights.items.length})`
      : panel.panelState.right === "words"
        ? `Words (${vocab.items.length})`
        : null;

  const leftPanelContent = renderLeftPanelContent({
    activePanelId: panel.panelState.left,
    book: currentBook,
    chapterIndex: currentChapterIndex,
    library,
    progressByHash,
    onJumpToTocNode: goToTocNode,
    onSelectBook: (hash) => { switchBook(hash); panel.closeLeftPanel(); },
    onUploadBook: uploadBook,
    onDeleteBook: removeBook,
    onArchiveBook: archiveBook,
    onUnarchiveBook: unarchiveBook,
  });

  const rightPanelContent = renderRightPanelContent({
    activePanelId: panel.panelState.right,
    ai,
    selectedText,
    autoExplainText: pendingExplainText,
    onAutoExplainConsumed: () => setPendingExplainText(null),
    onSignIn: signIn,
    highlights: highlights.items,
    onJumpToHighlight: (highlight) => handlePositionChange(highlight.anchor.chapterIndex, 0, 0),
    vocab,
    currentBookHash: currentBook?.hash ?? null,
    onReview: () => setShowReview(true),
    onQuiz: () => setShowQuiz(true),
    getCurrentChapterText,
  });

  return (
    <>
      <ProgressBar percentage={position?.percentage ?? 0} />
      <AppShell
        settings={settings}
        onSettingsChange={handleSettingsChange}
        panel={panel}
        topBarExpanded={topBarExpanded}
        onTopBarExpand={expandTopBar}
        onTopBarCollapse={closeTopBar}
        bookTitle={currentBook?.metadata.title ?? ""}
        bookAuthor={currentBook?.metadata.author ?? ""}
        bookFormat={currentBook?.format ?? null}
        readingTimeMinutes={readingTimeMinutes}
        user={user}
        dueWordCount={vocab.dueCount}
        onSignIn={signIn}
        onSignOut={signOut}
        onOpenSettings={() => setShowSettings(true)}
        leftPanelTitle={leftPanelTitle}
        rightPanelTitle={rightPanelTitle}
        leftPanelContent={leftPanelContent}
        rightPanelContent={rightPanelContent}
      >
        {currentBook && (
          <Reader
            book={currentBook}
            position={position}
            settings={settings}
            onSettingsChange={handleSettingsChange}
            highlights={highlights.items}
            onPositionChange={handlePositionChange}
            onSelectionAction={handleSelectionAction}
            onHighlightClick={handleHighlightClick}
            hasExplain={ai.available}
            aiAvailable={ai.available}
            pendingFragment={pendingFragment}
            onPendingFragmentConsumed={onPendingFragmentConsumed}
            onNavigateToSpine={jumpToChapter}
          />
        )}
      </AppShell>

      {dict && currentBook && (
        <DictionaryPopup
          loading={dict.loading}
          entry={dict.entry}
          notFoundWord={dict.notFoundWord}
          rect={dict.rect}
          selectionText={dict.selectionText}
          contextSentence={dict.contextSentence}
          bookHash={currentBook.hash}
          bookTitle={currentBook.metadata.title}
          chapterIndex={dict.chapterIndex}
          isSaved={savedWordId !== null}
          audioUrlFromEntry={
            (dict.entry as any)?.phonetics?.find?.((p: any) => p.audio)?.audio
          }
          onAutoSave={async (entry, sentence) => {
            const audio: string | undefined = (entry as any).phonetics?.find?.((p: any) => p.audio)?.audio;
            const existing = await vocab.findByWord(entry.word);
            const defs: VocabDefinition[] = (entry.meanings ?? []).flatMap((m) =>
              m.definitions.map((d) => ({ partOfSpeech: m.partOfSpeech, definition: d.definition, example: d.example }))
            ).slice(0, 3);
            const context: VocabContext = {
              bookHash: currentBook.hash,
              bookTitle: currentBook.metadata.title,
              chapterIndex: dict.chapterIndex,
              sentence,
              savedAt: Date.now(),
            };
            if (existing) {
              const w = await vocab.save({
                word: entry.word,
                phonetic: entry.phonetic,
                audioUrl: audio,
                definitions: defs.length > 0 ? defs : existing.definitions,
                context,
              });
              setSavedWordId(w.id);
              return;
            }
            const w = await vocab.save({
              word: entry.word,
              phonetic: entry.phonetic,
              audioUrl: audio,
              definitions: defs,
              context,
            });
            setSavedWordId(w.id);
          }}
          onUnsave={async () => {
            if (savedWordId) await vocab.unsave(savedWordId);
            setSavedWordId(null);
          }}
          onClose={() => { setDict(null); setSavedWordId(null); }}
        />
      )}
      {translate && (
        <TranslatePopup
          loading={translate.loading}
          source={translate.source}
          translation={translate.translation}
          error={translate.error}
          targetLang={translate.targetLang}
          rect={translate.rect}
          onClose={() => setTranslate(null)}
        />
      )}
      {showSettings && (
        <Settings
          settings={settings}
          onChange={handleSettingsChange}
          onClose={() => setShowSettings(false)}
          isPdf={currentBook?.format === "pdf"}
          theme={theme}
          isAuthenticated={!!user}
          onSignIn={signIn}
        />
      )}
      {editing && (() => {
        const h = highlights.items.find((x) => x.id === editing.id);
        if (!h) return null;
        return (
          <HighlightEditPopup
            highlight={h}
            rect={editing.rect}
            onChangeColor={(c) => highlights.update(h.id, { color: c })}
            onChangeNote={(n) => highlights.update(h.id, { note: n })}
            onDelete={() => { highlights.remove(h.id); setEditing(null); }}
            onClose={() => setEditing(null)}
          />
        );
      })()}
      {showReview && (
        <ReviewModal
          items={vocab.items}
          onRate={async (id, rating) => { await vocab.applyReview(id, rating); }}
          onClose={() => setShowReview(false)}
        />
      )}
      {showQuiz && (
        <QuizModal
          items={vocab.items}
          onClose={() => setShowQuiz(false)}
        />
      )}
    </>
  );
}

const ACCEPTED_BOOK_EXTENSIONS = ".epub,.pdf,.txt,.text";
const SUPPORTED_BOOK_FORMAT_PILLS: ReadonlyArray<{ label: string; colorClass: string }> = [
  { label: "EPUB", colorClass: "bg-matcha-300" },
  { label: "PDF", colorClass: "bg-pomegranate-400" },
  { label: "TXT", colorClass: "bg-slushie-500" },
];

interface EmptyStateHeroProps {
  onUploadBook: (file: File) => void;
  onSignIn: () => void;
  showSignIn: boolean;
  error: string | null;
}

function EmptyStateHero({ onUploadBook, onSignIn, showSignIn, error }: EmptyStateHeroProps) {
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [isDraggingFile, setIsDraggingFile] = useState(false);

  const openFilePicker = useCallback(() => {
    fileInputRef.current?.click();
  }, []);

  const handleFileInputChange = useCallback(
    (event: React.ChangeEvent<HTMLInputElement>) => {
      const file = event.target.files?.[0];
      if (file) onUploadBook(file);
      // Reset value so the user can re-select the same file later.
      event.target.value = "";
    },
    [onUploadBook],
  );

  const handleDragEnter = useCallback((event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    setIsDraggingFile(true);
  }, []);

  const handleDragOver = useCallback((event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    setIsDraggingFile(true);
  }, []);

  const handleDragLeave = useCallback((event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    setIsDraggingFile(false);
  }, []);

  const handleDrop = useCallback(
    (event: React.DragEvent<HTMLDivElement>) => {
      event.preventDefault();
      setIsDraggingFile(false);
      const file = event.dataTransfer.files?.[0];
      if (file) onUploadBook(file);
    },
    [onUploadBook],
  );

  return (
    <div className="h-full flex flex-col items-center justify-center bg-cream text-clay-black fade-in">
      <div
        className={`text-center max-w-sm px-6 py-8 rounded-[24px] transition-colors ${
          isDraggingFile ? "bg-clay-white clay-shadow" : ""
        }`}
        onDragEnter={handleDragEnter}
        onDragOver={handleDragOver}
        onDragLeave={handleDragLeave}
        onDrop={handleDrop}
      >
        <img
          src="/BookFlipSmall.jpg"
          alt="Instant Book Reader"
          className="w-24 h-24 mx-auto mb-8 rounded-[24px] object-cover clay-shadow"
        />

        <h1 className="text-4xl font-semibold tracking-tight mb-2" style={{ letterSpacing: "-1.6px" }}>
          Instant Reader
        </h1>
        <p className="text-charcoal mb-10">Your reading space, always one tab away.</p>

        <button
          onClick={openFilePicker}
          className="clay-btn-solid w-full text-lg !py-3 !rounded-[12px]"
        >
          Open a Book
        </button>
        <input
          ref={fileInputRef}
          type="file"
          accept={ACCEPTED_BOOK_EXTENSIONS}
          onChange={handleFileInputChange}
          className="hidden"
          aria-hidden="true"
        />

        <div className="mt-8 flex items-center justify-center gap-4">
          {SUPPORTED_BOOK_FORMAT_PILLS.map((formatPill) => (
            <span key={formatPill.label} className="flex items-center gap-1.5 text-xs text-silver">
              <span className={`w-1.5 h-1.5 rounded-full ${formatPill.colorClass}`} /> {formatPill.label}
            </span>
          ))}
        </div>

        <p className="mt-3 text-xs text-silver">
          Everything stays on your device &middot; Works offline
        </p>

        {showSignIn && (
          <button
            onClick={onSignIn}
            className="mt-5 text-xs text-silver hover:text-matcha-600 transition-colors underline underline-offset-2"
          >
            Sign in for cloud sync &amp; AI
          </button>
        )}

        {error && (
          <p className="mt-4 text-sm text-pomegranate-400 bg-pomegranate-400/10 px-4 py-2 rounded-[12px]">{error}</p>
        )}
      </div>
    </div>
  );
}

function stripHtmlForCount(html: string): string {
  if (!html) return "";
  const tmp = document.createElement("div");
  tmp.innerHTML = html;
  return tmp.textContent || tmp.innerText || "";
}

interface LeftPanelRenderArgs {
  activePanelId: "toc" | "library" | null;
  book: ReturnType<typeof useBook>["currentBook"];
  chapterIndex: number;
  library: ReturnType<typeof useBook>["library"];
  progressByHash: Record<string, number>;
  onJumpToTocNode: (node: TocNode) => void;
  onSelectBook: (hash: string) => void;
  onUploadBook: (file: File) => void;
  onDeleteBook: (hash: string) => void;
  onArchiveBook: (hash: string) => void;
  onUnarchiveBook: (hash: string) => void;
}

function renderLeftPanelContent({
  activePanelId,
  book,
  chapterIndex,
  library,
  progressByHash,
  onJumpToTocNode,
  onSelectBook,
  onUploadBook,
  onDeleteBook,
  onArchiveBook,
  onUnarchiveBook,
}: LeftPanelRenderArgs): React.ReactNode {
  if (activePanelId === "toc") {
    if (!book) {
      return (
        <p className="text-xs text-silver text-center py-12 px-4">No book is open.</p>
      );
    }
    return (
      <TocPanel
        book={book}
        currentChapterIndex={chapterIndex}
        onJump={onJumpToTocNode}
      />
    );
  }
  if (activePanelId === "library") {
    return (
      <LibraryPanel
        books={library}
        currentHash={book?.hash ?? null}
        progressByHash={progressByHash}
        onSelect={onSelectBook}
        onUpload={onUploadBook}
        onDelete={onDeleteBook}
        onArchive={onArchiveBook}
        onUnarchive={onUnarchiveBook}
      />
    );
  }
  return null;
}

interface RightPanelRenderArgs {
  activePanelId: "ai" | "highlights" | "words" | null;
  ai: ReturnType<typeof useAI>;
  selectedText: string;
  autoExplainText: string | null;
  onAutoExplainConsumed: () => void;
  onSignIn: () => void;
  highlights: ReturnType<typeof useHighlights>["items"];
  onJumpToHighlight: (highlight: ReturnType<typeof useHighlights>["items"][number]) => void;
  vocab: ReturnType<typeof useVocab>;
  currentBookHash: string | null;
  onReview: () => void;
  onQuiz: () => void;
  getCurrentChapterText: () => string;
}

function renderRightPanelContent({
  activePanelId,
  ai,
  selectedText,
  autoExplainText,
  onAutoExplainConsumed,
  onSignIn,
  highlights,
  onJumpToHighlight,
  vocab,
  currentBookHash,
  onReview,
  onQuiz,
  getCurrentChapterText,
}: RightPanelRenderArgs): React.ReactNode {
  if (activePanelId === "ai") {
    return (
      <AIPanel
        onSummarize={() => ai.summarize(getCurrentChapterText())}
        onAsk={(question) => ai.ask(question, getCurrentChapterText())}
        onHighlights={() => ai.highlights(getCurrentChapterText())}
        onExplain={(selection) => ai.explain(selection, getCurrentChapterText())}
        selectedText={selectedText}
        autoExplainText={autoExplainText}
        onAutoExplainConsumed={onAutoExplainConsumed}
        loading={ai.loading}
        error={ai.error}
        available={ai.available}
        onSignIn={onSignIn}
      />
    );
  }
  if (activePanelId === "highlights") {
    return <HighlightsPanel items={highlights} onJump={onJumpToHighlight} />;
  }
  if (activePanelId === "words") {
    return (
      <WordsPanel
        items={vocab.items}
        currentBookHash={currentBookHash}
        dueCount={vocab.dueCount}
        onDelete={(id) => vocab.unsave(id)}
        onResetStage={(id) => vocab.resetStage(id)}
        onReview={onReview}
        onQuiz={onQuiz}
      />
    );
  }
  return null;
}
