import {
  Suspense,
  lazy,
  type ComponentType,
  type LazyExoticComponent,
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { Badge } from "../../components/Badge";
import { TextField } from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { Toolbar } from "../../components/Toolbar";
import { ValidationPanel } from "../../components/ValidationPanel";
import type { GraphSelection } from "../../graph-kit/types";
import { invokeCommand } from "../../lib/tauri";
import { useRegisterEditorMenuCommands } from "../../menu/editorCommandRegistry";
import { EDITOR_MENU_COMMANDS } from "../../menu/menuCommands";
import type {
  AiConnectionTestResult,
  AiDraftPayload,
  AiGenerationResponse,
  AiSettings,
  DialogueData,
  DialogueDocumentPayload,
  DialogueWorkspacePayload,
  SaveDialoguesResult,
  ValidationIssue,
} from "../../types";
import type { AiGeneratePanelProps } from "../ai/AiGeneratePanel";
import { DialogueInspector } from "./DialogueInspector";
import { dialogueGraphAdapter } from "./dialogueGraphAdapter";

type GraphCanvasComponent = typeof import("../../graph-kit/GraphCanvas").GraphCanvas;
type GraphCanvasHandle = import("../../graph-kit/GraphCanvas").GraphCanvasHandle;
type GraphToolbarActionsComponent =
  typeof import("../../graph-kit/GraphToolbarActions").GraphToolbarActions;

const AiGeneratePanel = lazy(() =>
  import("../ai/AiGeneratePanel").then((module) => ({ default: module.AiGeneratePanel })),
) as LazyExoticComponent<ComponentType<AiGeneratePanelProps<DialogueData>>>;

type EditableDialogueDocument = DialogueDocumentPayload & {
  savedSnapshot: string;
  dirty: boolean;
  isDraft: boolean;
};

type DialogueWorkspaceProps = {
  workspace: DialogueWorkspacePayload;
  canPersist: boolean;
  onStatusChange: (status: string) => void;
  onReload: () => Promise<void>;
};

function createDraftDialogue(nextId: string): DialogueData {
  return dialogueGraphAdapter.normalizeDocument({
    dialog_id: nextId,
    nodes: [
      {
        id: "start",
        type: "dialog",
        title: "Start",
        speaker: "NPC",
        text: "New dialog...",
        is_start: true,
      },
      {
        id: "end",
        type: "end",
        title: "End",
        end_type: "normal",
      },
    ],
    connections: [
      {
        from: "start",
        from_port: 0,
        to: "end",
        to_port: 0,
      },
    ],
  });
}

function hydrateDocuments(
  documents: DialogueDocumentPayload[],
): EditableDialogueDocument[] {
  return documents.map((document) => {
    const normalized = dialogueGraphAdapter.normalizeDocument(document.dialog);
    return {
      ...document,
      dialog: normalized,
      savedSnapshot: JSON.stringify(normalized),
      dirty: false,
      isDraft: false,
    };
  });
}

function getDirtyState(dialog: DialogueData, savedSnapshot: string): boolean {
  return JSON.stringify(dialog) !== savedSnapshot;
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

function summarizeNodeTypes(document: DialogueData) {
  const counts = new Map<string, number>();
  for (const node of document.nodes) {
    counts.set(node.type, (counts.get(node.type) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([type, count]) => `${type}:${count}`)
    .join(" · ");
}

export function DialogueWorkspace({
  workspace,
  canPersist,
  onStatusChange,
  onReload,
}: DialogueWorkspaceProps) {
  const [documents, setDocuments] = useState<EditableDialogueDocument[]>(
    hydrateDocuments(workspace.documents),
  );
  const [selectedKey, setSelectedKey] = useState(workspace.documents[0]?.documentKey ?? "");
  const [searchText, setSearchText] = useState("");
  const [busy, setBusy] = useState(false);
  const [aiOpen, setAiOpen] = useState(false);
  const [GraphCanvasComponent, setGraphCanvasComponent] =
    useState<GraphCanvasComponent | null>(null);
  const [GraphToolbarActionsComponent, setGraphToolbarActionsComponent] =
    useState<GraphToolbarActionsComponent | null>(null);
  const [selection, setSelection] = useState<GraphSelection>({
    nodeId: null,
    edgeId: null,
  });
  const graphRef = useRef<GraphCanvasHandle | null>(null);
  const deferredSearch = useDeferredValue(searchText);
  const emptyDialogueRecord = useMemo(() => createDraftDialogue("dialog_draft"), []);

  useEffect(() => {
    setDocuments(hydrateDocuments(workspace.documents));
    setSelectedKey(workspace.documents[0]?.documentKey ?? "");
    setSelection({ nodeId: null, edgeId: null });
  }, [workspace]);

  useEffect(() => {
    if (!selectedKey || (GraphCanvasComponent && GraphToolbarActionsComponent)) {
      return;
    }

    let disposed = false;
    void Promise.all([
      import("../../graph-kit/GraphCanvas"),
      import("../../graph-kit/GraphToolbarActions"),
    ]).then(([graphCanvasModule, graphToolbarModule]) => {
      if (disposed) {
        return;
      }
      setGraphCanvasComponent(() => graphCanvasModule.GraphCanvas);
      setGraphToolbarActionsComponent(() => graphToolbarModule.GraphToolbarActions);
    });

    return () => {
      disposed = true;
    };
  }, [GraphCanvasComponent, GraphToolbarActionsComponent, selectedKey]);

  const filteredDocuments = useMemo(
    () =>
      documents.filter((document) => {
        if (!deferredSearch.trim()) {
          return true;
        }
        const haystack = `${document.dialog.dialog_id} ${document.fileName}`.toLowerCase();
        return haystack.includes(deferredSearch.trim().toLowerCase());
      }),
    [deferredSearch, documents],
  );

  const selectedDocument =
    documents.find((document) => document.documentKey === selectedKey) ?? null;
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
    const selected = documents.find((document) => document.documentKey === selectedKey);
    if (!selected || !canPersist) {
      return;
    }

    const timeoutId = window.setTimeout(() => {
      void invokeCommand<ValidationIssue[]>("validate_dialogue_document", {
        dialog: selected.dialog,
      })
        .then((issues) => {
          setDocuments((current) =>
            current.map((document) =>
              document.documentKey === selected.documentKey
                ? { ...document, validation: issues }
                : document,
            ),
          );
        })
        .catch(() => {});
    }, 220);

    return () => window.clearTimeout(timeoutId);
  }, [canPersist, documents, selectedKey]);

  function updateSelectedDialog(transform: (dialog: DialogueData) => DialogueData) {
    setDocuments((current) =>
      current.map((document) => {
        if (document.documentKey !== selectedKey) {
          return document;
        }
        const nextDialog = dialogueGraphAdapter.normalizeDocument(transform(document.dialog));
        return {
          ...document,
          dialog: nextDialog,
          dirty: getDirtyState(nextDialog, document.savedSnapshot),
        };
      }),
    );
  }

  async function validateCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select a dialogue first.");
      return;
    }

    if (!canPersist) {
      const counts = getIssueCounts(selectedDocument.validation);
      onStatusChange(
        counts.errorCount + counts.warningCount === 0
          ? "Current dialogue looks clean in fallback mode."
          : `Current dialogue has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
      return;
    }

    try {
      const issues = await invokeCommand<ValidationIssue[]>("validate_dialogue_document", {
        dialog: selectedDocument.dialog,
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
          ? `Dialogue ${selectedDocument.dialog.dialog_id} passed validation.`
          : `Dialogue ${selectedDocument.dialog.dialog_id} has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
    } catch (error) {
      onStatusChange(`Dialogue validation failed: ${String(error)}`);
    }
  }

  async function saveAll() {
    const dirtyDocuments = documents.filter((document) => document.dirty);
    if (!dirtyDocuments.length) {
      onStatusChange("No unsaved dialogue changes.");
      return;
    }
    if (!canPersist) {
      onStatusChange("Cannot save in UI fallback mode.");
      return;
    }

    setBusy(true);
    try {
      const result = await invokeCommand<SaveDialoguesResult>("save_dialogue_documents", {
        documents: dirtyDocuments.map((document) => ({
          originalId: document.isDraft ? null : document.originalId,
          dialog: document.dialog,
        })),
      });
      await onReload();
      onStatusChange(
        `Saved ${result.savedIds.length} dialogues. Removed ${result.deletedIds.length} renamed files.`,
      );
    } catch (error) {
      onStatusChange(`Dialogue save failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function deleteCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select a dialogue first.");
      return;
    }

    if (selectedDocument.isDraft) {
      const remaining = documents.filter(
        (document) => document.documentKey !== selectedDocument.documentKey,
      );
      setDocuments(remaining);
      setSelectedKey(remaining[0]?.documentKey ?? "");
      setSelection({ nodeId: null, edgeId: null });
      onStatusChange("Removed unsaved dialogue draft.");
      return;
    }

    if (!canPersist) {
      onStatusChange("Cannot delete project files in UI fallback mode.");
      return;
    }

    setBusy(true);
    try {
      await invokeCommand("delete_dialogue_document", {
        dialogId: selectedDocument.originalId,
      });
      await onReload();
      setSelection({ nodeId: null, edgeId: null });
      onStatusChange(`Deleted dialogue ${selectedDocument.originalId}.`);
    } catch (error) {
      onStatusChange(`Dialogue delete failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  function applyAiDraft(draft: AiDraftPayload<DialogueData>) {
    const nextDialog = dialogueGraphAdapter.normalizeDocument(draft.record);
    const existingDocument =
      documents.find((document) => document.dialog.dialog_id === nextDialog.dialog_id) ?? null;
    const targetKey =
      draft.operation === "revise" && selectedDocument
        ? selectedDocument.documentKey
        : existingDocument?.documentKey ?? null;

    if (targetKey) {
      setDocuments((current) =>
        current.map((document) =>
          document.documentKey === targetKey
            ? {
                ...document,
                dialog: nextDialog,
                dirty: true,
                validation: [],
                isDraft: document.isDraft || draft.operation === "create",
                fileName: `${nextDialog.dialog_id}.json`,
                relativePath: `data/dialogues/${nextDialog.dialog_id}.json`,
              }
            : document,
        ),
      );
      setSelectedKey(targetKey);
    } else {
      const draftDocument: EditableDialogueDocument = {
        documentKey: `draft-${nextDialog.dialog_id}`,
        originalId: nextDialog.dialog_id,
        fileName: `${nextDialog.dialog_id}.json`,
        relativePath: `data/dialogues/${nextDialog.dialog_id}.json`,
        dialog: nextDialog,
        validation: [],
        savedSnapshot: "",
        dirty: true,
        isDraft: true,
      };
      setDocuments((current) => [draftDocument, ...current]);
      setSelectedKey(draftDocument.documentKey);
    }

    setSelection({ nodeId: "start", edgeId: null });
    setAiOpen(false);
    onStatusChange(`AI draft applied to dialogue ${nextDialog.dialog_id}. Remember to save.`);
  }

  function createDraft() {
    const nextId = `dialog_${Date.now()}`;
    const draftDialog = createDraftDialogue(nextId);
    const draft: EditableDialogueDocument = {
      documentKey: `draft-${nextId}`,
      originalId: nextId,
      fileName: `${nextId}.json`,
      relativePath: `data/dialogues/${nextId}.json`,
      dialog: draftDialog,
      validation: [],
      savedSnapshot: "",
      dirty: true,
      isDraft: true,
    };
    setDocuments((current) => [draft, ...current]);
    setSelectedKey(draft.documentKey);
    setSelection({ nodeId: "start", edgeId: null });
    onStatusChange(`Created draft dialogue ${nextId}.`);
  }

  const selectedIssues = selectedDocument?.validation ?? [];
  const selectedCounts = getIssueCounts(selectedIssues);
  const applyAutoLayout = () => {
    updateSelectedDialog((dialog) => dialogueGraphAdapter.autoLayout(dialog));
    onStatusChange("Applied deterministic auto layout.");
  };
  const deleteGraphSelection = () => {
    graphRef.current?.deleteSelection();
  };

  const actions = [
    {
      id: "new",
      label: "New dialogue",
      onClick: createDraft,
      tone: "accent" as const,
      disabled: busy,
    },
    {
      id: "ai",
      label: "AI generate",
      onClick: () => setAiOpen(true),
      disabled: busy,
    },
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

  const menuCommands = useMemo(
    () => ({
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: {
        execute: () => {
          createDraft();
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.FILE_SAVE_ALL]: {
        execute: async () => {
          await saveAll();
        },
        isEnabled: () => !busy && dirtyCount > 0,
      },
      [EDITOR_MENU_COMMANDS.FILE_RELOAD]: {
        execute: async () => {
          await onReload();
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.FILE_DELETE_CURRENT]: {
        execute: async () => {
          await deleteCurrent();
        },
        isEnabled: () => !busy && Boolean(selectedDocument),
      },
      [EDITOR_MENU_COMMANDS.EDIT_VALIDATE_CURRENT]: {
        execute: async () => {
          await validateCurrent();
        },
        isEnabled: () => !busy && Boolean(selectedDocument),
      },
      [EDITOR_MENU_COMMANDS.EDIT_AUTO_LAYOUT]: {
        execute: () => {
          applyAutoLayout();
        },
        isEnabled: () => !busy && Boolean(selectedDocument),
      },
      [EDITOR_MENU_COMMANDS.EDIT_DELETE_SELECTION]: {
        execute: () => {
          deleteGraphSelection();
        },
        isEnabled: () => !busy && Boolean(selectedDocument),
      },
      [EDITOR_MENU_COMMANDS.AI_GENERATE]: {
        execute: () => {
          setAiOpen(true);
        },
        isEnabled: () => !busy,
      },
    }),
    [
      busy,
      deleteCurrent,
      dirtyCount,
      onReload,
      saveAll,
      selectedDocument,
      validateCurrent,
    ],
  );

  useRegisterEditorMenuCommands(menuCommands);

  function AiPanelLoadingFallback() {
    return (
      <div className="ai-modal-backdrop" role="presentation">
        <div className="ai-modal" role="dialog" aria-modal="true">
          <div className="empty-state">
            <Badge tone="muted">AI</Badge>
            <p>Loading AI generator...</p>
          </div>
        </div>
      </div>
    );
  }

  function GraphLoadingFallback() {
    return (
      <div className="empty-state">
        <Badge tone="muted">Graph</Badge>
        <p>Loading graph editor...</p>
      </div>
    );
  }

  return (
    <div className="workspace">
      <Toolbar actions={actions}>
        {selectedDocument && GraphToolbarActionsComponent ? (
          <GraphToolbarActionsComponent
            adapter={dialogueGraphAdapter}
            onAddNode={(type) => graphRef.current?.createNodeAtViewportCenter(type)}
            onAutoLayout={applyAutoLayout}
            onCenterView={() => graphRef.current?.centerView()}
            onDeleteSelection={deleteGraphSelection}
            disabled={busy}
          />
        ) : selectedDocument ? (
          <GraphLoadingFallback />
        ) : null}
      </Toolbar>

      <div className="workspace-grid">
        <aside className="column">
          <PanelSection label="Dialogue index" title="Project dialogues">
            <TextField
              label="Search"
              value={searchText}
              onChange={setSearchText}
              placeholder="Filter by dialog id"
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
                      setSelection({ nodeId: null, edgeId: null });
                    }}
                  >
                    <div className="item-row-top">
                      <strong>{document.dialog.dialog_id || "Unnamed dialogue"}</strong>
                      {document.dirty ? <Badge tone="warning">Dirty</Badge> : null}
                    </div>
                    <p>{summarizeNodeTypes(document.dialog)}</p>
                    <div className="row-badges">
                      <Badge tone="muted">{document.dialog.nodes.length} nodes</Badge>
                      <Badge tone="muted">{document.dialog.connections.length} edges</Badge>
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
              <PanelSection
                label="Document"
                title={selectedDocument.dialog.dialog_id || "Unnamed dialogue"}
              >
                <div className="stats-grid">
                  <article className="stat-card">
                    <span>Dialog ID</span>
                    <strong>{selectedDocument.dialog.dialog_id}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Nodes</span>
                    <strong>{selectedDocument.dialog.nodes.length}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Connections</span>
                    <strong>{selectedDocument.dialog.connections.length}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Validation</span>
                    <strong>
                      {selectedCounts.errorCount}E / {selectedCounts.warningCount}W
                    </strong>
                  </article>
                </div>
                <TextField
                  label="Dialog ID"
                  value={selectedDocument.dialog.dialog_id}
                  onChange={(value) =>
                    updateSelectedDialog((dialog) =>
                      dialogueGraphAdapter.setDocumentId(dialog, value.trim()),
                    )
                  }
                />
              </PanelSection>

              <PanelSection label="Graph" title="Flow editor">
                <div className="graph-panel">
                  {GraphCanvasComponent ? (
                    <GraphCanvasComponent
                      ref={graphRef}
                      adapter={dialogueGraphAdapter}
                      document={selectedDocument.dialog}
                      issues={selectedIssues}
                      selection={selection}
                      onSelectionChange={setSelection}
                      onDocumentChange={(dialog) => updateSelectedDialog(() => dialog)}
                    />
                  ) : (
                    <GraphLoadingFallback />
                  )}
                </div>
              </PanelSection>
            </>
          ) : (
            <PanelSection label="Selection" title="No dialogue selected">
              <div className="empty-state">
                <Badge tone="muted">Idle</Badge>
                <p>Select a dialogue from the left panel or create a new draft.</p>
              </div>
            </PanelSection>
          )}
        </main>

        <aside className="column">
          {selectedDocument ? (
            <DialogueInspector
              dialog={selectedDocument.dialog}
              selectedNodeId={selection.nodeId}
              onDialogChange={(dialog) => updateSelectedDialog(() => dialog)}
            />
          ) : null}

          <ValidationPanel issues={selectedIssues} />

          <PanelSection label="Selection" title="Graph focus" compact>
            <div className="toolbar-summary">
              <Badge tone={selection.nodeId ? "accent" : "muted"}>
                node: {selection.nodeId ?? "none"}
              </Badge>
              <Badge tone={selection.edgeId ? "accent" : "muted"}>
                edge: {selection.edgeId ?? "none"}
              </Badge>
              <Badge tone={dirtyCount > 0 ? "warning" : "muted"}>
                {dirtyCount} dirty docs
              </Badge>
              <Badge tone={totalIssues.errors > 0 ? "danger" : "success"}>
                {totalIssues.errors} errors
              </Badge>
            </div>
          </PanelSection>
        </aside>
      </div>

      {aiOpen ? (
        <Suspense fallback={<AiPanelLoadingFallback />}>
          <AiGeneratePanel
            open={aiOpen}
            title="Dialogue AI Generate"
            targetType="dialog"
            targetId={selectedDocument?.dialog.dialog_id ?? ""}
            currentRecord={selectedDocument?.dialog ?? emptyDialogueRecord}
            emptyRecord={emptyDialogueRecord}
            onClose={() => setAiOpen(false)}
            onGenerate={(request) =>
              invokeCommand<AiGenerationResponse<DialogueData>>("generate_dialogue_draft", {
                request,
              })
            }
            onLoadSettings={() => invokeCommand<AiSettings>("load_ai_settings")}
            onSaveSettings={(settings) =>
              invokeCommand<AiSettings>("save_ai_settings", { settings })
            }
            onTestSettings={(settings) =>
              invokeCommand<AiConnectionTestResult>("test_ai_provider", { settings })
            }
            onApply={applyAiDraft}
          />
        </Suspense>
      ) : null}
    </div>
  );
}
