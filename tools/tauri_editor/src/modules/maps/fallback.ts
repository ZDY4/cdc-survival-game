import type { MapWorkspacePayload } from "../../types";

export const fallbackMapWorkspace: MapWorkspacePayload = {
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
  dataDirectory: "data/maps",
  mapCount: 1,
  catalogs: {
    itemIds: ["1005", "1007", "1010"],
    characterIds: ["player", "trader_lao_wang", "zombie_walker"],
    buildingPrefabs: ["survivor_outpost_01_dormitory", "survivor_outpost_01_gatehouse"],
    interactiveKinds: ["enter_outdoor_location", "enter_subscene"],
  },
  documents: [
    {
      documentKey: "survivor_outpost_01_grid",
      originalId: "survivor_outpost_01_grid",
      fileName: "survivor_outpost_01_grid.json",
      relativePath: "data/maps/survivor_outpost_01_grid.json",
      map: {
        id: "survivor_outpost_01_grid",
        name: "Survivor Outpost 01 Grid",
        size: {
          width: 32,
          height: 32,
        },
        default_level: 0,
        levels: [
          {
            y: 0,
            cells: [],
          },
        ],
        entry_points: [
          {
            id: "default_entry",
            grid: { x: 15, y: 0, z: 29 },
            facing: null,
          },
          {
            id: "perimeter_return",
            grid: { x: 15, y: 0, z: 27 },
            facing: null,
          },
        ],
        objects: [
          {
            object_id: "survivor_outpost_01_dormitory",
            kind: "building",
            anchor: { x: 6, y: 0, z: 6 },
            footprint: { width: 6, height: 5 },
            rotation: "north",
            blocks_movement: true,
            blocks_sight: true,
            props: {
              building: {
                prefab_id: "survivor_outpost_01_dormitory",
              },
            },
          },
          {
            object_id: "survivor_outpost_01_perimeter_gate",
            kind: "interactive",
            anchor: { x: 15, y: 0, z: 28 },
            footprint: { width: 1, height: 1 },
            rotation: "north",
            blocks_movement: false,
            blocks_sight: false,
            props: {
              interactive: {
                display_name: "前往警戒区",
                interaction_distance: 1.4,
                interaction_kind: "enter_outdoor_location",
                target_id: "survivor_outpost_01_perimeter",
                options: [],
              },
            },
          },
        ],
      },
      validation: [],
    },
  ],
};
