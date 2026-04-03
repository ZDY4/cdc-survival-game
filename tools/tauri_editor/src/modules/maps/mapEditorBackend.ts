import { invokeCommand } from "../../lib/tauri";
import type {
  MapCellDefinition,
  MapDefinition,
  MapEntryPointDefinition,
  MapObjectDefinition,
} from "../../types";
import type { GridPoint } from "./mapEditorUtils";

export function createMapDraft(mapId: string) {
  return invokeCommand<MapDefinition>("create_map_draft", {
    mapId,
  });
}

export function upsertMapEntryPoint(map: MapDefinition, entryPoint: MapEntryPointDefinition) {
  return invokeCommand<MapDefinition>("upsert_map_entry_point", {
    map,
    entryPoint,
  });
}

export function removeMapEntryPoint(map: MapDefinition, entryPointId: string) {
  return invokeCommand<MapDefinition>("remove_map_entry_point", {
    map,
    entryPointId,
  });
}

export function upsertMapObject(map: MapDefinition, object: MapObjectDefinition) {
  return invokeCommand<MapDefinition>("upsert_map_object", {
    map,
    object,
  });
}

export function removeMapObject(map: MapDefinition, objectId: string) {
  return invokeCommand<MapDefinition>("remove_map_object", {
    map,
    objectId,
  });
}

export function paintMapCells(map: MapDefinition, level: number, cells: MapCellDefinition[]) {
  return invokeCommand<MapDefinition>("paint_map_cells", {
    map,
    level,
    cells,
  });
}

export function clearMapCells(map: MapDefinition, level: number, cells: GridPoint[]) {
  return invokeCommand<MapDefinition>("clear_map_cells", {
    map,
    level,
    cells,
  });
}

export function addMapLevel(map: MapDefinition, level: number) {
  return invokeCommand<MapDefinition>("add_map_level", {
    map,
    level,
  });
}

export function removeMapLevel(map: MapDefinition, level: number) {
  return invokeCommand<MapDefinition>("remove_map_level", {
    map,
    level,
  });
}
