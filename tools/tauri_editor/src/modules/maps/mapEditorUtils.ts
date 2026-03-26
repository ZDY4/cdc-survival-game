import type {
  MapAiSpawnProps,
  MapBuildingProps,
  MapDefinition,
  MapInteractiveProps,
  MapObjectDefinition,
  MapObjectFootprint,
  MapObjectKind,
  MapPickupProps,
  MapRotation,
} from "../../types";

export type GridPoint = {
  x: number;
  y: number;
  z: number;
};

export type PlacementTool = Exclude<MapObjectKind, never>;

export type PlacementDraft = {
  kind: MapObjectKind;
  anchor: GridPoint;
  footprint: MapObjectFootprint;
  rotation: MapRotation;
  blocksMovement: boolean;
  blocksSight: boolean;
  buildingPrefabId: string;
  pickupItemId: string;
  pickupMinCount: number;
  pickupMaxCount: number;
  interactiveKind: string;
  interactiveTargetId: string;
  aiSpawnId: string;
  aiCharacterId: string;
  aiAutoSpawn: boolean;
  aiRespawnEnabled: boolean;
  aiRespawnDelay: number;
  aiSpawnRadius: number;
};

export function createDraftMap(nextId: string): MapDefinition {
  return normalizeMapDocument({
    id: nextId,
    name: "New map",
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
    ],
    objects: [],
  });
}

export function createPlacementDraft(
  kind: MapObjectKind,
  level: number,
  sequence: number,
): PlacementDraft {
  return {
    kind,
    anchor: { x: 0, y: level, z: 0 },
    footprint: kind === "building" ? { width: 2, height: 2 } : { width: 1, height: 1 },
    rotation: "north",
    blocksMovement: kind === "building",
    blocksSight: kind === "building",
    buildingPrefabId: "survivor_outpost_01_dormitory",
    pickupItemId: "1005",
    pickupMinCount: 1,
    pickupMaxCount: 1,
    interactiveKind: "enter_outdoor_location",
    interactiveTargetId: "",
    aiSpawnId: `spawn_${sequence}`,
    aiCharacterId: "zombie_walker",
    aiAutoSpawn: true,
    aiRespawnEnabled: false,
    aiRespawnDelay: 10,
    aiSpawnRadius: 0,
  };
}

export function normalizeMapDocument(map: MapDefinition): MapDefinition {
  const normalizedLevels = [...(map.levels ?? [])]
    .map((level) => ({
      y: Number.isFinite(level.y) ? level.y : 0,
      cells: [...(level.cells ?? [])]
        .map((cell) => ({
          x: Math.max(0, Math.floor(cell.x ?? 0)),
          z: Math.max(0, Math.floor(cell.z ?? 0)),
          blocks_movement: Boolean(cell.blocks_movement),
          blocks_sight: Boolean(cell.blocks_sight),
          terrain: String(cell.terrain ?? ""),
        }))
        .sort((left, right) => left.z - right.z || left.x - right.x),
    }))
    .sort((left, right) => left.y - right.y);

  if (!normalizedLevels.some((level) => level.y === map.default_level)) {
    normalizedLevels.unshift({
      y: map.default_level ?? 0,
      cells: [],
    });
    normalizedLevels.sort((left, right) => left.y - right.y);
  }

  const seenLevels = new Set<number>();
  const levels = normalizedLevels.filter((level) => {
    if (seenLevels.has(level.y)) {
      return false;
    }
    seenLevels.add(level.y);
    return true;
  });

  const objects = [...(map.objects ?? [])]
    .map((object) => normalizeObject(object))
    .sort((left, right) => left.object_id.localeCompare(right.object_id));

  return {
    id: String(map.id ?? "").trim(),
    name: String(map.name ?? ""),
    size: {
      width: Math.max(1, Math.floor(map.size?.width ?? 1)),
      height: Math.max(1, Math.floor(map.size?.height ?? 1)),
    },
    default_level:
      typeof map.default_level === "number" && Number.isFinite(map.default_level)
        ? Math.floor(map.default_level)
        : 0,
    levels,
    objects,
  };
}

export function getMapDirtyState(map: MapDefinition, savedSnapshot: string): boolean {
  return JSON.stringify(normalizeMapDocument(map)) !== savedSnapshot;
}

export function summarizeMap(map: MapDefinition): string {
  return `${map.size.width}x${map.size.height} · ${map.levels.length} levels · ${map.objects.length} objects`;
}

export function getObjectsAtCell(map: MapDefinition, grid: GridPoint): MapObjectDefinition[] {
  return map.objects.filter((object) =>
    getOccupiedCells(object).some(
      (cell) => cell.x === grid.x && cell.y === grid.y && cell.z === grid.z,
    ),
  );
}

export function applyPlacement(
  map: MapDefinition,
  placement: PlacementDraft,
  anchor: GridPoint,
  objectId: string,
): MapDefinition {
  const next = normalizeMapDocument(map);
  ensureLevel(next, anchor.y);
  next.objects.push(
    normalizeObject({
      object_id: objectId,
      kind: placement.kind,
      anchor,
      footprint:
        placement.kind === "building"
          ? placement.footprint
          : {
              width: 1,
              height: 1,
            },
      rotation: placement.rotation,
      blocks_movement: placement.blocksMovement,
      blocks_sight: placement.blocksSight,
      props: buildProps(placement),
    }),
  );
  return normalizeMapDocument(next);
}

export function updateObject(
  map: MapDefinition,
  objectId: string,
  transform: (object: MapObjectDefinition) => MapObjectDefinition,
): MapDefinition {
  return normalizeMapDocument({
    ...map,
    objects: map.objects.map((object) =>
      object.object_id === objectId ? normalizeObject(transform(object)) : normalizeObject(object),
    ),
  });
}

export function removeObject(map: MapDefinition, objectId: string): MapDefinition {
  return normalizeMapDocument({
    ...map,
    objects: map.objects.filter((object) => object.object_id !== objectId),
  });
}

export function changeObjectKind(
  object: MapObjectDefinition,
  nextKind: MapObjectKind,
): MapObjectDefinition {
  const normalized = normalizeObject(object);

  switch (nextKind) {
    case "building":
      return normalizeObject({
        ...normalized,
        kind: nextKind,
        footprint: normalized.footprint,
        blocks_movement: true,
        blocks_sight: true,
        props: {
          building: normalizeBuildingProps(
            normalized.props.building ?? {
              prefab_id: "",
            },
          ),
        },
      });
    case "pickup":
      return normalizeObject({
        ...normalized,
        kind: nextKind,
        footprint: { width: 1, height: 1 },
        blocks_movement: false,
        blocks_sight: false,
        props: {
          pickup: normalizePickupProps(
            normalized.props.pickup ?? {
              item_id: "",
              min_count: 1,
              max_count: 1,
            },
          ),
        },
      });
    case "interactive":
      return normalizeObject({
        ...normalized,
        kind: nextKind,
        footprint: { width: 1, height: 1 },
        blocks_movement: false,
        blocks_sight: false,
        props: {
          interactive: normalizeInteractiveProps(
            normalized.props.interactive ?? {
              interaction_kind: "",
              target_id: null,
            },
          ),
        },
      });
    case "ai_spawn":
      return normalizeObject({
        ...normalized,
        kind: nextKind,
        footprint: { width: 1, height: 1 },
        blocks_movement: false,
        blocks_sight: false,
        props: {
          ai_spawn: normalizeAiSpawnProps(
            normalized.props.ai_spawn ?? {
              spawn_id: "",
              character_id: "",
              auto_spawn: true,
              respawn_enabled: false,
              respawn_delay: 10,
              spawn_radius: 0,
            },
          ),
        },
      });
    default:
      return normalized;
  }
}

export function getOccupiedCells(object: MapObjectDefinition): GridPoint[] {
  const { width, height } = rotatedFootprint(object.footprint, object.rotation);
  const cells: GridPoint[] = [];
  for (let z = 0; z < height; z += 1) {
    for (let x = 0; x < width; x += 1) {
      cells.push({
        x: object.anchor.x + x,
        y: object.anchor.y,
        z: object.anchor.z + z,
      });
    }
  }
  return cells;
}

export function rotatedFootprint(
  footprint: MapObjectFootprint,
  rotation: MapRotation,
): MapObjectFootprint {
  if (rotation === "east" || rotation === "west") {
    return {
      width: Math.max(1, footprint.height),
      height: Math.max(1, footprint.width),
    };
  }
  return {
    width: Math.max(1, footprint.width),
    height: Math.max(1, footprint.height),
  };
}

export function ensureLevel(map: MapDefinition, level: number) {
  if (!map.levels.some((entry) => entry.y === level)) {
    map.levels.push({
      y: level,
      cells: [],
    });
    map.levels.sort((left, right) => left.y - right.y);
  }
}

function normalizeObject(object: MapObjectDefinition): MapObjectDefinition {
  return {
    object_id: String(object.object_id ?? "").trim(),
    kind: object.kind,
    anchor: {
      x: Math.floor(object.anchor?.x ?? 0),
      y: Math.floor(object.anchor?.y ?? 0),
      z: Math.floor(object.anchor?.z ?? 0),
    },
    footprint: {
      width: Math.max(1, Math.floor(object.footprint?.width ?? 1)),
      height: Math.max(1, Math.floor(object.footprint?.height ?? 1)),
    },
    rotation: object.rotation ?? "north",
    blocks_movement: Boolean(object.blocks_movement),
    blocks_sight: Boolean(object.blocks_sight),
    props: {
      ...object.props,
      building: object.props?.building
        ? normalizeBuildingProps(object.props.building)
        : undefined,
      pickup: object.props?.pickup ? normalizePickupProps(object.props.pickup) : undefined,
      interactive: object.props?.interactive
        ? normalizeInteractiveProps(object.props.interactive)
        : undefined,
      ai_spawn: object.props?.ai_spawn ? normalizeAiSpawnProps(object.props.ai_spawn) : undefined,
    },
  };
}

function buildProps(placement: PlacementDraft): MapObjectDefinition["props"] {
  switch (placement.kind) {
    case "building":
      return {
        building: normalizeBuildingProps({
          prefab_id: placement.buildingPrefabId,
        }),
      };
    case "pickup":
      return {
        pickup: normalizePickupProps({
          item_id: placement.pickupItemId,
          min_count: placement.pickupMinCount,
          max_count: placement.pickupMaxCount,
        }),
      };
    case "interactive":
      return {
        interactive: normalizeInteractiveProps({
          interaction_kind: placement.interactiveKind,
          target_id: placement.interactiveTargetId || null,
        }),
      };
    case "ai_spawn":
      return {
        ai_spawn: normalizeAiSpawnProps({
          spawn_id: placement.aiSpawnId,
          character_id: placement.aiCharacterId,
          auto_spawn: placement.aiAutoSpawn,
          respawn_enabled: placement.aiRespawnEnabled,
          respawn_delay: placement.aiRespawnDelay,
          spawn_radius: placement.aiSpawnRadius,
        }),
      };
    default:
      return {};
  }
}

function normalizeBuildingProps(props: MapBuildingProps): MapBuildingProps {
  return {
    ...props,
    prefab_id: String(props.prefab_id ?? "").trim(),
  };
}

function normalizePickupProps(props: MapPickupProps): MapPickupProps {
  return {
    ...props,
    item_id: String(props.item_id ?? "").trim(),
    min_count: Math.max(1, Math.floor(props.min_count ?? 1)),
    max_count: Math.max(1, Math.floor(props.max_count ?? 1)),
  };
}

function normalizeInteractiveProps(props: MapInteractiveProps): MapInteractiveProps {
  return {
    ...props,
    interaction_kind: String(props.interaction_kind ?? "").trim(),
    target_id: props.target_id ? String(props.target_id).trim() : null,
  };
}

function normalizeAiSpawnProps(props: MapAiSpawnProps): MapAiSpawnProps {
  return {
    ...props,
    spawn_id: String(props.spawn_id ?? "").trim(),
    character_id: String(props.character_id ?? "").trim(),
    auto_spawn: Boolean(props.auto_spawn),
    respawn_enabled: Boolean(props.respawn_enabled),
    respawn_delay: Number.isFinite(props.respawn_delay) ? props.respawn_delay : 10,
    spawn_radius: Number.isFinite(props.spawn_radius) ? props.spawn_radius : 0,
  };
}
