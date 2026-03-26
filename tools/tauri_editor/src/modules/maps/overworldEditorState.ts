import { useEffect, useRef, useState } from "react";
import { invokeCommand } from "../../lib/tauri";
import type {
  OverworldDefinition,
  OverworldDocumentPayload,
  OverworldLocationDefinition,
  OverworldWorkspacePayload,
  SaveOverworldsResult,
  ValidationIssue,
} from "../../types";
import { MapEditorPendingIntent, shouldDeferPendingIntent } from "./mapEditorGuards";
import { NEW_MAP_DOCUMENT_KEY } from "./mapWindowing";
import type { GridPoint } from "./mapEditorUtils";
import {
  createDraftOverworld,
  createLocationDraft,
  getLocationAtCell,
  getOverworldDirtyState,
  normalizeOverworldDocument,
  removeLocation,
  removeWalkableCell,
  summarizeOverworld,
  upsertLocation,
  upsertWalkableCell,
  type OverworldLocationDraft,
} from "./overworldEditorUtils";
import { getIssueCounts } from "./mapEditorState";

export type EditableOverworldDocument = OverworldDocumentPayload & {
  savedSnapshot: string;
  dirty: boolean;
  isDraft: boolean;
};

export type OverworldTool = "select" | "paint" | "erase-cell" | "location";

type UseOverworldEditorStateOptions = {
  workspace: OverworldWorkspacePayload;
  canPersist: boolean;
  onStatusChange: (status: string) => void;
  onReload: () => Promise<void>;
  initialDocumentKey?: string | null;
};

function hydrateDocuments(documents: OverworldDocumentPayload[]): EditableOverworldDocument[] {
  return documents.map((document) => {
    const normalized = normalizeOverworldDocument(document.overworld);
    return {
      ...document,
      overworld: normalized,
      savedSnapshot: JSON.stringify(normalized),
      dirty: false,
      isDraft: false,
    };
  });
}

function getInitialSelectionKey(
  documents: EditableOverworldDocument[],
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

export function overworldGridKey(grid: GridPoint) {
  return `${grid.x}:${grid.y}:${grid.z}`;
}

export function useOverworldEditorState({
  workspace,
  canPersist,
  onStatusChange,
  onReload,
  initialDocumentKey = null,
}: UseOverworldEditorStateOptions) {
  const [documents, setDocuments] = useState<EditableOverworldDocument[]>(() =>
    hydrateDocuments(workspace.documents),
  );
  const [selectedKey, setSelectedKey] = useState(() =>
    getInitialSelectionKey(hydrateDocuments(workspace.documents), initialDocumentKey),
  );
  const [busy, setBusy] = useState(false);
  const [tool, setTool] = useState<OverworldTool>("paint");
  const [hoveredCell, setHoveredCell] = useState<GridPoint | null>(null);
  const [selectedLocationId, setSelectedLocationId] = useState<string | null>(null);
  const [terrainDraft, setTerrainDraft] = useState("road");
  const [locationDraft, setLocationDraft] = useState<OverworldLocationDraft>(() =>
    createLocationDraft(1),
  );
  const [locationSequence, setLocationSequence] = useState(1);
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
    setSelectedLocationId(null);
    setHoveredCell(null);
    setPendingIntent(null);
  }, [initialDocumentKey, workspace]);

  const selectedDocument =
    documents.find((document) => document.documentKey === selectedKey) ?? null;
  const selectedLocation =
    selectedDocument?.overworld.locations.find((location) => location.id === selectedLocationId) ??
    null;
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
  const selectedIssues = selectedDocument?.validation ?? [];
  const selectedCounts = getIssueCounts(selectedIssues);

  useEffect(() => {
    if (!selectedDocument || !canPersist) {
      return;
    }

    const timeoutId = window.setTimeout(() => {
      void invokeCommand<ValidationIssue[]>("validate_overworld_document", {
        overworld: selectedDocument.overworld,
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
  }, [canPersist, selectedDocument?.documentKey, selectedDocument?.overworld]);

  function updateSelectedOverworld(transform: (overworld: OverworldDefinition) => OverworldDefinition) {
    setDocuments((current) =>
      current.map((document) => {
        if (document.documentKey !== selectedKey) {
          return document;
        }
        const nextOverworld = normalizeOverworldDocument(transform(document.overworld));
        return {
          ...document,
          overworld: nextOverworld,
          dirty: getOverworldDirtyState(nextOverworld, document.savedSnapshot),
        };
      }),
    );
  }

  function commitSelection(documentKey: string) {
    if (documentKey === NEW_MAP_DOCUMENT_KEY) {
      const nextId = `overworld_${Date.now()}`;
      const draftOverworld = createDraftOverworld(nextId);
      const draft: EditableOverworldDocument = {
        documentKey: `draft-${nextId}`,
        originalId: nextId,
        fileName: `${nextId}.json`,
        relativePath: `data/overworld/${nextId}.json`,
        overworld: draftOverworld,
        validation: [],
        savedSnapshot: "",
        dirty: true,
        isDraft: true,
      };
      setDocuments((current) => [draft, ...current]);
      setSelectedKey(draft.documentKey);
      setSelectedLocationId(null);
      setHoveredCell(null);
      onStatusChange(`Created draft overworld ${nextId}.`);
      return;
    }

    const nextDocument = documents.find((document) => document.documentKey === documentKey);
    if (!nextDocument) {
      return;
    }
    setSelectedKey(nextDocument.documentKey);
    setSelectedLocationId(null);
    setHoveredCell(null);
    onStatusChange(`Opened overworld ${nextDocument.overworld.id}.`);
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
      onStatusChange("Resolve unsaved overworld changes before switching.");
      return false;
    }
    commitSelection(documentKey);
    return true;
  }

  function clearSelection() {
    setSelectedLocationId(null);
    setHoveredCell(null);
  }

  function updateSelectedLocation(
    transform: (location: OverworldLocationDefinition) => OverworldLocationDefinition,
  ) {
    if (!selectedLocationId) {
      return;
    }
    updateSelectedOverworld((overworld) => ({
      ...overworld,
      locations: overworld.locations.map((location) =>
        location.id === selectedLocationId ? transform(location) : location,
      ),
    }));
  }

  function deleteSelectedLocation() {
    if (!selectedLocation) {
      return;
    }
    updateSelectedOverworld((overworld) => removeLocation(overworld, selectedLocation.id));
    setSelectedLocationId(null);
    onStatusChange(`Deleted location ${selectedLocation.id}.`);
  }

  function handleGridCellClick(grid: GridPoint) {
    setHoveredCell(grid);
    if (!selectedDocument) {
      return;
    }

    if (tool === "select") {
      setSelectedLocationId(getLocationAtCell(selectedDocument.overworld, grid)?.id ?? null);
      return;
    }

    if (tool === "erase-cell") {
      updateSelectedOverworld((overworld) => removeWalkableCell(overworld, grid));
      onStatusChange(`Removed walkable cell ${grid.x}, ${grid.z}.`);
      return;
    }

    if (tool === "paint") {
      updateSelectedOverworld((overworld) => upsertWalkableCell(overworld, grid, terrainDraft));
      onStatusChange(`Painted overworld cell ${grid.x}, ${grid.z}.`);
      return;
    }

    const nextLocationId = locationDraft.id.trim() || `location_${locationSequence}`;
    setLocationSequence((current) => current + 1);
    updateSelectedOverworld((overworld) =>
      upsertLocation(overworld, {
        id: nextLocationId,
        name: locationDraft.name,
        description: locationDraft.description,
        kind: locationDraft.kind,
        map_id: locationDraft.mapId,
        entry_point_id: locationDraft.entryPointId,
        parent_outdoor_location_id: locationDraft.parentOutdoorLocationId || null,
        return_entry_point_id: locationDraft.returnEntryPointId || null,
        default_unlocked: locationDraft.defaultUnlocked,
        visible: locationDraft.visible,
        overworld_cell: { x: grid.x, y: grid.y, z: grid.z },
        danger_level: locationDraft.dangerLevel,
        icon: locationDraft.icon,
      }),
    );
    setSelectedLocationId(nextLocationId);
    onStatusChange(`Placed location ${nextLocationId}.`);
  }

  async function validateCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select an overworld first.");
      return false;
    }

    if (!canPersist) {
      const counts = getIssueCounts(selectedDocument.validation);
      onStatusChange(
        counts.errorCount + counts.warningCount === 0
          ? "Current overworld looks clean in fallback mode."
          : `Current overworld has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
      return true;
    }

    try {
      const issues = await invokeCommand<ValidationIssue[]>("validate_overworld_document", {
        overworld: selectedDocument.overworld,
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
          ? `Overworld ${selectedDocument.overworld.id} passed validation.`
          : `Overworld ${selectedDocument.overworld.id} has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
      return true;
    } catch (error) {
      onStatusChange(`Overworld validation failed: ${String(error)}`);
      return false;
    }
  }

  async function saveAll() {
    const dirtyDocuments = documents.filter((document) => document.dirty);
    if (!dirtyDocuments.length) {
      onStatusChange("No unsaved overworld changes.");
      return null;
    }
    if (!canPersist) {
      onStatusChange("Cannot save in UI fallback mode.");
      return null;
    }

    setBusy(true);
    try {
      const result = await invokeCommand<SaveOverworldsResult>("save_overworld_documents", {
        documents: dirtyDocuments.map((document) => ({
          originalId: document.isDraft ? null : document.originalId,
          overworld: document.overworld,
        })),
      });
      preferredSelectionAfterReloadRef.current = selectedDocument?.overworld.id ?? null;
      await onReload();
      onStatusChange(
        `Saved ${result.savedIds.length} overworld files. Removed ${result.deletedIds.length} renamed files.`,
      );
      return result;
    } catch (error) {
      onStatusChange(`Overworld save failed: ${String(error)}`);
      return null;
    } finally {
      setBusy(false);
    }
  }

  async function deleteCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select an overworld first.");
      return null;
    }

    if (selectedDocument.isDraft) {
      const remaining = documents.filter(
        (document) => document.documentKey !== selectedDocument.documentKey,
      );
      setDocuments(remaining);
      setSelectedKey(remaining[0]?.documentKey ?? "");
      setSelectedLocationId(null);
      setHoveredCell(null);
      onStatusChange("Removed unsaved overworld draft.");
      return [];
    }

    if (!canPersist) {
      onStatusChange("Cannot delete project files in UI fallback mode.");
      return null;
    }

    setBusy(true);
    try {
      await invokeCommand("delete_overworld_document", {
        overworldId: selectedDocument.originalId,
      });
      preferredSelectionAfterReloadRef.current = null;
      await onReload();
      setSelectedLocationId(null);
      setHoveredCell(null);
      onStatusChange(`Deleted overworld ${selectedDocument.originalId}.`);
      return [selectedDocument.originalId];
    } catch (error) {
      onStatusChange(`Overworld delete failed: ${String(error)}`);
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
      setSelectedKey(remaining[0]?.documentKey ?? "");
      setSelectedLocationId(null);
      setHoveredCell(null);
      onStatusChange("Discarded unsaved overworld draft.");
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
    setSelectedLocationId(null);
    setHoveredCell(null);
    onStatusChange(`Discarded unsaved changes for ${restored.overworld.id}.`);
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
      onStatusChange("Resolve unsaved overworld changes before closing.");
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
      onStatusChange("Stayed on current overworld.");
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
    onStatusChange("Closing overworld editor.");
    return intent.type;
  }

  return {
    documents,
    selectedKey,
    selectedDocument,
    selectedLocation,
    hoveredCell,
    tool,
    terrainDraft,
    locationDraft,
    busy,
    dirtyCount,
    totalIssues,
    selectedIssues,
    selectedCounts,
    pendingIntent,
    canCloseWithoutPrompt: !selectedDocument?.dirty,
    setHoveredCell,
    setTool,
    setTerrainDraft,
    setLocationDraft,
    clearSelection,
    updateSelectedOverworld,
    updateSelectedLocation,
    deleteSelectedLocation,
    handleGridCellClick,
    requestOpenDocument,
    requestNewDraft: () => requestOpenDocument(NEW_MAP_DOCUMENT_KEY),
    requestCloseWindow,
    resolvePendingAction,
    saveAll,
    validateCurrent,
    deleteCurrent,
    summarizeCurrent: selectedDocument ? summarizeOverworld(selectedDocument.overworld) : "",
  };
}
