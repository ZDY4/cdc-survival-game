import { useEffect, useMemo, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { Badge } from "../../components/Badge";
import { NumberField, TextField } from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { getRequestedSettingsSection } from "../../lib/editorSurface";
import { invokeCommand, isTauriRuntime } from "../../lib/tauri";
import type { AiConnectionTestResult, AiSettings, EditorSettingsSection } from "../../types";
import { emitSettingsChanged, SETTINGS_OPEN_SECTION_EVENT } from "./settingsWindowing";

type SettingsWindowProps = {
  status: string;
  onStatusChange: (status: string) => void;
};

type SectionDefinition = {
  id: EditorSettingsSection;
  label: string;
  description: string;
};

const SECTIONS: SectionDefinition[] = [
  {
    id: "ai",
    label: "AI",
    description: "Provider, model, timeout, and connection checks.",
  },
];

const defaultAiSettings: AiSettings = {
  baseUrl: "https://api.openai.com/v1",
  model: "gpt-4.1-mini",
  apiKey: "",
  timeoutSec: 45,
  maxContextRecords: 24,
};

export function SettingsWindow({ status, onStatusChange }: SettingsWindowProps) {
  const [activeSection, setActiveSection] = useState<EditorSettingsSection>(() =>
    getRequestedSettingsSection(typeof window === "undefined" ? "" : window.location.search),
  );
  const [aiSettings, setAiSettings] = useState<AiSettings>(defaultAiSettings);
  const [busy, setBusy] = useState(false);
  const [aiStatus, setAiStatus] = useState("");

  useEffect(() => {
    void invokeCommand<AiSettings>("load_ai_settings").then(
      (settings) => {
        setAiSettings(settings);
        onStatusChange("Settings loaded.");
      },
      (error) => {
        onStatusChange(`Failed to load settings: ${String(error)}`);
      },
    );
  }, [onStatusChange]);

  useEffect(() => {
    if (!isTauriRuntime()) {
      return;
    }

    let unlisten: (() => void) | undefined;
    void getCurrentWindow()
      .listen<{ section?: string }>(SETTINGS_OPEN_SECTION_EVENT, (event) => {
        if (event.payload.section === "ai") {
          setActiveSection("ai");
          onStatusChange("Opened AI settings.");
        }
      })
      .then((dispose) => {
        unlisten = dispose;
      });

    return () => {
      unlisten?.();
    };
  }, [onStatusChange]);

  const activeSectionDefinition = useMemo(
    () => SECTIONS.find((section) => section.id === activeSection) ?? SECTIONS[0],
    [activeSection],
  );

  async function saveAiSettings() {
    setBusy(true);
    try {
      const saved = await invokeCommand<AiSettings>("save_ai_settings", {
        settings: aiSettings,
      });
      setAiSettings(saved);
      setAiStatus("AI settings saved.");
      onStatusChange("Saved AI provider settings.");
      await emitSettingsChanged("ai");
    } catch (error) {
      const message = `Failed to save AI settings: ${String(error)}`;
      setAiStatus(message);
      onStatusChange(message);
    } finally {
      setBusy(false);
    }
  }

  async function testAiSettings() {
    setBusy(true);
    try {
      const result = await invokeCommand<AiConnectionTestResult>("test_ai_provider", {
        settings: aiSettings,
      });
      const message = result.ok ? "Provider connection test passed." : result.error || "Provider connection test failed.";
      setAiStatus(message);
      onStatusChange(message);
    } catch (error) {
      const message = `Failed to test AI provider: ${String(error)}`;
      setAiStatus(message);
      onStatusChange(message);
    } finally {
      setBusy(false);
    }
  }

  async function closeSettingsWindow() {
    if (!isTauriRuntime()) {
      return;
    }

    try {
      await getCurrentWindow().close();
    } catch (error) {
      onStatusChange(`Failed to close settings window: ${String(error)}`);
    }
  }

  return (
    <div className="settings-window">
      <header className="settings-window-chrome">
        <div className="settings-window-drag" data-tauri-drag-region>
          <strong>Settings</strong>
          <span>{activeSectionDefinition.label}</span>
        </div>
        <div className="settings-window-controls">
          <button
            type="button"
            className="toolbar-button settings-window-control"
            aria-label="Close settings window"
            title="Close settings window"
            onClick={() => void closeSettingsWindow()}
          >
            X
          </button>
        </div>
      </header>

      <aside className="settings-sidebar">
        <nav className="settings-nav">
          {SECTIONS.map((section) => (
            <button
              key={section.id}
              type="button"
              className={`settings-nav-item ${section.id === activeSection ? "settings-nav-item-active" : ""}`}
              onClick={() => setActiveSection(section.id)}
            >
              <strong>{section.label}</strong>
              <span>{section.description}</span>
            </button>
          ))}
        </nav>

        <div className="settings-sidebar-status">
          <Badge tone="accent">{activeSectionDefinition.label}</Badge>
          <Badge tone="muted">{busy ? "busy" : "ready"}</Badge>
        </div>
      </aside>

      <main className="settings-main">
        <header className="settings-header">
          <div>
            <h2>{activeSectionDefinition.label}</h2>
          </div>
          <div className="workspace-meta">
            <div>
              <span className="meta-label">Status</span>
              <strong>{status}</strong>
            </div>
          </div>
        </header>

        <section className="settings-body">
          <PanelSection
            label="AI"
            title="Provider settings"
            summary={
              <div className="toolbar-summary">
                <Badge tone="accent">{aiSettings.model || "No model"}</Badge>
                <Badge tone="muted">{aiSettings.baseUrl || "No endpoint"}</Badge>
              </div>
            }
          >
            <div className="form-grid">
              <TextField
                label="Base URL"
                value={aiSettings.baseUrl}
                onChange={(value) => setAiSettings((current) => ({ ...current, baseUrl: value }))}
              />
              <TextField
                label="Model"
                value={aiSettings.model}
                onChange={(value) => setAiSettings((current) => ({ ...current, model: value }))}
              />
              <TextField
                label="API Key"
                value={aiSettings.apiKey}
                onChange={(value) => setAiSettings((current) => ({ ...current, apiKey: value }))}
              />
              <NumberField
                label="Timeout (sec)"
                value={aiSettings.timeoutSec}
                min={5}
                onChange={(value) =>
                  setAiSettings((current) => ({ ...current, timeoutSec: Math.max(5, value) }))
                }
              />
              <NumberField
                label="Max context records"
                value={aiSettings.maxContextRecords}
                min={6}
                onChange={(value) =>
                  setAiSettings((current) => ({
                    ...current,
                    maxContextRecords: Math.max(6, value),
                  }))
                }
              />
            </div>
            <div className="toolbar-actions">
              <button type="button" className="toolbar-button" onClick={() => void testAiSettings()} disabled={busy}>
                Test connection
              </button>
              <button type="button" className="toolbar-button toolbar-accent" onClick={() => void saveAiSettings()} disabled={busy}>
                Save settings
              </button>
            </div>
            {aiStatus ? <p className="field-hint">{aiStatus}</p> : null}
          </PanelSection>
        </section>
      </main>
    </div>
  );
}
