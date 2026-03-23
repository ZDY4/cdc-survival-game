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
    fragmentKinds: [
      "economy",
      "stacking",
      "equip",
      "durability",
      "attribute_modifiers",
      "weapon",
      "usable",
      "crafting",
      "passive_effects",
    ],
    effectIds: ["consume_health_50"],
    effectEntries: [
      {
        value: "consume_health_50",
        label: "consume_health_50 · Generated consume_health_50",
      },
    ],
    equipmentSlots: [
      "head",
      "body",
      "hands",
      "legs",
      "feet",
      "back",
      "main_hand",
      "off_hand",
      "accessory",
    ],
    knownSubtypes: ["unarmed", "tool", "watch", "wood", "food", "healing"],
    itemIds: ["1001"],
  },
  documents: [
    {
      documentKey: "1001.json",
      originalId: 1001,
      fileName: "1001.json",
      relativePath: "data/items/1001.json",
      item: {
        id: 1001,
        name: "拳头",
        description: "最基础的攻击方式",
        icon_path: "res://assets/icons/weapons/fist.png",
        value: 0,
        weight: 0,
        fragments: [
          {
            kind: "economy",
            rarity: "common",
          },
          {
            kind: "stacking",
            stackable: false,
            max_stack: 1,
          },
          {
            kind: "equip",
            slots: ["main_hand"],
            level_requirement: 0,
            equip_effect_ids: [],
            unequip_effect_ids: [],
          },
          {
            kind: "weapon",
            subtype: "unarmed",
            damage: 5,
            attack_speed: 1,
            range: 1,
            stamina_cost: 2,
            crit_chance: 0.05,
            crit_multiplier: 1.5,
            accuracy: null,
            ammo_type: null,
            max_ammo: null,
            reload_time: null,
            on_hit_effect_ids: [],
          },
        ],
      },
      validation: [],
    },
  ],
};
