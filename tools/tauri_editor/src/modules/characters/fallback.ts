import type { CharacterWorkspacePayload } from "../../types";

export const fallbackCharacterWorkspace: CharacterWorkspacePayload = {
  bootstrap: {
    appName: "CDC Content Editor",
    workspaceRoot: "../../",
    sharedRustPath: "../../rust",
    activeStage: "Phase 1: Rust Foundation",
    stages: [
      {
        id: "phase-1",
        title: "Phase 1: Rust Foundation",
        description:
          "Build shared data models, protocol definitions, and validation before large runtime rewrites.",
      },
      {
        id: "phase-2",
        title: "Phase 2: Bevy Logic Service",
        description:
          "Move service-friendly gameplay logic into Bevy and connect clients over IPC or TCP.",
      },
      {
        id: "phase-3",
        title: "Phase 3: Editor Independence",
        description:
          "Replace Godot plugin editing flows with standalone editor modules incrementally.",
      },
    ],
    editorDomains: [
      "Items and recipes",
      "Dialogue and quest flows",
      "Multi-layer map authoring",
      "Import, export, and validation tools",
    ],
  },
  dataDirectory: "data/characters",
  characterCount: 0,
  catalogs: {
    settlementIds: [],
    roles: [],
    behaviorProfileIds: [],
    personalityProfileIds: [],
    scheduleProfileIds: [],
    needProfileIds: [],
    smartObjectAccessProfileIds: [],
  },
  references: {
    settlements: [],
    behaviors: [],
    schedules: [],
    personalities: [],
    needs: [],
    smartObjectAccess: [],
  },
  documents: [],
  warnings: ["Tauri host unavailable. Character preview is running in fallback mode."],
};
