import { useEffect, useMemo, useState } from "react";
import { EditorShell } from "./components/EditorShell";
import { detectCurrentSurface } from "./lib/editorSurface";
import { openOrFocusSettingsWindow } from "./lib/editorWindows";
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
import { fallbackQuestWorkspace } from "./modules/quests/fallback";
import { QuestWorkspace } from "./modules/quests/QuestWorkspace";
import { SettingsWindow } from "./modules/settings/SettingsWindow";
import type {
  DialogueWorkspacePayload,
  ItemWorkspacePayload,
  MapWorkspacePayload,
  QuestWorkspacePayload,
} from "./types";

function App() {
  const surface = detectCurrentSurface();
  const [itemWorkspace, setItemWorkspace] = useState<ItemWorkspacePayload>(fallbackWorkspace);
  const [dialogueWorkspace, setDialogueWorkspace] = useState<DialogueWorkspacePayload>(
    fallbackDialogueWorkspace,
  );
  const [questWorkspace, setQuestWorkspace] = useState<QuestWorkspacePayload>(fallbackQuestWorkspace);
  const [mapWorkspace, setMapWorkspace] = useState<MapWorkspacePayload>(fallbackMapWorkspace);
  const [status, setStatus] = useState("Loading editor workspaces...");
  const [activeModule, setActiveModule] = useState("items");
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

  useEffect(() => {
    if (surface === "map-editor") {
      return;
    }
    if (surface === "settings") {
      setStatus("Settings ready.");
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
          setActiveModule("items");
          setStatus("Switched to Items.");
        },
      },
      [EDITOR_MENU_COMMANDS.MODULE_DIALOGUES]: {
        execute: async () => {
          setActiveModule("dialogues");
          setStatus("Switched to Dialogues.");
        },
      },
      [EDITOR_MENU_COMMANDS.MODULE_QUESTS]: {
        execute: async () => {
          setActiveModule("quests");
          setStatus("Switched to Quests.");
        },
      },
      [EDITOR_MENU_COMMANDS.MODULE_MAPS]: {
        execute: async () => {
          setActiveModule("maps");
          setStatus("Switched to Maps.");
        },
      },
      [EDITOR_MENU_COMMANDS.AI_OPEN_PROVIDER_SETTINGS]: {
        execute: async () => {
          await openOrFocusSettingsWindow("ai");
          setStatus("Opened AI provider settings.");
        },
      },
      [EDITOR_MENU_COMMANDS.AI_TEST_PROVIDER_CONNECTION]: {
        execute: async () => {
          await openOrFocusSettingsWindow("ai");
          setStatus("Opened AI settings to test provider connection.");
        },
      },
    };
  }, [surface]);

  useRegisterEditorMenuCommands(shellMenuCommands);

  if (surface === "map-editor") {
    return <MapEditorWindow />;
  }

  if (surface === "settings") {
    return <SettingsWindow status={status} onStatusChange={setStatus} />;
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
