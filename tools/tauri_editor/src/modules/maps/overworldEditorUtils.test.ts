import { describe, expect, it } from "vitest";
import type { OverworldDefinition } from "../../types";
import {
  getLocationAtCell,
  normalizeOverworldDocument,
  removeLocation,
  removeWalkableCell,
  upsertLocation,
  upsertWalkableCell,
} from "./overworldEditorUtils";

describe("overworldEditorUtils", () => {
  it("normalizes and deduplicates walkable cells and locations", () => {
    const overworld = normalizeOverworldDocument({
      id: " main_overworld ",
      walkable_cells: [
        { grid: { x: 1.9, y: 0, z: 2.2 }, terrain: "road" },
        { grid: { x: 1, y: 0, z: 2 }, terrain: "forest" },
      ],
      locations: [
        {
          id: "town_gate",
          name: "Town Gate",
          description: "",
          kind: "outdoor",
          map_id: "town_map",
          entry_point_id: "default_entry",
          default_unlocked: true,
          visible: true,
          overworld_cell: { x: 1.2, y: 0, z: 2.9 },
          danger_level: 0,
          icon: "T",
        },
        {
          id: "town_gate",
          name: "Duplicate",
          description: "",
          kind: "outdoor",
          map_id: "town_map",
          entry_point_id: "default_entry",
          default_unlocked: false,
          visible: false,
          overworld_cell: { x: 9, y: 0, z: 9 },
          danger_level: 3,
          icon: "X",
        },
      ],
      travel_rules: {
        food_item_id: "1007",
        night_minutes_multiplier: 1.2,
        risk_multiplier: 1,
      },
    } as OverworldDefinition);

    expect(overworld.id).toBe("main_overworld");
    expect(overworld.walkable_cells).toHaveLength(1);
    expect(overworld.locations).toHaveLength(1);
    expect(overworld.locations[0].overworld_cell).toEqual({ x: 1, y: 0, z: 2 });
  });

  it("adds and removes walkable cells and locations deterministically", () => {
    const base: OverworldDefinition = {
      id: "main_overworld",
      walkable_cells: [],
      locations: [],
      travel_rules: {
        food_item_id: "1007",
        night_minutes_multiplier: 1.2,
        risk_multiplier: 1,
      },
    };

    const withCell = upsertWalkableCell(base, { x: 4, y: 0, z: 5 }, "road");
    const withLocation = upsertLocation(withCell, {
      id: "camp_01",
      name: "Camp",
      description: "",
      kind: "outdoor",
      map_id: "camp_map",
      entry_point_id: "default_entry",
      parent_outdoor_location_id: null,
      return_entry_point_id: null,
      default_unlocked: true,
      visible: true,
      overworld_cell: { x: 4, y: 0, z: 5 },
      danger_level: 1,
      icon: "C",
    });

    expect(getLocationAtCell(withLocation, { x: 4, y: 0, z: 5 })?.id).toBe("camp_01");

    const withoutLocation = removeLocation(withLocation, "camp_01");
    const withoutCell = removeWalkableCell(withoutLocation, { x: 4, y: 0, z: 5 });

    expect(withoutLocation.locations).toHaveLength(0);
    expect(withoutCell.walkable_cells).toHaveLength(0);
  });
});
