import { describe, expect, it } from "vitest";
import type { MapDefinition } from "../../types";
import {
  applyPlacement,
  changeObjectKind,
  createDraftMap,
  createPlacementDraft,
  getMapDirtyState,
  getObjectsAtCell,
  normalizeMapDocument,
  updateObject,
} from "./mapEditorUtils";

describe("mapEditorUtils", () => {
  it("normalizes levels and default level", () => {
    const map = normalizeMapDocument({
      id: "demo",
      name: "Demo",
      size: { width: 0, height: 0 },
      default_level: 2,
      levels: [{ y: 0, cells: [] }],
      entry_points: [],
      objects: [],
    } as MapDefinition);

    expect(map.size.width).toBe(1);
    expect(map.size.height).toBe(1);
    expect(map.levels.some((level) => level.y === 2)).toBe(true);
  });

  it("preserves and normalizes entry points", () => {
    const map = normalizeMapDocument({
      id: "demo",
      name: "Demo",
      size: { width: 4, height: 4 },
      default_level: 0,
      levels: [{ y: 0, cells: [] }],
      entry_points: [
        {
          id: " gate_north ",
          grid: { x: 2.9, y: 0.1, z: 1.6 },
          facing: "south",
        },
      ],
      objects: [],
    } as MapDefinition);

    expect(map.entry_points).toEqual([
      {
        id: "gate_north",
        grid: { x: 2, y: 0, z: 1 },
        facing: "south",
      },
    ]);
  });

  it("places rectangular buildings using footprint", () => {
    const baseMap = createDraftMap("demo");
    const placement = createPlacementDraft("building", 0, 1);
    placement.footprint = { width: 4, height: 3 };

    const next = applyPlacement(baseMap, placement, { x: 2, y: 0, z: 5 }, "house_01");
    const house = next.objects[0];

    expect(house.footprint.width).toBe(4);
    expect(house.footprint.height).toBe(3);
    expect(getObjectsAtCell(next, { x: 5, y: 0, z: 7 })).toHaveLength(1);
    expect(getObjectsAtCell(next, { x: 6, y: 0, z: 8 })).toHaveLength(0);
  });

  it("updates selection-targeted object anchors", () => {
    const baseMap = createDraftMap("demo");
    const placement = createPlacementDraft("pickup", 0, 1);
    const placed = applyPlacement(baseMap, placement, { x: 1, y: 0, z: 1 }, "pickup_01");

    const moved = updateObject(placed, "pickup_01", (object) => ({
      ...object,
      anchor: { x: 3, y: 1, z: 4 },
    }));

    expect(moved.objects[0].anchor).toEqual({ x: 3, y: 1, z: 4 });
  });

  it("tracks dirty state against saved snapshot", () => {
    const baseMap = createDraftMap("demo");
    const savedSnapshot = JSON.stringify(normalizeMapDocument(baseMap));
    const placement = createPlacementDraft("interactive", 0, 1);
    const next = applyPlacement(baseMap, placement, { x: 4, y: 0, z: 4 }, "door_01");

    expect(getMapDirtyState(baseMap, savedSnapshot)).toBe(false);
    expect(getMapDirtyState(next, savedSnapshot)).toBe(true);
  });

  it("retyping a building resets single-cell object payload and footprint", () => {
    const building = {
      object_id: "house_01",
      kind: "building",
      anchor: { x: 2, y: 0, z: 3 },
      footprint: { width: 4, height: 3 },
      rotation: "east",
      blocks_movement: true,
      blocks_sight: true,
      props: {
        building: {
          prefab_id: "survivor_outpost_01_dormitory",
        },
      },
    } as const;

    const pickup = changeObjectKind(building, "pickup");

    expect(pickup.kind).toBe("pickup");
    expect(pickup.footprint).toEqual({ width: 1, height: 1 });
    expect(pickup.blocks_movement).toBe(false);
    expect(pickup.blocks_sight).toBe(false);
    expect(pickup.props.pickup?.item_id).toBe("");
    expect(pickup.props.building).toBeUndefined();
  });
});
