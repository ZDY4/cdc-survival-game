import { useEffect, useMemo, useRef, useState } from "react";
import { invokeCommand } from "../../lib/tauri";
import type {
  MapDefinition,
  MapDocumentPayload,
  MapEntryPointDefinition,
  MapObjectDefinition,
  MapObjectKind,
  MapRotation,
  MapWorkspacePayload,
  SaveMapsResult,
  ValidationIssue,
} from "../../types";
import {
  applyPlacement,
  buildPlacementObject,
  changeObjectKind,
  createDraftMap,
  createPlacementDraft,
  getMapDirtyState,
  getObjectsAtCell,
  getOccupiedCells,
  normalizeMapDocument,
  removeObject,
  updateObject,
  type GridPoint,
  type PlacementDraft,
} from "./mapEditorUtils";
import {
  addMapLevel,
  clearMapCells,
  createMapDraft,
  paintMapCells,
  removeMapLevel,
  removeMapEntryPoint,
  removeMapObject,
  upsertMapEntryPoint,
  upsertMapObject,
} from "./mapEditorBackend";
import { MapEditorPendingIntent, shouldDeferPendingIntent } from "./mapEditorGuards";
import { NEW_MAP_DOCUMENT_KEY } from "./mapWindowing";

export type EditableMapDocument = MapDocumentPayload & {
  savedSnapshot: string;
  dirty: boolean;
  isDraft: boolean;
};

export type MapLayer = "cells" | "objects" | "entryPoints";

export type CellDraft = {
  terrain: string;
  blocksMovement: boolean;
  blocksSight: boolean;
};

export type EntryPointDraft = {
  id: string;
  facing: string;
};

export type MapTool = "select" | "erase" | "paint-cell" | "entry-point" | MapObjectKind;

type UseMapEditorStateOptions = {
  workspace: MapWorkspacePayload;
  canPersist: boolean;
  onStatusChange: (status: string) => void;
  onReload: () => Promise<void>;
  initialDocumentKey?: string | null;
};

function getInitialSelectionKey(
  documents: EditableMapDocument[],
  ...candidates: Array<string | null | undefined>
) {
  for (const candidate of candidates) {
    if (!candidate) {
      continue;
    }
    if (documents.some((document) => document.documentKey === candidate)) {
      return candidate;
    }
  }
  return documents[0]?.documentKey ?? "";
}

function nextRotation(rotation: MapRotation): MapRotation {
  const rotations: MapRotation[] = ["north", "east", "south", "west"];
  const index = rotations.indexOf(rotation);
  return rotations[(index + 1) % rotations.length];
}

function lastObject(objects: MapObjectDefinition[]) {
  return objects.length > 0 ? objects[objects.length - 1] : undefined;
}

function cellAtGrid(map: MapDefinition, grid: GridPoint) {
  const level = map.levels.find((entry) => entry.y === grid.y);
  return level?.cells.find((cell) => cell.x === grid.x && cell.z === grid.z) ?? null;
}

function entryPointAtGrid(map: MapDefinition, grid: GridPoint) {
  return (
    map.entry_points.find(
      (entryPoint) =>
        entryPoint.grid.x === grid.x &&
        entryPoint.grid.y === grid.y &&
        entryPoint.grid.z === grid.z,
    ) ?? null
  );
}

function initialToolForLayer(layer: MapLayer): MapTool {
  switch (layer) {
    case "cells":
      return "paint-cell";
    case "entryPoints":
      return "entry-point";
    case "objects":
    default:
      return "select";
  }
}

export function gridKey(grid: GridPoint) {
  return `${grid.x}:${grid.y}:${grid.z}`;
}

export function objectGlyph(kind: MapObjectKind) {
  switch (kind) {
    case "building":
      return "B";
    case "pickup":
      return "P";
    case "interactive":
      return "I";
    case "ai_spawn":
      return "A";
    default:
      return "?";
  }
}

function isObjectPlacementTool(tool: MapTool): tool is MapObjectKind {
  return (
    tool === "building" ||
    tool === "pickup" ||
    tool === "interactive" ||
    tool === "ai_spawn"
  );
}

export function hydrateDocuments(documents: MapDocumentPayload[]): EditableMapDocument[] {
  return documents.map((document) => {
    const normalized = normalizeMapDocument(document.map);
    return {
      ...document,
      map: normalized,
      savedSnapshot: JSON.stringify(normalized),
      dirty: false,
      isDraft: false,
    };
  });
}

export function getIssueCounts(issues: ValidationIssue[]) {
  let errorCount = 0;
  let warningCount = 0;
  for (const issue of issues) {
    if (issue.severity === "error") {
      errorCount += 1;
    } else {
      warningCount += 1;
    }
  }
  return { errorCount, warningCount };
}

export function useMapEditorState({
  workspace,
  canPersist,
  onStatusChange,
  onReload,
  initialDocumentKey = null,
}: UseMapEditorStateOptions) {
  const [documents, setDocuments] = useState<EditableMapDocument[]>(() =>
    hydrateDocuments(workspace.documents),
  );
  const [selectedKey, setSelectedKey] = useState(() =>
    getInitialSelectionKey(hydrateDocuments(workspace.documents), initialDocumentKey),
  );
  const [busy, setBusy] = useState(false);
  const [currentLevel, setCurrentLevel] = useState(workspace.documents[0]?.map.default_level ?? 0);
  const [layer, setLayer] = useState<MapLayer>("objects");
  const [selectedObjectId, setSelectedObjectId] = useState<string | null>(null);
  const [selectedEntryPointId, setSelectedEntryPointId] = useState<string | null>(null);
  const [selectedCellKey, setSelectedCellKey] = useState<string | null>(null);
  const [hoveredCell, setHoveredCell] = useState<GridPoint | null>(null);
  const [tool, setTool] = useState<MapTool>("select");
  const [cellDraft, setCellDraft] = useState<CellDraft>({
    terrain: "floor",
    blocksMovement: false,
    blocksSight: false,
  });
  const [entryPointDraft, setEntryPointDraft] = useState<EntryPointDraft>({
    id: "default_entry",
    facing: "",
  });
  const [placementDraft, setPlacementDraft] = useState<PlacementDraft>(
    createPlacementDraft("building", currentLevel, 1),
  );
  const [objectSequence, setObjectSequence] = useState(1);
  const [pendingIntent, setPendingIntent] = useState<MapEditorPendingIntent | null>(null);
  const preferredSelectionAfterReloadRef = useRef<string | null>(initialDocumentKey ?? null);

  useEffect(() => {
    const hydrated = hydrateDocuments(workspace.documents);
    setDocuments(hydrated);
    setSelectedKey((current) => {
      const next = getInitialSelectionKey(
        hydrated,
        preferredSelectionAfterReloadRef.current,
        current,
        initialDocumentKey,
      );
      preferredSelectionAfterReloadRef.current = null;
      return next;
    });
    setSelectedObjectId(null);
    setSelectedEntryPointId(null);
    setSelectedCellKey(null);
    setHoveredCell(null);
    setPendingIntent(null);
  }, [initialDocumentKey, workspace]);

  const selectedDocument =
    documents.find((document) => document.documentKey === selectedKey) ?? null;
  const selectedObject =
    selectedDocument?.map.objects.find((object) => object.object_id === selectedObjectId) ?? null;
  const selectedEntryPoint =
    selectedDocument?.map.entry_points.find((entryPoint) => entryPoint.id === selectedEntryPointId) ??
    null;
  const selectedCell =
    selectedDocument && selectedCellKey
      ? selectedDocument.map.levels
          .flatMap((level) =>
            level.cells.map((cell) => ({
              ...cell,
              y: level.y,
            })),
          )
          .find((cell) => gridKey({ x: cell.x, y: cell.y, z: cell.z }) === selectedCellKey) ?? null
      : null;
  const dirtyCount = documents.filter((document) => document.dirty).length;
  const totalIssues = documents.reduce(
    (totals, document) => {
      const counts = getIssueCounts(document.validation);
      return {
        errors: totals.errors + counts.errorCount,
        warnings: totals.warnings + counts.warningCount,
      };
    },
    { errors: 0, warnings: 0 },
  );

  useEffect(() => {
    if (!selectedDocument) {
      return;
    }
    if (!selectedDocument.map.levels.some((level) => level.y === currentLevel)) {
      setCurrentLevel(selectedDocument.map.default_level);
    }
  }, [currentLevel, selectedDocument]);

  useEffect(() => {
    setPlacementDraft((current) => ({
      ...current,
      anchor: { ...current.anchor, y: currentLevel },
    }));
  }, [currentLevel]);

  useEffect(() => {
    if (!selectedDocument || !canPersist) {
      return;
    }

    const timeoutId = window.setTimeout(() => {
      void invokeCommand<ValidationIssue[]>("validate_map_document", {
        map: selectedDocument.map,
      })
        .then((issues) => {
          setDocuments((current) =>
            current.map((document) =>
              document.documentKey === selectedDocument.documentKey
                ? { ...document, validation: issues }
                : document,
            ),
          );
        })
        .catch(() => {});
    }, 220);

    return () => window.clearTimeout(timeoutId);
  }, [canPersist, selectedDocument?.documentKey, selectedDocument?.map]);

  const selectedIssues = selectedDocument?.validation ?? [];
  const selectedCounts = getIssueCounts(selectedIssues);
  const toolOptions: MapTool[] = useMemo(() => {
    switch (layer) {
      case "cells":
        return ["select", "paint-cell", "erase"];
      case "entryPoints":
        return ["select", "entry-point", "erase"];
      case "objects":
      default:
        return ["select", "erase", "building", "pickup", "interactive", "ai_spawn"];
    }
  }, [layer]);
  const hoveredPreview =
    layer === "objects" && hoveredCell && isObjectPlacementTool(tool)
      ? getOccupiedCells({
          object_id: "preview",
          kind: tool,
          anchor: hoveredCell,
          footprint: tool === "building" ? placementDraft.footprint : { width: 1, height: 1 },
          rotation: placementDraft.rotation,
          blocks_movement: placementDraft.blocksMovement,
          blocks_sight: placementDraft.blocksSight,
          props: {},
        })
      : [];
  const selectedCoverage = selectedObject
    ? getOccupiedCells(selectedObject)
    : selectedEntryPoint
      ? [
          {
            x: selectedEntryPoint.grid.x,
            y: selectedEntryPoint.grid.y,
            z: selectedEntryPoint.grid.z,
          },
        ]
      : selectedCell
        ? [{ x: selectedCell.x, y: selectedCell.y, z: selectedCell.z }]
        : [];

  function commitSelection(documentKey: string) {
    if (documentKey === NEW_MAP_DOCUMENT_KEY) {
      const nextId = `map_${Date.now()}`;
      void (async () => {
        try {
          const draftMap = canPersist ? await createMapDraft(nextId) : createDraftMap(nextId);
          const draft: EditableMapDocument = {
            documentKey: `draft-${nextId}`,
            originalId: nextId,
            fileName: `${nextId}.json`,
            relativePath: `data/maps/${nextId}.json`,
            map: normalizeMapDocument(draftMap),
            validation: [],
            savedSnapshot: "",
            dirty: true,
            isDraft: true,
          };
          setDocuments((current) => [draft, ...current]);
          setSelectedKey(draft.documentKey);
          setCurrentLevel(draftMap.default_level);
          setSelectedObjectId(null);
          setSelectedEntryPointId(null);
          setSelectedCellKey(null);
          setHoveredCell(null);
          onStatusChange(`Created draft map ${nextId}.`);
        } catch (error) {
          onStatusChange(`Create map draft failed: ${String(error)}`);
        }
      })();
      return;
    }

    const nextDocument = documents.find((document) => document.documentKey === documentKey);
    if (!nextDocument) {
      return;
    }
    setSelectedKey(nextDocument.documentKey);
    setCurrentLevel(nextDocument.map.default_level);
    setSelectedObjectId(null);
    setSelectedEntryPointId(null);
    setSelectedCellKey(null);
    setHoveredCell(null);
    onStatusChange(`Opened map ${nextDocument.map.id}.`);
  }

  function updateSelectedMap(transform: (map: MapDefinition) => MapDefinition) {
    setDocuments((current) =>
      current.map((document) => {
        if (document.documentKey !== selectedKey) {
          return document;
        }
        const nextMap = normalizeMapDocument(transform(document.map));
        return {
          ...document,
          map: nextMap,
          dirty: getMapDirtyState(nextMap, document.savedSnapshot),
        };
      }),
    );
  }

  function replaceDocumentMap(documentKey: string, nextMap: MapDefinition) {
    setDocuments((current) =>
      current.map((document) => {
        if (document.documentKey !== documentKey) {
          return document;
        }
        const normalized = normalizeMapDocument(nextMap);
        return {
          ...document,
          map: normalized,
          dirty: getMapDirtyState(normalized, document.savedSnapshot),
        };
      }),
    );
  }

  async function runDocumentMutation(
    documentKey: string,
    localTransform: () => MapDefinition,
    remoteTransform: () => Promise<MapDefinition>,
    errorPrefix: string,
    onSuccess?: (nextMap: MapDefinition) => void,
  ) {
    try {
      const nextMap = canPersist ? await remoteTransform() : localTransform();
      replaceDocumentMap(documentKey, nextMap);
      onSuccess?.(nextMap);
      return nextMap;
    } catch (error) {
      onStatusChange(`${errorPrefix}: ${String(error)}`);
      return null;
    }
  }

  function requestOpenDocument(documentKey: string) {
    const intent: MapEditorPendingIntent = { type: "switch-document", documentKey };
    if (
      shouldDeferPendingIntent(
        Boolean(selectedDocument?.dirty),
        selectedDocument?.documentKey ?? null,
        intent,
      )
    ) {
      setPendingIntent(intent);
      onStatusChange("Resolve unsaved map changes before switching.");
      return false;
    }
    commitSelection(documentKey);
    return true;
  }

  function clearSelection() {
    setSelectedObjectId(null);
    setSelectedEntryPointId(null);
    setSelectedCellKey(null);
    setHoveredCell(null);
  }

  function setToolMode(nextTool: MapTool) {
    setTool(nextTool);
    if (layer === "objects" && nextTool !== "select" && nextTool !== "erase" && nextTool !== "paint-cell" && nextTool !== "entry-point") {
      setPlacementDraft(createPlacementDraft(nextTool, currentLevel, objectSequence));
    }
  }

  function setLayerMode(nextLayer: MapLayer) {
    setLayer(nextLayer);
    setTool(initialToolForLayer(nextLayer));
    clearSelection();
  }

  function updateSelectedObject(transform: (object: MapObjectDefinition) => MapObjectDefinition) {
    if (!selectedObjectId) {
      return;
    }
    updateSelectedMap((map) => updateObject(map, selectedObjectId, transform));
  }

  function updateSelectedEntryPoint(
    transform: (entryPoint: MapEntryPointDefinition) => MapEntryPointDefinition,
  ) {
    if (!selectedEntryPointId) {
      return;
    }
    updateSelectedMap((map) => ({
      ...map,
      entry_points: map.entry_points.map((entryPoint) =>
        entryPoint.id === selectedEntryPointId ? transform(entryPoint) : entryPoint,
      ),
    }));
  }

  function deleteSelectedObject() {
    if (!selectedObject || !selectedDocument) {
      return;
    }
    const objectId = selectedObject.object_id;
    const documentKey = selectedDocument.documentKey;
    const currentMap = selectedDocument.map;
    setSelectedObjectId(null);
    void runDocumentMutation(
      documentKey,
      () => removeObject(currentMap, objectId),
      () => removeMapObject(currentMap, objectId),
      "Delete object failed",
      () => {
        onStatusChange(`Deleted object ${objectId}.`);
      },
    );
  }

  function deleteSelectedEntryPoint() {
    if (!selectedEntryPoint || !selectedDocument) {
      return;
    }
    const entryPointId = selectedEntryPoint.id;
    const documentKey = selectedDocument.documentKey;
    const currentMap = selectedDocument.map;
    setSelectedEntryPointId(null);
    void runDocumentMutation(
      documentKey,
      () => ({
        ...currentMap,
        entry_points: currentMap.entry_points.filter((entryPoint) => entryPoint.id !== entryPointId),
      }),
      () => removeMapEntryPoint(currentMap, entryPointId),
      "Delete entry point failed",
      () => {
        onStatusChange(`Deleted entry point ${entryPointId}.`);
      },
    );
  }

  function addLevel() {
    if (!selectedDocument) {
      return;
    }
    const nextLevel =
      selectedDocument.map.levels.reduce((maxLevel, level) => Math.max(maxLevel, level.y), 0) + 1;
    const documentKey = selectedDocument.documentKey;
    const currentMap = selectedDocument.map;
    void runDocumentMutation(
      documentKey,
      () => ({
        ...currentMap,
        levels: [...currentMap.levels, { y: nextLevel, cells: [] }],
      }),
      () => addMapLevel(currentMap, nextLevel),
      "Add level failed",
      () => {
        setCurrentLevel(nextLevel);
        onStatusChange(`Added level ${nextLevel}.`);
      },
    );
  }

  function stepLevel(delta: -1 | 1) {
    if (!selectedDocument) {
      return;
    }
    const levels = selectedDocument.map.levels.map((level) => level.y).sort((left, right) => left - right);
    const currentIndex = levels.indexOf(currentLevel);
    if (currentIndex === -1) {
      setCurrentLevel(selectedDocument.map.default_level);
      return;
    }
    const nextIndex = Math.min(levels.length - 1, Math.max(0, currentIndex + delta));
    setCurrentLevel(levels[nextIndex]);
  }

  function removeCurrentLevel() {
    if (!selectedDocument) {
      return;
    }
    if (selectedDocument.map.levels.length <= 1) {
      onStatusChange("A map must keep at least one level.");
      return;
    }
    const documentKey = selectedDocument.documentKey;
    const currentMap = selectedDocument.map;
    const nextLevels = currentMap.levels.filter((level) => level.y !== currentLevel);
    setSelectedObjectId(null);
    setSelectedEntryPointId(null);
    setSelectedCellKey(null);
    void runDocumentMutation(
      documentKey,
      () => ({
        ...currentMap,
        default_level:
          currentMap.default_level === currentLevel ? nextLevels[0]?.y ?? 0 : currentMap.default_level,
        levels: nextLevels,
        entry_points: currentMap.entry_points.filter((entryPoint) => entryPoint.grid.y !== currentLevel),
        objects: currentMap.objects.filter((object) => object.anchor.y !== currentLevel),
      }),
      () => removeMapLevel(currentMap, currentLevel),
      "Remove level failed",
      (nextMap) => {
        setCurrentLevel(nextMap.default_level);
        onStatusChange(`Removed level ${currentLevel} and its placed objects.`);
      },
    );
  }

  function handleGridCellClick(grid: GridPoint) {
    setHoveredCell(grid);
    if (!selectedDocument) {
      return;
    }

    if (layer === "cells") {
      if (tool === "select") {
        setSelectedCellKey(gridKey(grid));
        setSelectedObjectId(null);
        setSelectedEntryPointId(null);
        const existingCell = cellAtGrid(selectedDocument.map, grid);
        if (existingCell) {
          setCellDraft({
            terrain: existingCell.terrain,
            blocksMovement: existingCell.blocks_movement,
            blocksSight: existingCell.blocks_sight,
          });
        }
        return;
      }

      if (tool === "erase") {
        const documentKey = selectedDocument.documentKey;
        const currentMap = selectedDocument.map;
        void runDocumentMutation(
          documentKey,
          () => ({
            ...currentMap,
            levels: currentMap.levels.map((level) =>
              level.y === grid.y
                ? {
                    ...level,
                    cells: level.cells.filter((cell) => !(cell.x === grid.x && cell.z === grid.z)),
                  }
                : level,
            ),
          }),
          () => clearMapCells(currentMap, grid.y, [grid]),
          "Clear cell failed",
          () => {
            onStatusChange(`Cleared cell ${grid.x}, ${grid.z} on level ${grid.y}.`);
          },
        );
        if (selectedCellKey === gridKey(grid)) {
          setSelectedCellKey(null);
        }
        return;
      }

      const documentKey = selectedDocument.documentKey;
      const currentMap = selectedDocument.map;
      const paintedCell = {
        x: grid.x,
        z: grid.z,
        blocks_movement: cellDraft.blocksMovement,
        blocks_sight: cellDraft.blocksSight,
        terrain: cellDraft.terrain,
      };
      void runDocumentMutation(
        documentKey,
        () => ({
          ...currentMap,
          levels: currentMap.levels.map((level) =>
            level.y === grid.y
              ? {
                  ...level,
                  cells: [
                    ...level.cells.filter((cell) => !(cell.x === grid.x && cell.z === grid.z)),
                    paintedCell,
                  ],
                }
              : level,
          ),
        }),
        () => paintMapCells(currentMap, grid.y, [paintedCell]),
        "Paint cell failed",
        () => {
          onStatusChange(`Painted cell ${grid.x}, ${grid.z} on level ${grid.y}.`);
        },
      );
      setSelectedCellKey(gridKey(grid));
      setSelectedObjectId(null);
      setSelectedEntryPointId(null);
      return;
    }

    if (layer === "entryPoints") {
      const entryPoint = entryPointAtGrid(selectedDocument.map, grid);
      if (tool === "select") {
        setSelectedEntryPointId(entryPoint?.id ?? null);
        setSelectedObjectId(null);
        setSelectedCellKey(null);
        if (entryPoint) {
          setEntryPointDraft({
            id: entryPoint.id,
            facing: entryPoint.facing ? String(entryPoint.facing) : "",
          });
        }
        return;
      }

      if (tool === "erase") {
        if (!entryPoint) {
          return;
        }
        const documentKey = selectedDocument.documentKey;
        const currentMap = selectedDocument.map;
        void runDocumentMutation(
          documentKey,
          () => ({
            ...currentMap,
            entry_points: currentMap.entry_points.filter(
              (candidate) => candidate.id !== entryPoint.id,
            ),
          }),
          () => removeMapEntryPoint(currentMap, entryPoint.id),
          "Delete entry point failed",
          () => {
            onStatusChange(`Deleted entry point ${entryPoint.id}.`);
          },
        );
        if (selectedEntryPointId === entryPoint.id) {
          setSelectedEntryPointId(null);
        }
        return;
      }

      const nextEntryPointId =
        entryPointDraft.id.trim() || `entry_${selectedDocument.map.entry_points.length + 1}`;
      const documentKey = selectedDocument.documentKey;
      const currentMap = selectedDocument.map;
      const nextEntryPoint = {
        id: nextEntryPointId,
        grid: { x: grid.x, y: grid.y, z: grid.z },
        facing: entryPointDraft.facing.trim() ? entryPointDraft.facing.trim() : null,
      };
      void runDocumentMutation(
        documentKey,
        () => ({
          ...currentMap,
          entry_points: [
            ...currentMap.entry_points.filter((candidate) => candidate.id !== nextEntryPointId),
            nextEntryPoint,
          ],
          default_level: nextEntryPointId === "default_entry" ? grid.y : currentMap.default_level,
        }),
        () => upsertMapEntryPoint(currentMap, nextEntryPoint),
        "Place entry point failed",
        () => {
          onStatusChange(`Placed entry point ${nextEntryPointId}.`);
        },
      );
      setSelectedEntryPointId(nextEntryPointId);
      setSelectedObjectId(null);
      setSelectedCellKey(null);
      return;
    }

    const objectsAtCell = getObjectsAtCell(selectedDocument.map, grid);
    if (tool === "select") {
      setSelectedObjectId(lastObject(objectsAtCell)?.object_id ?? null);
      setSelectedEntryPointId(null);
      setSelectedCellKey(null);
      return;
    }
    if (tool === "erase") {
      const target = lastObject(objectsAtCell);
      if (!target) {
        return;
      }
      const documentKey = selectedDocument.documentKey;
      const currentMap = selectedDocument.map;
      void runDocumentMutation(
        documentKey,
        () => removeObject(currentMap, target.object_id),
        () => removeMapObject(currentMap, target.object_id),
        "Erase object failed",
        () => {
          onStatusChange(`Erased ${target.object_id}.`);
        },
      );
      if (selectedObjectId === target.object_id) {
        setSelectedObjectId(null);
      }
      return;
    }

    if (!isObjectPlacementTool(tool)) {
      return;
    }

    const nextObjectId = `${tool}_${objectSequence}`;
    const documentKey = selectedDocument.documentKey;
    const currentMap = selectedDocument.map;
    const nextObject = buildPlacementObject(
      {
        ...placementDraft,
        kind: tool,
      },
      grid,
      nextObjectId,
    );
    setObjectSequence((current) => current + 1);
    setSelectedObjectId(nextObjectId);
    setSelectedEntryPointId(null);
    setSelectedCellKey(null);
    void runDocumentMutation(
      documentKey,
      () =>
        applyPlacement(
          currentMap,
          {
            ...placementDraft,
            kind: tool,
          },
          grid,
          nextObjectId,
        ),
      () => upsertMapObject(currentMap, nextObject),
      "Place object failed",
      () => {
        onStatusChange(`Placed object ${nextObjectId}.`);
      },
    );
  }

  function rotatePlacement() {
    setPlacementDraft((current) => ({
      ...current,
      rotation: nextRotation(current.rotation),
    }));
  }

  async function validateCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select a map first.");
      return false;
    }

    if (!canPersist) {
      const counts = getIssueCounts(selectedDocument.validation);
      onStatusChange(
        counts.errorCount + counts.warningCount === 0
          ? "Current map looks clean in fallback mode."
          : `Current map has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
      return true;
    }

    try {
      const issues = await invokeCommand<ValidationIssue[]>("validate_map_document", {
        map: selectedDocument.map,
      });
      setDocuments((current) =>
        current.map((document) =>
          document.documentKey === selectedDocument.documentKey
            ? { ...document, validation: issues }
            : document,
        ),
      );
      const counts = getIssueCounts(issues);
      onStatusChange(
        counts.errorCount + counts.warningCount === 0
          ? `Map ${selectedDocument.map.id} passed validation.`
          : `Map ${selectedDocument.map.id} has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
      return true;
    } catch (error) {
      onStatusChange(`Map validation failed: ${String(error)}`);
      return false;
    }
  }

  async function saveAll() {
    const dirtyDocuments = documents.filter((document) => document.dirty);
    if (!dirtyDocuments.length) {
      onStatusChange("No unsaved map changes.");
      return null;
    }
    if (!canPersist) {
      onStatusChange("Cannot save in UI fallback mode.");
      return null;
    }

    setBusy(true);
    try {
      const result = await invokeCommand<SaveMapsResult>("save_map_documents", {
        documents: dirtyDocuments.map((document) => ({
          originalId: document.isDraft ? null : document.originalId,
          map: document.map,
        })),
      });
      preferredSelectionAfterReloadRef.current = selectedDocument?.map.id ?? null;
      await onReload();
      onStatusChange(
        `Saved ${result.savedIds.length} maps. Removed ${result.deletedIds.length} renamed files.`,
      );
      return result;
    } catch (error) {
      onStatusChange(`Map save failed: ${String(error)}`);
      return null;
    } finally {
      setBusy(false);
    }
  }

  async function deleteCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select a map first.");
      return null;
    }

    if (selectedDocument.isDraft) {
      const remaining = documents.filter(
        (document) => document.documentKey !== selectedDocument.documentKey,
      );
      setDocuments(remaining);
      setSelectedKey(remaining[0]?.documentKey ?? "");
      setSelectedObjectId(null);
      setSelectedEntryPointId(null);
      setSelectedCellKey(null);
      setHoveredCell(null);
      onStatusChange("Removed unsaved map draft.");
      return [];
    }

    if (!canPersist) {
      onStatusChange("Cannot delete project files in UI fallback mode.");
      return null;
    }

    setBusy(true);
    try {
      await invokeCommand("delete_map_document", {
        mapId: selectedDocument.originalId,
      });
      preferredSelectionAfterReloadRef.current = null;
      await onReload();
      setSelectedObjectId(null);
      setSelectedEntryPointId(null);
      setSelectedCellKey(null);
      setHoveredCell(null);
      onStatusChange(`Deleted map ${selectedDocument.originalId}.`);
      return [selectedDocument.originalId];
    } catch (error) {
      onStatusChange(`Map delete failed: ${String(error)}`);
      return null;
    } finally {
      setBusy(false);
    }
  }

  function discardCurrentChanges() {
    if (!selectedDocument?.dirty) {
      return;
    }

    if (selectedDocument.isDraft) {
      const remaining = documents.filter(
        (document) => document.documentKey !== selectedDocument.documentKey,
      );
      setDocuments(remaining);
      const nextSelection = remaining[0]?.documentKey ?? "";
      setSelectedKey(nextSelection);
      const nextDocument = remaining.find((document) => document.documentKey === nextSelection);
      setCurrentLevel(nextDocument?.map.default_level ?? 0);
      setSelectedObjectId(null);
      setSelectedEntryPointId(null);
      setSelectedCellKey(null);
      setHoveredCell(null);
      onStatusChange("Discarded unsaved draft.");
      return;
    }

    const original = workspace.documents.find(
      (document) => document.documentKey === selectedDocument.documentKey,
    );
    if (!original) {
      return;
    }

    const restored = hydrateDocuments([original])[0];
    setDocuments((current) =>
      current.map((document) =>
        document.documentKey === restored.documentKey ? restored : document,
      ),
    );
    setCurrentLevel(restored.map.default_level);
    setSelectedObjectId(null);
    setSelectedEntryPointId(null);
    setSelectedCellKey(null);
    setHoveredCell(null);
    onStatusChange(`Discarded unsaved changes for ${restored.map.id}.`);
  }

  function requestCloseWindow() {
    const intent: MapEditorPendingIntent = { type: "close-window" };
    if (
      shouldDeferPendingIntent(
        Boolean(selectedDocument?.dirty),
        selectedDocument?.documentKey ?? null,
        intent,
      )
    ) {
      setPendingIntent(intent);
      onStatusChange("Resolve unsaved map changes before closing.");
      return false;
    }
    return true;
  }

  async function resolvePendingAction(
    action: "save" | "discard" | "cancel",
    options?: { skipSave?: boolean },
  ) {
    if (!pendingIntent) {
      return null;
    }

    if (action === "cancel") {
      setPendingIntent(null);
      onStatusChange("Stayed on current map.");
      return null;
    }

    if (action === "save") {
      if (!options?.skipSave) {
        const result = await saveAll();
        if (!result) {
          return null;
        }
      }
    } else {
      discardCurrentChanges();
    }

    const intent = pendingIntent;
    setPendingIntent(null);
    if (intent.type === "switch-document") {
      commitSelection(intent.documentKey);
      return intent.type;
    }
    onStatusChange("Closing map editor.");
    return intent.type;
  }

  return {
    documents,
    selectedKey,
    selectedDocument,
    selectedObject,
    selectedEntryPoint,
    selectedCell,
    selectedObjectId,
    hoveredCell,
    currentLevel,
    layer,
    cellDraft,
    entryPointDraft,
    placementDraft,
    tool,
    busy,
    dirtyCount,
    totalIssues,
    selectedIssues,
    selectedCounts,
    toolOptions,
    hoveredPreview,
    selectedCoverage,
    pendingIntent,
    canCloseWithoutPrompt: !selectedDocument?.dirty,
    setCurrentLevel,
    setHoveredCell,
    setLayerMode,
    setCellDraft,
    setEntryPointDraft,
    setPlacementDraft,
    setSelectedObjectId,
    setToolMode,
    clearSelection,
    changeSelectedObjectKind: (nextKind: MapObjectKind) =>
      updateSelectedObject((object) => changeObjectKind(object, nextKind)),
    updateSelectedMap,
    updateSelectedObject,
    updateSelectedEntryPoint,
    handleGridCellClick,
    requestOpenDocument,
    requestNewDraft: () => requestOpenDocument(NEW_MAP_DOCUMENT_KEY),
    requestCloseWindow,
    resolvePendingAction,
    saveAll,
    validateCurrent,
    deleteCurrent,
    addLevel,
    removeCurrentLevel,
    stepLevel,
    rotatePlacement,
    deleteSelectedObject,
    deleteSelectedEntryPoint,
  };
}
