import { useEffect, useMemo, useRef, useState } from "react";
import { invokeCommand } from "../../lib/tauri";
import type {
  MapDefinition,
  MapDocumentPayload,
  MapObjectDefinition,
  MapObjectKind,
  MapRotation,
  MapWorkspacePayload,
  SaveMapsResult,
  ValidationIssue,
} from "../../types";
import {
  applyPlacement,
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
import { MapEditorPendingIntent, shouldDeferPendingIntent } from "./mapEditorGuards";
import { NEW_MAP_DOCUMENT_KEY } from "./mapWindowing";

export type EditableMapDocument = MapDocumentPayload & {
  savedSnapshot: string;
  dirty: boolean;
  isDraft: boolean;
};

export type MapTool = "select" | "erase" | MapObjectKind;

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
  const [selectedObjectId, setSelectedObjectId] = useState<string | null>(null);
  const [hoveredCell, setHoveredCell] = useState<GridPoint | null>(null);
  const [tool, setTool] = useState<MapTool>("select");
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
    setHoveredCell(null);
    setPendingIntent(null);
  }, [initialDocumentKey, workspace]);

  const selectedDocument =
    documents.find((document) => document.documentKey === selectedKey) ?? null;
  const selectedObject =
    selectedDocument?.map.objects.find((object) => object.object_id === selectedObjectId) ?? null;
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
  }, [canPersist, selectedDocument]);

  const selectedIssues = selectedDocument?.validation ?? [];
  const selectedCounts = getIssueCounts(selectedIssues);
  const toolOptions: MapTool[] = ["select", "erase", "building", "pickup", "interactive", "ai_spawn"];
  const hoveredPreview =
    hoveredCell && tool !== "select" && tool !== "erase"
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
  const selectedCoverage = selectedObject ? getOccupiedCells(selectedObject) : [];

  function commitSelection(documentKey: string) {
    if (documentKey === NEW_MAP_DOCUMENT_KEY) {
      const nextId = `map_${Date.now()}`;
      const draftMap = createDraftMap(nextId);
      const draft: EditableMapDocument = {
        documentKey: `draft-${nextId}`,
        originalId: nextId,
        fileName: `${nextId}.json`,
        relativePath: `data/maps/${nextId}.json`,
        map: draftMap,
        validation: [],
        savedSnapshot: "",
        dirty: true,
        isDraft: true,
      };
      setDocuments((current) => [draft, ...current]);
      setSelectedKey(draft.documentKey);
      setCurrentLevel(draftMap.default_level);
      setSelectedObjectId(null);
      setHoveredCell(null);
      onStatusChange(`Created draft map ${nextId}.`);
      return;
    }

    const nextDocument = documents.find((document) => document.documentKey === documentKey);
    if (!nextDocument) {
      return;
    }
    setSelectedKey(nextDocument.documentKey);
    setCurrentLevel(nextDocument.map.default_level);
    setSelectedObjectId(null);
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
    setHoveredCell(null);
  }

  function setToolMode(nextTool: MapTool) {
    setTool(nextTool);
    if (nextTool !== "select" && nextTool !== "erase") {
      setPlacementDraft(createPlacementDraft(nextTool, currentLevel, objectSequence));
    }
  }

  function updateSelectedObject(transform: (object: MapObjectDefinition) => MapObjectDefinition) {
    if (!selectedObjectId) {
      return;
    }
    updateSelectedMap((map) => updateObject(map, selectedObjectId, transform));
  }

  function deleteSelectedObject() {
    if (!selectedObject) {
      return;
    }
    updateSelectedMap((map) => removeObject(map, selectedObject.object_id));
    setSelectedObjectId(null);
    onStatusChange(`Deleted object ${selectedObject.object_id}.`);
  }

  function addLevel() {
    if (!selectedDocument) {
      return;
    }
    const nextLevel =
      selectedDocument.map.levels.reduce((maxLevel, level) => Math.max(maxLevel, level.y), 0) + 1;
    updateSelectedMap((map) => ({
      ...map,
      levels: [...map.levels, { y: nextLevel, cells: [] }],
    }));
    setCurrentLevel(nextLevel);
    onStatusChange(`Added level ${nextLevel}.`);
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
    const nextLevels = selectedDocument.map.levels.filter((level) => level.y !== currentLevel);
    updateSelectedMap((map) => ({
      ...map,
      default_level:
        map.default_level === currentLevel ? nextLevels[0]?.y ?? 0 : map.default_level,
      levels: nextLevels,
      objects: map.objects.filter((object) => object.anchor.y !== currentLevel),
    }));
    setCurrentLevel(nextLevels[0]?.y ?? 0);
    setSelectedObjectId(null);
    onStatusChange(`Removed level ${currentLevel} and its placed objects.`);
  }

  function handleGridCellClick(grid: GridPoint) {
    setHoveredCell(grid);
    if (!selectedDocument) {
      return;
    }

    const objectsAtCell = getObjectsAtCell(selectedDocument.map, grid);
    if (tool === "select") {
      setSelectedObjectId(lastObject(objectsAtCell)?.object_id ?? null);
      return;
    }
    if (tool === "erase") {
      const target = lastObject(objectsAtCell);
      if (!target) {
        return;
      }
      updateSelectedMap((map) => removeObject(map, target.object_id));
      if (selectedObjectId === target.object_id) {
        setSelectedObjectId(null);
      }
      onStatusChange(`Erased ${target.object_id}.`);
      return;
    }

    const nextObjectId = `${tool}_${objectSequence}`;
    setObjectSequence((current) => current + 1);
    setSelectedObjectId(nextObjectId);
    updateSelectedMap((map) =>
      applyPlacement(
        map,
        {
          ...placementDraft,
          kind: tool,
        },
        grid,
        nextObjectId,
      ),
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
    selectedObjectId,
    hoveredCell,
    currentLevel,
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
    setPlacementDraft,
    setSelectedObjectId,
    setToolMode,
    clearSelection,
    changeSelectedObjectKind: (nextKind: MapObjectKind) =>
      updateSelectedObject((object) => changeObjectKind(object, nextKind)),
    updateSelectedMap,
    updateSelectedObject,
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
  };
}
