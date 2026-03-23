import type { ItemDefinition, ItemFragment } from "../../types";

export const DEFAULT_RARITIES = ["common", "uncommon", "rare", "epic", "legendary"];

export function createDefaultFragment(kind: string): ItemFragment {
  switch (kind) {
    case "economy":
      return { kind: "economy", rarity: "common" };
    case "stacking":
      return { kind: "stacking", stackable: false, max_stack: 1 };
    case "equip":
      return {
        kind: "equip",
        slots: ["main_hand"],
        level_requirement: 0,
        equip_effect_ids: [],
        unequip_effect_ids: [],
      };
    case "durability":
      return {
        kind: "durability",
        durability: -1,
        max_durability: -1,
        repairable: false,
        repair_materials: [],
      };
    case "attribute_modifiers":
      return { kind: "attribute_modifiers", attributes: {} };
    case "weapon":
      return {
        kind: "weapon",
        subtype: "",
        damage: 0,
        attack_speed: 1,
        range: 1,
        stamina_cost: 0,
        crit_chance: 0,
        crit_multiplier: 1.5,
        accuracy: null,
        ammo_type: null,
        max_ammo: null,
        reload_time: null,
        on_hit_effect_ids: [],
      };
    case "usable":
      return {
        kind: "usable",
        subtype: "",
        use_time: 0,
        uses: 1,
        consume_on_use: true,
        effect_ids: [],
      };
    case "crafting":
      return {
        kind: "crafting",
        crafting_recipe: {
          materials: [],
          time: 0,
        },
        deconstruct_yield: [],
      };
    case "passive_effects":
      return { kind: "passive_effects", effect_ids: [] };
    default:
      return { kind: "economy", rarity: "common" };
  }
}

export function createDefaultItem(nextId: number): ItemDefinition {
  return {
    id: nextId,
    name: "New Item",
    description: "",
    icon_path: "",
    value: 0,
    weight: 0,
    fragments: [createDefaultFragment("economy"), createDefaultFragment("stacking")],
  };
}

export const KNOWN_ITEM_KEYS = new Set([
  "id",
  "name",
  "description",
  "icon_path",
  "value",
  "weight",
  "fragments",
]);
