import { useEffect, useRef, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { Badge } from "../../components/Badge";
import { NumberField, SelectField, TextField } from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { ValidationPanel } from "../../components/ValidationPanel";
import { getRequestedDocumentKey } from "../../lib/editorSurface";
import { invokeCommand, isTauriRuntime } from "../../lib/tauri";
import type { MapEditorOpenDocumentPayload, MapRotation, MapWorkspacePayload } from "../../types";
import { fallbackMapWorkspace } from "./fallback";
import { MapObjectInspector } from "./MapObjectInspector";
import { resolveMapEditorShortcut } from "./mapEditorShortcuts";
import { getIssueCounts, gridKey, objectGlyph, useMapEditorState } from "./mapEditorState";
import { getObjectsAtCell } from "./mapEditorUtils";
import {
  MAP_EDITOR_OPEN_DOCUMENT_EVENT,
  emitMapEditorSaveComplete,
  emitMapEditorSessionEnded,
  emitMapEditorStateChanged,
} from "./mapWindowing";

export function MapEditorWindow() {
  const [workspace, setWorkspace] = useState<MapWorkspacePayload>(fallbackMapWorkspace);
  const [canPersist, setCanPersist] = useState(false);
  const [status, setStatus] = useState("Loading map editor...");
  const [inspectorCollapsed, setInspectorCollapsed] = useState(false);
  const initialRequestRef = useRef<string | null>(getRequestedDocumentKey(window.location.search));

  async function loadWorkspace() {
    try {
      const payload = await invokeCommand<MapWorkspacePayload>("load_map_workspace");
      setWorkspace(payload);
      setCanPersist(true);
      setStatus(`Loaded ${payload.mapCount} maps from project data.`);
    } catch (error) {
      setWorkspace(fallbackMapWorkspace);
      setCanPersist(false);
      setStatus(
        `Running in fallback mode. ${String(error)}. Start the Tauri host to read project files.`,
      );
    }
  }

  useEffect(() => {
    void loadWorkspace();
  }, []);

  const editor = useMapEditorState({
    workspace,
    canPersist,
    onStatusChange: setStatus,
    onReload: loadWorkspace,
    initialDocumentKey: initialRequestRef.current,
  });
  const editorRef = useRef(editor);

  useEffect(() => {
    editorRef.current = editor;
  }, [editor]);

  useEffect(() => {
    if (!initialRequestRef.current) {
      return;
    }
    const request = initialRequestRef.current;
    initialRequestRef.current = null;
    editor.requestOpenDocument(request);
  }, [editor, workspace]);

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
          editorRef.current.requestOpenDocument(event.payload.documentKey);
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
  }, []);

  useEffect(() => {
    if (!editor.selectedDocument) {
      return;
    }
    const counts = getIssueCounts(editor.selectedDocument.validation);
    void emitMapEditorStateChanged({
      documentKey: editor.selectedDocument.documentKey,
      mapId: editor.selectedDocument.map.id,
      dirty: editor.selectedDocument.dirty,
      errorCount: counts.errorCount,
      warningCount: counts.warningCount,
      objectCount: editor.selectedDocument.map.objects.length,
      level: editor.currentLevel,
    });
  }, [editor.currentLevel, editor.selectedDocument]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const action = resolveMapEditorShortcut({
        key: event.key,
        ctrlKey: event.ctrlKey,
        metaKey: event.metaKey,
        altKey: event.altKey,
        target: event.target,
      });
      if (!action) {
        return;
      }

      event.preventDefault();
      const current = editorRef.current;
      switch (action.type) {
        case "save":
          void handleSave();
          break;
        case "set-tool":
          current.setToolMode(action.tool);
          break;
        case "rotate":
          current.rotatePlacement();
          break;
        case "level-step":
          current.stepLevel(action.delta);
          break;
        case "delete-selection":
          current.deleteSelectedObject();
          break;
        case "clear-selection":
          if (current.pendingIntent) {
            void handlePendingResolution("cancel");
            return;
          }
          current.clearSelection();
          break;
      }
    };

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

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

  const selectedDocument = editor.selectedDocument;

  return (
    <div className="map-editor-window">
      <header className="map-editor-header">
        <div>
          <p className="eyebrow">Map Editor</p>
          <h1>{editor.selectedDocument?.map.id || "No map selected"}</h1>
          <p className="shell-copy">Dedicated Tauri 2 window for focused map authoring.</p>
        </div>
        <div className="map-editor-header-actions">
          <button
            type="button"
            className="toolbar-button toolbar-accent"
            onClick={() => {
              void handleSave();
            }}
            disabled={editor.busy || editor.dirtyCount === 0}
          >
            Save All
          </button>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => {
              void editor.validateCurrent();
            }}
            disabled={editor.busy || !editor.selectedDocument}
          >
            Validate
          </button>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => {
              setInspectorCollapsed((current) => !current);
            }}
          >
            {inspectorCollapsed ? "Show Inspector" : "Hide Inspector"}
          </button>
          <button
            type="button"
            className="toolbar-button toolbar-danger"
            onClick={() => {
              void handleDeleteCurrent();
            }}
            disabled={editor.busy || !editor.selectedDocument}
          >
            Delete Map
          </button>
        </div>
      </header>

      <div className="map-editor-status">
        <span className="status-dot" />
        <span>{status}</span>
        <div className="toolbar-summary">
          <Badge tone="accent">{editor.documents.length} docs</Badge>
          <Badge tone={editor.dirtyCount > 0 ? "warning" : "muted"}>
            {editor.dirtyCount} dirty
          </Badge>
          <Badge tone={editor.totalIssues.errors > 0 ? "danger" : "success"}>
            {editor.totalIssues.errors} errors
          </Badge>
          <Badge tone={editor.totalIssues.warnings > 0 ? "warning" : "muted"}>
            {editor.totalIssues.warnings} warnings
          </Badge>
        </div>
      </div>

      <div
        className={`map-editor-layout ${
          inspectorCollapsed ? "map-editor-layout-inspector-collapsed" : ""
        }`}
      >
        <aside className="column">
          {editor.selectedDocument ? (
            <>
              <PanelSection label="Document" title={editor.selectedDocument.map.id || "Unnamed map"}>
                <div className="stats-grid stats-grid-compact">
                  <article className="stat-card">
                    <span>Grid</span>
                    <strong>
                      {editor.selectedDocument.map.size.width} x {editor.selectedDocument.map.size.height}
                    </strong>
                  </article>
                  <article className="stat-card">
                    <span>Objects</span>
                    <strong>{editor.selectedDocument.map.objects.length}</strong>
                  </article>
                </div>
                <div className="form-grid">
                  <TextField
                    label="Map ID"
                    value={editor.selectedDocument.map.id}
                    onChange={(value) =>
                      editor.updateSelectedMap((map) => ({ ...map, id: value.trim() }))
                    }
                  />
                  <TextField
                    label="Name"
                    value={editor.selectedDocument.map.name}
                    onChange={(value) =>
                      editor.updateSelectedMap((map) => ({ ...map, name: value }))
                    }
                  />
                  <NumberField
                    label="Width"
                    value={editor.selectedDocument.map.size.width}
                    onChange={(value) =>
                      editor.updateSelectedMap((map) => ({
                        ...map,
                        size: { ...map.size, width: Math.max(1, Math.floor(value)) },
                      }))
                    }
                    min={1}
                  />
                  <NumberField
                    label="Height"
                    value={editor.selectedDocument.map.size.height}
                    onChange={(value) =>
                      editor.updateSelectedMap((map) => ({
                        ...map,
                        size: { ...map.size, height: Math.max(1, Math.floor(value)) },
                      }))
                    }
                    min={1}
                  />
                </div>
              </PanelSection>

              <PanelSection label="Authoring" title="Tools and levels">
                <div className="toolbar-summary">
                  <button
                    type="button"
                    className="toolbar-button"
                    onClick={editor.addLevel}
                    disabled={editor.busy}
                  >
                    Add level
                  </button>
                  <button
                    type="button"
                    className="toolbar-button toolbar-danger"
                    onClick={editor.removeCurrentLevel}
                    disabled={editor.busy}
                  >
                    Remove level
                  </button>
                </div>
                <div className="form-grid">
                  <SelectField
                    label="Current level"
                    value={String(editor.currentLevel)}
                    onChange={(value) => editor.setCurrentLevel(Number(value))}
                    options={editor.selectedDocument.map.levels.map((level) => String(level.y))}
                    allowBlank={false}
                  />
                  <SelectField
                    label="Default level"
                    value={String(editor.selectedDocument.map.default_level)}
                    onChange={(value) =>
                      editor.updateSelectedMap((map) => ({
                        ...map,
                        default_level: Number(value),
                      }))
                    }
                    options={editor.selectedDocument.map.levels.map((level) => String(level.y))}
                    allowBlank={false}
                  />
                  <SelectField
                    label="Tool"
                    value={editor.tool}
                    onChange={(value) => editor.setToolMode(value as typeof editor.tool)}
                    options={editor.toolOptions}
                    allowBlank={false}
                  />
                  <SelectField
                    label="Rotation"
                    value={editor.placementDraft.rotation}
                    onChange={(value) =>
                      editor.setPlacementDraft((current) => ({
                        ...current,
                        rotation: value as MapRotation,
                      }))
                    }
                    options={["north", "east", "south", "west"]}
                    allowBlank={false}
                  />
                  <NumberField
                    label="Brush width"
                    value={editor.placementDraft.footprint.width}
                    onChange={(value) =>
                      editor.setPlacementDraft((current) => ({
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
                    value={editor.placementDraft.footprint.height}
                    onChange={(value) =>
                      editor.setPlacementDraft((current) => ({
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
                <div className="shortcut-hints">
                  <Badge tone="muted">Ctrl/Cmd+S save</Badge>
                  <Badge tone="muted">V/E select-erase</Badge>
                  <Badge tone="muted">1-4 place</Badge>
                  <Badge tone="muted">R rotate</Badge>
                  <Badge tone="muted">[ ] level</Badge>
                </div>
              </PanelSection>
            </>
          ) : (
            <PanelSection label="Selection" title="No map selected">
              <div className="empty-state">
                <Badge tone="muted">Idle</Badge>
                <p>Open a map from the main window to start editing.</p>
              </div>
            </PanelSection>
          )}
        </aside>

        <main className="column column-main">
          {selectedDocument ? (
            <PanelSection label="Canvas" title="Focused placement">
              <div className="map-editor-stage map-editor-stage-focus">
                <div className="map-canvas-meta">
                  <Badge tone="accent">level {editor.currentLevel}</Badge>
                  <Badge tone="muted">
                    hover {editor.hoveredCell ? `${editor.hoveredCell.x},${editor.hoveredCell.z}` : "none"}
                  </Badge>
                  <Badge tone="muted">{editor.tool}</Badge>
                  <Badge tone={selectedDocument.dirty ? "warning" : "muted"}>
                    {selectedDocument.dirty ? "Dirty" : "Saved"}
                  </Badge>
                </div>
                <div
                  className="map-grid-canvas map-grid-canvas-focus"
                  style={{
                    gridTemplateColumns: `repeat(${selectedDocument.map.size.width}, minmax(32px, 1fr))`,
                  }}
                >
                  {Array.from({
                    length: selectedDocument.map.size.width * selectedDocument.map.size.height,
                  }).map((_, index) => {
                    const x = index % selectedDocument.map.size.width;
                    const z = Math.floor(index / selectedDocument.map.size.width);
                    const grid = { x, y: editor.currentLevel, z };
                    const objects = getObjectsAtCell(selectedDocument.map, grid);
                    const topObject = objects.length > 0 ? objects[objects.length - 1] : null;
                    const isSelected = editor.selectedCoverage.some(
                      (cell) => gridKey(cell) === gridKey(grid),
                    );
                    const isPreview = editor.hoveredPreview.some(
                      (cell) => gridKey(cell) === gridKey(grid),
                    );
                    return (
                      <button
                        key={gridKey(grid)}
                        type="button"
                        className={`map-grid-cell map-grid-cell-focus ${
                          topObject ? "map-grid-cell-occupied" : ""
                        } ${isSelected ? "map-grid-cell-selected" : ""} ${
                          isPreview ? "map-grid-cell-preview" : ""
                        }`}
                        onMouseEnter={() => editor.setHoveredCell(grid)}
                        onClick={() => editor.handleGridCellClick(grid)}
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
          ) : null}
        </main>

        {!inspectorCollapsed ? (
          <aside className="column">
            {editor.selectedDocument ? (
              <PanelSection
                label="Inspector"
                title={editor.selectedObject ? editor.selectedObject.object_id : "No object selected"}
              >
                {editor.selectedObject ? (
                  <MapObjectInspector
                    selectedObject={editor.selectedObject}
                    workspace={workspace}
                    updateSelectedObject={editor.updateSelectedObject}
                    changeSelectedObjectKind={editor.changeSelectedObjectKind}
                    deleteSelectedObject={editor.deleteSelectedObject}
                  />
                ) : (
                  <div className="empty-state">
                    <Badge tone="muted">Inspect</Badge>
                    <p>Select an object from the canvas to edit payload and placement.</p>
                  </div>
                )}
              </PanelSection>
            ) : null}

            <ValidationPanel issues={editor.selectedIssues} />
          </aside>
        ) : null}
      </div>

      {editor.pendingIntent ? (
        <div className="modal-backdrop">
          <div className="modal-card">
            <p className="eyebrow">Unsaved Changes</p>
            <h2>Resolve current map before continuing</h2>
            <p className="shell-copy">
              Save and continue, discard the current edits, or cancel and stay on the current map.
            </p>
            <div className="toolbar-summary">
              <button
                type="button"
                className="toolbar-button toolbar-accent"
                onClick={() => {
                  void handlePendingResolution("save");
                }}
              >
                Save and switch
              </button>
              <button
                type="button"
                className="toolbar-button toolbar-danger"
                onClick={() => {
                  void handlePendingResolution("discard");
                }}
              >
                Discard and switch
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
