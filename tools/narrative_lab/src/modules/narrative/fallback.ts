import type { NarrativeWorkspacePayload } from "../../types";
import { NARRATIVE_DOC_TYPES } from "./narrativeTemplates";

export const fallbackNarrativeWorkspace: NarrativeWorkspacePayload = {
  bootstrap: {
    appName: "CDC Narrative Lab",
    workspaceRoot: "No workspace selected",
    sharedRustPath: "Not connected",
    activeStage: "Phase 1: Narrative Authoring",
    stages: [
      {
        id: "phase-1",
        title: "Phase 1: Narrative Authoring",
        description:
          "Create markdown-first planning docs for tasks, locations, characters, monsters, and items.",
      },
      {
        id: "phase-2",
        title: "Phase 2: Structuring Handoff",
        description: "Prepare approved narrative docs for later breakdown into structured game content.",
      },
      {
        id: "phase-3",
        title: "Phase 3: Project Integration",
        description: "Optionally connect a game project to enrich AI context with story and runtime data.",
      },
    ],
    editorDomains: [
      "Narrative planning and review",
      "Task, location, character, monster, and item drafting",
      "Worldbuilding and background reference writing",
      "Structuring bundle export",
    ],
  },
  dataDirectory: "",
  documentCount: 0,
  docTypes: NARRATIVE_DOC_TYPES,
  documents: [],
  workspaceRoot: "",
  workspaceName: "",
  connectedProjectRoot: null,
  projectContextStatus: "未选择工作区。",
};
