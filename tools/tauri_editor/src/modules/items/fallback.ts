import type { ItemWorkspacePayload } from "../../types";

export const fallbackWorkspace: ItemWorkspacePayload = {
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
  dataDirectory: "data/items",
  itemCount: 1,
  catalogs: {
    itemTypes: ["weapon", "armor", "consumable", "material", "misc", "accessory", "ammo"],
    rarities: ["common", "uncommon", "rare", "epic"],
    slots: ["head", "body", "hands", "legs", "feet", "back", "main_hand", "accessory"],
    subtypes: ["unarmed", "tool", "watch", "wood", "food", "healing"],
  },
  documents: [
    {
      documentKey: "1001",
      originalId: 1001,
      fileName: "1001.json",
      relativePath: "data/items/1001.json",
      item: {
        id: 1001,
        name: "拳头",
        description: "最基础的攻击方式",
        type: "weapon",
        subtype: "unarmed",
        rarity: "common",
        weight: 0,
        value: 0,
        stackable: false,
        max_stack: 1,
        icon_path: "res://assets/icons/weapons/fist.png",
        equippable: true,
        slot: "main_hand",
        level_requirement: 0,
        durability: -1,
        max_durability: -1,
        repairable: false,
        usable: false,
        weapon_data: {
          damage: 5,
          attack_speed: 1,
          range: 1,
          stamina_cost: 2,
          crit_chance: 0.05,
          crit_multiplier: 1.5,
        },
        armor_data: null,
        consumable_data: null,
        special_effects: [],
        attributes_bonus: {},
      },
      validation: [],
    },
  ],
};
