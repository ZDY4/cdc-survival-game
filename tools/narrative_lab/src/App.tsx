import { useEffect, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { detectCurrentSurface } from "./lib/editorSurface";
import { invokeCommand, isTauriRuntime } from "./lib/tauri";
import { useEditorMenuBridge } from "./menu/menuBridge";
import { fallbackNarrativeWorkspace } from "./modules/narrative/fallback";
import { NarrativeWorkspace } from "./modules/narrative/NarrativeWorkspace";
import { SETTINGS_CHANGED_EVENT } from "./modules/settings/settingsWindowing";
import { SettingsWindow } from "./modules/settings/SettingsWindow";
import type {
  EditorRuntimeFlags,
  NarrativeAppSettings,
  NarrativeWorkspacePayload,
} from "./types";

const defaultNarrativeAppSettings: NarrativeAppSettings = {
  recentWorkspaces: [],
  lastWorkspace: null,
  connectedProjectRoot: null,
  recentProjectRoots: [],
  workspaceLayouts: {},
};

const defaultEditorRuntimeFlags: EditorRuntimeFlags = {
  menuSelfTestScenario: null,
};

function App() {
  const surface = detectCurrentSurface();
  const [narrativeWorkspace, setNarrativeWorkspace] = useState<NarrativeWorkspacePayload>(
    fallbackNarrativeWorkspace,
  );
  const [narrativeAppSettings, setNarrativeAppSettings] = useState<NarrativeAppSettings>(
    defaultNarrativeAppSettings,
  );
  const [editorRuntimeFlags, setEditorRuntimeFlags] =
    useState<EditorRuntimeFlags>(defaultEditorRuntimeFlags);
  const [status, setStatus] = useState("Loading Narrative Lab...");
  const [canPersist, setCanPersist] = useState(false);
  const [narrativeStartupReady, setNarrativeStartupReady] = useState(surface === "settings");

  async function loadNarrativeWorkspaceOnly() {
    const workspaceRoot = narrativeAppSettings.lastWorkspace?.trim();
    if (!workspaceRoot) {
      setNarrativeWorkspace({
        ...fallbackNarrativeWorkspace,
        connectedProjectRoot: narrativeAppSettings.connectedProjectRoot ?? null,
        projectContextStatus: "选择或创建一个工作区后即可开始使用 Narrative Lab。",
      });
      setStatus("Choose or create a narrative workspace to get started.");
      return;
    }

    try {
      const narrativePayload = await invokeCommand<NarrativeWorkspacePayload>(
        "load_narrative_workspace",
        {
          workspaceRoot,
          projectRoot: narrativeAppSettings.connectedProjectRoot ?? null,
        },
      );
      setNarrativeWorkspace(narrativePayload);
      setCanPersist(true);
      setStatus(
        `Loaded ${narrativePayload.documentCount} narrative docs from ${narrativePayload.workspaceRoot}.`,
      );
    } catch (error) {
      setNarrativeWorkspace(fallbackNarrativeWorkspace);
      setCanPersist(false);
      setStatus(
        `Running Narrative Lab in fallback mode. ${String(error)}. Start the Tauri host to read project files.`,
      );
    }
  }

  async function refreshNarrativeSessionFromSettings() {
    const settings = await invokeCommand<NarrativeAppSettings>("load_narrative_app_settings");
    setNarrativeAppSettings(settings);
    setCanPersist(true);

    const workspaceRoot = settings.lastWorkspace?.trim();
    if (!workspaceRoot) {
      setNarrativeWorkspace({
        ...fallbackNarrativeWorkspace,
        connectedProjectRoot: settings.connectedProjectRoot ?? null,
        projectContextStatus: "选择或创建一个工作区后即可开始使用 Narrative Lab。",
      });
      setStatus("Choose or create a narrative workspace to get started.");
      return;
    }

    const payload = await invokeCommand<NarrativeWorkspacePayload>("load_narrative_workspace", {
      workspaceRoot,
      projectRoot: settings.connectedProjectRoot ?? null,
    });
    setNarrativeWorkspace(payload);
    setStatus(`Loaded ${payload.documentCount} narrative docs from ${payload.workspaceRoot}.`);
  }

  async function saveNarrativeSettings(nextSettings: NarrativeAppSettings) {
    const saved = await invokeCommand<NarrativeAppSettings>("save_narrative_app_settings", {
      settings: nextSettings,
    });
    setNarrativeAppSettings(saved);
    return saved;
  }

  async function openNarrativeWorkspace(workspaceRoot: string) {
    const saved = await saveNarrativeSettings({
      ...narrativeAppSettings,
      lastWorkspace: workspaceRoot,
    });
    try {
      const payload = await invokeCommand<NarrativeWorkspacePayload>("load_narrative_workspace", {
        workspaceRoot: saved.lastWorkspace,
        projectRoot: saved.connectedProjectRoot ?? null,
      });
      setNarrativeWorkspace(payload);
      setCanPersist(true);
      setStatus(`Loaded ${payload.documentCount} narrative docs from ${payload.workspaceRoot}.`);
    } catch (error) {
      setStatus(`Failed to open narrative workspace: ${String(error)}`);
    }
  }

  async function connectNarrativeProject(projectRoot: string | null) {
    const saved = await saveNarrativeSettings({
      ...narrativeAppSettings,
      connectedProjectRoot: projectRoot,
    });
    if (!saved.lastWorkspace?.trim()) {
      setNarrativeWorkspace((current) => ({
        ...current,
        connectedProjectRoot: saved.connectedProjectRoot ?? null,
        projectContextStatus: saved.connectedProjectRoot
          ? "已记录项目路径；打开工作区后会尝试加载项目上下文。"
          : "未连接项目，将只使用 narrative 文稿与模板上下文。",
      }));
      setStatus(
        saved.connectedProjectRoot
          ? "Saved project context path. Open a workspace to activate it."
          : "Disconnected project context.",
      );
      return;
    }

    try {
      const payload = await invokeCommand<NarrativeWorkspacePayload>("load_narrative_workspace", {
        workspaceRoot: saved.lastWorkspace,
        projectRoot: saved.connectedProjectRoot ?? null,
      });
      setNarrativeWorkspace(payload);
      setStatus(payload.projectContextStatus);
    } catch (error) {
      setStatus(`Failed to refresh project context: ${String(error)}`);
    }
  }

  useEffect(() => {
    if (!isTauriRuntime()) {
      return;
    }

    void invokeCommand<EditorRuntimeFlags>("get_editor_runtime_flags")
      .then(setEditorRuntimeFlags)
      .catch(() => {
        setEditorRuntimeFlags(defaultEditorRuntimeFlags);
      });
  }, []);

  useEffect(() => {
    if (surface === "settings") {
      setStatus("Settings ready.");
      setNarrativeStartupReady(true);
      return;
    }

    setNarrativeStartupReady(false);
    void invokeCommand<NarrativeAppSettings>("load_narrative_app_settings")
      .then((settings) => {
        setNarrativeAppSettings(settings);
        setCanPersist(true);
        if (!settings.lastWorkspace?.trim()) {
          setNarrativeWorkspace({
            ...fallbackNarrativeWorkspace,
            connectedProjectRoot: settings.connectedProjectRoot ?? null,
            projectContextStatus: "选择或创建一个工作区后即可开始使用 Narrative Lab。",
          });
          setStatus("Choose or create a narrative workspace to get started.");
          setNarrativeStartupReady(true);
          return;
        }

        return invokeCommand<NarrativeWorkspacePayload>("load_narrative_workspace", {
          workspaceRoot: settings.lastWorkspace,
          projectRoot: settings.connectedProjectRoot ?? null,
        }).then((payload) => {
          setNarrativeWorkspace(payload);
          setStatus(`Loaded ${payload.documentCount} narrative docs from ${payload.workspaceRoot}.`);
          setNarrativeStartupReady(true);
        });
      })
      .catch((error) => {
        setCanPersist(false);
        setNarrativeAppSettings(defaultNarrativeAppSettings);
        setNarrativeWorkspace(fallbackNarrativeWorkspace);
        setStatus(
          `Running Narrative Lab in fallback mode. ${String(error)}. Start the Tauri host to read project files.`,
        );
        setNarrativeStartupReady(true);
      });
  }, [surface]);

  useEffect(() => {
    if (!isTauriRuntime() || surface === "settings") {
      return;
    }

    let unlisten: (() => void) | undefined;
    void getCurrentWindow()
      .listen<{ section?: string }>(SETTINGS_CHANGED_EVENT, (event) => {
        if (event.payload.section !== "workspace") {
          return;
        }
        void refreshNarrativeSessionFromSettings().catch((error) => {
          setStatus(`Failed to refresh Narrative Lab settings: ${String(error)}`);
        });
      })
      .then((dispose) => {
        unlisten = dispose;
      });

    return () => {
      unlisten?.();
    };
  }, [surface]);

  useEditorMenuBridge(setStatus, true);

  if (surface === "settings") {
    return <SettingsWindow status={status} onStatusChange={setStatus} />;
  }

  return (
    <NarrativeWorkspace
      workspace={narrativeWorkspace}
      appSettings={narrativeAppSettings}
      canPersist={canPersist}
      startupReady={narrativeStartupReady}
      selfTestScenario={editorRuntimeFlags.menuSelfTestScenario ?? null}
      status={status}
      runtimeLabel={isTauriRuntime() && canPersist ? "Tauri host connected" : "UI fallback mode"}
      onStatusChange={setStatus}
      onReload={loadNarrativeWorkspaceOnly}
      onOpenWorkspace={openNarrativeWorkspace}
      onConnectProject={connectNarrativeProject}
      onSaveAppSettings={saveNarrativeSettings}
    />
  );
}

export default App;
