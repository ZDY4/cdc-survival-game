import type { OverworldWorkspacePayload } from "../../types";

export const fallbackOverworldWorkspace: OverworldWorkspacePayload = {
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
  dataDirectory: "data/overworld",
  overworldCount: 1,
  catalogs: {
    mapIds: ["survivor_outpost_01_grid", "street_a_grid", "survivor_outpost_01_interior_grid"],
    locationKinds: ["outdoor", "interior", "dungeon"],
    terrainKinds: ["road", "street", "ruins"],
    mapEntryPointsByMap: {
      survivor_outpost_01_grid: ["default_entry", "perimeter_return"],
      street_a_grid: ["default_entry"],
      survivor_outpost_01_interior_grid: ["default_entry", "outdoor_return"],
    },
  },
  documents: [
    {
      documentKey: "main_overworld",
      originalId: "main_overworld",
      fileName: "main_overworld.json",
      relativePath: "data/overworld/main_overworld.json",
      overworld: {
        id: "main_overworld",
        locations: [
          {
            id: "survivor_outpost_01",
            name: "幸存者据点01",
            description: "世界地图入口样例",
            kind: "outdoor",
            map_id: "survivor_outpost_01_grid",
            entry_point_id: "default_entry",
            parent_outdoor_location_id: null,
            return_entry_point_id: null,
            default_unlocked: true,
            visible: true,
            overworld_cell: { x: 0, y: 0, z: 0 },
            danger_level: 0,
            icon: "res://assets/icons/location_safehouse.png",
          },
          {
            id: "survivor_outpost_01_interior",
            name: "幸存者据点01室内",
            description: "室内入口样例",
            kind: "interior",
            map_id: "survivor_outpost_01_interior_grid",
            entry_point_id: "default_entry",
            parent_outdoor_location_id: "survivor_outpost_01",
            return_entry_point_id: "outdoor_return",
            default_unlocked: true,
            visible: false,
            overworld_cell: { x: 0, y: 0, z: 0 },
            danger_level: 0,
            icon: "res://assets/icons/location_safehouse.png",
          },
        ],
        walkable_cells: [
          { grid: { x: 0, y: 0, z: 0 }, terrain: "road" },
          { grid: { x: 1, y: 0, z: 0 }, terrain: "road" },
          { grid: { x: 2, y: 0, z: 0 }, terrain: "street" },
        ],
        travel_rules: {
          food_item_id: "1007",
          night_minutes_multiplier: 1.2,
          risk_multiplier: 1,
        },
      },
      validation: [],
    },
  ],
};
