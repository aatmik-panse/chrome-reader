import React from "react";
import RailButton from "./RailButton";
import type { RightPanelId } from "../../hooks/usePanelState";

export const RIGHT_RAIL_WIDTH_PX = 60;

interface RightRailProps {
  activePanelId: RightPanelId | null;
  visible: boolean;
  onActivatePanel: (panelId: RightPanelId) => void;
  dueWordCount: number;
}

export default function RightRail({
  activePanelId,
  visible,
  onActivatePanel,
  dueWordCount,
}: RightRailProps) {
  if (!visible) return null;
  const dueBadge = dueWordCount > 0 ? dueWordCount : undefined;
  return (
    <nav
      aria-label="Tools navigation"
      className="flex flex-col items-center py-3 border-l border-oat bg-cream/60 flex-shrink-0"
      style={{ width: RIGHT_RAIL_WIDTH_PX }}
    >
      <div className="flex flex-col gap-1">
        <RailButton
          label="AI Assistant"
          active={activePanelId === "ai"}
          onClick={() => onActivatePanel("ai")}
          tooltipPosition="left"
        >
          <SparkleIcon />
        </RailButton>
        <RailButton
          label="Highlights"
          active={activePanelId === "highlights"}
          onClick={() => onActivatePanel("highlights")}
          tooltipPosition="left"
        >
          <HighlightIcon />
        </RailButton>
        <RailButton
          label="Words"
          active={activePanelId === "words"}
          onClick={() => onActivatePanel("words")}
          badge={dueBadge}
          tooltipPosition="left"
        >
          <BookIcon />
        </RailButton>
      </div>
    </nav>
  );
}

function SparkleIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z" />
      <path d="M20 3v4" />
      <path d="M22 5h-4" />
    </svg>
  );
}

function HighlightIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="m9 11-6 6v3h9l3-3" />
      <path d="m22 12-4.6 4.6a2 2 0 0 1-2.8 0l-5.2-5.2a2 2 0 0 1 0-2.8L14 4" />
    </svg>
  );
}

function BookIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H19a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H6.5a1 1 0 0 1 0-5H20" />
      <path d="M8 7h6" />
      <path d="M8 11h8" />
    </svg>
  );
}
