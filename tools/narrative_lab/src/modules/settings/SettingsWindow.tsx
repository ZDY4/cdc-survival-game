import { useEffect, useMemo, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { Badge } from "../../components/Badge";
import { NumberField, TextField } from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { getRequestedSettingsSection } from "../../lib/editorSurface";
import { invokeCommand, isTauriRuntime } from "../../lib/tauri";
import type {
  AiConnectionTestResult,
  AiSettings,
  CloudWorkspaceMeta,
  EditorSettingsSection,
  NarrativeAppSettings,
  NarrativeSessionRestoreMode,
  NarrativeSyncSettings,
} from "../../types";
import {
  emitSettingsChanged,
  SETTINGS_OPEN_SECTION_EVENT,
} from "./settingsWindowing";

type SettingsWindowProps = {
  status: string;
  onStatusChange: (status: string) => void;
};

type SectionDefinition = {
  id: EditorSettingsSection;
  label: string;
  description: string;
};

type CompactSelectItem = {
  id: string;
  title: string;
  detail: string;
  badge?: string;
  tone?: "muted" | "accent" | "warning" | "success";
  active?: boolean;
  onSelect: () => void;
};

const SECTIONS: SectionDefinition[] = [
  {
    id: "ai",
    label: "AI",
    description: "Provider, model, timeout, and connection checks.",
  },
  {
    id: "narrative-sync",
    label: "Narrative Sync",
    description: "Cloud sync, workspace binding, and mobile handoff settings.",
  },
  {
    id: "workspace",
    label: "Workspace / Project",
    description: "Narrative workspace root and connected project context.",
  },
];

const defaultAiSettings: AiSettings = {
  baseUrl: "https://api.openai.com/v1",
  model: "gpt-4.1-mini",
  apiKey: "",
  timeoutSec: 45,
  maxContextRecords: 24,
};

const defaultSyncSettings: NarrativeSyncSettings = {
  serverUrl: "",
  authToken: "",
  workspaceId: "",
  deviceLabel: "desktop-local",
  lastSyncAt: null,
  lastSyncStatus: "",
};

const defaultNarrativeAppSettings: NarrativeAppSettings = {
  recentWorkspaces: [],
  lastWorkspace: null,
  connectedProjectRoot: null,
  recentProjectRoots: [],
  sessionRestoreMode: "ask",
  workspaceLayouts: {},
  workspaceAgentSessions: {},
};

const SESSION_RESTORE_OPTIONS: Array<{
  id: NarrativeSessionRestoreMode;
  label: string;
  description: string;
}> = [
  {
    id: "ask",
    label: "每次询问",
    description: "启动工作区时提示恢复上次 agent 会话或只恢复文档。",
  },
  {
    id: "always",
    label: "自动恢复",
    description: "进入工作区后直接恢复最近保存的 Narrative Lab 会话。",
  },
  {
    id: "documents_only",
    label: "仅恢复文档",
    description: "保留工作区文档状态，但默认不恢复 agent 上下文。",
  },
];

function compactPathLabel(path: string): string {
  const normalized = path.replace(/\\/g, "/");
  const parts = normalized.split("/").filter(Boolean);
  if (parts.length === 0) {
    return path;
  }
  return parts.length === 1 ? parts[0] : parts.slice(-2).join(" / ");
}

function CompactSelectList({
  label,
  items,
  emptyMessage,
}: {
  label: string;
  items: CompactSelectItem[];
  emptyMessage: string;
}) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      {items.length > 0 ? (
        <div className="settings-link-list">
          {items.map((item) => (
            <button
              key={item.id}
              type="button"
              className={`settings-link-item ${item.active ? "settings-link-item-active" : ""}`}
              onClick={item.onSelect}
            >
              <div className="settings-link-copy">
                <strong>{item.title}</strong>
                <span>{item.detail}</span>
              </div>
              {item.badge ? <Badge tone={item.tone ?? "muted"}>{item.badge}</Badge> : null}
            </button>
          ))}
        </div>
      ) : (
        <div className="workspace-empty settings-empty-inline">
          <p>{emptyMessage}</p>
        </div>
      )}
    </label>
  );
}

export function SettingsWindow({ status, onStatusChange }: SettingsWindowProps) {
  const [activeSection, setActiveSection] = useState<EditorSettingsSection>(() =>
    getRequestedSettingsSection(typeof window === "undefined" ? "" : window.location.search),
  );
  const [aiSettings, setAiSettings] = useState<AiSettings>(defaultAiSettings);
  const [syncSettings, setSyncSettings] = useState<NarrativeSyncSettings>(defaultSyncSettings);
  const [appSettings, setAppSettings] = useState<NarrativeAppSettings>(defaultNarrativeAppSettings);
  const [cloudWorkspaces, setCloudWorkspaces] = useState<CloudWorkspaceMeta[]>([]);
  const [cloudWorkspaceName, setCloudWorkspaceName] = useState("");
  const [busy, setBusy] = useState(false);
  const [aiStatus, setAiStatus] = useState("");
  const [syncStatus, setSyncStatus] = useState("");
  const [workspaceStatus, setWorkspaceStatus] = useState("");

  useEffect(() => {
    void Promise.all([
      invokeCommand<AiSettings>("load_ai_settings").then(setAiSettings),
      invokeCommand<NarrativeSyncSettings>("load_narrative_sync_settings").then(setSyncSettings),
      invokeCommand<NarrativeAppSettings>("load_narrative_app_settings").then(setAppSettings),
    ]).then(
      () => {
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
        const next = event.payload.section;
        if (next === "ai" || next === "narrative-sync" || next === "workspace") {
          setActiveSection(next);
          onStatusChange(`Opened ${SECTIONS.find((section) => section.id === next)?.label ?? next} settings.`);
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
  const cloudWorkspaceItems = useMemo<CompactSelectItem[]>(
    () =>
      cloudWorkspaces.map((entry) => ({
        id: entry.workspaceId,
        title: entry.name,
        detail: entry.workspaceId,
        badge: syncSettings.workspaceId === entry.workspaceId ? "current" : undefined,
        tone: "accent",
        active: syncSettings.workspaceId === entry.workspaceId,
        onSelect: () => {
          setSyncSettings((current) => ({ ...current, workspaceId: entry.workspaceId }));
          const message = `Selected cloud workspace ${entry.name}.`;
          setSyncStatus(message);
          onStatusChange(message);
        },
      })),
    [cloudWorkspaces, onStatusChange, syncSettings.workspaceId],
  );
  const recentWorkspaceItems = useMemo<CompactSelectItem[]>(
    () =>
      appSettings.recentWorkspaces.map((path) => ({
        id: `workspace:${path}`,
        title: compactPathLabel(path),
        detail: path,
        badge: appSettings.lastWorkspace === path ? "current" : undefined,
        tone: "accent",
        active: appSettings.lastWorkspace === path,
        onSelect: () => {
          setAppSettings((current) => ({ ...current, lastWorkspace: path }));
          const message = `Prepared workspace root ${path}.`;
          setWorkspaceStatus(message);
          onStatusChange(message);
        },
      })),
    [appSettings.lastWorkspace, appSettings.recentWorkspaces, onStatusChange],
  );
  const recentProjectItems = useMemo<CompactSelectItem[]>(
    () =>
      appSettings.recentProjectRoots.map((path) => ({
        id: `project:${path}`,
        title: compactPathLabel(path),
        detail: path,
        badge: appSettings.connectedProjectRoot === path ? "current" : undefined,
        tone: "accent",
        active: appSettings.connectedProjectRoot === path,
        onSelect: () => {
          setAppSettings((current) => ({ ...current, connectedProjectRoot: path }));
          const message = `Prepared project root ${path}.`;
          setWorkspaceStatus(message);
          onStatusChange(message);
        },
      })),
    [appSettings.connectedProjectRoot, appSettings.recentProjectRoots, onStatusChange],
  );
  const persistedSessionCount = useMemo(
    () =>
      Object.values(appSettings.workspaceAgentSessions ?? {}).reduce((count, state) => {
        if (!state || typeof state !== "object" || !("sessions" in state)) {
          return count;
        }
        const sessions = (state as { sessions?: Record<string, unknown> }).sessions ?? {};
        return count + Object.keys(sessions).length;
      }, 0),
    [appSettings.workspaceAgentSessions],
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

  async function saveSyncSettings() {
    setBusy(true);
    try {
      const saved = await invokeCommand<NarrativeSyncSettings>("save_narrative_sync_settings", {
        settings: syncSettings,
      });
      setSyncSettings(saved);
      setSyncStatus("Narrative Sync settings saved.");
      onStatusChange("Saved Narrative Sync settings.");
      await emitSettingsChanged("narrative-sync");
    } catch (error) {
      const message = `Failed to save sync settings: ${String(error)}`;
      setSyncStatus(message);
      onStatusChange(message);
    } finally {
      setBusy(false);
    }
  }

  async function refreshCloudWorkspaces() {
    setBusy(true);
    try {
      const result = await invokeCommand<CloudWorkspaceMeta[]>("list_cloud_workspaces");
      setCloudWorkspaces(result);
      const message = `Loaded ${result.length} cloud workspaces.`;
      setSyncStatus(message);
      onStatusChange(message);
    } catch (error) {
      const message = `Failed to load cloud workspaces: ${String(error)}`;
      setSyncStatus(message);
      onStatusChange(message);
    } finally {
      setBusy(false);
    }
  }

  async function createCloudWorkspace() {
    if (!cloudWorkspaceName.trim()) {
      const message = "Enter a cloud workspace name first.";
      setSyncStatus(message);
      onStatusChange(message);
      return;
    }

    setBusy(true);
    try {
      const created = await invokeCommand<CloudWorkspaceMeta>("create_cloud_workspace", {
        input: { name: cloudWorkspaceName.trim() },
      });
      setCloudWorkspaces((current) => [
        created,
        ...current.filter((workspace) => workspace.workspaceId !== created.workspaceId),
      ]);
      setSyncSettings((current) => ({
        ...current,
        workspaceId: created.workspaceId,
      }));
      setCloudWorkspaceName("");
      const message = `Created cloud workspace ${created.name}.`;
      setSyncStatus(message);
      onStatusChange(message);
    } catch (error) {
      const message = `Failed to create cloud workspace: ${String(error)}`;
      setSyncStatus(message);
      onStatusChange(message);
    } finally {
      setBusy(false);
    }
  }

  async function saveWorkspaceSettings() {
    setBusy(true);
    try {
      const saved = await invokeCommand<NarrativeAppSettings>("save_narrative_app_settings", {
        settings: {
          ...appSettings,
          lastWorkspace: appSettings.lastWorkspace?.trim() || null,
          connectedProjectRoot: appSettings.connectedProjectRoot?.trim() || null,
        },
      });
      setAppSettings(saved);
      setWorkspaceStatus("Workspace settings saved.");
      onStatusChange("Saved workspace and project settings.");
      await emitSettingsChanged("workspace");
    } catch (error) {
      const message = `Failed to save workspace settings: ${String(error)}`;
      setWorkspaceStatus(message);
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
          {activeSection === "ai" ? (
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
          ) : null}

          {activeSection === "narrative-sync" ? (
            <>
              <PanelSection
                label="Narrative Sync"
                title="Cloud sync and mobile handoff"
                summary={
                  <div className="toolbar-summary">
                    <Badge tone="accent">{syncSettings.workspaceId || "No workspace ID"}</Badge>
                    <Badge tone="muted">{syncSettings.deviceLabel || "desktop-local"}</Badge>
                  </div>
                }
              >
                <div className="form-grid">
                  <TextField
                    label="Server URL"
                    value={syncSettings.serverUrl}
                    onChange={(value) => setSyncSettings((current) => ({ ...current, serverUrl: value }))}
                    placeholder="http://127.0.0.1:4852"
                  />
                  <TextField
                    label="Auth token"
                    value={syncSettings.authToken}
                    onChange={(value) => setSyncSettings((current) => ({ ...current, authToken: value }))}
                  />
                  <TextField
                    label="Workspace ID"
                    value={syncSettings.workspaceId}
                    onChange={(value) => setSyncSettings((current) => ({ ...current, workspaceId: value }))}
                  />
                  <TextField
                    label="Device label"
                    value={syncSettings.deviceLabel}
                    onChange={(value) => setSyncSettings((current) => ({ ...current, deviceLabel: value }))}
                  />
                </div>
                <div className="toolbar-actions">
                  <button type="button" className="toolbar-button" onClick={() => void refreshCloudWorkspaces()} disabled={busy}>
                    Refresh cloud workspaces
                  </button>
                  <button type="button" className="toolbar-button toolbar-accent" onClick={() => void saveSyncSettings()} disabled={busy}>
                    Save sync settings
                  </button>
                </div>
                {syncStatus ? <p className="field-hint">{syncStatus}</p> : null}
              </PanelSection>

              <PanelSection
                label="Cloud"
                title="Workspace binding"
                summary={
                  <div className="toolbar-summary">
                    <Badge tone="muted">{cloudWorkspaces.length} known</Badge>
                    <Badge tone="muted">{syncSettings.lastSyncStatus || "No recent sync"}</Badge>
                  </div>
                }
              >
                <div className="form-grid">
                  <TextField
                    label="Create cloud workspace"
                    value={cloudWorkspaceName}
                    onChange={setCloudWorkspaceName}
                    placeholder="My Narrative Cloud"
                  />
                </div>
                <div className="toolbar-actions">
                  <button type="button" className="toolbar-button" onClick={() => void createCloudWorkspace()} disabled={busy || !cloudWorkspaceName.trim()}>
                    Create workspace
                  </button>
                </div>
                <CompactSelectList
                  label="Known cloud workspaces"
                  items={cloudWorkspaceItems}
                  emptyMessage="No cloud workspaces loaded yet."
                />
              </PanelSection>
            </>
          ) : null}

          {activeSection === "workspace" ? (
            <PanelSection
              label="Workspace"
              title="Narrative workspace and project context"
              summary={
                <div className="toolbar-summary">
                  <Badge tone="accent">{appSettings.lastWorkspace || "No workspace"}</Badge>
                  <Badge tone="muted">{appSettings.connectedProjectRoot || "No project"}</Badge>
                </div>
              }
            >
              <div className="form-grid">
                <TextField
                  label="Workspace root"
                  value={appSettings.lastWorkspace ?? ""}
                  onChange={(value) =>
                    setAppSettings((current) => ({
                      ...current,
                      lastWorkspace: value,
                    }))
                  }
                  placeholder="D:/Projects/.../narrative_workspace"
                />
                <TextField
                  label="Connected project root"
                  value={appSettings.connectedProjectRoot ?? ""}
                  onChange={(value) =>
                    setAppSettings((current) => ({
                      ...current,
                      connectedProjectRoot: value,
                    }))
                  }
                  placeholder="D:/Projects/.../cdc-survival-game"
                />
              </div>
              <label className="field">
                <span className="field-label">Session restore</span>
                <div className="segmented-control" style={{ flexWrap: "wrap" }}>
                  {SESSION_RESTORE_OPTIONS.map((option) => (
                    <button
                      key={option.id}
                      type="button"
                      className={`segmented-control-item ${
                        (appSettings.sessionRestoreMode ?? "ask") === option.id
                          ? "segmented-control-item-active"
                          : ""
                      }`.trim()}
                      onClick={() =>
                        setAppSettings((current) => ({
                          ...current,
                          sessionRestoreMode: option.id,
                        }))
                      }
                    >
                      {option.label}
                    </button>
                  ))}
                </div>
                <span className="field-hint">
                  {
                    SESSION_RESTORE_OPTIONS.find(
                      (option) => option.id === (appSettings.sessionRestoreMode ?? "ask"),
                    )?.description
                  }
                </span>
              </label>
              <div className="toolbar-actions">
                <button
                  type="button"
                  className="toolbar-button"
                  onClick={() =>
                    setAppSettings((current) => ({
                      ...current,
                      connectedProjectRoot: null,
                    }))
                  }
                  disabled={busy}
                >
                  Clear project binding
                </button>
                <button type="button" className="toolbar-button toolbar-accent" onClick={() => void saveWorkspaceSettings()} disabled={busy}>
                  Save workspace settings
                </button>
              </div>
              {workspaceStatus ? <p className="field-hint">{workspaceStatus}</p> : null}
              <div className="toolbar-summary">
                <Badge tone="muted">{`已保存会话 ${persistedSessionCount}`}</Badge>
                <Badge tone="muted">{appSettings.sessionRestoreMode ?? "ask"}</Badge>
              </div>
              <CompactSelectList
                label="Recent workspaces"
                items={recentWorkspaceItems}
                emptyMessage="No workspace history yet."
              />
              <CompactSelectList
                label="Recent project roots"
                items={recentProjectItems}
                emptyMessage="No project bindings recorded yet."
              />
            </PanelSection>
          ) : null}
        </section>
      </main>
    </div>
  );
}
