import React, { useState } from "react";
import { ReaderSettings, PdfViewMode, PdfTint } from "../lib/storage";
import ThemeGrid, { resolvePresetBaseId } from "./settings/ThemeGrid";
import ThemeBuilder from "./settings/ThemeBuilder";
import ByokSettings from "./settings/ByokSettings";
import type { UseThemeResult } from "../hooks/useTheme";
import type { CustomThemeDef } from "../lib/themes/types";

export type SettingsSection = "themes" | "reader" | "ai" | "pdf";

interface SettingsProps {
  settings: ReaderSettings;
  onChange: (settings: ReaderSettings) => void;
  onClose: () => void;
  isPdf?: boolean;
  theme: UseThemeResult;
  initialSection?: SettingsSection | null;
}

const VIEW_MODE_OPTIONS: { id: PdfViewMode; label: string }[] = [
  { id: "single", label: "Single" },
  { id: "continuous", label: "Scroll" },
  { id: "spread", label: "Spread" },
];

const PDF_TINT_OPTIONS: { id: PdfTint; label: string }[] = [
  { id: "normal", label: "Normal" },
  { id: "dark", label: "Dark" },
  { id: "sepia", label: "Sepia" },
];

const SECTIONS: { id: SettingsSection; label: string; icon: React.ReactNode }[] = [
  {
    id: "themes",
    label: "Themes",
    icon: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
        <path d="M8 2a6 6 0 1 0 0 12c.6 0 1-.4 1-1 0-.3-.1-.5-.3-.7-.2-.2-.3-.4-.3-.7 0-.6.4-1 1-1H11c1.7 0 3-1.3 3-3 0-3.3-2.7-5.6-6-5.6z" />
        <circle cx="5" cy="6" r="0.7" />
        <circle cx="8" cy="4.5" r="0.7" />
        <circle cx="11" cy="6" r="0.7" />
        <circle cx="11.5" cy="9" r="0.7" />
      </svg>
    ),
  },
  {
    id: "reader",
    label: "Reader",
    icon: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
        <path d="M2 3h4.5c.8 0 1.5.7 1.5 1.5V14c0-.8-.7-1-1.5-1H2V3z" />
        <path d="M14 3H9.5C8.7 3 8 3.7 8 4.5V14c0-.8.7-1 1.5-1H14V3z" />
      </svg>
    ),
  },
  {
    id: "ai",
    label: "AI Keys",
    icon: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
        <path d="M11 7a3 3 0 1 1-2.5 4.7L4 13l-1-1 1.3-3.5A3 3 0 1 1 11 7z" />
        <circle cx="11" cy="7" r="0.5" fill="currentColor" />
      </svg>
    ),
  },
  {
    id: "pdf",
    label: "PDF Viewer",
    icon: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
        <path d="M4 2h5l4 4v8a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V3a1 1 0 0 1 1-1z" />
        <path d="M9 2v4h4" />
        <path d="M5.5 9.5h5M5.5 12h3" />
      </svg>
    ),
  },
];

function Toggle({ value, onChange }: { value: boolean; onChange: () => void }) {
  return (
    <button
      onClick={onChange}
      className={`w-11 h-6 rounded-full transition-all duration-200 relative flex-shrink-0 ${
        value ? "bg-matcha-600" : "bg-oat"
      }`}
    >
      <div className={`absolute top-0.5 w-5 h-5 rounded-full bg-clay-white shadow-sm transition-all duration-200 ${
        value ? "left-[22px]" : "left-0.5"
      }`} />
    </button>
  );
}

function ToggleRow({ label, description, value, onChange }: { label: string; description?: string; value: boolean; onChange: () => void }) {
  return (
    <div className="flex items-center justify-between gap-4">
      <div className="min-w-0">
        <p className="text-sm text-clay-black">{label}</p>
        {description && <p className="text-xs text-silver mt-0.5">{description}</p>}
      </div>
      <Toggle value={value} onChange={onChange} />
    </div>
  );
}

export default function Settings({ settings, onChange, onClose, isPdf, theme, initialSection }: SettingsProps) {
  const update = (patch: Partial<ReaderSettings>) => onChange({ ...settings, ...patch });
  const [activeSection, setActiveSection] = useState<SettingsSection>(
    initialSection ?? (isPdf ? "pdf" : "themes"),
  );
  const [editingCustomTheme, setEditingCustomTheme] = useState<CustomThemeDef | null>(null);
  const [showThemeBuilder, setShowThemeBuilder] = useState(false);

  const closeThemeBuilder = () => {
    setShowThemeBuilder(false);
    setEditingCustomTheme(null);
  };

  const isPdfTintOverrideEnabled = settings.pdfTintOverride !== null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 fade-in">
      <div className="clay-card w-full max-w-2xl !p-0 overflow-hidden modal-enter flex flex-col" style={{ height: "min(560px, 85vh)" }}>
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-oat flex-shrink-0">
          <h2 className="text-lg font-semibold tracking-tight" style={{ letterSpacing: "-0.4px" }}>Settings</h2>
          <button onClick={onClose} className="clay-btn-white !p-2 !rounded-[8px]">
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
          </button>
        </div>

        {/* Body: sidebar + content */}
        <div className="flex flex-1 overflow-hidden">
          {/* Sidebar */}
          <div className="w-[160px] flex-shrink-0 border-r border-oat bg-oat/20 py-3 px-2 space-y-0.5">
            {SECTIONS.map((section) => (
              <button
                key={section.id}
                onClick={() => setActiveSection(section.id)}
                className={`w-full flex items-center gap-2.5 px-3 py-2 rounded-[8px] text-left transition-all text-sm ${
                  activeSection === section.id
                    ? "bg-clay-white shadow-sm text-clay-black font-medium"
                    : "text-charcoal hover:bg-clay-white/50 hover:text-clay-black"
                }`}
              >
                <span className={activeSection === section.id ? "text-matcha-600" : "text-silver"}>{section.icon}</span>
                {section.label}
              </button>
            ))}
          </div>

          {/* Content */}
          <div className="flex-1 overflow-y-auto px-6 py-5">
            {activeSection === "themes" && (
              <div className="space-y-5">
                {!showThemeBuilder && (
                  <ThemeGrid
                    presets={theme.presets}
                    customThemes={theme.customThemes}
                    activeThemeId={theme.activeThemeId}
                    onSelect={theme.setThemeId}
                    onCreateCustom={() => {
                      setEditingCustomTheme(null);
                      setShowThemeBuilder(true);
                    }}
                    onEditCustom={(customTheme) => {
                      setEditingCustomTheme(customTheme);
                      setShowThemeBuilder(true);
                    }}
                    onDeleteCustom={theme.deleteCustomTheme}
                  />
                )}
                {showThemeBuilder && (
                  <ThemeBuilder
                    initialBaseId={
                      editingCustomTheme?.baseId ??
                      resolvePresetBaseId(
                        theme.activeThemeId,
                        theme.customThemes,
                        theme.presets,
                      )
                    }
                    existing={editingCustomTheme ?? undefined}
                    presets={theme.presets}
                    onSave={async (built) => {
                      await theme.saveCustomTheme(built);
                      theme.setThemeId(built.id);
                      closeThemeBuilder();
                    }}
                    onCancel={closeThemeBuilder}
                  />
                )}
              </div>
            )}

            {activeSection === "reader" && (
              <div className="space-y-6">
                <div>
                  <p className="clay-label mb-2">Translate to</p>
                  <select
                    value={settings.translateTo}
                    onChange={(e) => update({ translateTo: e.target.value })}
                    className="w-full px-3 py-2 text-sm rounded-[8px] border border-oat bg-clay-white text-clay-black"
                  >
                    <option value="en">English</option>
                    <option value="es">Spanish</option>
                    <option value="fr">French</option>
                    <option value="de">German</option>
                    <option value="it">Italian</option>
                    <option value="pt">Portuguese</option>
                    <option value="hi">Hindi</option>
                    <option value="ja">Japanese</option>
                    <option value="zh">Chinese</option>
                    <option value="ar">Arabic</option>
                  </select>
                </div>

                <div className="border-t border-oat pt-5">
                  <p className="clay-label mb-3">Layout</p>
                  <div className="space-y-3">
                    <ToggleRow
                      label="Show left navigation rail"
                      description="Table of Contents, Library, Settings"
                      value={settings.showLeftRail}
                      onChange={() => update({ showLeftRail: !settings.showLeftRail })}
                    />
                    <ToggleRow
                      label="Show right tools rail"
                      description="AI, Highlights, Words, account"
                      value={settings.showRightRail}
                      onChange={() => update({ showRightRail: !settings.showRightRail })}
                    />
                  </div>
                </div>
              </div>
            )}

            {activeSection === "ai" && <ByokSettings />}

            {activeSection === "pdf" && (
              <div className="space-y-6">
                {/* View Mode */}
                <div>
                  <p className="clay-label mb-2">View Mode</p>
                  <div className="flex gap-2">
                    {VIEW_MODE_OPTIONS.map((mode) => (
                      <button
                        key={mode.id}
                        onClick={() => update({ pdfViewMode: mode.id })}
                        className={`flex-1 py-2 text-xs font-medium rounded-[8px] border transition-all ${
                          settings.pdfViewMode === mode.id
                            ? "border-clay-black clay-shadow"
                            : "border-oat hover:border-charcoal"
                        }`}
                      >
                        {mode.label}
                      </button>
                    ))}
                  </div>
                </div>

                {/* PDF tint override */}
                <div>
                  <ToggleRow
                    label="Override theme PDF tint"
                    description="Force a specific PDF tint regardless of the active theme"
                    value={isPdfTintOverrideEnabled}
                    onChange={() =>
                      update({
                        pdfTintOverride: isPdfTintOverrideEnabled ? null : "normal",
                      })
                    }
                  />
                  {isPdfTintOverrideEnabled && (
                    <div className="flex gap-2 mt-3">
                      {PDF_TINT_OPTIONS.map((tintOption) => (
                        <button
                          key={tintOption.id}
                          onClick={() => update({ pdfTintOverride: tintOption.id })}
                          className={`flex-1 py-2 text-xs font-medium rounded-[8px] border transition-all ${
                            settings.pdfTintOverride === tintOption.id
                              ? "border-clay-black clay-shadow"
                              : "border-oat hover:border-charcoal"
                          }`}
                        >
                          {tintOption.label}
                        </button>
                      ))}
                    </div>
                  )}
                </div>

                {/* Toggles */}
                <div className="space-y-4">
                  <ToggleRow
                    label="Thumbnail Strip"
                    description="Show page previews along the bottom"
                    value={settings.pdfShowThumbnailStrip}
                    onChange={() => update({ pdfShowThumbnailStrip: !settings.pdfShowThumbnailStrip })}
                  />
                </div>

                {/* Toolbar visibility */}
                <div className="border-t border-oat pt-5">
                  <p className="clay-label mb-3">Toolbar Controls</p>
                  <div className="space-y-3">
                    <ToggleRow
                      label="View Mode Picker"
                      description="Single / Scroll / Spread buttons"
                      value={settings.pdfShowViewMode}
                      onChange={() => update({ pdfShowViewMode: !settings.pdfShowViewMode })}
                    />
                    <ToggleRow
                      label="Page Navigation"
                      description="Previous / next buttons and page input"
                      value={settings.pdfShowPageNav}
                      onChange={() => update({ pdfShowPageNav: !settings.pdfShowPageNav })}
                    />
                    <ToggleRow
                      label="Color Mode"
                      description="Normal / Dark / Sepia buttons"
                      value={settings.pdfShowColorMode}
                      onChange={() => update({ pdfShowColorMode: !settings.pdfShowColorMode })}
                    />
                    <ToggleRow
                      label="Zoom Controls"
                      description="Zoom in / out / reset buttons"
                      value={settings.pdfShowZoom}
                      onChange={() => update({ pdfShowZoom: !settings.pdfShowZoom })}
                    />
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
