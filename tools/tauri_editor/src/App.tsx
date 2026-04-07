import { getCurrentWindow } from "@tauri-apps/api/window";
import { useEffect, useMemo, useRef, useState } from "react";
import { DataEditorShell } from "./components/DataEditorShell";
import { detectCurrentSurface } from "./lib/editorSurface";
import {
  getConfiguredStartupSurface,
  openOrFocusEditorWindow,
  openOrFocusModuleEditor,
  openOrFocusSettingsWindow,
} from "./lib/editorWindows";
import { isModuleEditorSurface } from "./lib/editorSurfaces";
import { invokeCommand, isTauriRuntime } from "./lib/tauri";
import { useRegisterEditorMenuCommands } from "./menu/editorCommandRegistry";
import { useEditorMenuBridge } from "./menu/menuBridge";
import { EDITOR_MENU_COMMANDS } from "./menu/menuCommands";
import { DialogueWorkspace } from "./modules/dialogues/DialogueWorkspace";
import { fallbackDialogueWorkspace } from "./modules/dialogues/fallback";
import { CharacterWorkspace } from "./modules/characters/CharacterWorkspace";
import { fallbackCharacterWorkspace } from "./modules/characters/fallback";
import { fallbackWorkspace } from "./modules/items/fallback";
import { ItemWorkspace } from "./modules/items/ItemWorkspace";
import { fallbackQuestWorkspace } from "./modules/quests/fallback";
import { QuestWorkspace } from "./modules/quests/QuestWorkspace";
import { SettingsWindow } from "./modules/settings/SettingsWindow";
import type {
  DialogueWorkspacePayload,
  CharacterWorkspacePayload,
  ItemWorkspacePayload,
  QuestWorkspacePayload,
} from "./types";

function App() {
  const surface = detectCurrentSurface();
  const [itemWorkspace, setItemWorkspace] = useState<ItemWorkspacePayload>(fallbackWorkspace);
  const [characterWorkspace, setCharacterWorkspace] =
    useState<CharacterWorkspacePayload>(fallbackCharacterWorkspace);
  const [dialogueWorkspace, setDialogueWorkspace] = useState<DialogueWorkspacePayload>(
    fallbackDialogueWorkspace,
  );
  const [questWorkspace, setQuestWorkspace] = useState<QuestWorkspacePayload>(fallbackQuestWorkspace);
  const [status, setStatus] = useState("Loading editor workspace...");
  const [canPersist, setCanPersist] = useState(false);
  const [sidebarVisible, setSidebarVisible] = useState(true);
  const [statusBarVisible, setStatusBarVisible] = useState(true);
  const bootstrapStartedRef = useRef(false);

  async function loadItemWorkspace() {
    try {
      const payload = await invokeCommand<ItemWorkspacePayload>("load_item_workspace");
      setItemWorkspace(payload);
      setCanPersist(true);
      setStatus(`Loaded ${payload.itemCount} items from project data.`);
    } catch (error) {
      setItemWorkspace(fallbackWorkspace);
      setCanPersist(false);
      setStatus(`Running in fallback mode. ${String(error)}. Start the Tauri host to read project files.`);
    }
  }

  async function loadDialogueWorkspace() {
    try {
      const payload = await invokeCommand<DialogueWorkspacePayload>("load_dialogue_workspace");
      setDialogueWorkspace(payload);
      setCanPersist(true);
      setStatus(`Loaded ${payload.dialogCount} dialogues from project data.`);
    } catch (error) {
      setDialogueWorkspace(fallbackDialogueWorkspace);
      setCanPersist(false);
      setStatus(`Running in fallback mode. ${String(error)}. Start the Tauri host to read project files.`);
    }
  }

  async function loadCharacterWorkspace() {
    try {
      const payload = await invokeCommand<CharacterWorkspacePayload>("load_character_workspace");
      setCharacterWorkspace(payload);
      setCanPersist(true);
      setStatus(`Loaded ${payload.characterCount} characters from project data.`);
    } catch (error) {
      setCharacterWorkspace(fallbackCharacterWorkspace);
      setCanPersist(false);
      setStatus(`Running in fallback mode. ${String(error)}. Start the Tauri host to read project files.`);
    }
  }

  async function loadQuestWorkspace() {
    try {
      const payload = await invokeCommand<QuestWorkspacePayload>("load_quest_workspace");
      setQuestWorkspace(payload);
      setCanPersist(true);
      setStatus(`Loaded ${payload.questCount} quests from project data.`);
    } catch (error) {
      setQuestWorkspace(fallbackQuestWorkspace);
      setCanPersist(false);
      setStatus(`Running in fallback mode. ${String(error)}. Start the Tauri host to read project files.`);
    }
  }

  useEffect(() => {
    if (surface === "settings") {
      setStatus("Settings ready.");
      return;
    }

    if (surface === "main") {
      if (bootstrapStartedRef.current) {
        return;
      }
      bootstrapStartedRef.current = true;
      const startupSurface = getConfiguredStartupSurface(
        import.meta.env.VITE_EDITOR_START_SURFACE as string | undefined,
      );
      setStatus(`Opening ${startupSurface} editor...`);
      void openOrFocusEditorWindow(startupSurface)
        .then(async () => {
          if (isTauriRuntime()) {
            await getCurrentWindow().close();
          }
        })
        .catch((error) => {
          setStatus(`Failed to open ${startupSurface} editor: ${String(error)}`);
        });
      return;
    }

    switch (surface) {
      case "items":
        void loadItemWorkspace();
        break;
      case "characters":
        void loadCharacterWorkspace();
        break;
      case "dialogues":
        void loadDialogueWorkspace();
        break;
      case "quests":
        void loadQuestWorkspace();
        break;
      default:
        break;
    }
  }, [surface]);

  useEditorMenuBridge(setStatus, isModuleEditorSurface(surface));

  const shellMenuCommands = useMemo(() => {
    if (!isModuleEditorSurface(surface)) {
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
          await openOrFocusModuleEditor(EDITOR_MENU_COMMANDS.MODULE_ITEMS);
          setStatus("Opened Items editor.");
        },
      },
      [EDITOR_MENU_COMMANDS.MODULE_CHARACTERS]: {
        execute: async () => {
          await openOrFocusModuleEditor(EDITOR_MENU_COMMANDS.MODULE_CHARACTERS);
          setStatus("Opened Character editor.");
        },
      },
      [EDITOR_MENU_COMMANDS.MODULE_DIALOGUES]: {
        execute: async () => {
          await openOrFocusModuleEditor(EDITOR_MENU_COMMANDS.MODULE_DIALOGUES);
          setStatus("Opened Dialogues editor.");
        },
      },
      [EDITOR_MENU_COMMANDS.MODULE_QUESTS]: {
        execute: async () => {
          await openOrFocusModuleEditor(EDITOR_MENU_COMMANDS.MODULE_QUESTS);
          setStatus("Opened Quests editor.");
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

  if (surface === "main") {
    return null;
  }

  if (surface === "settings") {
    return <SettingsWindow status={status} onStatusChange={setStatus} />;
  }

  const runtimeLabel = isTauriRuntime() && canPersist ? "Tauri host connected" : "UI fallback mode";

  if (surface === "items") {
    return (
      <DataEditorShell
        title="Items"
        subtitle="Item definitions and validation."
        bootstrap={itemWorkspace.bootstrap}
        status={status}
        runtimeLabel={runtimeLabel}
        showStatusBar={statusBarVisible}
      >
        <ItemWorkspace
          workspace={itemWorkspace}
          canPersist={canPersist}
          onStatusChange={setStatus}
          onReload={loadItemWorkspace}
          indexVisible={sidebarVisible}
        />
      </DataEditorShell>
    );
  }

  if (surface === "characters") {
    return (
      <DataEditorShell
        title="Characters"
        subtitle="Character definitions, life bindings, and AI preview."
        bootstrap={characterWorkspace.bootstrap}
        status={status}
        runtimeLabel={runtimeLabel}
        shellClassName="data-editor-shell-characters"
        showHeader={false}
        showStatusBar={statusBarVisible}
      >
        <CharacterWorkspace
          workspace={characterWorkspace}
          canPersist={canPersist}
          onStatusChange={setStatus}
          indexVisible={sidebarVisible}
        />
      </DataEditorShell>
    );
  }

  if (surface === "dialogues") {
    return (
      <DataEditorShell
        title="Dialogues"
        subtitle="Dialogue graphs, node editing, and validation."
        bootstrap={dialogueWorkspace.bootstrap}
        status={status}
        runtimeLabel={runtimeLabel}
        showStatusBar={statusBarVisible}
      >
        <DialogueWorkspace
          workspace={dialogueWorkspace}
          canPersist={canPersist}
          onStatusChange={setStatus}
          onReload={loadDialogueWorkspace}
          indexVisible={sidebarVisible}
        />
      </DataEditorShell>
    );
  }

  if (surface === "quests") {
    return (
      <DataEditorShell
        title="Quests"
        subtitle="Quest relationships, flow editing, and rewards."
        bootstrap={questWorkspace.bootstrap}
        status={status}
        runtimeLabel={runtimeLabel}
        showStatusBar={statusBarVisible}
      >
        <QuestWorkspace
          workspace={questWorkspace}
          canPersist={canPersist}
          onStatusChange={setStatus}
          onReload={loadQuestWorkspace}
          indexVisible={sidebarVisible}
        />
      </DataEditorShell>
    );
  }

  return null;
}

export default App;
