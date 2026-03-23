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
    buildingPrefabs: ["safehouse_house", "safehouse_upper_room"],
    interactiveKinds: ["enter_outdoor_location", "enter_subscene"],
  },
  documents: [
    {
      documentKey: "safehouse_grid",
      originalId: "safehouse_grid",
      fileName: "safehouse_grid.json",
      relativePath: "data/maps/safehouse_grid.json",
      map: {
        id: "safehouse_grid",
        name: "Safehouse Grid",
        size: {
          width: 12,
          height: 12,
        },
        default_level: 0,
        levels: [
          {
            y: 0,
            cells: [],
          },
          {
            y: 1,
            cells: [],
          },
        ],
        objects: [
          {
            object_id: "safehouse_building_ground",
            kind: "building",
            anchor: { x: 7, y: 0, z: 4 },
            footprint: { width: 3, height: 2 },
            rotation: "north",
            blocks_movement: true,
            blocks_sight: true,
            props: {
              building: {
                prefab_id: "safehouse_house",
              },
            },
          },
          {
            object_id: "safehouse_spawn_zombie",
            kind: "ai_spawn",
            anchor: { x: 10, y: 0, z: 2 },
            footprint: { width: 1, height: 1 },
            rotation: "north",
            blocks_movement: false,
            blocks_sight: false,
            props: {
              ai_spawn: {
                spawn_id: "safehouse_enemy_spawn",
                character_id: "zombie_walker",
                auto_spawn: true,
                respawn_enabled: true,
                respawn_delay: 20,
                spawn_radius: 2,
              },
            },
          },
        ],
      },
      validation: [],
    },
  ],
};
