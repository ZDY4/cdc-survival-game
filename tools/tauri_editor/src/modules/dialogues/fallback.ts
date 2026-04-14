import type { DialogueWorkspacePayload } from "../../types";

export const fallbackDialogueWorkspace: DialogueWorkspacePayload = {
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
          "Replace legacy plugin editing flows with standalone editor modules incrementally.",
      },
    ],
    editorDomains: [
      "Items and recipes",
      "Dialogue and quest flows",
      "Multi-layer map authoring",
      "Import, export, and validation tools",
    ],
  },
  dataDirectory: "data/dialogues",
  dialogCount: 1,
  catalogs: {
    nodeTypes: ["dialog", "choice", "condition", "action", "end"],
  },
  documents: [
    {
      documentKey: "trader_lao_wang",
      originalId: "trader_lao_wang",
      fileName: "trader_lao_wang.json",
      relativePath: "data/dialogues/trader_lao_wang.json",
      dialog: {
        dialog_id: "trader_lao_wang",
        nodes: [
          {
            id: "start",
            type: "dialog",
            title: "Start",
            speaker: "老王",
            text: "要看看货吗？今天刚整理出一批还算像样的物资。",
            is_start: true,
            next: "choice_1",
          },
          {
            id: "choice_1",
            type: "choice",
            options: [
              { text: "交易", next: "trade_action" },
              { text: "离开", next: "leave_end" },
            ],
          },
        ],
        connections: [],
      },
      validation: [],
    },
  ],
};
