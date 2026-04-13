import { useEffect, useRef, useState } from "react";
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

function normalizeNarrativeAppSettings(
  settings: NarrativeAppSettings,
): NarrativeAppSettings {
  return {
    ...settings,
    sessionRestoreMode: "always",
  };
}

function mergeNarrativeAppSettings(
  current: NarrativeAppSettings,
  next: NarrativeAppSettings,
): NarrativeAppSettings {
  return {
    ...current,
    ...next,
    workspaceLayouts: {
      ...(current.workspaceLayouts ?? {}),
      ...(next.workspaceLayouts ?? {}),
    },
    workspaceAgentSessions: {
      ...(current.workspaceAgentSessions ?? {}),
      ...(next.workspaceAgentSessions ?? {}),
    },
  };
}

const defaultNarrativeAppSettings: NarrativeAppSettings = {
  recentWorkspaces: [],
  lastWorkspace: null,
  connectedProjectRoot: null,
  recentProjectRoots: [],
  sessionRestoreMode: "always",
  workspaceLayouts: {},
  workspaceAgentSessions: {},
};

const defaultEditorRuntimeFlags: EditorRuntimeFlags = {
  menuSelfTestScenario: null,
  chatRegressionMode: null,
  autoCloseAfterSelfTest: false,
};

function App() {
  const surface = detectCurrentSurface();
  const [narrativeWorkspace, setNarrativeWorkspace] = useState<NarrativeWorkspacePayload>(
    fallbackNarrativeWorkspace,
  );
  const [narrativeAppSettings, setNarrativeAppSettings] = useState<NarrativeAppSettings>(
    defaultNarrativeAppSettings,
  );
  const narrativeAppSettingsRef = useRef<NarrativeAppSettings>(defaultNarrativeAppSettings);
  const narrativeSettingsSaveQueueRef = useRef(Promise.resolve());
  const [editorRuntimeFlags, setEditorRuntimeFlags] =
    useState<EditorRuntimeFlags>(defaultEditorRuntimeFlags);
  const [status, setStatus] = useState("正在加载叙事实验室...");
  const [canPersist, setCanPersist] = useState(false);
  const [narrativeStartupReady, setNarrativeStartupReady] = useState(surface === "settings");

  useEffect(() => {
    narrativeAppSettingsRef.current = narrativeAppSettings;
  }, [narrativeAppSettings]);

  async function loadNarrativeWorkspaceOnly() {
    const workspaceRoot = narrativeAppSettings.lastWorkspace?.trim();
    if (!workspaceRoot) {
      setNarrativeWorkspace({
        ...fallbackNarrativeWorkspace,
        connectedProjectRoot: narrativeAppSettings.connectedProjectRoot ?? null,
        projectContextStatus: "选择或创建一个工作区后即可开始使用叙事实验室。",
      });
      setStatus("请选择或创建一个叙事工作区后开始使用。");
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
      setStatus(`已从 ${narrativePayload.workspaceRoot} 加载 ${narrativePayload.documentCount} 份叙事文档。`);
    } catch (error) {
      setNarrativeWorkspace(fallbackNarrativeWorkspace);
      setCanPersist(false);
      setStatus(`叙事实验室正在以回退模式运行。${String(error)}。请启动 Tauri 宿主以读取项目文件。`);
    }
  }

  async function refreshNarrativeSessionFromSettings() {
    const settings = normalizeNarrativeAppSettings(
      await invokeCommand<NarrativeAppSettings>("load_narrative_app_settings"),
    );
    setNarrativeAppSettings(settings);
    setCanPersist(true);

    const workspaceRoot = settings.lastWorkspace?.trim();
    if (!workspaceRoot) {
      setNarrativeWorkspace({
        ...fallbackNarrativeWorkspace,
        connectedProjectRoot: settings.connectedProjectRoot ?? null,
        projectContextStatus: "选择或创建一个工作区后即可开始使用叙事实验室。",
      });
      setStatus("请选择或创建一个叙事工作区后开始使用。");
      return;
    }

    const payload = await invokeCommand<NarrativeWorkspacePayload>("load_narrative_workspace", {
      workspaceRoot,
      projectRoot: settings.connectedProjectRoot ?? null,
    });
    setNarrativeWorkspace(payload);
    setStatus(`已从 ${payload.workspaceRoot} 加载 ${payload.documentCount} 份叙事文档。`);
  }

  async function saveNarrativeSettings(nextSettings: NarrativeAppSettings) {
    const queuedSave = narrativeSettingsSaveQueueRef.current
      .catch(() => undefined)
      .then(async () => {
        const merged = normalizeNarrativeAppSettings(
          mergeNarrativeAppSettings(narrativeAppSettingsRef.current, nextSettings),
        );
        const saved = await invokeCommand<NarrativeAppSettings>("save_narrative_app_settings", {
          settings: merged,
        });
        const normalized = normalizeNarrativeAppSettings(saved);
        narrativeAppSettingsRef.current = normalized;
        setNarrativeAppSettings(normalized);
        return normalized;
      });

    narrativeSettingsSaveQueueRef.current = queuedSave.then(
      () => undefined,
      () => undefined,
    );
    return queuedSave;
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
      setStatus(`已从 ${payload.workspaceRoot} 加载 ${payload.documentCount} 份叙事文档。`);
    } catch (error) {
      setStatus(`打开叙事工作区失败：${String(error)}`);
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
          ? "已保存项目上下文路径。打开工作区后即可激活。"
          : "已断开项目上下文连接。",
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
      setStatus(`刷新项目上下文失败：${String(error)}`);
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
      setStatus("设置已就绪。");
      setNarrativeStartupReady(true);
      return;
    }

    setNarrativeStartupReady(false);
    void invokeCommand<NarrativeAppSettings>("load_narrative_app_settings")
      .then((loadedSettings) => {
        const settings = normalizeNarrativeAppSettings(loadedSettings);
        setNarrativeAppSettings(settings);
        setCanPersist(true);
        if (!settings.lastWorkspace?.trim()) {
          setNarrativeWorkspace({
            ...fallbackNarrativeWorkspace,
            connectedProjectRoot: settings.connectedProjectRoot ?? null,
            projectContextStatus: "选择或创建一个工作区后即可开始使用叙事实验室。",
          });
          setStatus("请选择或创建一个叙事工作区后开始使用。");
          setNarrativeStartupReady(true);
          return;
        }

        return invokeCommand<NarrativeWorkspacePayload>("load_narrative_workspace", {
          workspaceRoot: settings.lastWorkspace,
          projectRoot: settings.connectedProjectRoot ?? null,
        }).then((payload) => {
          setNarrativeWorkspace(payload);
          setStatus(`已从 ${payload.workspaceRoot} 加载 ${payload.documentCount} 份叙事文档。`);
          setNarrativeStartupReady(true);
        });
      })
      .catch((error) => {
        setCanPersist(false);
        setNarrativeAppSettings(defaultNarrativeAppSettings);
        setNarrativeWorkspace(fallbackNarrativeWorkspace);
        setStatus(`叙事实验室正在以回退模式运行。${String(error)}。请启动 Tauri 宿主以读取项目文件。`);
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
          setStatus(`刷新叙事实验室设置失败：${String(error)}`);
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
    return (
      <div className="narrative-lab-app narrative-lab-app-settings">
        <SettingsWindow status={status} onStatusChange={setStatus} />
      </div>
    );
  }

  return (
    <div className="narrative-lab-app narrative-lab-app-workspace">
      <NarrativeWorkspace
        workspace={narrativeWorkspace}
        appSettings={narrativeAppSettings}
        canPersist={canPersist}
        startupReady={narrativeStartupReady}
        selfTestScenario={editorRuntimeFlags.menuSelfTestScenario ?? null}
        chatRegressionMode={editorRuntimeFlags.chatRegressionMode ?? null}
        autoCloseAfterSelfTest={editorRuntimeFlags.autoCloseAfterSelfTest ?? false}
        status={status}
        onStatusChange={setStatus}
        onReload={loadNarrativeWorkspaceOnly}
        onOpenWorkspace={openNarrativeWorkspace}
        onConnectProject={connectNarrativeProject}
        onSaveAppSettings={saveNarrativeSettings}
      />
    </div>
  );
}

export default App;
