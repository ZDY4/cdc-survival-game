import type { QuestWorkspacePayload } from "../../types";

export const fallbackQuestWorkspace: QuestWorkspacePayload = {
  bootstrap: {
    appName: "CDC Content Editor",
    workspaceRoot: "D:/Projects/cdc-survival-game",
    sharedRustPath: "D:/Projects/cdc-survival-game/rust",
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
        description: "Introduce the Bevy logic service and move suitable gameplay systems behind IPC or TCP.",
      },
      {
        id: "phase-3",
        title: "Phase 3: Editor Independence",
        description: "Migrate content workflows from the Godot plugin into this standalone editor incrementally.",
      },
    ],
    editorDomains: [
      "Items and recipes",
      "Dialogue and quest flows",
      "Multi-layer map authoring",
      "Import, export, and validation tools",
    ],
  },
  dataDirectory: "data/quests",
  questCount: 1,
  catalogs: {
    nodeTypes: ["start", "objective", "dialog", "choice", "reward", "end"],
    objectiveTypes: ["travel", "search", "collect", "kill", "sleep", "survive", "craft", "build"],
    itemIds: ["1007", "1008"],
    dialogIds: ["trader_lao_wang"],
    questIds: ["find_food"],
    locationIds: ["supermarket", "hospital"],
    recipeIds: [],
  },
  documents: [
    {
      documentKey: "find_food",
      originalId: "find_food",
      fileName: "find_food.json",
      relativePath: "data/quests/find_food.json",
      quest: {
        quest_id: "find_food",
        title: "Food Shortage",
        description: "Travel to the market and bring food back.",
        prerequisites: [],
        time_limit: -1,
        flow: {
          start_node_id: "start",
          nodes: {
            start: {
              id: "start",
              type: "start",
              title: "Start",
              position: { x: 160, y: 160 },
            },
            objective_1: {
              id: "objective_1",
              type: "objective",
              title: "Travel",
              description: "Reach the supermarket",
              objective_type: "travel",
              target: "supermarket",
              count: 1,
              position: { x: 420, y: 160 },
            },
            reward_1: {
              id: "reward_1",
              type: "reward",
              title: "Reward",
              rewards: {
                items: [{ id: 1008, count: 2 }],
                experience: 200,
                skill_points: 1,
                unlock_location: "",
                unlock_recipes: [],
                title: "",
              },
              position: { x: 700, y: 160 },
            },
            end: {
              id: "end",
              type: "end",
              title: "End",
              position: { x: 960, y: 160 },
            },
          },
          connections: [
            { from: "start", from_port: 0, to: "objective_1", to_port: 0 },
            { from: "objective_1", from_port: 0, to: "reward_1", to_port: 0 },
            { from: "reward_1", from_port: 0, to: "end", to_port: 0 },
          ],
        },
        _editor: {
          relationship_position: { x: 180, y: 140 },
        },
      },
      validation: [],
    },
  ],
};
