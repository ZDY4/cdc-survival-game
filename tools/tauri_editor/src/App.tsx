import { useEffect, useMemo, useState } from "react";
import { EditorShell } from "./components/EditorShell";
import { detectCurrentSurface } from "./lib/editorSurface";
import { openOrFocusMainEditor, openOrFocusNarrativeLab } from "./lib/editorWindows";
import { invokeCommand, isTauriRuntime } from "./lib/tauri";
import { useRegisterEditorMenuCommands } from "./menu/editorCommandRegistry";
import { useEditorMenuBridge } from "./menu/menuBridge";
import { EDITOR_MENU_COMMANDS } from "./menu/menuCommands";
import { DialogueWorkspace } from "./modules/dialogues/DialogueWorkspace";
import { fallbackDialogueWorkspace } from "./modules/dialogues/fallback";
import { fallbackWorkspace } from "./modules/items/fallback";
import { ItemWorkspace } from "./modules/items/ItemWorkspace";
import { MapEditorWindow } from "./modules/maps/MapEditorWindow";
import { MapLibraryWorkspace } from "./modules/maps/MapLibraryWorkspace";
import { fallbackMapWorkspace } from "./modules/maps/fallback";
import { fallbackNarrativeWorkspace } from "./modules/narrative/fallback";
import { NarrativeWorkspace } from "./modules/narrative/NarrativeWorkspace";
import { fallbackQuestWorkspace } from "./modules/quests/fallback";
import { QuestWorkspace } from "./modules/quests/QuestWorkspace";
import type {
  DialogueWorkspacePayload,
  ItemWorkspacePayload,
  MapWorkspacePayload,
  NarrativeAppSettings,
  NarrativeWorkspacePayload,
  QuestWorkspacePayload,
} from "./types";

const defaultNarrativeAppSettings: NarrativeAppSettings = {
  recentWorkspaces: [],
  lastWorkspace: null,
  connectedProjectRoot: null,
  recentProjectRoots: [],
  workspaceLayouts: {},
};

function App() {
  const surface = detectCurrentSurface();
  const [itemWorkspace, setItemWorkspace] = useState<ItemWorkspacePayload>(fallbackWorkspace);
  const [dialogueWorkspace, setDialogueWorkspace] = useState<DialogueWorkspacePayload>(
    fallbackDialogueWorkspace,
  );
  const [narrativeWorkspace, setNarrativeWorkspace] = useState<NarrativeWorkspacePayload>(
    fallbackNarrativeWorkspace,
  );
  const [narrativeAppSettings, setNarrativeAppSettings] = useState<NarrativeAppSettings>(
    defaultNarrativeAppSettings,
  );
  const [questWorkspace, setQuestWorkspace] = useState<QuestWorkspacePayload>(fallbackQuestWorkspace);
  const [mapWorkspace, setMapWorkspace] = useState<MapWorkspacePayload>(fallbackMapWorkspace);
  const [status, setStatus] = useState("Loading editor workspaces...");
  const [activeModule, setActiveModule] = useState(
    surface === "narrative-lab" ? "narrative" : "items",
  );
  const [canPersist, setCanPersist] = useState(false);
  const [sidebarVisible, setSidebarVisible] = useState(true);
  const [statusBarVisible, setStatusBarVisible] = useState(true);

  async function loadMainWorkspaces() {
    try {
      const [itemPayload, dialoguePayload, questPayload, mapPayload] = await Promise.all([
        invokeCommand<ItemWorkspacePayload>("load_item_workspace"),
        invokeCommand<DialogueWorkspacePayload>("load_dialogue_workspace"),
        invokeCommand<QuestWorkspacePayload>("load_quest_workspace"),
        invokeCommand<MapWorkspacePayload>("load_map_workspace"),
      ]);
      setItemWorkspace(itemPayload);
      setDialogueWorkspace(dialoguePayload);
      setQuestWorkspace(questPayload);
      setMapWorkspace(mapPayload);
      setCanPersist(true);
      setStatus(
        `Loaded ${itemPayload.itemCount} items, ${dialoguePayload.dialogCount} dialogues, ${questPayload.questCount} quests, and ${mapPayload.mapCount} maps from project data.`,
      );
    } catch (error) {
      setItemWorkspace(fallbackWorkspace);
      setDialogueWorkspace(fallbackDialogueWorkspace);
      setQuestWorkspace(fallbackQuestWorkspace);
      setMapWorkspace(fallbackMapWorkspace);
      setCanPersist(false);
      setStatus(
        `Running in fallback mode. ${String(error)}. Start the Tauri host to read project files.`,
      );
    }
  }

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
    if (surface === "map-editor") {
      return;
    }
    setActiveModule(surface === "narrative-lab" ? "narrative" : "items");
    if (surface === "narrative-lab") {
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
            return;
          }

          return invokeCommand<NarrativeWorkspacePayload>("load_narrative_workspace", {
            workspaceRoot: settings.lastWorkspace,
            projectRoot: settings.connectedProjectRoot ?? null,
          }).then((payload) => {
            setNarrativeWorkspace(payload);
            setStatus(`Loaded ${payload.documentCount} narrative docs from ${payload.workspaceRoot}.`);
          });
        })
        .catch((error) => {
          setCanPersist(false);
          setNarrativeAppSettings(defaultNarrativeAppSettings);
          setNarrativeWorkspace(fallbackNarrativeWorkspace);
          setStatus(
            `Running Narrative Lab in fallback mode. ${String(error)}. Start the Tauri host to read project files.`,
          );
        });
      return;
    }
    void loadMainWorkspaces();
  }, [surface]);

  useEditorMenuBridge(setStatus, surface !== "map-editor");

  const shellMenuCommands = useMemo(() => {
    if (surface === "map-editor") {
      return {};
    }

    return {
      [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_SIDEBAR]: {
        execute: () => {
          setSidebarVisible((current) => !current);
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_STATUS_BAR]: {
        execute: () => {
          setStatusBarVisible((current) => !current);
        },
      },
      [EDITOR_MENU_COMMANDS.MODULE_ITEMS]: {
        execute: async () => {
          if (surface === "narrative-lab") {
            await openOrFocusMainEditor(EDITOR_MENU_COMMANDS.MODULE_ITEMS);
            return;
          }
          setActiveModule("items");
          setStatus("Switched to Items.");
        },
      },
      [EDITOR_MENU_COMMANDS.MODULE_DIALOGUES]: {
        execute: async () => {
          if (surface === "narrative-lab") {
            await openOrFocusMainEditor(EDITOR_MENU_COMMANDS.MODULE_DIALOGUES);
            return;
          }
          setActiveModule("dialogues");
          setStatus("Switched to Dialogues.");
        },
      },
      [EDITOR_MENU_COMMANDS.MODULE_QUESTS]: {
        execute: async () => {
          if (surface === "narrative-lab") {
            await openOrFocusMainEditor(EDITOR_MENU_COMMANDS.MODULE_QUESTS);
            return;
          }
          setActiveModule("quests");
          setStatus("Switched to Quests.");
        },
      },
      [EDITOR_MENU_COMMANDS.MODULE_MAPS]: {
        execute: async () => {
          if (surface === "narrative-lab") {
            await openOrFocusMainEditor(EDITOR_MENU_COMMANDS.MODULE_MAPS);
            return;
          }
          setActiveModule("maps");
          setStatus("Switched to Maps.");
        },
      },
      [EDITOR_MENU_COMMANDS.MODULE_NARRATIVE]: {
        execute: async () => {
          if (surface === "narrative-lab") {
            setStatus("Narrative Lab is already active.");
            return;
          }
          await openOrFocusNarrativeLab();
          setStatus("Opened Narrative Lab.");
        },
      },
    };
  }, [surface]);

  useRegisterEditorMenuCommands(shellMenuCommands);

  if (surface === "map-editor") {
    return <MapEditorWindow />;
  }

  if (surface === "narrative-lab") {
    return (
      <EditorShell
        title="Narrative Lab"
        subtitle="Markdown-first writing studio for outlines, scenes, branches, reviews, and AI-assisted revision."
        bootstrap={narrativeWorkspace.bootstrap}
        modules={[{ id: "narrative", label: "Narrative Lab", state: "active" as const }]}
        activeModule="narrative"
        onModuleChange={() => {}}
        status={status}
        primaryMetaLabel="Workspace"
        secondaryMetaLabel="Project"
        primaryMetaValue={narrativeWorkspace.workspaceRoot || "No workspace selected"}
        secondaryMetaValue={
          narrativeWorkspace.connectedProjectRoot || narrativeAppSettings.connectedProjectRoot || "Not connected"
        }
        runtimeLabel={isTauriRuntime() && canPersist ? "Tauri host connected" : "UI fallback mode"}
        shellMode="narrative"
        brandEyebrow="Narrative Studio"
        topbarEyebrow="Workbench"
        topbarHeadline="Write, review, and iterate on narrative documents in a dedicated standalone workspace."
        showSidebar={sidebarVisible}
        showStatusBar={statusBarVisible}
      >
        <NarrativeWorkspace
          workspace={narrativeWorkspace}
          appSettings={narrativeAppSettings}
          canPersist={canPersist}
          onStatusChange={setStatus}
          onReload={loadNarrativeWorkspaceOnly}
          onOpenWorkspace={openNarrativeWorkspace}
          onConnectProject={connectNarrativeProject}
          onSaveAppSettings={saveNarrativeSettings}
        />
      </EditorShell>
    );
  }

  const modules = [
    { id: "items", label: "Items", state: "active" as const },
    { id: "dialogues", label: "Dialogues", state: "active" as const },
    { id: "quests", label: "Quests", state: "active" as const },
    { id: "maps", label: "Maps", state: "active" as const },
  ];

  return (
    <EditorShell
      title={itemWorkspace.bootstrap.appName}
      subtitle="Standalone content editor for the Bevy + Godot + Tauri migration path."
      bootstrap={itemWorkspace.bootstrap}
      modules={modules}
      activeModule={activeModule}
      onModuleChange={setActiveModule}
      status={status}
      runtimeLabel={isTauriRuntime() && canPersist ? "Tauri host connected" : "UI fallback mode"}
      showSidebar={sidebarVisible}
      showStatusBar={statusBarVisible}
    >
      {activeModule === "items" ? (
        <ItemWorkspace
          workspace={itemWorkspace}
          canPersist={canPersist}
          onStatusChange={setStatus}
          onReload={loadMainWorkspaces}
        />
      ) : null}
      {activeModule === "dialogues" ? (
        <DialogueWorkspace
          workspace={dialogueWorkspace}
          canPersist={canPersist}
          onStatusChange={setStatus}
          onReload={loadMainWorkspaces}
        />
      ) : null}
      {activeModule === "quests" ? (
        <QuestWorkspace
          workspace={questWorkspace}
          canPersist={canPersist}
          onStatusChange={setStatus}
          onReload={loadMainWorkspaces}
        />
      ) : null}
      {activeModule === "maps" ? (
        <MapLibraryWorkspace
          workspace={mapWorkspace}
          canPersist={canPersist}
          onStatusChange={setStatus}
          onReload={loadMainWorkspaces}
        />
      ) : null}
    </EditorShell>
  );
}

export default App;
