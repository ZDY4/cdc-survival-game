import { useDeferredValue, useMemo, useState } from "react";
import { Badge } from "../../components/Badge";
import { PanelSection } from "../../components/PanelSection";
import { Toolbar } from "../../components/Toolbar";
import { TextField } from "../../components/fields";
import { invokeCommand, isTauriRuntime } from "../../lib/tauri";
import { useRegisterEditorMenuCommands } from "../../menu/editorCommandRegistry";
import { EDITOR_MENU_COMMANDS } from "../../menu/menuCommands";
import type {
  MapWorkspacePayload,
  OverworldWorkspacePayload,
  SpatialDocumentType,
  ValidationIssue,
} from "../../types";
import { getIssueCounts } from "./mapEditorState";
import { openOrFocusMapEditor } from "./mapWindowing";
import { summarizeMap } from "./mapEditorUtils";
import { summarizeOverworld } from "./overworldEditorUtils";

type SpatialLibraryWorkspaceProps = {
  mapWorkspace: MapWorkspacePayload;
  overworldWorkspace: OverworldWorkspacePayload;
  canPersist: boolean;
  onStatusChange: (status: string) => void;
  onReload: () => Promise<void>;
  indexVisible?: boolean;
};

export function SpatialLibraryWorkspace({
  mapWorkspace,
  overworldWorkspace,
  canPersist,
  onStatusChange,
  onReload,
  indexVisible = true,
}: SpatialLibraryWorkspaceProps) {
  const [activeKind, setActiveKind] = useState<SpatialDocumentType>("map");
  const [searchText, setSearchText] = useState("");
  const [selectedMapKey, setSelectedMapKey] = useState(mapWorkspace.documents[0]?.documentKey ?? "");
  const [selectedOverworldKey, setSelectedOverworldKey] = useState(
    overworldWorkspace.documents[0]?.documentKey ?? "",
  );
  const deferredSearch = useDeferredValue(searchText);

  const filteredMaps = useMemo(
    () =>
      mapWorkspace.documents.filter((document) => {
        if (!deferredSearch.trim()) {
          return true;
        }
        const haystack = `${document.map.id} ${document.fileName}`.toLowerCase();
        return haystack.includes(deferredSearch.trim().toLowerCase());
      }),
    [deferredSearch, mapWorkspace.documents],
  );
  const filteredOverworlds = useMemo(
    () =>
      overworldWorkspace.documents.filter((document) => {
        if (!deferredSearch.trim()) {
          return true;
        }
        const haystack = `${document.overworld.id} ${document.fileName}`.toLowerCase();
        return haystack.includes(deferredSearch.trim().toLowerCase());
      }),
    [deferredSearch, overworldWorkspace.documents],
  );

  const selectedMap =
    mapWorkspace.documents.find((document) => document.documentKey === selectedMapKey) ?? null;
  const selectedOverworld =
    overworldWorkspace.documents.find((document) => document.documentKey === selectedOverworldKey) ??
    null;

  async function openDocument(documentType: SpatialDocumentType, documentKey: string) {
    if (!isTauriRuntime()) {
      onStatusChange("Focused editor windows are only available inside the Tauri host.");
      return;
    }
    await openOrFocusMapEditor(documentType, documentKey);
    onStatusChange(
      documentType === "map"
        ? `Opened tactical map editor for ${documentKey}.`
        : `Opened overworld editor for ${documentKey}.`,
    );
  }

  async function validateCurrent(kind: SpatialDocumentType) {
    if (kind === "map") {
      if (!selectedMap) {
        onStatusChange("Select a tactical map first.");
        return;
      }
      if (!canPersist) {
        const counts = getIssueCounts(selectedMap.validation);
        onStatusChange(
          counts.errorCount + counts.warningCount === 0
            ? "Current map looks clean in fallback mode."
            : `Current map has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
        );
        return;
      }
      try {
        const issues = await invokeCommand<ValidationIssue[]>("validate_map_document", {
          map: selectedMap.map,
        });
        const counts = getIssueCounts(issues);
        onStatusChange(
          counts.errorCount + counts.warningCount === 0
            ? `Map ${selectedMap.map.id} passed validation.`
            : `Map ${selectedMap.map.id} has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
        );
      } catch (error) {
        onStatusChange(`Map validation failed: ${String(error)}`);
      }
      return;
    }

    if (!selectedOverworld) {
      onStatusChange("Select an overworld first.");
      return;
    }
    if (!canPersist) {
      const counts = getIssueCounts(selectedOverworld.validation);
      onStatusChange(
        counts.errorCount + counts.warningCount === 0
          ? "Current overworld looks clean in fallback mode."
          : `Current overworld has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
      return;
    }
    try {
      const issues = await invokeCommand<ValidationIssue[]>("validate_overworld_document", {
        overworld: selectedOverworld.overworld,
      });
      const counts = getIssueCounts(issues);
      onStatusChange(
        counts.errorCount + counts.warningCount === 0
          ? `Overworld ${selectedOverworld.overworld.id} passed validation.`
          : `Overworld ${selectedOverworld.overworld.id} has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
    } catch (error) {
      onStatusChange(`Overworld validation failed: ${String(error)}`);
    }
  }

  useRegisterEditorMenuCommands({
    [EDITOR_MENU_COMMANDS.FILE_RELOAD]: {
      execute: async () => {
        await onReload();
      },
    },
    [EDITOR_MENU_COMMANDS.EDIT_VALIDATE_CURRENT]: {
      execute: async () => {
        await validateCurrent(activeKind);
      },
      isEnabled: () => (activeKind === "map" ? Boolean(selectedMap) : Boolean(selectedOverworld)),
    },
  });

  const totalMapIssues = mapWorkspace.documents.reduce(
    (totals, document) => {
      const counts = getIssueCounts(document.validation);
      return {
        errors: totals.errors + counts.errorCount,
        warnings: totals.warnings + counts.warningCount,
      };
    },
    { errors: 0, warnings: 0 },
  );
  const totalOverworldIssues = overworldWorkspace.documents.reduce(
    (totals, document) => {
      const counts = getIssueCounts(document.validation);
      return {
        errors: totals.errors + counts.errorCount,
        warnings: totals.warnings + counts.warningCount,
      };
    },
    { errors: 0, warnings: 0 },
  );

  const actions = [
    {
      id: "new-map",
      label: activeKind === "map" ? "New map" : "New overworld",
      tone: "accent" as const,
      disabled: !isTauriRuntime(),
      onClick: () => {
        void openDocument(activeKind, "__new_map__");
      },
    },
    {
      id: "open",
      label: "Open editor",
      disabled: activeKind === "map" ? !selectedMap : !selectedOverworld,
      onClick: () => {
        if (activeKind === "map" && selectedMap) {
          void openDocument("map", selectedMap.documentKey);
        }
        if (activeKind === "overworld" && selectedOverworld) {
          void openDocument("overworld", selectedOverworld.documentKey);
        }
      },
    },
    {
      id: "reload",
      label: "Reload",
      onClick: () => {
        void onReload();
      },
    },
  ];

  return (
    <div className="workspace workspace-maps">
      <Toolbar actions={actions}>
        <div className="toolbar-summary">
          <button
            type="button"
            className={`toolbar-button ${activeKind === "map" ? "toolbar-accent" : ""}`}
            onClick={() => setActiveKind("map")}
          >
            小地图
          </button>
          <button
            type="button"
            className={`toolbar-button ${activeKind === "overworld" ? "toolbar-accent" : ""}`}
            onClick={() => setActiveKind("overworld")}
          >
            世界地图
          </button>
          <Badge tone="muted">{mapWorkspace.mapCount} maps</Badge>
          <Badge tone="muted">{overworldWorkspace.overworldCount} overworlds</Badge>
          <Badge tone={totalMapIssues.errors + totalOverworldIssues.errors > 0 ? "danger" : "success"}>
            {totalMapIssues.errors + totalOverworldIssues.errors} errors
          </Badge>
        </div>
      </Toolbar>

      <div
        className={[
          "workspace-grid",
          "map-library-grid",
          "workspace-grid-maps",
          indexVisible ? "" : "workspace-grid-left-hidden",
        ].filter(Boolean).join(" ")}
      >
        {indexVisible ? (
        <aside className="column workspace-index-column">
          <PanelSection
            label={activeKind === "map" ? "Tactical Maps" : "Overworlds"}
            title={activeKind === "map" ? "Project maps" : "Project overworlds"}
          >
            <TextField
              label="Search"
              value={searchText}
              onChange={setSearchText}
              placeholder={
                activeKind === "map" ? "Filter by map id" : "Filter by overworld id"
              }
            />
            <div className="item-list">
              {activeKind === "map"
                ? filteredMaps.map((document) => {
                    const counts = getIssueCounts(document.validation);
                    return (
                      <button
                        key={document.documentKey}
                        type="button"
                        className={`item-row ${
                          document.documentKey === selectedMapKey ? "item-row-active" : ""
                        }`}
                        onClick={() => setSelectedMapKey(document.documentKey)}
                        onDoubleClick={() => {
                          void openDocument("map", document.documentKey);
                        }}
                      >
                        <div className="item-row-top">
                          <strong>{document.map.id || "Unnamed map"}</strong>
                        </div>
                        <p>{summarizeMap(document.map)}</p>
                        <div className="row-badges">
                          <Badge tone="muted">{document.map.entry_points.length} entries</Badge>
                          {counts.errorCount > 0 ? (
                            <Badge tone="danger">{counts.errorCount} errors</Badge>
                          ) : null}
                          {counts.warningCount > 0 ? (
                            <Badge tone="warning">{counts.warningCount} warnings</Badge>
                          ) : null}
                        </div>
                      </button>
                    );
                  })
                : filteredOverworlds.map((document) => {
                    const counts = getIssueCounts(document.validation);
                    return (
                      <button
                        key={document.documentKey}
                        type="button"
                        className={`item-row ${
                          document.documentKey === selectedOverworldKey ? "item-row-active" : ""
                        }`}
                        onClick={() => setSelectedOverworldKey(document.documentKey)}
                        onDoubleClick={() => {
                          void openDocument("overworld", document.documentKey);
                        }}
                      >
                        <div className="item-row-top">
                          <strong>{document.overworld.id || "Unnamed overworld"}</strong>
                        </div>
                        <p>{summarizeOverworld(document.overworld)}</p>
                        <div className="row-badges">
                          <Badge tone="muted">{document.overworld.locations.length} locations</Badge>
                          {counts.errorCount > 0 ? (
                            <Badge tone="danger">{counts.errorCount} errors</Badge>
                          ) : null}
                          {counts.warningCount > 0 ? (
                            <Badge tone="warning">{counts.warningCount} warnings</Badge>
                          ) : null}
                        </div>
                      </button>
                    );
                  })}
            </div>
          </PanelSection>
        </aside>
        ) : null}

        <main className="column column-main">
          {activeKind === "map" && selectedMap ? (
            <PanelSection
              label="Map"
              title={selectedMap.map.id || "Unnamed map"}
              summary={
                <div className="toolbar-summary">
                  <Badge tone="muted">
                    {selectedMap.map.size.width} x {selectedMap.map.size.height}
                  </Badge>
                  <Badge tone="muted">{selectedMap.map.levels.length} levels</Badge>
                  <Badge tone="muted">{selectedMap.map.entry_points.length} entries</Badge>
                  <Badge tone="muted">{selectedMap.map.objects.length} objects</Badge>
                </div>
              }
            >
              <div className="summary-row">
                <div className="summary-row-main">
                  <strong>File</strong>
                  <p>{selectedMap.relativePath}</p>
                </div>
                <Badge tone="muted">{selectedMap.fileName}</Badge>
              </div>
              <div className="toolbar-summary">
                <button
                  type="button"
                  className="toolbar-button toolbar-accent"
                  onClick={() => {
                    void openDocument("map", selectedMap.documentKey);
                  }}
                >
                  Open map editor
                </button>
              </div>
            </PanelSection>
          ) : null}

          {activeKind === "overworld" && selectedOverworld ? (
            <PanelSection
              label="Overworld"
              title={selectedOverworld.overworld.id || "Unnamed overworld"}
              summary={
                <div className="toolbar-summary">
                  <Badge tone="muted">
                    {selectedOverworld.overworld.walkable_cells.length} cells
                  </Badge>
                  <Badge tone="muted">
                    {selectedOverworld.overworld.locations.length} locations
                  </Badge>
                </div>
              }
            >
              <div className="summary-row">
                <div className="summary-row-main">
                  <strong>File</strong>
                  <p>{selectedOverworld.relativePath}</p>
                </div>
                <Badge tone="muted">{selectedOverworld.fileName}</Badge>
              </div>
              <div className="toolbar-summary">
                <button
                  type="button"
                  className="toolbar-button toolbar-accent"
                  onClick={() => {
                    void openDocument("overworld", selectedOverworld.documentKey);
                  }}
                >
                  Open overworld editor
                </button>
              </div>
            </PanelSection>
          ) : null}
        </main>
      </div>
    </div>
  );
}
