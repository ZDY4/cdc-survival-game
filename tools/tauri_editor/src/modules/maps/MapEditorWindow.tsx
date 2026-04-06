import { useEffect, useMemo, useRef, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { Badge } from "../../components/Badge";
import { CheckboxField, NumberField, SelectField, TextField } from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { ValidationPanel } from "../../components/ValidationPanel";
import {
  getRequestedDocumentKey,
  getRequestedDocumentType,
} from "../../lib/editorSurface";
import { openOrFocusModuleEditor } from "../../lib/editorWindows";
import { invokeCommand, isTauriRuntime } from "../../lib/tauri";
import { useRegisterEditorMenuCommands } from "../../menu/editorCommandRegistry";
import { useEditorMenuBridge } from "../../menu/menuBridge";
import { EDITOR_MENU_COMMANDS } from "../../menu/menuCommands";
import type {
  MapCellDefinition,
  MapEditorOpenDocumentPayload,
  MapWorkspacePayload,
  OverworldDocumentPayload,
  OverworldWorkspacePayload,
  SpatialDocumentType,
} from "../../types";
import { fallbackMapWorkspace } from "./fallback";
import { MapObjectInspector } from "./MapObjectInspector";
import { gridKey, objectGlyph, useMapEditorState } from "./mapEditorState";
import { getObjectsAtCell } from "./mapEditorUtils";
import {
  MAP_EDITOR_OPEN_DOCUMENT_EVENT,
  emitMapEditorSaveComplete,
  emitMapEditorSessionEnded,
  emitMapEditorStateChanged,
} from "./mapWindowing";
import { OverworldLocationInspector } from "./OverworldLocationInspector";
import { useOverworldEditorState } from "./overworldEditorState";
import { fallbackOverworldWorkspace } from "./overworldFallback";
import { getLocationAtCell, summarizeOverworld } from "./overworldEditorUtils";

function collectOverworldReferences(
  mapId: string,
  workspace: OverworldWorkspacePayload,
): Array<{
  overworldId: string;
  documentKey: string;
  locationId: string;
  locationName: string;
}> {
  return workspace.documents.flatMap((document) =>
    document.overworld.locations
      .filter((location) => location.map_id === mapId)
      .map((location) => ({
        overworldId: document.overworld.id,
        documentKey: document.documentKey,
        locationId: location.id,
        locationName: location.name || location.id,
      })),
  );
}

function findMapDocumentForOverworldLocation(
  location: OverworldDocumentPayload["overworld"]["locations"][number] | null,
  workspace: MapWorkspacePayload,
) {
  if (!location) {
    return null;
  }
  return workspace.documents.find((document) => document.map.id === location.map_id) ?? null;
}

function computeOverworldBounds(workspace: OverworldWorkspacePayload, selectedKey: string | null) {
  const selectedDocument =
    workspace.documents.find((document) => document.documentKey === selectedKey) ?? null;
  const cells = selectedDocument?.overworld.walkable_cells ?? [];
  const locations = selectedDocument?.overworld.locations ?? [];
  const points = [
    ...cells.map((cell) => cell.grid),
    ...locations.map((location) => location.overworld_cell),
  ];
  if (!points.length) {
    return { minX: -2, maxX: 2, minZ: -2, maxZ: 2 };
  }
  return {
    minX: Math.min(...points.map((point) => point.x)) - 1,
    maxX: Math.max(...points.map((point) => point.x)) + 1,
    minZ: Math.min(...points.map((point) => point.z)) - 1,
    maxZ: Math.max(...points.map((point) => point.z)) + 1,
  };
}

function formatGrid(grid: { x: number; y: number; z: number }) {
  return `${grid.x}, ${grid.y}, ${grid.z}`;
}

function activeButtonClass(active: boolean) {
  return `toolbar-button ${active ? "toolbar-accent" : ""}`.trim();
}

export function MapEditorWindow() {
  const [mapWorkspace, setMapWorkspace] = useState<MapWorkspacePayload>(fallbackMapWorkspace);
  const [overworldWorkspace, setOverworldWorkspace] =
    useState<OverworldWorkspacePayload>(fallbackOverworldWorkspace);
  const [canPersist, setCanPersist] = useState(false);
  const [status, setStatus] = useState("Loading spatial editor...");
  const [inspectorCollapsed, setInspectorCollapsed] = useState(false);
  const [statusBarVisible, setStatusBarVisible] = useState(true);
  const initialRequestRef = useRef<string | null>(getRequestedDocumentKey(window.location.search));
  const initialDocumentTypeRef = useRef<SpatialDocumentType>(
    getRequestedDocumentType(window.location.search),
  );
  const [activeDocumentType, setActiveDocumentType] = useState<SpatialDocumentType>(
    initialDocumentTypeRef.current,
  );

  async function loadWorkspaces() {
    try {
      const [mapsPayload, overworldPayload] = await Promise.all([
        invokeCommand<MapWorkspacePayload>("load_map_workspace"),
        invokeCommand<OverworldWorkspacePayload>("load_overworld_workspace"),
      ]);
      setMapWorkspace(mapsPayload);
      setOverworldWorkspace(overworldPayload);
      setCanPersist(true);
      setStatus(
        `Loaded ${mapsPayload.mapCount} tactical maps and ${overworldPayload.overworldCount} overworld files.`,
      );
    } catch (error) {
      setMapWorkspace(fallbackMapWorkspace);
      setOverworldWorkspace(fallbackOverworldWorkspace);
      setCanPersist(false);
      setStatus(
        `Running in fallback mode. ${String(error)}. Start the Tauri host to read project files.`,
      );
    }
  }

  useEffect(() => {
    void loadWorkspaces();
  }, []);

  useEditorMenuBridge(setStatus, true);

  const mapEditor = useMapEditorState({
    workspace: mapWorkspace,
    canPersist,
    onStatusChange: setStatus,
    onReload: loadWorkspaces,
    initialDocumentKey: initialDocumentTypeRef.current === "map" ? initialRequestRef.current : null,
  });
  const overworldEditor = useOverworldEditorState({
    workspace: overworldWorkspace,
    canPersist,
    onStatusChange: setStatus,
    onReload: loadWorkspaces,
    initialDocumentKey:
      initialDocumentTypeRef.current === "overworld" ? initialRequestRef.current : null,
  });

  const activeEditor = activeDocumentType === "map" ? mapEditor : overworldEditor;
  const editorRef = useRef(activeEditor);

  useEffect(() => {
    editorRef.current = activeEditor;
  }, [activeEditor]);

  useEffect(() => {
    if (!initialRequestRef.current) {
      return;
    }
    const request = initialRequestRef.current;
    const requestType = initialDocumentTypeRef.current;
    initialRequestRef.current = null;
    setActiveDocumentType(requestType);
    if (requestType === "map") {
      mapEditor.requestOpenDocument(request);
    } else {
      overworldEditor.requestOpenDocument(request);
    }
  }, [mapEditor, overworldEditor, mapWorkspace, overworldWorkspace]);

  useEffect(() => {
    if (!isTauriRuntime()) {
      return;
    }

    let mounted = true;
    const currentWindow = getCurrentWindow();

    const setup = async () => {
      const unlistenOpenDocument = await currentWindow.listen<MapEditorOpenDocumentPayload>(
        MAP_EDITOR_OPEN_DOCUMENT_EVENT,
        (event) => {
          if (!mounted) {
            return;
          }
          if (editorRef.current.selectedDocument?.dirty) {
            setStatus("Save or discard current changes before switching documents.");
            return;
          }
          setActiveDocumentType(event.payload.documentType);
          if (event.payload.documentType === "map") {
            mapEditor.requestOpenDocument(event.payload.documentKey);
          } else {
            overworldEditor.requestOpenDocument(event.payload.documentKey);
          }
        },
      );

      const unlistenClose = await currentWindow.onCloseRequested(async (event) => {
        if (!mounted) {
          return;
        }
        if (!editorRef.current.requestCloseWindow()) {
          event.preventDefault();
          return;
        }
        await emitMapEditorSessionEnded({
          documentKey: editorRef.current.selectedDocument?.documentKey,
        });
      });

      return () => {
        void unlistenOpenDocument();
        void unlistenClose();
      };
    };

    let teardown: (() => void) | undefined;
    void setup().then((cleanup) => {
      teardown = cleanup;
    });

    return () => {
      mounted = false;
      teardown?.();
    };
  }, [mapEditor, overworldEditor]);

  useEffect(() => {
    if (activeDocumentType !== "map" || !mapEditor.selectedDocument) {
      return;
    }
    const counts = mapEditor.selectedCounts;
    void emitMapEditorStateChanged({
      documentKey: mapEditor.selectedDocument.documentKey,
      mapId: mapEditor.selectedDocument.map.id,
      dirty: mapEditor.selectedDocument.dirty,
      errorCount: counts.errorCount,
      warningCount: counts.warningCount,
      objectCount: mapEditor.selectedDocument.map.objects.length,
      level: mapEditor.currentLevel,
    });
  }, [
    activeDocumentType,
    mapEditor.currentLevel,
    mapEditor.selectedCounts,
    mapEditor.selectedDocument,
  ]);

  async function handleSave() {
    const result = await editorRef.current.saveAll();
    if (!result) {
      return;
    }
    await emitMapEditorSaveComplete(result);
  }

  async function handleDeleteCurrent() {
    const deletedIds = await editorRef.current.deleteCurrent();
    if (!deletedIds) {
      return;
    }
    await emitMapEditorSaveComplete({
      savedIds: [],
      deletedIds,
    });
  }

  async function handlePendingResolution(action: "save" | "discard" | "cancel") {
    if (action === "save") {
      const result = await editorRef.current.saveAll();
      if (!result) {
        return;
      }
      await emitMapEditorSaveComplete(result);
      const outcome = await editorRef.current.resolvePendingAction("save", { skipSave: true });
      if (outcome === "close-window") {
        await emitMapEditorSessionEnded({
          documentKey: editorRef.current.selectedDocument?.documentKey,
        });
        await getCurrentWindow().close();
      }
      return;
    }

    const outcome = await editorRef.current.resolvePendingAction(action);
    if (outcome === "close-window") {
      await emitMapEditorSessionEnded({
        documentKey: editorRef.current.selectedDocument?.documentKey,
      });
      await getCurrentWindow().close();
    }
  }

  async function openLinkedDocument(documentType: SpatialDocumentType, documentKey: string) {
    if (editorRef.current.selectedDocument?.dirty) {
      setStatus("Save or discard current changes before switching linked documents.");
      return;
    }
    setActiveDocumentType(documentType);
    if (documentType === "map") {
      mapEditor.requestOpenDocument(documentKey);
    } else {
      overworldEditor.requestOpenDocument(documentKey);
    }
  }

  useRegisterEditorMenuCommands({
    [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: {
      execute: () => {
        editorRef.current.requestNewDraft();
      },
      isEnabled: () => !editorRef.current.busy,
    },
    [EDITOR_MENU_COMMANDS.FILE_SAVE_ALL]: {
      execute: async () => {
        await handleSave();
      },
      isEnabled: () => !editorRef.current.busy && editorRef.current.dirtyCount > 0,
    },
    [EDITOR_MENU_COMMANDS.FILE_RELOAD]: {
      execute: async () => {
        await loadWorkspaces();
      },
      isEnabled: () => !editorRef.current.busy && editorRef.current.dirtyCount === 0,
    },
    [EDITOR_MENU_COMMANDS.FILE_DELETE_CURRENT]: {
      execute: async () => {
        await handleDeleteCurrent();
      },
      isEnabled: () => !editorRef.current.busy && Boolean(editorRef.current.selectedDocument),
    },
    [EDITOR_MENU_COMMANDS.EDIT_VALIDATE_CURRENT]: {
      execute: async () => {
        await editorRef.current.validateCurrent();
      },
      isEnabled: () => !editorRef.current.busy && Boolean(editorRef.current.selectedDocument),
    },
    [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_STATUS_BAR]: {
      execute: () => {
        setStatusBarVisible((current) => !current);
      },
    },
    [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_INSPECTOR]: {
      execute: () => {
        setInspectorCollapsed((current) => !current);
      },
    },
    [EDITOR_MENU_COMMANDS.MODULE_ITEMS]: {
      execute: async () => {
        await openOrFocusModuleEditor(EDITOR_MENU_COMMANDS.MODULE_ITEMS);
      },
    },
    [EDITOR_MENU_COMMANDS.MODULE_DIALOGUES]: {
      execute: async () => {
        await openOrFocusModuleEditor(EDITOR_MENU_COMMANDS.MODULE_DIALOGUES);
      },
    },
    [EDITOR_MENU_COMMANDS.MODULE_QUESTS]: {
      execute: async () => {
        await openOrFocusModuleEditor(EDITOR_MENU_COMMANDS.MODULE_QUESTS);
      },
    },
    [EDITOR_MENU_COMMANDS.MODULE_MAPS]: {
      execute: async () => {
        await openOrFocusModuleEditor(EDITOR_MENU_COMMANDS.MODULE_MAPS);
      },
    },
  });

  const tacticalReferences = useMemo(
    () =>
      mapEditor.selectedDocument
        ? collectOverworldReferences(mapEditor.selectedDocument.map.id, overworldWorkspace)
        : [],
    [mapEditor.selectedDocument, overworldWorkspace],
  );
  const overworldLinkedMap = useMemo(
    () => findMapDocumentForOverworldLocation(overworldEditor.selectedLocation, mapWorkspace),
    [mapWorkspace, overworldEditor.selectedLocation],
  );
  const overworldBounds = useMemo(
    () =>
      computeOverworldBounds(
        overworldWorkspace,
        overworldEditor.selectedDocument?.documentKey ?? null,
      ),
    [overworldEditor.selectedDocument?.documentKey, overworldWorkspace],
  );
  const overworldColumns = overworldBounds.maxX - overworldBounds.minX + 1;
  const overworldRows = overworldBounds.maxZ - overworldBounds.minZ + 1;

  const selectedMapDocument = mapEditor.selectedDocument;
  const selectedOverworldDocument = overworldEditor.selectedDocument;
  const activeDirtyCount = activeEditor.dirtyCount;
  const activeBusy = activeEditor.busy;
  const activePendingIntent = activeEditor.pendingIntent;
  const activeCounts =
    activeDocumentType === "map" ? mapEditor.selectedCounts : overworldEditor.selectedCounts;

  const currentMapLevel = selectedMapDocument?.map.levels.find(
    (level) => level.y === mapEditor.currentLevel,
  );
  const currentMapCells = currentMapLevel?.cells ?? [];
  const currentMapCellLookup = useMemo(
    () =>
      new Map(
        currentMapCells.map((cell) => [
          gridKey({ x: cell.x, y: mapEditor.currentLevel, z: cell.z }),
          cell,
        ]),
      ),
    [currentMapCells, mapEditor.currentLevel],
  );
  const currentEntryPointLookup = useMemo(
    () =>
      new Map(
        (selectedMapDocument?.map.entry_points ?? [])
          .filter((entryPoint) => entryPoint.grid.y === mapEditor.currentLevel)
          .map((entryPoint) => [
            gridKey({
              x: entryPoint.grid.x,
              y: entryPoint.grid.y,
              z: entryPoint.grid.z,
            }),
            entryPoint,
          ]),
      ),
    [mapEditor.currentLevel, selectedMapDocument],
  );
  const selectedCoverageLookup = useMemo(
    () => new Set(mapEditor.selectedCoverage.map((grid) => gridKey(grid))),
    [mapEditor.selectedCoverage],
  );
  const hoveredPreviewLookup = useMemo(
    () => new Set(mapEditor.hoveredPreview.map((grid) => gridKey(grid))),
    [mapEditor.hoveredPreview],
  );
  const mapColumns = selectedMapDocument?.map.size.width ?? 0;
  const mapRows = selectedMapDocument?.map.size.height ?? 0;
  const mapCells = useMemo(() => {
    if (!selectedMapDocument) {
      return [];
    }
    return Array.from({ length: mapRows * mapColumns }, (_, index) => {
      const x = index % mapColumns;
      const z = Math.floor(index / mapColumns);
      return { x, y: mapEditor.currentLevel, z };
    });
  }, [mapColumns, mapEditor.currentLevel, mapRows, selectedMapDocument]);

  const overworldCellLookup = useMemo(
    () =>
      new Map(
        (selectedOverworldDocument?.overworld.walkable_cells ?? []).map((cell) => [
          gridKey(cell.grid),
          cell,
        ]),
      ),
    [selectedOverworldDocument],
  );
  const overworldGridCells = useMemo(() => {
    if (!selectedOverworldDocument) {
      return [];
    }
    return Array.from({ length: overworldRows * overworldColumns }, (_, index) => {
      const x = overworldBounds.minX + (index % overworldColumns);
      const z = overworldBounds.minZ + Math.floor(index / overworldColumns);
      return { x, y: 0, z };
    });
  }, [
    overworldBounds.minX,
    overworldBounds.minZ,
    overworldColumns,
    overworldRows,
    selectedOverworldDocument,
  ]);

  return (
    <div className="map-editor-window">
      <header className="map-editor-header">
        <div>
          <span className="eyebrow">Spatial Editing</span>
          <h1>Tactical Map + Overworld Workspace</h1>
          <p className="shell-copy">
            Keep tactical maps and overworld links in one focused editor while Rust stays the
            authority for saved data and validation.
          </p>
        </div>
        <div className="map-editor-header-actions">
          <button
            type="button"
            className={activeButtonClass(activeDocumentType === "map")}
            onClick={() => setActiveDocumentType("map")}
          >
            小地图
          </button>
          <button
            type="button"
            className={activeButtonClass(activeDocumentType === "overworld")}
            onClick={() => setActiveDocumentType("overworld")}
          >
            世界地图
          </button>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => {
              editorRef.current.requestNewDraft();
            }}
            disabled={activeBusy}
          >
            New
          </button>
          <button
            type="button"
            className="toolbar-button toolbar-accent"
            onClick={() => {
              void handleSave();
            }}
            disabled={activeBusy || activeDirtyCount === 0}
          >
            Save all
          </button>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => {
              void editorRef.current.validateCurrent();
            }}
            disabled={activeBusy || !editorRef.current.selectedDocument}
          >
            Validate
          </button>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => {
              void loadWorkspaces();
            }}
            disabled={activeBusy}
          >
            Reload
          </button>
          <button
            type="button"
            className="toolbar-button toolbar-danger"
            onClick={() => {
              void handleDeleteCurrent();
            }}
            disabled={activeBusy || !editorRef.current.selectedDocument}
          >
            Delete
          </button>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => setInspectorCollapsed((current) => !current)}
          >
            {inspectorCollapsed ? "Show inspector" : "Hide inspector"}
          </button>
        </div>
      </header>

      {statusBarVisible ? (
        <div className="map-editor-status">
          <div className="toolbar-summary">
            <span className="status-dot" />
            <strong>{status}</strong>
          </div>
          <div className="toolbar-summary">
            <Badge tone={canPersist ? "success" : "warning"}>
              {canPersist ? "Tauri host connected" : "Fallback mode"}
            </Badge>
            <Badge tone={activeDirtyCount > 0 ? "warning" : "muted"}>
              {activeDirtyCount} dirty
            </Badge>
            <Badge tone={activeCounts.errorCount > 0 ? "danger" : "success"}>
              {activeCounts.errorCount} errors
            </Badge>
            <Badge tone={activeCounts.warningCount > 0 ? "warning" : "muted"}>
              {activeCounts.warningCount} warnings
            </Badge>
          </div>
        </div>
      ) : null}

      <div
        className={`map-editor-layout ${
          inspectorCollapsed ? "map-editor-layout-inspector-collapsed" : ""
        }`.trim()}
      >
        <aside className="column">
          <PanelSection
            label={activeDocumentType === "map" ? "Tactical Maps" : "Overworlds"}
            title={activeDocumentType === "map" ? "Documents" : "World documents"}
            summary={
              <div className="toolbar-summary">
                <Badge tone="muted">
                  {activeDocumentType === "map"
                    ? `${mapEditor.documents.length} maps`
                    : `${overworldEditor.documents.length} overworlds`}
                </Badge>
              </div>
            }
          >
            <div className="item-list">
              {activeDocumentType === "map"
                ? mapEditor.documents.map((document) => {
                    const counts = document.validation;
                    return (
                      <button
                        key={document.documentKey}
                        type="button"
                        className={`item-row ${
                          document.documentKey === mapEditor.selectedKey ? "item-row-active" : ""
                        }`}
                        onClick={() => {
                          mapEditor.requestOpenDocument(document.documentKey);
                        }}
                      >
                        <div className="item-row-top">
                          <strong>{document.map.id || "Unnamed map"}</strong>
                          <div className="row-badges">
                            {document.dirty ? <Badge tone="warning">Dirty</Badge> : null}
                            {document.isDraft ? <Badge tone="accent">Draft</Badge> : null}
                          </div>
                        </div>
                        <p>
                          {document.map.size.width}x{document.map.size.height} ·{" "}
                          {document.map.levels.length} levels · {document.map.objects.length} objects
                        </p>
                        <div className="row-badges">
                          <Badge tone="muted">{document.map.entry_points.length} entries</Badge>
                          {counts.some((issue) => issue.severity === "error") ? (
                            <Badge tone="danger">
                              {counts.filter((issue) => issue.severity === "error").length} errors
                            </Badge>
                          ) : null}
                        </div>
                      </button>
                    );
                  })
                : overworldEditor.documents.map((document) => {
                    const counts = document.validation;
                    return (
                      <button
                        key={document.documentKey}
                        type="button"
                        className={`item-row ${
                          document.documentKey === overworldEditor.selectedKey
                            ? "item-row-active"
                            : ""
                        }`}
                        onClick={() => {
                          overworldEditor.requestOpenDocument(document.documentKey);
                        }}
                      >
                        <div className="item-row-top">
                          <strong>{document.overworld.id || "Unnamed overworld"}</strong>
                          <div className="row-badges">
                            {document.dirty ? <Badge tone="warning">Dirty</Badge> : null}
                            {document.isDraft ? <Badge tone="accent">Draft</Badge> : null}
                          </div>
                        </div>
                        <p>{summarizeOverworld(document.overworld)}</p>
                        <div className="row-badges">
                          <Badge tone="muted">{document.overworld.locations.length} locations</Badge>
                          {counts.some((issue) => issue.severity === "error") ? (
                            <Badge tone="danger">
                              {counts.filter((issue) => issue.severity === "error").length} errors
                            </Badge>
                          ) : null}
                        </div>
                      </button>
                    );
                  })}
            </div>
          </PanelSection>

          {activeDocumentType === "map" && selectedMapDocument ? (
            <>
              <PanelSection
                label="Map"
                title={selectedMapDocument.map.id || "Unnamed map"}
                summary={
                  <div className="toolbar-summary">
                    <Badge tone="muted">
                      {selectedMapDocument.map.size.width} x {selectedMapDocument.map.size.height}
                    </Badge>
                    <Badge tone="muted">{selectedMapDocument.map.levels.length} levels</Badge>
                  </div>
                }
              >
                <TextField
                  label="Map ID"
                  value={selectedMapDocument.map.id}
                  onChange={(value) =>
                    mapEditor.updateSelectedMap((map) => ({
                      ...map,
                      id: value.trim(),
                    }))
                  }
                />
                <TextField
                  label="Map name"
                  value={selectedMapDocument.map.name}
                  onChange={(value) =>
                    mapEditor.updateSelectedMap((map) => ({
                      ...map,
                      name: value,
                    }))
                  }
                />
                <div className="form-grid">
                  <NumberField
                    label="Width"
                    value={selectedMapDocument.map.size.width}
                    min={1}
                    onChange={(value) =>
                      mapEditor.updateSelectedMap((map) => ({
                        ...map,
                        size: {
                          ...map.size,
                          width: Math.max(1, Math.floor(value)),
                        },
                      }))
                    }
                  />
                  <NumberField
                    label="Height"
                    value={selectedMapDocument.map.size.height}
                    min={1}
                    onChange={(value) =>
                      mapEditor.updateSelectedMap((map) => ({
                        ...map,
                        size: {
                          ...map.size,
                          height: Math.max(1, Math.floor(value)),
                        },
                      }))
                    }
                  />
                </div>
                <div className="toolbar-summary">
                  <button
                    type="button"
                    className="toolbar-button"
                    onClick={() => mapEditor.stepLevel(-1)}
                  >
                    Level -
                  </button>
                  <Badge tone="accent">Y {mapEditor.currentLevel}</Badge>
                  <button
                    type="button"
                    className="toolbar-button"
                    onClick={() => mapEditor.stepLevel(1)}
                  >
                    Level +
                  </button>
                  <button
                    type="button"
                    className="toolbar-button"
                    onClick={() => mapEditor.addLevel()}
                  >
                    Add level
                  </button>
                  <button
                    type="button"
                    className="toolbar-button toolbar-danger"
                    onClick={() => mapEditor.removeCurrentLevel()}
                  >
                    Remove level
                  </button>
                </div>
              </PanelSection>

              <PanelSection label="Layer" title="Editing mode">
                <div className="toolbar-summary">
                  <button
                    type="button"
                    className={activeButtonClass(mapEditor.layer === "cells")}
                    onClick={() => mapEditor.setLayerMode("cells")}
                  >
                    Cells
                  </button>
                  <button
                    type="button"
                    className={activeButtonClass(mapEditor.layer === "objects")}
                    onClick={() => mapEditor.setLayerMode("objects")}
                  >
                    Objects
                  </button>
                  <button
                    type="button"
                    className={activeButtonClass(mapEditor.layer === "entryPoints")}
                    onClick={() => mapEditor.setLayerMode("entryPoints")}
                  >
                    Entry points
                  </button>
                </div>
                <div className="toolbar-summary">
                  {mapEditor.toolOptions.map((tool) => (
                    <button
                      key={tool}
                      type="button"
                      className={activeButtonClass(mapEditor.tool === tool)}
                      onClick={() => mapEditor.setToolMode(tool)}
                    >
                      {tool}
                    </button>
                  ))}
                </div>
              </PanelSection>

              {mapEditor.layer === "cells" ? (
                <PanelSection label="Cells" title="Cell paint settings" compact>
                  <TextField
                    label="Terrain"
                    value={mapEditor.cellDraft.terrain}
                    onChange={(value) =>
                      mapEditor.setCellDraft((current) => ({
                        ...current,
                        terrain: value,
                      }))
                    }
                  />
                  <div className="toggle-grid">
                    <CheckboxField
                      label="Blocks movement"
                      value={mapEditor.cellDraft.blocksMovement}
                      onChange={(value) =>
                        mapEditor.setCellDraft((current) => ({
                          ...current,
                          blocksMovement: value,
                        }))
                      }
                    />
                    <CheckboxField
                      label="Blocks sight"
                      value={mapEditor.cellDraft.blocksSight}
                      onChange={(value) =>
                        mapEditor.setCellDraft((current) => ({
                          ...current,
                          blocksSight: value,
                        }))
                      }
                    />
                  </div>
                </PanelSection>
              ) : null}

              {mapEditor.layer === "entryPoints" ? (
                <PanelSection label="Entry" title="Entry point draft" compact>
                  <TextField
                    label="Entry ID"
                    value={mapEditor.entryPointDraft.id}
                    onChange={(value) =>
                      mapEditor.setEntryPointDraft((current) => ({
                        ...current,
                        id: value,
                      }))
                    }
                  />
                  <TextField
                    label="Facing"
                    value={mapEditor.entryPointDraft.facing}
                    onChange={(value) =>
                      mapEditor.setEntryPointDraft((current) => ({
                        ...current,
                        facing: value,
                      }))
                    }
                    hint="Optional direction string stored on the entry point."
                  />
                </PanelSection>
              ) : null}

              {mapEditor.layer === "objects" &&
              mapEditor.tool !== "select" &&
              mapEditor.tool !== "erase" ? (
                <PanelSection label="Placement" title="Object draft" compact>
                  <div className="form-grid">
                    <NumberField
                      label="Footprint W"
                      value={mapEditor.placementDraft.footprint.width}
                      min={1}
                      onChange={(value) =>
                        mapEditor.setPlacementDraft((current) => ({
                          ...current,
                          footprint: {
                            ...current.footprint,
                            width: Math.max(1, Math.floor(value)),
                          },
                        }))
                      }
                    />
                    <NumberField
                      label="Footprint H"
                      value={mapEditor.placementDraft.footprint.height}
                      min={1}
                      onChange={(value) =>
                        mapEditor.setPlacementDraft((current) => ({
                          ...current,
                          footprint: {
                            ...current.footprint,
                            height: Math.max(1, Math.floor(value)),
                          },
                        }))
                      }
                    />
                    <SelectField
                      label="Rotation"
                      value={mapEditor.placementDraft.rotation}
                      onChange={(value) =>
                        mapEditor.setPlacementDraft((current) => ({
                          ...current,
                          rotation: value as typeof current.rotation,
                        }))
                      }
                      options={["north", "east", "south", "west"]}
                      allowBlank={false}
                    />
                    <div className="toolbar-summary">
                      <button
                        type="button"
                        className="toolbar-button"
                        onClick={() => mapEditor.rotatePlacement()}
                      >
                        Rotate 90°
                      </button>
                    </div>
                  </div>
                  <div className="toggle-grid">
                    <CheckboxField
                      label="Blocks movement"
                      value={mapEditor.placementDraft.blocksMovement}
                      onChange={(value) =>
                        mapEditor.setPlacementDraft((current) => ({
                          ...current,
                          blocksMovement: value,
                        }))
                      }
                    />
                    <CheckboxField
                      label="Blocks sight"
                      value={mapEditor.placementDraft.blocksSight}
                      onChange={(value) =>
                        mapEditor.setPlacementDraft((current) => ({
                          ...current,
                          blocksSight: value,
                        }))
                      }
                    />
                  </div>
                  {mapEditor.tool === "building" ? (
                    <TextField
                      label="Prefab"
                      value={mapEditor.placementDraft.buildingPrefabId}
                      onChange={(value) =>
                        mapEditor.setPlacementDraft((current) => ({
                          ...current,
                          buildingPrefabId: value,
                        }))
                      }
                    />
                  ) : null}
                  {mapEditor.tool === "pickup" ? (
                    <div className="form-grid">
                      <SelectField
                        label="Item ID"
                        value={mapEditor.placementDraft.pickupItemId}
                        onChange={(value) =>
                          mapEditor.setPlacementDraft((current) => ({
                            ...current,
                            pickupItemId: value,
                          }))
                        }
                        options={mapWorkspace.catalogs.itemIds}
                      />
                      <NumberField
                        label="Min count"
                        value={mapEditor.placementDraft.pickupMinCount}
                        min={1}
                        onChange={(value) =>
                          mapEditor.setPlacementDraft((current) => ({
                            ...current,
                            pickupMinCount: Math.max(1, Math.floor(value)),
                          }))
                        }
                      />
                      <NumberField
                        label="Max count"
                        value={mapEditor.placementDraft.pickupMaxCount}
                        min={1}
                        onChange={(value) =>
                          mapEditor.setPlacementDraft((current) => ({
                            ...current,
                            pickupMaxCount: Math.max(1, Math.floor(value)),
                          }))
                        }
                      />
                    </div>
                  ) : null}
                  {mapEditor.tool === "interactive" ? (
                    <div className="form-grid">
                      <TextField
                        label="Interaction kind"
                        value={mapEditor.placementDraft.interactiveKind}
                        onChange={(value) =>
                          mapEditor.setPlacementDraft((current) => ({
                            ...current,
                            interactiveKind: value,
                          }))
                        }
                      />
                      <TextField
                        label="Target ID"
                        value={mapEditor.placementDraft.interactiveTargetId}
                        onChange={(value) =>
                          mapEditor.setPlacementDraft((current) => ({
                            ...current,
                            interactiveTargetId: value,
                          }))
                        }
                      />
                    </div>
                  ) : null}
                  {mapEditor.tool === "ai_spawn" ? (
                    <>
                      <div className="form-grid">
                        <TextField
                          label="Spawn ID"
                          value={mapEditor.placementDraft.aiSpawnId}
                          onChange={(value) =>
                            mapEditor.setPlacementDraft((current) => ({
                              ...current,
                              aiSpawnId: value,
                            }))
                          }
                        />
                        <SelectField
                          label="Character"
                          value={mapEditor.placementDraft.aiCharacterId}
                          onChange={(value) =>
                            mapEditor.setPlacementDraft((current) => ({
                              ...current,
                              aiCharacterId: value,
                            }))
                          }
                          options={mapWorkspace.catalogs.characterIds}
                        />
                        <NumberField
                          label="Respawn delay"
                          value={mapEditor.placementDraft.aiRespawnDelay}
                          onChange={(value) =>
                            mapEditor.setPlacementDraft((current) => ({
                              ...current,
                              aiRespawnDelay: value,
                            }))
                          }
                        />
                        <NumberField
                          label="Spawn radius"
                          value={mapEditor.placementDraft.aiSpawnRadius}
                          onChange={(value) =>
                            mapEditor.setPlacementDraft((current) => ({
                              ...current,
                              aiSpawnRadius: value,
                            }))
                          }
                        />
                      </div>
                      <div className="toggle-grid">
                        <CheckboxField
                          label="Auto spawn"
                          value={mapEditor.placementDraft.aiAutoSpawn}
                          onChange={(value) =>
                            mapEditor.setPlacementDraft((current) => ({
                              ...current,
                              aiAutoSpawn: value,
                            }))
                          }
                        />
                        <CheckboxField
                          label="Respawn enabled"
                          value={mapEditor.placementDraft.aiRespawnEnabled}
                          onChange={(value) =>
                            mapEditor.setPlacementDraft((current) => ({
                              ...current,
                              aiRespawnEnabled: value,
                            }))
                          }
                        />
                      </div>
                    </>
                  ) : null}
                </PanelSection>
              ) : null}
            </>
          ) : null}

          {activeDocumentType === "overworld" && selectedOverworldDocument ? (
            <>
              <PanelSection
                label="Overworld"
                title={selectedOverworldDocument.overworld.id || "Unnamed overworld"}
                summary={
                  <div className="toolbar-summary">
                    <Badge tone="muted">
                      {selectedOverworldDocument.overworld.walkable_cells.length} cells
                    </Badge>
                    <Badge tone="muted">
                      {selectedOverworldDocument.overworld.locations.length} locations
                    </Badge>
                  </div>
                }
              >
                <TextField
                  label="Overworld ID"
                  value={selectedOverworldDocument.overworld.id}
                  onChange={(value) =>
                    overworldEditor.updateSelectedOverworld((overworld) => ({
                      ...overworld,
                      id: value.trim(),
                    }))
                  }
                />
                <div className="form-grid">
                  <TextField
                    label="Food item ID"
                    value={selectedOverworldDocument.overworld.travel_rules.food_item_id}
                    onChange={(value) =>
                      overworldEditor.updateSelectedOverworld((overworld) => ({
                        ...overworld,
                        travel_rules: {
                          ...overworld.travel_rules,
                          food_item_id: value.trim(),
                        },
                      }))
                    }
                  />
                  <NumberField
                    label="Night multiplier"
                    value={selectedOverworldDocument.overworld.travel_rules.night_minutes_multiplier}
                    step={0.1}
                    onChange={(value) =>
                      overworldEditor.updateSelectedOverworld((overworld) => ({
                        ...overworld,
                        travel_rules: {
                          ...overworld.travel_rules,
                          night_minutes_multiplier: value,
                        },
                      }))
                    }
                  />
                  <NumberField
                    label="Risk multiplier"
                    value={selectedOverworldDocument.overworld.travel_rules.risk_multiplier}
                    step={0.1}
                    onChange={(value) =>
                      overworldEditor.updateSelectedOverworld((overworld) => ({
                        ...overworld,
                        travel_rules: {
                          ...overworld.travel_rules,
                          risk_multiplier: value,
                        },
                      }))
                    }
                  />
                </div>
              </PanelSection>

              <PanelSection label="Tools" title="World edit mode">
                <div className="toolbar-summary">
                  {(["select", "paint", "erase-cell", "location"] as const).map((tool) => (
                    <button
                      key={tool}
                      type="button"
                      className={activeButtonClass(overworldEditor.tool === tool)}
                      onClick={() => overworldEditor.setTool(tool)}
                    >
                      {tool}
                    </button>
                  ))}
                </div>
                <TextField
                  label="Paint terrain"
                  value={overworldEditor.terrainDraft}
                  onChange={overworldEditor.setTerrainDraft}
                  hint={`Known terrains: ${overworldWorkspace.catalogs.terrainKinds.join(", ")}`}
                />
              </PanelSection>

              <PanelSection label="Location" title="Location draft">
                <div className="form-grid">
                  <TextField
                    label="Location ID"
                    value={overworldEditor.locationDraft.id}
                    onChange={(value) =>
                      overworldEditor.setLocationDraft((current) => ({
                        ...current,
                        id: value,
                      }))
                    }
                  />
                  <TextField
                    label="Name"
                    value={overworldEditor.locationDraft.name}
                    onChange={(value) =>
                      overworldEditor.setLocationDraft((current) => ({
                        ...current,
                        name: value,
                      }))
                    }
                  />
                  <SelectField
                    label="Kind"
                    value={overworldEditor.locationDraft.kind}
                    onChange={(value) =>
                      overworldEditor.setLocationDraft((current) => ({
                        ...current,
                        kind: value as typeof current.kind,
                      }))
                    }
                    options={overworldWorkspace.catalogs.locationKinds}
                    allowBlank={false}
                  />
                  <NumberField
                    label="Danger"
                    value={overworldEditor.locationDraft.dangerLevel}
                    onChange={(value) =>
                      overworldEditor.setLocationDraft((current) => ({
                        ...current,
                        dangerLevel: Math.floor(value),
                      }))
                    }
                  />
                  <SelectField
                    label="Map ID"
                    value={overworldEditor.locationDraft.mapId}
                    onChange={(value) =>
                      overworldEditor.setLocationDraft((current) => ({
                        ...current,
                        mapId: value,
                      }))
                    }
                    options={overworldWorkspace.catalogs.mapIds}
                  />
                  <TextField
                    label="Entry point ID"
                    value={overworldEditor.locationDraft.entryPointId}
                    onChange={(value) =>
                      overworldEditor.setLocationDraft((current) => ({
                        ...current,
                        entryPointId: value,
                      }))
                    }
                  />
                  <TextField
                    label="Parent outdoor"
                    value={overworldEditor.locationDraft.parentOutdoorLocationId}
                    onChange={(value) =>
                      overworldEditor.setLocationDraft((current) => ({
                        ...current,
                        parentOutdoorLocationId: value,
                      }))
                    }
                  />
                  <TextField
                    label="Return entry point"
                    value={overworldEditor.locationDraft.returnEntryPointId}
                    onChange={(value) =>
                      overworldEditor.setLocationDraft((current) => ({
                        ...current,
                        returnEntryPointId: value,
                      }))
                    }
                  />
                  <TextField
                    label="Icon"
                    value={overworldEditor.locationDraft.icon}
                    onChange={(value) =>
                      overworldEditor.setLocationDraft((current) => ({
                        ...current,
                        icon: value,
                      }))
                    }
                  />
                </div>
                <TextField
                  label="Description"
                  value={overworldEditor.locationDraft.description}
                  onChange={(value) =>
                    overworldEditor.setLocationDraft((current) => ({
                      ...current,
                      description: value,
                    }))
                  }
                />
                <div className="toggle-grid">
                  <CheckboxField
                    label="Default unlocked"
                    value={overworldEditor.locationDraft.defaultUnlocked}
                    onChange={(value) =>
                      overworldEditor.setLocationDraft((current) => ({
                        ...current,
                        defaultUnlocked: value,
                      }))
                    }
                  />
                  <CheckboxField
                    label="Visible"
                    value={overworldEditor.locationDraft.visible}
                    onChange={(value) =>
                      overworldEditor.setLocationDraft((current) => ({
                        ...current,
                        visible: value,
                      }))
                    }
                  />
                </div>
              </PanelSection>
            </>
          ) : null}
        </aside>

        <main className="column column-main map-editor-stage-focus">
          {activeDocumentType === "map" && selectedMapDocument ? (
            <>
              <PanelSection
                label="Canvas"
                title={selectedMapDocument.map.name || selectedMapDocument.map.id || "Tactical map"}
                summary={
                  <div className="map-canvas-meta">
                    <Badge tone="muted">{selectedMapDocument.relativePath}</Badge>
                    <Badge tone="accent">Layer: {mapEditor.layer}</Badge>
                    <Badge tone="muted">Tool: {mapEditor.tool}</Badge>
                    <Badge tone="muted">
                      Hover:{" "}
                      {mapEditor.hoveredCell ? formatGrid(mapEditor.hoveredCell) : "None"}
                    </Badge>
                  </div>
                }
              >
                <div className="shortcut-hints">
                  <Badge tone="muted">Cells = terrain + movement flags</Badge>
                  <Badge tone="muted">Objects = building / pickup / interactive / ai_spawn</Badge>
                  <Badge tone="muted">Entry points = map entrances used by overworld locations</Badge>
                </div>
                <div
                  className="map-grid-canvas map-grid-canvas-focus"
                  style={{
                    gridTemplateColumns: `repeat(${Math.max(1, mapColumns)}, minmax(32px, 1fr))`,
                  }}
                >
                  {mapCells.map((grid) => {
                    const key = gridKey(grid);
                    const cell = currentMapCellLookup.get(key) ?? null;
                    const entryPoint = currentEntryPointLookup.get(key) ?? null;
                    const objects = getObjectsAtCell(selectedMapDocument.map, grid);
                    const topObject = objects.length > 0 ? objects[objects.length - 1] : null;
                    const isSelected = selectedCoverageLookup.has(key);
                    const isPreview = hoveredPreviewLookup.has(key);
                    const hasContent = Boolean(cell || entryPoint || topObject);
                    const label = entryPoint
                      ? "E"
                      : topObject
                        ? objectGlyph(topObject.kind)
                        : cell?.terrain.slice(0, 1).toUpperCase() || "";
                    const titleBits = [
                      `Grid ${formatGrid(grid)}`,
                      cell ? `terrain=${cell.terrain}` : "empty cell",
                      entryPoint ? `entry=${entryPoint.id}` : null,
                      topObject ? `object=${topObject.object_id}` : null,
                    ].filter(Boolean);

                    return (
                      <button
                        key={key}
                        type="button"
                        className={`map-grid-cell map-grid-cell-focus ${
                          hasContent ? "map-grid-cell-occupied" : ""
                        } ${isSelected ? "map-grid-cell-selected" : ""} ${
                          isPreview ? "map-grid-cell-preview" : ""
                        }`.trim()}
                        title={titleBits.join(" | ")}
                        onMouseEnter={() => mapEditor.setHoveredCell(grid)}
                        onClick={() => mapEditor.handleGridCellClick(grid)}
                      >
                        {label}
                      </button>
                    );
                  })}
                </div>
              </PanelSection>

              <PanelSection label="Links" title="Overworld references" compact>
                {tacticalReferences.length === 0 ? (
                  <div className="empty-state">
                    <Badge tone="muted">No links</Badge>
                    <p>No overworld location currently references this tactical map.</p>
                  </div>
                ) : (
                  <div className="item-list">
                    {tacticalReferences.map((reference) => (
                      <div
                        key={`${reference.documentKey}:${reference.locationId}`}
                        className="summary-row"
                      >
                        <div className="summary-row-main">
                          <strong>{reference.locationName}</strong>
                          <p>
                            {reference.overworldId} · {reference.locationId}
                          </p>
                        </div>
                        <button
                          type="button"
                          className="toolbar-button"
                          onClick={() => {
                            void openLinkedDocument("overworld", reference.documentKey);
                          }}
                        >
                          Open world
                        </button>
                      </div>
                    ))}
                  </div>
                )}
              </PanelSection>
            </>
          ) : null}

          {activeDocumentType === "overworld" && selectedOverworldDocument ? (
            <>
              <PanelSection
                label="Canvas"
                title={selectedOverworldDocument.overworld.id || "World map"}
                summary={
                  <div className="map-canvas-meta">
                    <Badge tone="muted">{selectedOverworldDocument.relativePath}</Badge>
                    <Badge tone="accent">Tool: {overworldEditor.tool}</Badge>
                    <Badge tone="muted">
                      Hover:{" "}
                      {overworldEditor.hoveredCell ? formatGrid(overworldEditor.hoveredCell) : "None"}
                    </Badge>
                    <Badge tone="muted">
                      Bounds X {overworldBounds.minX}..{overworldBounds.maxX} / Z{" "}
                      {overworldBounds.minZ}..{overworldBounds.maxZ}
                    </Badge>
                  </div>
                }
              >
                <div className="shortcut-hints">
                  <Badge tone="muted">Paint walkable cells</Badge>
                  <Badge tone="muted">Place locations on walkable cells</Badge>
                  <Badge tone="muted">Links point to map_id + entry_point_id</Badge>
                </div>
                <div
                  className="map-grid-canvas map-grid-canvas-focus"
                  style={{
                    gridTemplateColumns: `repeat(${Math.max(1, overworldColumns)}, minmax(34px, 1fr))`,
                  }}
                >
                  {overworldGridCells.map((grid) => {
                    const key = gridKey(grid);
                    const cell = overworldCellLookup.get(key) ?? null;
                    const location = getLocationAtCell(selectedOverworldDocument.overworld, grid);
                    const isSelected =
                      location?.id !== undefined &&
                      location.id === overworldEditor.selectedLocation?.id;
                    const label = location
                      ? (location.icon || location.name || location.id).slice(0, 1).toUpperCase()
                      : cell?.terrain.slice(0, 1).toUpperCase() || "";
                    const titleBits = [
                      `Grid ${formatGrid(grid)}`,
                      cell ? `terrain=${cell.terrain}` : "not walkable",
                      location ? `location=${location.id}` : null,
                    ].filter(Boolean);

                    return (
                      <button
                        key={key}
                        type="button"
                        className={`map-grid-cell map-grid-cell-focus ${
                          cell || location ? "map-grid-cell-occupied" : ""
                        } ${isSelected ? "map-grid-cell-selected" : ""}`.trim()}
                        title={titleBits.join(" | ")}
                        onMouseEnter={() => overworldEditor.setHoveredCell(grid)}
                        onClick={() => overworldEditor.handleGridCellClick(grid)}
                      >
                        {label}
                      </button>
                    );
                  })}
                </div>
              </PanelSection>

              <PanelSection label="Preview" title="Linked tactical map" compact>
                {overworldEditor.selectedLocation && overworldLinkedMap ? (
                  <div className="summary-row">
                    <div className="summary-row-main">
                      <strong>{overworldLinkedMap.map.name || overworldLinkedMap.map.id}</strong>
                      <p>
                        entry: {overworldEditor.selectedLocation.entry_point_id} · map:{" "}
                        {overworldLinkedMap.map.id}
                      </p>
                    </div>
                    <button
                      type="button"
                      className="toolbar-button"
                      onClick={() => {
                        void openLinkedDocument("map", overworldLinkedMap.documentKey);
                      }}
                    >
                      Open map
                    </button>
                  </div>
                ) : (
                  <div className="empty-state">
                    <Badge tone="muted">No link</Badge>
                    <p>Select a location with a valid tactical map link to inspect it here.</p>
                  </div>
                )}
              </PanelSection>
            </>
          ) : null}
        </main>

        {!inspectorCollapsed ? (
          <aside className="column">
            {activeDocumentType === "map" && selectedMapDocument ? (
              <>
                {mapEditor.selectedCell ? (
                  <PanelSection label="Cell" title="Selected cell">
                    <div className="summary-row">
                      <div className="summary-row-main">
                        <strong>Grid</strong>
                        <p>{formatGrid(mapEditor.selectedCell)}</p>
                      </div>
                      <Badge tone="accent">{mapEditor.selectedCell.terrain}</Badge>
                    </div>
                    <TextField
                      label="Terrain"
                      value={mapEditor.selectedCell.terrain}
                      onChange={(value) =>
                        mapEditor.updateSelectedMap((map) => ({
                          ...map,
                          levels: map.levels.map((level) =>
                            level.y === mapEditor.selectedCell?.y
                              ? {
                                  ...level,
                                  cells: level.cells.map((cell) =>
                                    cell.x === mapEditor.selectedCell?.x &&
                                    cell.z === mapEditor.selectedCell?.z
                                      ? {
                                          ...cell,
                                          terrain: value,
                                        }
                                      : cell,
                                  ),
                                }
                              : level,
                          ),
                        }))
                      }
                    />
                    <div className="toggle-grid">
                      <CheckboxField
                        label="Blocks movement"
                        value={mapEditor.selectedCell.blocks_movement}
                        onChange={(value) =>
                          mapEditor.updateSelectedMap((map) => ({
                            ...map,
                            levels: map.levels.map((level) =>
                              level.y === mapEditor.selectedCell?.y
                                ? {
                                    ...level,
                                    cells: level.cells.map((cell) =>
                                      cell.x === mapEditor.selectedCell?.x &&
                                      cell.z === mapEditor.selectedCell?.z
                                        ? {
                                            ...cell,
                                            blocks_movement: value,
                                          }
                                        : cell,
                                    ),
                                  }
                                : level,
                            ),
                          }))
                        }
                      />
                      <CheckboxField
                        label="Blocks sight"
                        value={mapEditor.selectedCell.blocks_sight}
                        onChange={(value) =>
                          mapEditor.updateSelectedMap((map) => ({
                            ...map,
                            levels: map.levels.map((level) =>
                              level.y === mapEditor.selectedCell?.y
                                ? {
                                    ...level,
                                    cells: level.cells.map((cell) =>
                                      cell.x === mapEditor.selectedCell?.x &&
                                      cell.z === mapEditor.selectedCell?.z
                                        ? {
                                            ...cell,
                                            blocks_sight: value,
                                          }
                                        : cell,
                                    ),
                                  }
                                : level,
                            ),
                          }))
                        }
                      />
                    </div>
                  </PanelSection>
                ) : null}

                {mapEditor.selectedEntryPoint ? (
                  <PanelSection label="Entry" title="Selected entry point">
                    <TextField
                      label="Entry ID"
                      value={mapEditor.selectedEntryPoint.id}
                      onChange={(value) =>
                        mapEditor.updateSelectedEntryPoint((entryPoint) => ({
                          ...entryPoint,
                          id: value.trim(),
                        }))
                      }
                    />
                    <div className="form-grid">
                      <NumberField
                        label="X"
                        value={mapEditor.selectedEntryPoint.grid.x}
                        onChange={(value) =>
                          mapEditor.updateSelectedEntryPoint((entryPoint) => ({
                            ...entryPoint,
                            grid: {
                              ...entryPoint.grid,
                              x: Math.floor(value),
                            },
                          }))
                        }
                      />
                      <NumberField
                        label="Y"
                        value={mapEditor.selectedEntryPoint.grid.y}
                        onChange={(value) =>
                          mapEditor.updateSelectedEntryPoint((entryPoint) => ({
                            ...entryPoint,
                            grid: {
                              ...entryPoint.grid,
                              y: Math.floor(value),
                            },
                          }))
                        }
                      />
                      <NumberField
                        label="Z"
                        value={mapEditor.selectedEntryPoint.grid.z}
                        onChange={(value) =>
                          mapEditor.updateSelectedEntryPoint((entryPoint) => ({
                            ...entryPoint,
                            grid: {
                              ...entryPoint.grid,
                              z: Math.floor(value),
                            },
                          }))
                        }
                      />
                      <TextField
                        label="Facing"
                        value={mapEditor.selectedEntryPoint.facing ?? ""}
                        onChange={(value) =>
                          mapEditor.updateSelectedEntryPoint((entryPoint) => ({
                            ...entryPoint,
                            facing: value.trim() || null,
                          }))
                        }
                      />
                    </div>
                    <button
                      type="button"
                      className="toolbar-button toolbar-danger"
                      onClick={() => mapEditor.deleteSelectedEntryPoint()}
                    >
                      Delete selected entry point
                    </button>
                  </PanelSection>
                ) : null}

                <PanelSection label="Object" title="Selected object">
                  {mapEditor.selectedObject ? (
                    <MapObjectInspector
                      selectedObject={mapEditor.selectedObject}
                      workspace={mapWorkspace}
                      updateSelectedObject={mapEditor.updateSelectedObject}
                      changeSelectedObjectKind={mapEditor.changeSelectedObjectKind}
                      deleteSelectedObject={mapEditor.deleteSelectedObject}
                    />
                  ) : (
                    <div className="empty-state">
                      <Badge tone="muted">No object</Badge>
                      <p>Select an object cell or switch to object layer to place one.</p>
                    </div>
                  )}
                </PanelSection>

                <ValidationPanel issues={mapEditor.selectedIssues} />
              </>
            ) : null}

            {activeDocumentType === "overworld" && selectedOverworldDocument ? (
              <>
                <PanelSection label="Location" title="Selected location">
                  {overworldEditor.selectedLocation ? (
                    <OverworldLocationInspector
                      selectedLocation={overworldEditor.selectedLocation}
                      workspace={overworldWorkspace}
                      updateSelectedLocation={overworldEditor.updateSelectedLocation}
                      deleteSelectedLocation={overworldEditor.deleteSelectedLocation}
                    />
                  ) : (
                    <div className="empty-state">
                      <Badge tone="muted">No location</Badge>
                      <p>Select a location marker or use the location tool to place one.</p>
                    </div>
                  )}
                </PanelSection>

                <PanelSection label="World" title="Current selection" compact>
                  <div className="summary-row">
                    <div className="summary-row-main">
                      <strong>Hovered cell</strong>
                      <p>
                        {overworldEditor.hoveredCell
                          ? formatGrid(overworldEditor.hoveredCell)
                          : "None"}
                      </p>
                    </div>
                    <Badge tone="muted">{overworldEditor.summarizeCurrent}</Badge>
                  </div>
                </PanelSection>

                <ValidationPanel issues={overworldEditor.selectedIssues} />
              </>
            ) : null}
          </aside>
        ) : null}
      </div>

      {activePendingIntent ? (
        <div className="modal-backdrop">
          <div className="modal-card">
            <div>
              <span className="eyebrow">Unsaved Changes</span>
              <h2>Resolve pending action</h2>
            </div>
            <p className="shell-copy">
              {activePendingIntent.type === "switch-document"
                ? "Save, discard, or cancel before switching to another document."
                : "Save, discard, or cancel before closing this editor window."}
            </p>
            <div className="toolbar-summary">
              <button
                type="button"
                className="toolbar-button toolbar-accent"
                onClick={() => {
                  void handlePendingResolution("save");
                }}
              >
                Save and continue
              </button>
              <button
                type="button"
                className="toolbar-button toolbar-danger"
                onClick={() => {
                  void handlePendingResolution("discard");
                }}
              >
                Discard changes
              </button>
              <button
                type="button"
                className="toolbar-button"
                onClick={() => {
                  void handlePendingResolution("cancel");
                }}
              >
                Cancel
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}
