import React, { useCallback, useEffect } from "react";
import LeftRail from "./shell/LeftRail";
import RightRail from "./shell/RightRail";
import Panel from "./shell/Panel";
import TopBar from "./shell/TopBar";
import type { ReaderSettings } from "../lib/storage";
import type {
  AnyPanelId,
  LeftPanelId,
  RightPanelId,
  UsePanelStateResult,
} from "../hooks/usePanelState";

interface AppShellProps {
  settings: ReaderSettings;
  onSettingsChange: (next: ReaderSettings) => void;

  panel: UsePanelStateResult;

  topBarExpanded: boolean;
  onTopBarExpand: () => void;
  onTopBarCollapse: () => void;

  bookTitle: string;
  bookAuthor: string;
  bookFormat: "epub" | "pdf" | "txt" | null;
  readingTimeMinutes: number | null;

  dueWordCount: number;
  onOpenSettings: () => void;

  leftPanelTitle: string | null;
  rightPanelTitle: string | null;
  leftPanelContent: React.ReactNode;
  rightPanelContent: React.ReactNode;

  children: React.ReactNode;
}

/**
 * Persistent layout chrome for the reader.
 *
 * Composition only — does not own any state besides what's already passed
 * in via `panel`. App.tsx remains the orchestration layer for book/
 * settings/theme/position.
 */
export default function AppShell({
  settings,
  onSettingsChange,
  panel,
  topBarExpanded,
  onTopBarExpand,
  onTopBarCollapse,
  bookTitle,
  bookAuthor,
  bookFormat,
  readingTimeMinutes,
  dueWordCount,
  onOpenSettings,
  leftPanelTitle,
  rightPanelTitle,
  leftPanelContent,
  rightPanelContent,
  children,
}: AppShellProps) {
  const { panelState, closeLeftPanel, closeRightPanel,
    toggleLeftPanel, toggleRightPanel, setPanelWidth, getPanelWidth } = panel;

  // Hide-rail-forces-panel-closed enforcement.
  useEffect(() => {
    if (!settings.showLeftRail && panelState.left !== null) closeLeftPanel();
  }, [settings.showLeftRail, panelState.left, closeLeftPanel]);

  useEffect(() => {
    if (!settings.showRightRail && panelState.right !== null) closeRightPanel();
  }, [settings.showRightRail, panelState.right, closeRightPanel]);

  // Keyboard shortcuts: [/] toggles, Esc closes.
  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (target && /^(input|textarea|select)$/i.test(target.tagName)) return;
      if (target?.isContentEditable) return;
      if (event.key === "[") {
        if (!settings.showLeftRail) return;
        event.preventDefault();
        toggleLeftPanel(panelState.left ?? "toc");
      } else if (event.key === "]") {
        if (!settings.showRightRail) return;
        event.preventDefault();
        toggleRightPanel(panelState.right ?? "ai");
      } else if (event.key === "Escape") {
        if (panelState.left !== null) closeLeftPanel();
        else if (panelState.right !== null) closeRightPanel();
      }
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [
    settings.showLeftRail,
    settings.showRightRail,
    panelState.left,
    panelState.right,
    toggleLeftPanel,
    toggleRightPanel,
    closeLeftPanel,
    closeRightPanel,
  ]);

  const handleActivateLeft = useCallback(
    (panelId: LeftPanelId) => toggleLeftPanel(panelId),
    [toggleLeftPanel],
  );
  const handleActivateRight = useCallback(
    (panelId: RightPanelId) => toggleRightPanel(panelId),
    [toggleRightPanel],
  );

  const updatePanelWidth = (panelId: AnyPanelId) => (widthPx: number) =>
    setPanelWidth(panelId, widthPx);

  return (
    <div className="h-full flex flex-col bg-cream text-clay-black">
      <TopBar
        bookTitle={bookTitle}
        bookAuthor={bookAuthor}
        bookFormat={bookFormat}
        readingTimeMinutes={readingTimeMinutes}
        expanded={topBarExpanded}
        onExpand={onTopBarExpand}
        onCollapse={onTopBarCollapse}
        settings={settings}
        onSettingsChange={onSettingsChange}
      />
      <div className="flex flex-1 overflow-hidden">
        <LeftRail
          activePanelId={panelState.left}
          visible={settings.showLeftRail}
          onActivatePanel={handleActivateLeft}
          onOpenSettings={onOpenSettings}
        />
        {panelState.left !== null && (
          <Panel
            side="left"
            widthPx={getPanelWidth(panelState.left)}
            title={leftPanelTitle ?? ""}
            onClose={closeLeftPanel}
            onWidthChange={updatePanelWidth(panelState.left)}
          >
            {leftPanelContent}
          </Panel>
        )}
        <main className="flex-1 min-w-0 overflow-hidden">{children}</main>
        {panelState.right !== null && (
          <Panel
            side="right"
            widthPx={getPanelWidth(panelState.right)}
            title={rightPanelTitle ?? ""}
            onClose={closeRightPanel}
            onWidthChange={updatePanelWidth(panelState.right)}
          >
            {rightPanelContent}
          </Panel>
        )}
        <RightRail
          activePanelId={panelState.right}
          visible={settings.showRightRail}
          onActivatePanel={handleActivateRight}
          dueWordCount={dueWordCount}
        />
      </div>
    </div>
  );
}
