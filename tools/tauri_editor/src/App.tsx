import { useEffect, useState } from "react";
import { EditorShell } from "./components/EditorShell";
import { invokeCommand, isTauriRuntime } from "./lib/tauri";
import { DialogueWorkspace } from "./modules/dialogues/DialogueWorkspace";
import { fallbackDialogueWorkspace } from "./modules/dialogues/fallback";
import { fallbackWorkspace } from "./modules/items/fallback";
import { ItemWorkspace } from "./modules/items/ItemWorkspace";
import type { DialogueWorkspacePayload, ItemWorkspacePayload } from "./types";

function App() {
  const [itemWorkspace, setItemWorkspace] = useState<ItemWorkspacePayload>(fallbackWorkspace);
  const [dialogueWorkspace, setDialogueWorkspace] = useState<DialogueWorkspacePayload>(
    fallbackDialogueWorkspace,
  );
  const [status, setStatus] = useState("Loading editor workspaces...");
  const [activeModule, setActiveModule] = useState("items");
  const [canPersist, setCanPersist] = useState(false);

  async function loadAllWorkspaces() {
    try {
      const [itemPayload, dialoguePayload] = await Promise.all([
        invokeCommand<ItemWorkspacePayload>("load_item_workspace"),
        invokeCommand<DialogueWorkspacePayload>("load_dialogue_workspace"),
      ]);
      setItemWorkspace(itemPayload);
      setDialogueWorkspace(dialoguePayload);
      setCanPersist(true);
      setStatus(
        `Loaded ${itemPayload.itemCount} items and ${dialoguePayload.dialogCount} dialogues from project data.`,
      );
    } catch (error) {
      setItemWorkspace(fallbackWorkspace);
      setDialogueWorkspace(fallbackDialogueWorkspace);
      setCanPersist(false);
      setStatus(
        `Running in fallback mode. ${String(error)}. Start the Tauri host to read project files.`,
      );
    }
  }

  useEffect(() => {
    void loadAllWorkspaces();
  }, []);

  const modules = [
    { id: "items", label: "Items", state: "active" as const },
    { id: "dialogues", label: "Dialogues", state: "active" as const },
    { id: "quests", label: "Quests", state: "planned" as const },
    { id: "maps", label: "Maps", state: "planned" as const },
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
    >
      {activeModule === "items" ? (
        <ItemWorkspace
          workspace={itemWorkspace}
          canPersist={canPersist}
          onStatusChange={setStatus}
          onReload={loadAllWorkspaces}
        />
      ) : null}
      {activeModule === "dialogues" ? (
        <DialogueWorkspace
          workspace={dialogueWorkspace}
          canPersist={canPersist}
          onStatusChange={setStatus}
          onReload={loadAllWorkspaces}
        />
      ) : null}
    </EditorShell>
  );
}

export default App;
