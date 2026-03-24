import { useDeferredValue, useEffect, useMemo, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { Badge } from "../../components/Badge";
import { PanelSection } from "../../components/PanelSection";
import { Toolbar } from "../../components/Toolbar";
import { TextField } from "../../components/fields";
import { invokeCommand, isTauriRuntime } from "../../lib/tauri";
import { useRegisterEditorMenuCommands } from "../../menu/editorCommandRegistry";
import { EDITOR_MENU_COMMANDS } from "../../menu/menuCommands";
import type {
  MapDocumentPayload,
  MapEditorSaveCompletePayload,
  MapEditorSessionEndedPayload,
  MapEditorStateChangedPayload,
  MapWorkspacePayload,
  ValidationIssue,
} from "../../types";
import {
  MAP_EDITOR_SAVE_COMPLETE_EVENT,
  MAP_EDITOR_SESSION_ENDED_EVENT,
  MAP_EDITOR_STATE_CHANGED_EVENT,
  NEW_MAP_DOCUMENT_KEY,
  openOrFocusMapEditor,
} from "./mapWindowing";
import { getIssueCounts } from "./mapEditorState";
import { summarizeMap } from "./mapEditorUtils";

type MapLibraryWorkspaceProps = {
  workspace: MapWorkspacePayload;
  canPersist: boolean;
  onStatusChange: (status: string) => void;
  onReload: () => Promise<void>;
};

function buildSummary(document: MapDocumentPayload): MapEditorStateChangedPayload {
  const counts = getIssueCounts(document.validation);
  return {
    documentKey: document.documentKey,
    mapId: document.map.id,
    dirty: false,
    errorCount: counts.errorCount,
    warningCount: counts.warningCount,
    objectCount: document.map.objects.length,
    level: document.map.default_level,
  };
}

export function MapLibraryWorkspace({
  workspace,
  canPersist,
  onStatusChange,
  onReload,
}: MapLibraryWorkspaceProps) {
  const [searchText, setSearchText] = useState("");
  const [selectedKey, setSelectedKey] = useState(workspace.documents[0]?.documentKey ?? "");
  const [liveSummaries, setLiveSummaries] = useState<Record<string, MapEditorStateChangedPayload>>({});
  const deferredSearch = useDeferredValue(searchText);

  useEffect(() => {
    setSelectedKey((current) =>
      workspace.documents.some((document) => document.documentKey === current)
        ? current
        : workspace.documents[0]?.documentKey ?? "",
    );
  }, [workspace]);

  useEffect(() => {
    if (!isTauriRuntime()) {
      return;
    }

    let mounted = true;
    const currentWindow = getCurrentWindow();

    const setup = async () => {
      const unlistenStateChanged = await currentWindow.listen<MapEditorStateChangedPayload>(
        MAP_EDITOR_STATE_CHANGED_EVENT,
        (event) => {
          if (!mounted) {
            return;
          }
          setLiveSummaries((current) => ({
            ...current,
            [event.payload.documentKey]: event.payload,
          }));
        },
      );

      const unlistenSaveComplete = await currentWindow.listen<MapEditorSaveCompletePayload>(
        MAP_EDITOR_SAVE_COMPLETE_EVENT,
        () => {
          if (!mounted) {
            return;
          }
          setLiveSummaries({});
          void onReload();
        },
      );

      const unlistenSessionEnded = await currentWindow.listen<MapEditorSessionEndedPayload>(
        MAP_EDITOR_SESSION_ENDED_EVENT,
        () => {
          if (!mounted) {
            return;
          }
          void onReload();
        },
      );

      return () => {
        void unlistenStateChanged();
        void unlistenSaveComplete();
        void unlistenSessionEnded();
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
  }, [onReload]);

  const filteredDocuments = useMemo(
    () =>
      workspace.documents.filter((document) => {
        if (!deferredSearch.trim()) {
          return true;
        }
        const haystack = `${document.map.id} ${document.fileName}`.toLowerCase();
        return haystack.includes(deferredSearch.trim().toLowerCase());
      }),
    [deferredSearch, workspace.documents],
  );

  const selectedDocument =
    workspace.documents.find((document) => document.documentKey === selectedKey) ?? null;
  const totalIssues = workspace.documents.reduce(
    (totals, document) => {
      const live = liveSummaries[document.documentKey];
      if (live) {
        return {
          errors: totals.errors + live.errorCount,
          warnings: totals.warnings + live.warningCount,
        };
      }
      const counts = getIssueCounts(document.validation);
      return {
        errors: totals.errors + counts.errorCount,
        warnings: totals.warnings + counts.warningCount,
      };
    },
    { errors: 0, warnings: 0 },
  );
  const dirtyCount = Object.values(liveSummaries).filter((summary) => summary.dirty).length;

  async function handleOpen(documentKey: string) {
    if (!isTauriRuntime()) {
      onStatusChange("Map editor windowing is only available inside the Tauri host.");
      return;
    }
    await openOrFocusMapEditor(documentKey);
    if (documentKey === NEW_MAP_DOCUMENT_KEY) {
      onStatusChange("Opened map editor for a new draft.");
      return;
    }
    const document = workspace.documents.find((entry) => entry.documentKey === documentKey);
    onStatusChange(`Opened map editor for ${document?.map.id ?? documentKey}.`);
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
      const counts = getIssueCounts(issues);
      setLiveSummaries((current) => ({
        ...current,
        [selectedDocument.documentKey]: {
          ...(current[selectedDocument.documentKey] ?? buildSummary(selectedDocument)),
          errorCount: counts.errorCount,
          warningCount: counts.warningCount,
        },
      }));
      onStatusChange(
        counts.errorCount + counts.warningCount === 0
          ? `Map ${selectedDocument.map.id} passed validation.`
          : `Map ${selectedDocument.map.id} has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
    } catch (error) {
      onStatusChange(`Map validation failed: ${String(error)}`);
    }
  }

  async function deleteCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select a map first.");
      return;
    }

    if (!canPersist) {
      onStatusChange("Cannot delete project files in UI fallback mode.");
      return;
    }

    try {
      await invokeCommand("delete_map_document", {
        mapId: selectedDocument.originalId,
      });
      setLiveSummaries((current) => {
        const next = { ...current };
        delete next[selectedDocument.documentKey];
        return next;
      });
      await onReload();
      onStatusChange(`Deleted map ${selectedDocument.originalId}.`);
    } catch (error) {
      onStatusChange(`Map delete failed: ${String(error)}`);
    }
  }

  useRegisterEditorMenuCommands({
    [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: {
      execute: async () => {
        await handleOpen(NEW_MAP_DOCUMENT_KEY);
      },
      isEnabled: () => isTauriRuntime(),
    },
    [EDITOR_MENU_COMMANDS.FILE_RELOAD]: {
      execute: async () => {
        setLiveSummaries({});
        await onReload();
      },
    },
    [EDITOR_MENU_COMMANDS.FILE_DELETE_CURRENT]: {
      execute: async () => {
        await deleteCurrent();
      },
      isEnabled: () => Boolean(selectedDocument) && canPersist,
    },
    [EDITOR_MENU_COMMANDS.EDIT_VALIDATE_CURRENT]: {
      execute: async () => {
        await validateCurrent();
      },
      isEnabled: () => Boolean(selectedDocument),
    },
  });

  const actions = [
    {
      id: "new",
      label: "New map",
      tone: "accent" as const,
      disabled: !canPersist && !isTauriRuntime(),
      onClick: () => {
        void handleOpen(NEW_MAP_DOCUMENT_KEY);
      },
    },
    {
      id: "open",
      label: "Open editor",
      disabled: !selectedDocument,
      onClick: () => {
        if (!selectedDocument) {
          return;
        }
        void handleOpen(selectedDocument.documentKey);
      },
    },
    {
      id: "reload",
      label: "Reload",
      onClick: () => {
        setLiveSummaries({});
        void onReload();
      },
    },
  ];

  return (
    <div className="workspace">
      <Toolbar actions={actions}>
        <div className="toolbar-summary">
          <Badge tone="accent">{workspace.mapCount} files</Badge>
          <Badge tone={dirtyCount > 0 ? "warning" : "muted"}>{dirtyCount} editing</Badge>
          <Badge tone={totalIssues.errors > 0 ? "danger" : "success"}>
            {totalIssues.errors} errors
          </Badge>
          <Badge tone={totalIssues.warnings > 0 ? "warning" : "muted"}>
            {totalIssues.warnings} warnings
          </Badge>
        </div>
      </Toolbar>

      <div className="workspace-grid map-library-grid">
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
                const live = liveSummaries[document.documentKey] ?? buildSummary(document);
                return (
                  <button
                    key={document.documentKey}
                    type="button"
                    className={`item-row ${
                      document.documentKey === selectedKey ? "item-row-active" : ""
                    }`}
                    onClick={() => setSelectedKey(document.documentKey)}
                    onDoubleClick={() => {
                      void handleOpen(document.documentKey);
                    }}
                  >
                    <div className="item-row-top">
                      <strong>{document.map.id || "Unnamed map"}</strong>
                      <div className="row-badges">
                        {live.dirty ? <Badge tone="warning">Dirty</Badge> : null}
                        {live.dirty || live.level !== document.map.default_level ? (
                          <Badge tone="accent">Live</Badge>
                        ) : null}
                      </div>
                    </div>
                    <p>{summarizeMap(document.map)}</p>
                    <div className="row-badges">
                      <Badge tone="muted">{document.map.levels.length} levels</Badge>
                      <Badge tone="muted">{live.objectCount} objects</Badge>
                      {live.errorCount > 0 ? (
                        <Badge tone="danger">{live.errorCount} errors</Badge>
                      ) : null}
                      {live.warningCount > 0 ? (
                        <Badge tone="warning">{live.warningCount} warnings</Badge>
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
            <PanelSection label="Overview" title={selectedDocument.map.id || "Unnamed map"}>
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
                  <span>Levels</span>
                  <strong>{selectedDocument.map.levels.length}</strong>
                </article>
                <article className="stat-card">
                  <span>Objects</span>
                  <strong>{selectedDocument.map.objects.length}</strong>
                </article>
              </div>

              <div className="list-summary">
                <div className="summary-row">
                  <div className="summary-row-main">
                    <strong>File</strong>
                    <p>{selectedDocument.relativePath}</p>
                  </div>
                  <Badge tone="muted">{selectedDocument.fileName}</Badge>
                </div>
                <div className="summary-row">
                  <div className="summary-row-main">
                    <strong>Editing flow</strong>
                    <p>Open the dedicated map window for placement, shortcuts, and focused inspection.</p>
                  </div>
                  <Badge tone="accent">Single editor window</Badge>
                </div>
              </div>

              <div className="toolbar-summary">
                <button
                  type="button"
                  className="toolbar-button toolbar-accent"
                  onClick={() => {
                    void handleOpen(selectedDocument.documentKey);
                  }}
                >
                  Open In Map Editor
                </button>
              </div>
            </PanelSection>
          ) : (
            <PanelSection label="Selection" title="No map selected">
              <div className="empty-state">
                <Badge tone="muted">Idle</Badge>
                <p>Select a map from the left panel to open the focused editor window.</p>
              </div>
            </PanelSection>
          )}
        </main>
      </div>
    </div>
  );
}
