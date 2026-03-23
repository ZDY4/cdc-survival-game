import { useDeferredValue, useEffect, useMemo, useState } from "react";
import { Badge } from "../../components/Badge";
import {
  CheckboxField,
  NumberField,
  SelectField,
  TextField,
} from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { Toolbar } from "../../components/Toolbar";
import { ValidationPanel } from "../../components/ValidationPanel";
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
  summarizeMap,
  updateObject,
  type GridPoint,
  type PlacementDraft,
} from "./mapEditorUtils";

type EditableMapDocument = MapDocumentPayload & {
  savedSnapshot: string;
  dirty: boolean;
  isDraft: boolean;
};

type MapWorkspaceProps = {
  workspace: MapWorkspacePayload;
  canPersist: boolean;
  onStatusChange: (status: string) => void;
  onReload: () => Promise<void>;
};

type MapTool = "select" | "erase" | MapObjectKind;

function hydrateDocuments(documents: MapDocumentPayload[]): EditableMapDocument[] {
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

function getIssueCounts(issues: ValidationIssue[]) {
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

function gridKey(grid: GridPoint) {
  return `${grid.x}:${grid.y}:${grid.z}`;
}

function lastObject(objects: MapObjectDefinition[]) {
  return objects.length > 0 ? objects[objects.length - 1] : undefined;
}

function objectGlyph(kind: MapObjectKind) {
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

export function MapWorkspace({
  workspace,
  canPersist,
  onStatusChange,
  onReload,
}: MapWorkspaceProps) {
  const [documents, setDocuments] = useState<EditableMapDocument[]>(
    hydrateDocuments(workspace.documents),
  );
  const [selectedKey, setSelectedKey] = useState(workspace.documents[0]?.documentKey ?? "");
  const [searchText, setSearchText] = useState("");
  const [busy, setBusy] = useState(false);
  const [currentLevel, setCurrentLevel] = useState(workspace.documents[0]?.map.default_level ?? 0);
  const [selectedObjectId, setSelectedObjectId] = useState<string | null>(null);
  const [hoveredCell, setHoveredCell] = useState<GridPoint | null>(null);
  const [tool, setTool] = useState<MapTool>("select");
  const [placementDraft, setPlacementDraft] = useState<PlacementDraft>(
    createPlacementDraft("building", currentLevel, 1),
  );
  const [objectSequence, setObjectSequence] = useState(1);
  const deferredSearch = useDeferredValue(searchText);

  useEffect(() => {
    setDocuments(hydrateDocuments(workspace.documents));
    setSelectedKey(workspace.documents[0]?.documentKey ?? "");
    setCurrentLevel(workspace.documents[0]?.map.default_level ?? 0);
    setSelectedObjectId(null);
    setHoveredCell(null);
  }, [workspace]);

  const filteredDocuments = useMemo(
    () =>
      documents.filter((document) => {
        if (!deferredSearch.trim()) {
          return true;
        }
        const haystack = `${document.map.id} ${document.fileName}`.toLowerCase();
        return haystack.includes(deferredSearch.trim().toLowerCase());
      }),
    [deferredSearch, documents],
  );

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

  function createDraft() {
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
    onStatusChange(`Created draft map ${nextId}.`);
  }

  async function validateCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select a map first.");
      return;
    }

    if (!canPersist) {
      const counts = getIssueCounts(selectedDocument.validation);
      onStatusChange(
        counts.errorCount + counts.warningCount === 0
          ? "Current map looks clean in fallback mode."
          : `Current map has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
      return;
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
    } catch (error) {
      onStatusChange(`Map validation failed: ${String(error)}`);
    }
  }

  async function saveAll() {
    const dirtyDocuments = documents.filter((document) => document.dirty);
    if (!dirtyDocuments.length) {
      onStatusChange("No unsaved map changes.");
      return;
    }
    if (!canPersist) {
      onStatusChange("Cannot save in UI fallback mode.");
      return;
    }

    setBusy(true);
    try {
      const result = await invokeCommand<SaveMapsResult>("save_map_documents", {
        documents: dirtyDocuments.map((document) => ({
          originalId: document.isDraft ? null : document.originalId,
          map: document.map,
        })),
      });
      await onReload();
      onStatusChange(
        `Saved ${result.savedIds.length} maps. Removed ${result.deletedIds.length} renamed files.`,
      );
    } catch (error) {
      onStatusChange(`Map save failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function deleteCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select a map first.");
      return;
    }

    if (selectedDocument.isDraft) {
      const remaining = documents.filter(
        (document) => document.documentKey !== selectedDocument.documentKey,
      );
      setDocuments(remaining);
      setSelectedKey(remaining[0]?.documentKey ?? "");
      setSelectedObjectId(null);
      onStatusChange("Removed unsaved map draft.");
      return;
    }

    if (!canPersist) {
      onStatusChange("Cannot delete project files in UI fallback mode.");
      return;
    }

    setBusy(true);
    try {
      await invokeCommand("delete_map_document", {
        mapId: selectedDocument.originalId,
      });
      await onReload();
      setSelectedObjectId(null);
      onStatusChange(`Deleted map ${selectedDocument.originalId}.`);
    } catch (error) {
      onStatusChange(`Map delete failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
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

  function updateSelectedObject(transform: (object: MapObjectDefinition) => MapObjectDefinition) {
    if (!selectedObjectId) {
      return;
    }
    updateSelectedMap((map) => updateObject(map, selectedObjectId, transform));
  }

  const actions = [
    { id: "new", label: "New map", onClick: createDraft, tone: "accent" as const, disabled: busy },
    {
      id: "save",
      label: "Save all",
      onClick: () => {
        void saveAll();
      },
      disabled: busy || dirtyCount === 0,
    },
    {
      id: "validate",
      label: "Validate current",
      onClick: () => {
        void validateCurrent();
      },
      disabled: busy || !selectedDocument,
    },
    {
      id: "reload",
      label: "Reload",
      onClick: () => {
        void onReload();
      },
      disabled: busy,
    },
    {
      id: "delete",
      label: "Delete current",
      onClick: () => {
        void deleteCurrent();
      },
      tone: "danger" as const,
      disabled: busy || !selectedDocument,
    },
  ];

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

  return (
    <div className="workspace">
      <Toolbar actions={actions}>
        <div className="toolbar-summary">
          <Badge tone="accent">{workspace.mapCount} files</Badge>
          <Badge tone={dirtyCount > 0 ? "warning" : "muted"}>{dirtyCount} dirty</Badge>
          <Badge tone={totalIssues.errors > 0 ? "danger" : "success"}>
            {totalIssues.errors} errors
          </Badge>
          <Badge tone={totalIssues.warnings > 0 ? "warning" : "muted"}>
            {totalIssues.warnings} warnings
          </Badge>
        </div>
      </Toolbar>

      <div className="workspace-grid">
        <aside className="column">
          <PanelSection label="Map index" title="Project maps">
            <TextField
              label="Search"
              value={searchText}
              onChange={setSearchText}
              placeholder="Filter by map id"
            />
            <div className="item-list">
              {filteredDocuments.map((document) => {
                const counts = getIssueCounts(document.validation);
                return (
                  <button
                    key={document.documentKey}
                    type="button"
                    className={`item-row ${
                      document.documentKey === selectedKey ? "item-row-active" : ""
                    }`}
                    onClick={() => {
                      setSelectedKey(document.documentKey);
                      setCurrentLevel(document.map.default_level);
                      setSelectedObjectId(null);
                    }}
                  >
                    <div className="item-row-top">
                      <strong>{document.map.id || "Unnamed map"}</strong>
                      {document.dirty ? <Badge tone="warning">Dirty</Badge> : null}
                    </div>
                    <p>{summarizeMap(document.map)}</p>
                    <div className="row-badges">
                      <Badge tone="muted">{document.map.levels.length} levels</Badge>
                      <Badge tone="muted">{document.map.objects.length} objects</Badge>
                      {counts.errorCount > 0 ? (
                        <Badge tone="danger">{counts.errorCount} errors</Badge>
                      ) : null}
                    </div>
                  </button>
                );
              })}
            </div>
          </PanelSection>
        </aside>

        <main className="column column-main">
          {selectedDocument ? (
            <>
              <PanelSection label="Document" title={selectedDocument.map.id || "Unnamed map"}>
                <div className="stats-grid">
                  <article className="stat-card">
                    <span>Map ID</span>
                    <strong>{selectedDocument.map.id}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Grid</span>
                    <strong>
                      {selectedDocument.map.size.width} x {selectedDocument.map.size.height}
                    </strong>
                  </article>
                  <article className="stat-card">
                    <span>Objects</span>
                    <strong>{selectedDocument.map.objects.length}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Validation</span>
                    <strong>
                      {selectedCounts.errorCount}E / {selectedCounts.warningCount}W
                    </strong>
                  </article>
                </div>
                <div className="form-grid">
                  <TextField
                    label="Map ID"
                    value={selectedDocument.map.id}
                    onChange={(value) =>
                      updateSelectedMap((map) => ({ ...map, id: value.trim() }))
                    }
                  />
                  <TextField
                    label="Name"
                    value={selectedDocument.map.name}
                    onChange={(value) => updateSelectedMap((map) => ({ ...map, name: value }))}
                  />
                  <NumberField
                    label="Width"
                    value={selectedDocument.map.size.width}
                    onChange={(value) =>
                      updateSelectedMap((map) => ({
                        ...map,
                        size: { ...map.size, width: Math.max(1, Math.floor(value)) },
                      }))
                    }
                    min={1}
                  />
                  <NumberField
                    label="Height"
                    value={selectedDocument.map.size.height}
                    onChange={(value) =>
                      updateSelectedMap((map) => ({
                        ...map,
                        size: { ...map.size, height: Math.max(1, Math.floor(value)) },
                      }))
                    }
                    min={1}
                  />
                </div>
              </PanelSection>

              <PanelSection label="Authoring" title="Levels and placement">
                <div className="toolbar-summary">
                  <button
                    type="button"
                    className="toolbar-button"
                    onClick={addLevel}
                    disabled={busy}
                  >
                    Add level
                  </button>
                  <button
                    type="button"
                    className="toolbar-button toolbar-danger"
                    onClick={removeCurrentLevel}
                    disabled={busy}
                  >
                    Remove current level
                  </button>
                </div>
                <div className="form-grid">
                  <SelectField
                    label="Current level"
                    value={String(currentLevel)}
                    onChange={(value) => setCurrentLevel(Number(value))}
                    options={selectedDocument.map.levels.map((level) => String(level.y))}
                    allowBlank={false}
                  />
                  <SelectField
                    label="Default level"
                    value={String(selectedDocument.map.default_level)}
                    onChange={(value) =>
                      updateSelectedMap((map) => ({ ...map, default_level: Number(value) }))
                    }
                    options={selectedDocument.map.levels.map((level) => String(level.y))}
                    allowBlank={false}
                  />
                  <SelectField
                    label="Tool"
                    value={tool}
                    onChange={(value) => {
                      const nextTool = value as MapTool;
                      setTool(nextTool);
                      if (nextTool !== "select" && nextTool !== "erase") {
                        setPlacementDraft(createPlacementDraft(nextTool, currentLevel, objectSequence));
                      }
                    }}
                    options={toolOptions}
                    allowBlank={false}
                  />
                  <SelectField
                    label="Rotation"
                    value={placementDraft.rotation}
                    onChange={(value) =>
                      setPlacementDraft((current) => ({
                        ...current,
                        rotation: value as MapRotation,
                      }))
                    }
                    options={["north", "east", "south", "west"]}
                    allowBlank={false}
                  />
                  <NumberField
                    label="Brush width"
                    value={placementDraft.footprint.width}
                    onChange={(value) =>
                      setPlacementDraft((current) => ({
                        ...current,
                        footprint: {
                          ...current.footprint,
                          width: Math.max(1, Math.floor(value)),
                        },
                      }))
                    }
                    min={1}
                  />
                  <NumberField
                    label="Brush height"
                    value={placementDraft.footprint.height}
                    onChange={(value) =>
                      setPlacementDraft((current) => ({
                        ...current,
                        footprint: {
                          ...current.footprint,
                          height: Math.max(1, Math.floor(value)),
                        },
                      }))
                    }
                    min={1}
                  />
                </div>
              </PanelSection>

              <PanelSection label="Canvas" title="Grid placement">
                <div className="map-editor-stage">
                  <div className="map-canvas-meta">
                    <Badge tone="accent">level {currentLevel}</Badge>
                    <Badge tone="muted">
                      hover {hoveredCell ? `${hoveredCell.x},${hoveredCell.z}` : "none"}
                    </Badge>
                    <Badge tone="muted">{tool}</Badge>
                  </div>
                  <div
                    className="map-grid-canvas"
                    style={{
                      gridTemplateColumns: `repeat(${selectedDocument.map.size.width}, minmax(24px, 1fr))`,
                    }}
                  >
                    {Array.from({
                      length: selectedDocument.map.size.width * selectedDocument.map.size.height,
                    }).map((_, index) => {
                      const x = index % selectedDocument.map.size.width;
                      const z = Math.floor(index / selectedDocument.map.size.width);
                      const grid = { x, y: currentLevel, z };
                      const objects = getObjectsAtCell(selectedDocument.map, grid);
                      const topObject = lastObject(objects) ?? null;
                      const isSelected = selectedCoverage.some((cell) => gridKey(cell) === gridKey(grid));
                      const isPreview = hoveredPreview.some((cell) => gridKey(cell) === gridKey(grid));
                      return (
                        <button
                          key={gridKey(grid)}
                          type="button"
                          className={`map-grid-cell ${topObject ? "map-grid-cell-occupied" : ""} ${
                            isSelected ? "map-grid-cell-selected" : ""
                          } ${isPreview ? "map-grid-cell-preview" : ""}`}
                          onMouseEnter={() => setHoveredCell(grid)}
                          onClick={() => handleGridCellClick(grid)}
                          title={
                            topObject
                              ? `${topObject.object_id} (${topObject.kind})`
                              : `${grid.x}, ${grid.y}, ${grid.z}`
                          }
                        >
                          {topObject ? objectGlyph(topObject.kind) : ""}
                        </button>
                      );
                    })}
                  </div>
                </div>
              </PanelSection>
            </>
          ) : (
            <PanelSection label="Selection" title="No map selected">
              <div className="empty-state">
                <Badge tone="muted">Idle</Badge>
                <p>Select a map from the left panel or create a new draft.</p>
              </div>
            </PanelSection>
          )}
        </main>

        <aside className="column">
          {selectedDocument ? (
            <PanelSection
              label="Selection"
              title={selectedObject ? selectedObject.object_id : "No object selected"}
            >
              {selectedObject ? (
                <>
                  <div className="form-grid">
                    <TextField
                      label="Object ID"
                      value={selectedObject.object_id}
                      onChange={(value) =>
                        updateSelectedObject((object) => ({ ...object, object_id: value.trim() }))
                      }
                    />
                    <SelectField
                      label="Kind"
                      value={selectedObject.kind}
                      onChange={(value) =>
                        updateSelectedObject((object) =>
                          changeObjectKind(object, value as MapObjectKind),
                        )
                      }
                      options={["building", "pickup", "interactive", "ai_spawn"]}
                      allowBlank={false}
                    />
                    <NumberField
                      label="Anchor X"
                      value={selectedObject.anchor.x}
                      onChange={(value) =>
                        updateSelectedObject((object) => ({
                          ...object,
                          anchor: { ...object.anchor, x: Math.floor(value) },
                        }))
                      }
                    />
                    <NumberField
                      label="Anchor Y"
                      value={selectedObject.anchor.y}
                      onChange={(value) =>
                        updateSelectedObject((object) => ({
                          ...object,
                          anchor: { ...object.anchor, y: Math.floor(value) },
                        }))
                      }
                    />
                    <NumberField
                      label="Anchor Z"
                      value={selectedObject.anchor.z}
                      onChange={(value) =>
                        updateSelectedObject((object) => ({
                          ...object,
                          anchor: { ...object.anchor, z: Math.floor(value) },
                        }))
                      }
                    />
                    <SelectField
                      label="Rotation"
                      value={selectedObject.rotation}
                      onChange={(value) =>
                        updateSelectedObject((object) => ({
                          ...object,
                          rotation: value as MapRotation,
                        }))
                      }
                      options={["north", "east", "south", "west"]}
                      allowBlank={false}
                    />
                  </div>

                  <div className="form-grid">
                    <NumberField
                      label="Footprint W"
                      value={selectedObject.footprint.width}
                      onChange={(value) =>
                        updateSelectedObject((object) => ({
                          ...object,
                          footprint: {
                            ...object.footprint,
                            width: Math.max(1, Math.floor(value)),
                          },
                        }))
                      }
                      min={1}
                    />
                    <NumberField
                      label="Footprint H"
                      value={selectedObject.footprint.height}
                      onChange={(value) =>
                        updateSelectedObject((object) => ({
                          ...object,
                          footprint: {
                            ...object.footprint,
                            height: Math.max(1, Math.floor(value)),
                          },
                        }))
                      }
                      min={1}
                    />
                  </div>

                  <div className="toggle-grid">
                    <CheckboxField
                      label="Blocks movement"
                      value={selectedObject.blocks_movement}
                      onChange={(value) =>
                        updateSelectedObject((object) => ({ ...object, blocks_movement: value }))
                      }
                    />
                    <CheckboxField
                      label="Blocks sight"
                      value={selectedObject.blocks_sight}
                      onChange={(value) =>
                        updateSelectedObject((object) => ({ ...object, blocks_sight: value }))
                      }
                    />
                  </div>

                  {selectedObject.kind === "building" ? (
                    <TextField
                      label="Prefab"
                      value={selectedObject.props.building?.prefab_id ?? ""}
                      onChange={(value) =>
                        updateSelectedObject((object) => ({
                          ...object,
                          props: {
                            ...object.props,
                            building: {
                              ...(object.props.building ?? {}),
                              prefab_id: value,
                            },
                          },
                        }))
                      }
                      hint={`Suggestions: ${workspace.catalogs.buildingPrefabs.join(", ")}`}
                    />
                  ) : null}

                  {selectedObject.kind === "pickup" ? (
                    <div className="form-grid">
                      <SelectField
                        label="Item"
                        value={selectedObject.props.pickup?.item_id ?? ""}
                        onChange={(value) =>
                          updateSelectedObject((object) => ({
                            ...object,
                            props: {
                              ...object.props,
                              pickup: {
                                ...(object.props.pickup ?? {}),
                                item_id: value,
                                min_count: object.props.pickup?.min_count ?? 1,
                                max_count: object.props.pickup?.max_count ?? 1,
                              },
                            },
                          }))
                        }
                        options={workspace.catalogs.itemIds}
                      />
                      <NumberField
                        label="Min count"
                        value={selectedObject.props.pickup?.min_count ?? 1}
                        onChange={(value) =>
                          updateSelectedObject((object) => ({
                            ...object,
                            props: {
                              ...object.props,
                              pickup: {
                                ...(object.props.pickup ?? {}),
                                item_id: object.props.pickup?.item_id ?? "",
                                min_count: Math.max(1, Math.floor(value)),
                                max_count: object.props.pickup?.max_count ?? 1,
                              },
                            },
                          }))
                        }
                      />
                      <NumberField
                        label="Max count"
                        value={selectedObject.props.pickup?.max_count ?? 1}
                        onChange={(value) =>
                          updateSelectedObject((object) => ({
                            ...object,
                            props: {
                              ...object.props,
                              pickup: {
                                ...(object.props.pickup ?? {}),
                                item_id: object.props.pickup?.item_id ?? "",
                                min_count: object.props.pickup?.min_count ?? 1,
                                max_count: Math.max(1, Math.floor(value)),
                              },
                            },
                          }))
                        }
                      />
                    </div>
                  ) : null}

                  {selectedObject.kind === "interactive" ? (
                    <div className="form-grid">
                      <TextField
                        label="Interaction"
                        value={selectedObject.props.interactive?.interaction_kind ?? ""}
                        onChange={(value) =>
                          updateSelectedObject((object) => ({
                            ...object,
                            props: {
                              ...object.props,
                              interactive: {
                                ...(object.props.interactive ?? {}),
                                interaction_kind: value,
                              },
                            },
                          }))
                        }
                        hint={`Suggestions: ${workspace.catalogs.interactiveKinds.join(", ")}`}
                      />
                      <TextField
                        label="Target ID"
                        value={selectedObject.props.interactive?.target_id ?? ""}
                        onChange={(value) =>
                          updateSelectedObject((object) => ({
                            ...object,
                            props: {
                              ...object.props,
                              interactive: {
                                ...(object.props.interactive ?? {}),
                                interaction_kind:
                                  object.props.interactive?.interaction_kind ?? "",
                                target_id: value,
                              },
                            },
                          }))
                        }
                      />
                    </div>
                  ) : null}

                  {selectedObject.kind === "ai_spawn" ? (
                    <>
                      <div className="form-grid">
                        <TextField
                          label="Spawn ID"
                          value={selectedObject.props.ai_spawn?.spawn_id ?? ""}
                          onChange={(value) =>
                            updateSelectedObject((object) => ({
                              ...object,
                              props: {
                                ...object.props,
                                ai_spawn: {
                                  ...(object.props.ai_spawn ?? {}),
                                  spawn_id: value.trim(),
                                  character_id: object.props.ai_spawn?.character_id ?? "",
                                  auto_spawn: object.props.ai_spawn?.auto_spawn ?? true,
                                  respawn_enabled:
                                    object.props.ai_spawn?.respawn_enabled ?? false,
                                  respawn_delay: object.props.ai_spawn?.respawn_delay ?? 10,
                                  spawn_radius: object.props.ai_spawn?.spawn_radius ?? 0,
                                },
                              },
                            }))
                          }
                        />
                        <SelectField
                          label="Character"
                          value={selectedObject.props.ai_spawn?.character_id ?? ""}
                          onChange={(value) =>
                            updateSelectedObject((object) => ({
                              ...object,
                              props: {
                                ...object.props,
                                ai_spawn: {
                                  ...(object.props.ai_spawn ?? {}),
                                  spawn_id: object.props.ai_spawn?.spawn_id ?? "",
                                  character_id: value,
                                  auto_spawn: object.props.ai_spawn?.auto_spawn ?? true,
                                  respawn_enabled:
                                    object.props.ai_spawn?.respawn_enabled ?? false,
                                  respawn_delay: object.props.ai_spawn?.respawn_delay ?? 10,
                                  spawn_radius: object.props.ai_spawn?.spawn_radius ?? 0,
                                },
                              },
                            }))
                          }
                          options={workspace.catalogs.characterIds}
                        />
                        <NumberField
                          label="Respawn delay"
                          value={selectedObject.props.ai_spawn?.respawn_delay ?? 10}
                          onChange={(value) =>
                            updateSelectedObject((object) => ({
                              ...object,
                              props: {
                                ...object.props,
                                ai_spawn: {
                                  ...(object.props.ai_spawn ?? {}),
                                  spawn_id: object.props.ai_spawn?.spawn_id ?? "",
                                  character_id: object.props.ai_spawn?.character_id ?? "",
                                  auto_spawn: object.props.ai_spawn?.auto_spawn ?? true,
                                  respawn_enabled:
                                    object.props.ai_spawn?.respawn_enabled ?? false,
                                  respawn_delay: value,
                                  spawn_radius: object.props.ai_spawn?.spawn_radius ?? 0,
                                },
                              },
                            }))
                          }
                        />
                        <NumberField
                          label="Spawn radius"
                          value={selectedObject.props.ai_spawn?.spawn_radius ?? 0}
                          onChange={(value) =>
                            updateSelectedObject((object) => ({
                              ...object,
                              props: {
                                ...object.props,
                                ai_spawn: {
                                  ...(object.props.ai_spawn ?? {}),
                                  spawn_id: object.props.ai_spawn?.spawn_id ?? "",
                                  character_id: object.props.ai_spawn?.character_id ?? "",
                                  auto_spawn: object.props.ai_spawn?.auto_spawn ?? true,
                                  respawn_enabled:
                                    object.props.ai_spawn?.respawn_enabled ?? false,
                                  respawn_delay: object.props.ai_spawn?.respawn_delay ?? 10,
                                  spawn_radius: value,
                                },
                              },
                            }))
                          }
                        />
                      </div>
                      <div className="toggle-grid">
                        <CheckboxField
                          label="Auto spawn"
                          value={selectedObject.props.ai_spawn?.auto_spawn ?? true}
                          onChange={(value) =>
                            updateSelectedObject((object) => ({
                              ...object,
                              props: {
                                ...object.props,
                                ai_spawn: {
                                  ...(object.props.ai_spawn ?? {}),
                                  spawn_id: object.props.ai_spawn?.spawn_id ?? "",
                                  character_id: object.props.ai_spawn?.character_id ?? "",
                                  auto_spawn: value,
                                  respawn_enabled:
                                    object.props.ai_spawn?.respawn_enabled ?? false,
                                  respawn_delay: object.props.ai_spawn?.respawn_delay ?? 10,
                                  spawn_radius: object.props.ai_spawn?.spawn_radius ?? 0,
                                },
                              },
                            }))
                          }
                        />
                        <CheckboxField
                          label="Respawn enabled"
                          value={selectedObject.props.ai_spawn?.respawn_enabled ?? false}
                          onChange={(value) =>
                            updateSelectedObject((object) => ({
                              ...object,
                              props: {
                                ...object.props,
                                ai_spawn: {
                                  ...(object.props.ai_spawn ?? {}),
                                  spawn_id: object.props.ai_spawn?.spawn_id ?? "",
                                  character_id: object.props.ai_spawn?.character_id ?? "",
                                  auto_spawn: object.props.ai_spawn?.auto_spawn ?? true,
                                  respawn_enabled: value,
                                  respawn_delay: object.props.ai_spawn?.respawn_delay ?? 10,
                                  spawn_radius: object.props.ai_spawn?.spawn_radius ?? 0,
                                },
                              },
                            }))
                          }
                        />
                      </div>
                    </>
                  ) : null}

                  <button
                    type="button"
                    className="toolbar-button toolbar-danger"
                    onClick={() => {
                      updateSelectedMap((map) => removeObject(map, selectedObject.object_id));
                      setSelectedObjectId(null);
                    }}
                  >
                    Delete selected object
                  </button>
                </>
              ) : (
                <div className="empty-state">
                  <Badge tone="muted">Idle</Badge>
                  <p>Select an object from the grid to edit its payload and placement.</p>
                </div>
              )}
            </PanelSection>
          ) : null}

          <ValidationPanel issues={selectedIssues} />
        </aside>
      </div>
    </div>
  );
}
