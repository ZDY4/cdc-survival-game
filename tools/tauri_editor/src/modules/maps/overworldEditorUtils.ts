import type {
  OverworldDefinition,
  OverworldLocationDefinition,
  OverworldLocationKind,
  OverworldTravelRuleSet,
} from "../../types";
import type { GridPoint } from "./mapEditorUtils";

export type OverworldLocationDraft = {
  id: string;
  name: string;
  description: string;
  kind: OverworldLocationKind;
  mapId: string;
  entryPointId: string;
  parentOutdoorLocationId: string;
  returnEntryPointId: string;
  defaultUnlocked: boolean;
  visible: boolean;
  dangerLevel: number;
  icon: string;
};

export function createDraftOverworld(nextId: string): OverworldDefinition {
  return normalizeOverworldDocument({
    id: nextId,
    locations: [],
    walkable_cells: [{ grid: { x: 0, y: 0, z: 0 }, terrain: "road" }],
    travel_rules: {
      food_item_id: "1007",
      night_minutes_multiplier: 1.2,
      risk_multiplier: 1,
    },
  });
}

export function createLocationDraft(sequence: number): OverworldLocationDraft {
  return {
    id: `location_${sequence}`,
    name: "New location",
    description: "",
    kind: "outdoor",
    mapId: "",
    entryPointId: "default_entry",
    parentOutdoorLocationId: "",
    returnEntryPointId: "",
    defaultUnlocked: false,
    visible: true,
    dangerLevel: 0,
    icon: "",
  };
}

export function normalizeOverworldDocument(overworld: OverworldDefinition): OverworldDefinition {
  const walkableCells = [...(overworld.walkable_cells ?? [])]
    .map((cell) => ({
      ...cell,
      grid: {
        x: Math.floor(cell.grid?.x ?? 0),
        y: Math.floor(cell.grid?.y ?? 0),
        z: Math.floor(cell.grid?.z ?? 0),
      },
      terrain: String(cell.terrain ?? ""),
    }))
    .sort(
      (left, right) =>
        left.grid.y - right.grid.y || left.grid.z - right.grid.z || left.grid.x - right.grid.x,
    )
    .filter((cell, index, collection) => {
      return (
        collection.findIndex(
          (candidate) =>
            candidate.grid.x === cell.grid.x &&
            candidate.grid.y === cell.grid.y &&
            candidate.grid.z === cell.grid.z,
        ) === index
      );
    });

  const locations = [...(overworld.locations ?? [])]
    .map((location) => normalizeLocation(location))
    .sort((left, right) => left.id.localeCompare(right.id))
    .filter((location, index, collection) => {
      return collection.findIndex((candidate) => candidate.id === location.id) === index;
    });

  return {
    id: String(overworld.id ?? "").trim(),
    locations,
    walkable_cells: walkableCells,
    travel_rules: normalizeTravelRules(overworld.travel_rules),
  };
}

export function getOverworldDirtyState(overworld: OverworldDefinition, savedSnapshot: string): boolean {
  return JSON.stringify(normalizeOverworldDocument(overworld)) !== savedSnapshot;
}

export function summarizeOverworld(overworld: OverworldDefinition): string {
  return `${overworld.walkable_cells.length} cells · ${overworld.locations.length} locations`;
}

export function getLocationAtCell(overworld: OverworldDefinition, grid: GridPoint) {
  return (
    overworld.locations.find(
      (location) =>
        location.overworld_cell.x === grid.x &&
        location.overworld_cell.y === grid.y &&
        location.overworld_cell.z === grid.z,
    ) ?? null
  );
}

export function upsertWalkableCell(
  overworld: OverworldDefinition,
  grid: GridPoint,
  terrain: string,
): OverworldDefinition {
  return normalizeOverworldDocument({
    ...overworld,
    walkable_cells: [
      ...overworld.walkable_cells.filter(
        (cell) =>
          !(
            cell.grid.x === grid.x &&
            cell.grid.y === grid.y &&
            cell.grid.z === grid.z
          ),
      ),
      {
        grid: { x: grid.x, y: grid.y, z: grid.z },
        terrain,
      },
    ],
  });
}

export function removeWalkableCell(overworld: OverworldDefinition, grid: GridPoint): OverworldDefinition {
  return normalizeOverworldDocument({
    ...overworld,
    walkable_cells: overworld.walkable_cells.filter(
      (cell) =>
        !(
          cell.grid.x === grid.x &&
          cell.grid.y === grid.y &&
          cell.grid.z === grid.z
        ),
    ),
  });
}

export function upsertLocation(
  overworld: OverworldDefinition,
  location: OverworldLocationDefinition,
): OverworldDefinition {
  return normalizeOverworldDocument({
    ...overworld,
    locations: [
      ...overworld.locations.filter((candidate) => candidate.id !== location.id),
      normalizeLocation(location),
    ],
  });
}

export function removeLocation(overworld: OverworldDefinition, locationId: string): OverworldDefinition {
  return normalizeOverworldDocument({
    ...overworld,
    locations: overworld.locations.filter((location) => location.id !== locationId),
  });
}

function normalizeLocation(location: OverworldLocationDefinition): OverworldLocationDefinition {
  return {
    ...location,
    id: String(location.id ?? "").trim(),
    name: String(location.name ?? ""),
    description: String(location.description ?? ""),
    kind: (location.kind ?? "outdoor") as OverworldLocationKind,
    map_id: String(location.map_id ?? "").trim(),
    entry_point_id: String(location.entry_point_id ?? "").trim(),
    parent_outdoor_location_id: location.parent_outdoor_location_id
      ? String(location.parent_outdoor_location_id).trim()
      : null,
    return_entry_point_id: location.return_entry_point_id
      ? String(location.return_entry_point_id).trim()
      : null,
    default_unlocked: Boolean(location.default_unlocked),
    visible: Boolean(location.visible ?? true),
    overworld_cell: {
      x: Math.floor(location.overworld_cell?.x ?? 0),
      y: Math.floor(location.overworld_cell?.y ?? 0),
      z: Math.floor(location.overworld_cell?.z ?? 0),
    },
    danger_level: Math.floor(location.danger_level ?? 0),
    icon: String(location.icon ?? ""),
  };
}

function normalizeTravelRules(rules?: OverworldTravelRuleSet | null): OverworldTravelRuleSet {
  return {
    food_item_id: String(rules?.food_item_id ?? "1007").trim(),
    night_minutes_multiplier: Number.isFinite(rules?.night_minutes_multiplier)
      ? Number(rules?.night_minutes_multiplier)
      : 1.2,
    risk_multiplier: Number.isFinite(rules?.risk_multiplier) ? Number(rules?.risk_multiplier) : 1,
  };
}
