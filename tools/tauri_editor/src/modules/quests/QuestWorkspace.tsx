import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { Badge } from "../../components/Badge";
import {
  NumberField,
  SelectField,
  TextareaField,
  TextField,
  TokenListField,
} from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { Toolbar } from "../../components/Toolbar";
import { ValidationPanel } from "../../components/ValidationPanel";
import { GraphCanvas, type GraphCanvasHandle } from "../../graph-kit/GraphCanvas";
import { GraphToolbarActions } from "../../graph-kit/GraphToolbarActions";
import type { GraphSelection } from "../../graph-kit/types";
import { invokeCommand } from "../../lib/tauri";
import type {
  AiConnectionTestResult,
  AiDraftPayload,
  AiGenerationResponse,
  AiSettings,
  QuestChoiceOption,
  QuestData,
  QuestDocumentPayload,
  QuestNode,
  QuestWorkspacePayload,
  SaveQuestsResult,
  ValidationIssue,
} from "../../types";
import { AiGeneratePanel } from "../ai/AiGeneratePanel";
import {
  questFlowGraphAdapter,
  questRelationshipGraphAdapter,
  type QuestRelationshipDocument,
} from "./questGraphAdapters";

type EditableQuestDocument = QuestDocumentPayload & {
  savedSnapshot: string;
  dirty: boolean;
  isDraft: boolean;
};

type QuestWorkspaceProps = {
  workspace: QuestWorkspacePayload;
  canPersist: boolean;
  onStatusChange: (status: string) => void;
  onReload: () => Promise<void>;
};

type QuestViewMode = "relationship" | "flow";

function createDraftQuest(nextId: string): QuestData {
  return questFlowGraphAdapter.normalizeDocument({
    quest_id: nextId,
    title: "New quest",
    description: "",
    prerequisites: [],
    time_limit: -1,
    flow: {
      start_node_id: "start",
      nodes: {
        start: {
          id: "start",
          type: "start",
          title: "Start",
          position: { x: 160, y: 160 },
        },
        objective_1: {
          id: "objective_1",
          type: "objective",
          title: "Objective",
          description: "Reach the target",
          objective_type: "travel",
          target: "",
          count: 1,
          position: { x: 440, y: 160 },
        },
        end: {
          id: "end",
          type: "end",
          title: "End",
          position: { x: 760, y: 160 },
        },
      },
      connections: [
        { from: "start", from_port: 0, to: "objective_1", to_port: 0 },
        { from: "objective_1", from_port: 0, to: "end", to_port: 0 },
      ],
    },
    _editor: {
      relationship_position: { x: 180, y: 140 },
    },
  });
}

function hydrateDocuments(documents: QuestDocumentPayload[]): EditableQuestDocument[] {
  return documents.map((document) => {
    const normalized = questFlowGraphAdapter.normalizeDocument(document.quest);
    return {
      ...document,
      quest: normalized,
      savedSnapshot: JSON.stringify(normalized),
      dirty: false,
      isDraft: false,
    };
  });
}

function getDirtyState(quest: QuestData, savedSnapshot: string) {
  return JSON.stringify(quest) !== savedSnapshot;
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

function summarizeQuest(document: QuestData) {
  const nodeCount = Object.keys(document.flow.nodes ?? {}).length;
  const prereqCount = document.prerequisites?.length ?? 0;
  return `${nodeCount} nodes · ${prereqCount} prereqs`;
}

function formatChoiceOptions(options: QuestChoiceOption[] = []) {
  return options.map((option) => `${option.text} => ${option.next ?? ""}`).join("\n");
}

function parseChoiceOptions(text: string): QuestChoiceOption[] {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [left, right] = line.split("=>");
      return {
        text: left?.trim() ?? "",
        next: right?.trim() ?? "",
      };
    });
}

function formatRewardItems(node: QuestNode) {
  return (node.rewards?.items ?? []).map((item) => `${item.id}=${item.count}`).join("\n");
}

function parseRewardItems(text: string) {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [id, count] = line.split("=");
      return {
        id: Number(id?.trim() ?? 0),
        count: Number(count?.trim() ?? 1),
      };
    })
    .filter((item) => Number.isFinite(item.id) && item.id > 0 && Number.isFinite(item.count));
}

function updateQuestNode(quest: QuestData, nodeId: string, transform: (node: QuestNode) => QuestNode) {
  const normalized = questFlowGraphAdapter.normalizeDocument(quest);
  const current = normalized.flow.nodes[nodeId];
  if (!current) {
    return normalized;
  }
  return {
    ...normalized,
    flow: {
      ...normalized.flow,
      nodes: {
        ...normalized.flow.nodes,
        [nodeId]: transform(current),
      },
    },
  };
}

function defaultReward() {
  return {
    items: [],
    experience: 0,
    skill_points: 0,
    unlock_location: "",
    unlock_recipes: [],
    title: "",
  };
}

export function QuestWorkspace({
  workspace,
  canPersist,
  onStatusChange,
  onReload,
}: QuestWorkspaceProps) {
  const [documents, setDocuments] = useState<EditableQuestDocument[]>(hydrateDocuments(workspace.documents));
  const [selectedKey, setSelectedKey] = useState(workspace.documents[0]?.documentKey ?? "");
  const [searchText, setSearchText] = useState("");
  const [busy, setBusy] = useState(false);
  const [viewMode, setViewMode] = useState<QuestViewMode>("relationship");
  const [flowSelection, setFlowSelection] = useState<GraphSelection>({ nodeId: null, edgeId: null });
  const [relationshipSelection, setRelationshipSelection] = useState<GraphSelection>({
    nodeId: null,
    edgeId: null,
  });
  const [aiOpen, setAiOpen] = useState(false);
  const flowGraphRef = useRef<GraphCanvasHandle | null>(null);
  const relationshipGraphRef = useRef<GraphCanvasHandle | null>(null);
  const deferredSearch = useDeferredValue(searchText);
  const emptyQuestRecord = useMemo(() => createDraftQuest("quest_draft"), []);

  useEffect(() => {
    setDocuments(hydrateDocuments(workspace.documents));
    setSelectedKey(workspace.documents[0]?.documentKey ?? "");
    setFlowSelection({ nodeId: null, edgeId: null });
    setRelationshipSelection({ nodeId: null, edgeId: null });
  }, [workspace]);

  useEffect(() => {
    if (viewMode === "relationship" && relationshipSelection.nodeId) {
      setSelectedKey(relationshipSelection.nodeId);
    }
  }, [relationshipSelection.nodeId, viewMode]);

  const filteredDocuments = useMemo(
    () =>
      documents.filter((document) => {
        if (!deferredSearch.trim()) {
          return true;
        }
        const haystack = `${document.quest.quest_id} ${document.quest.title} ${document.fileName}`.toLowerCase();
        return haystack.includes(deferredSearch.trim().toLowerCase());
      }),
    [deferredSearch, documents],
  );

  const selectedDocument = documents.find((document) => document.documentKey === selectedKey) ?? null;
  const selectedIssues = selectedDocument?.validation ?? [];
  const selectedCounts = getIssueCounts(selectedIssues);
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

  const relationshipDocument: QuestRelationshipDocument = useMemo(
    () => ({ quests: documents.map((document) => document.quest) }),
    [documents],
  );

  useEffect(() => {
    const selected = documents.find((document) => document.documentKey === selectedKey);
    if (!selected || !canPersist) {
      return;
    }

    const timeoutId = window.setTimeout(() => {
      void invokeCommand<ValidationIssue[]>("validate_quest_document", {
        quest: selected.quest,
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

  function updateSelectedQuest(transform: (quest: QuestData) => QuestData) {
    setDocuments((current) =>
      current.map((document) => {
        if (document.documentKey !== selectedKey) {
          return document;
        }
        const nextQuest = questFlowGraphAdapter.normalizeDocument(transform(document.quest));
        return {
          ...document,
          quest: nextQuest,
          dirty: getDirtyState(nextQuest, document.savedSnapshot),
        };
      }),
    );
  }

  function updateAllFromRelationship(document: QuestRelationshipDocument) {
    setDocuments((current) =>
      current.map((item) => {
        const nextQuest = document.quests.find((quest) => quest.quest_id === item.quest.quest_id);
        if (!nextQuest) {
          return item;
        }
        const normalized = questFlowGraphAdapter.normalizeDocument(nextQuest);
        return {
          ...item,
          quest: normalized,
          dirty: getDirtyState(normalized, item.savedSnapshot),
        };
      }),
    );
  }

  function createDraft() {
    const nextId = `quest_${Date.now()}`;
    const draftQuest = createDraftQuest(nextId);
    const draft: EditableQuestDocument = {
      documentKey: nextId,
      originalId: nextId,
      fileName: `${nextId}.json`,
      relativePath: `data/quests/${nextId}.json`,
      quest: draftQuest,
      validation: [],
      savedSnapshot: "",
      dirty: true,
      isDraft: true,
    };
    setDocuments((current) => [draft, ...current]);
    setSelectedKey(draft.documentKey);
    setViewMode("flow");
    setFlowSelection({ nodeId: "objective_1", edgeId: null });
    onStatusChange(`Created draft quest ${nextId}.`);
  }

  async function validateCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select a quest first.");
      return;
    }

    if (!canPersist) {
      const counts = getIssueCounts(selectedDocument.validation);
      onStatusChange(
        counts.errorCount + counts.warningCount === 0
          ? "Current quest looks clean in fallback mode."
          : `Current quest has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
      return;
    }

    try {
      const issues = await invokeCommand<ValidationIssue[]>("validate_quest_document", {
        quest: selectedDocument.quest,
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
          ? `Quest ${selectedDocument.quest.quest_id} passed validation.`
          : `Quest ${selectedDocument.quest.quest_id} has ${counts.errorCount} errors and ${counts.warningCount} warnings.`,
      );
    } catch (error) {
      onStatusChange(`Quest validation failed: ${String(error)}`);
    }
  }

  async function saveAll() {
    const dirtyDocuments = documents.filter((document) => document.dirty);
    if (!dirtyDocuments.length) {
      onStatusChange("No unsaved quest changes.");
      return;
    }
    if (!canPersist) {
      onStatusChange("Cannot save in UI fallback mode.");
      return;
    }

    setBusy(true);
    try {
      const result = await invokeCommand<SaveQuestsResult>("save_quest_documents", {
        documents: dirtyDocuments.map((document) => ({
          originalId: document.isDraft ? null : document.originalId,
          quest: document.quest,
        })),
      });
      await onReload();
      onStatusChange(
        `Saved ${result.savedIds.length} quests. Removed ${result.deletedIds.length} renamed files.`,
      );
    } catch (error) {
      onStatusChange(`Quest save failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function deleteCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select a quest first.");
      return;
    }

    if (selectedDocument.isDraft) {
      const remaining = documents.filter((document) => document.documentKey !== selectedDocument.documentKey);
      setDocuments(remaining);
      setSelectedKey(remaining[0]?.documentKey ?? "");
      setFlowSelection({ nodeId: null, edgeId: null });
      setRelationshipSelection({ nodeId: null, edgeId: null });
      onStatusChange("Removed unsaved quest draft.");
      return;
    }

    if (!canPersist) {
      onStatusChange("Cannot delete project files in UI fallback mode.");
      return;
    }

    setBusy(true);
    try {
      await invokeCommand("delete_quest_document", {
        questId: selectedDocument.originalId,
      });
      await onReload();
      setFlowSelection({ nodeId: null, edgeId: null });
      setRelationshipSelection({ nodeId: null, edgeId: null });
      onStatusChange(`Deleted quest ${selectedDocument.originalId}.`);
    } catch (error) {
      onStatusChange(`Quest delete failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  function applyAiDraft(draft: AiDraftPayload<QuestData>) {
    const nextQuest = questFlowGraphAdapter.normalizeDocument(draft.record);
    const existingKey =
      documents.find((document) => document.quest.quest_id === nextQuest.quest_id)?.documentKey ?? null;

    if (draft.operation === "revise" && selectedDocument) {
      updateSelectedQuest(() => nextQuest);
      setSelectedKey(selectedDocument.documentKey);
      setViewMode("flow");
    } else if (existingKey) {
      setDocuments((current) =>
        current.map((document) =>
          document.documentKey === existingKey
            ? {
                ...document,
                quest: nextQuest,
                dirty: true,
                validation: [],
              }
            : document,
        ),
      );
      setSelectedKey(existingKey);
      setViewMode("flow");
    } else {
      const draftDocument: EditableQuestDocument = {
        documentKey: nextQuest.quest_id,
        originalId: nextQuest.quest_id,
        fileName: `${nextQuest.quest_id}.json`,
        relativePath: `data/quests/${nextQuest.quest_id}.json`,
        quest: nextQuest,
        validation: [],
        savedSnapshot: "",
        dirty: true,
        isDraft: true,
      };
      setDocuments((current) => [draftDocument, ...current]);
      setSelectedKey(draftDocument.documentKey);
      setViewMode("flow");
    }

    setAiOpen(false);
    onStatusChange(`AI draft applied to quest ${nextQuest.quest_id}. Remember to save.`);
  }

  const actions = [
    {
      id: "new",
      label: "New quest",
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

  const selectedNode =
    viewMode === "flow" && selectedDocument && flowSelection.nodeId
      ? selectedDocument.quest.flow.nodes[flowSelection.nodeId] ?? null
      : null;

  return (
    <div className="workspace">
      <Toolbar actions={actions}>
        <div className="toolbar-actions">
          <button
            type="button"
            className={`toolbar-button ${viewMode === "relationship" ? "toolbar-accent" : ""}`}
            onClick={() => setViewMode("relationship")}
          >
            Relationship
          </button>
          <button
            type="button"
            className={`toolbar-button ${viewMode === "flow" ? "toolbar-accent" : ""}`}
            onClick={() => setViewMode("flow")}
            disabled={!selectedDocument}
          >
            Flow
          </button>
        </div>
        {viewMode === "flow" && selectedDocument ? (
          <GraphToolbarActions
            adapter={questFlowGraphAdapter}
            onAddNode={(type) => flowGraphRef.current?.createNodeAtViewportCenter(type)}
            onAutoLayout={() => {
              updateSelectedQuest((quest) => questFlowGraphAdapter.autoLayout(quest));
              onStatusChange("Applied deterministic quest flow layout.");
            }}
            onCenterView={() => flowGraphRef.current?.centerView()}
            onDeleteSelection={() => flowGraphRef.current?.deleteSelection()}
            disabled={busy}
          />
        ) : null}
        {viewMode === "relationship" ? (
          <div className="toolbar-actions">
            <button
              type="button"
              className="toolbar-button"
              onClick={() => {
                updateAllFromRelationship(questRelationshipGraphAdapter.autoLayout(relationshipDocument));
                onStatusChange("Applied relationship auto layout.");
              }}
              disabled={busy}
            >
              Auto layout
            </button>
            <button
              type="button"
              className="toolbar-button"
              onClick={() => relationshipGraphRef.current?.centerView()}
              disabled={busy}
            >
              Center
            </button>
            <button
              type="button"
              className="toolbar-button"
              onClick={() => relationshipGraphRef.current?.deleteSelection()}
              disabled={busy}
            >
              Delete selection
            </button>
          </div>
        ) : null}
      </Toolbar>

      <div className="workspace-grid">
        <aside className="column">
          <PanelSection label="Quest index" title="Project quests">
            <TextField
              label="Search"
              value={searchText}
              onChange={setSearchText}
              placeholder="Filter by quest id or title"
            />
            <div className="item-list">
              {filteredDocuments.map((document) => {
                const counts = getIssueCounts(document.validation);
                return (
                  <button
                    key={document.documentKey}
                    type="button"
                    className={`item-row ${document.documentKey === selectedKey ? "item-row-active" : ""}`}
                    onClick={() => {
                      setSelectedKey(document.documentKey);
                      setRelationshipSelection({ nodeId: document.documentKey, edgeId: null });
                    }}
                  >
                    <div className="item-row-top">
                      <strong>{document.quest.title || document.quest.quest_id || "Unnamed quest"}</strong>
                      {document.dirty ? <Badge tone="warning">Dirty</Badge> : null}
                    </div>
                    <p>{document.quest.quest_id}</p>
                    <div className="row-badges">
                      <Badge tone="muted">{summarizeQuest(document.quest)}</Badge>
                      {counts.errorCount > 0 ? <Badge tone="danger">{counts.errorCount} errors</Badge> : null}
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
              <PanelSection label="Document" title={selectedDocument.quest.title || selectedDocument.quest.quest_id}>
                <div className="stats-grid">
                  <article className="stat-card">
                    <span>Quest ID</span>
                    <strong>{selectedDocument.quest.quest_id}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Title</span>
                    <strong>{selectedDocument.quest.title || "Untitled"}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Nodes</span>
                    <strong>{Object.keys(selectedDocument.quest.flow.nodes).length}</strong>
                  </article>
                  <article className="stat-card">
                    <span>Validation</span>
                    <strong>{selectedCounts.errorCount}E / {selectedCounts.warningCount}W</strong>
                  </article>
                </div>
              </PanelSection>

              <PanelSection
                label={viewMode === "relationship" ? "Relationship graph" : "Flow graph"}
                title={viewMode === "relationship" ? "Quest prerequisite map" : "Quest flow editor"}
              >
                <div className="graph-panel">
                  {viewMode === "relationship" ? (
                    <GraphCanvas
                      ref={relationshipGraphRef}
                      adapter={questRelationshipGraphAdapter}
                      document={relationshipDocument}
                      issues={selectedIssues}
                      selection={relationshipSelection}
                      onSelectionChange={setRelationshipSelection}
                      onDocumentChange={updateAllFromRelationship}
                    />
                  ) : (
                    <GraphCanvas
                      ref={flowGraphRef}
                      adapter={questFlowGraphAdapter}
                      document={selectedDocument.quest}
                      issues={selectedIssues}
                      selection={flowSelection}
                      onSelectionChange={setFlowSelection}
                      onDocumentChange={(quest) => updateSelectedQuest(() => quest)}
                    />
                  )}
                </div>
              </PanelSection>
            </>
          ) : (
            <PanelSection label="Selection" title="No quest selected">
              <div className="empty-state">
                <Badge tone="muted">Idle</Badge>
                <p>Select a quest from the left panel or create a new draft.</p>
              </div>
            </PanelSection>
          )}
        </main>

        <aside className="column">
          {selectedDocument ? (
            <PanelSection label="Quest" title="Quest properties">
              <TextField
                label="Quest ID"
                value={selectedDocument.quest.quest_id}
                onChange={(value) => updateSelectedQuest((quest) => ({ ...quest, quest_id: value.trim() }))}
              />
              <TextField
                label="Title"
                value={selectedDocument.quest.title}
                onChange={(value) => updateSelectedQuest((quest) => ({ ...quest, title: value }))}
              />
              <TextareaField
                label="Description"
                value={selectedDocument.quest.description}
                onChange={(value) => updateSelectedQuest((quest) => ({ ...quest, description: value }))}
              />
              <TokenListField
                label="Prerequisites"
                values={selectedDocument.quest.prerequisites ?? []}
                onChange={(values) =>
                  updateSelectedQuest((quest) => ({ ...quest, prerequisites: values.filter(Boolean) }))
                }
              />
              <NumberField
                label="Time limit"
                value={selectedDocument.quest.time_limit}
                onChange={(value) => updateSelectedQuest((quest) => ({ ...quest, time_limit: value }))}
              />
              <div className="field-grid">
                <NumberField
                  label="Relationship X"
                  value={selectedDocument.quest._editor?.relationship_position?.x ?? 0}
                  onChange={(value) =>
                    updateSelectedQuest((quest) => ({
                      ...quest,
                      _editor: {
                        ...(quest._editor ?? {}),
                        relationship_position: {
                          x: value,
                          y: quest._editor?.relationship_position?.y ?? 0,
                        },
                      },
                    }))
                  }
                />
                <NumberField
                  label="Relationship Y"
                  value={selectedDocument.quest._editor?.relationship_position?.y ?? 0}
                  onChange={(value) =>
                    updateSelectedQuest((quest) => ({
                      ...quest,
                      _editor: {
                        ...(quest._editor ?? {}),
                        relationship_position: {
                          x: quest._editor?.relationship_position?.x ?? 0,
                          y: value,
                        },
                      },
                    }))
                  }
                />
              </div>
            </PanelSection>
          ) : null}

          {viewMode === "flow" && selectedDocument && selectedNode ? (
            <PanelSection label="Node" title={`${selectedNode.type} · ${selectedNode.id}`}>
              <TextField
                label="Node ID"
                value={selectedNode.id}
                onChange={(value) =>
                  updateSelectedQuest((quest) => {
                    const nextId = value.trim();
                    if (!nextId || nextId === selectedNode.id || quest.flow.nodes[nextId]) {
                      return quest;
                    }
                    const next = questFlowGraphAdapter.normalizeDocument(quest);
                    const node = { ...next.flow.nodes[selectedNode.id], id: nextId };
                    const nextNodes = { ...next.flow.nodes };
                    delete nextNodes[selectedNode.id];
                    nextNodes[nextId] = node;
                    const nextConnections = next.flow.connections.map((connection) => ({
                      ...connection,
                      from: connection.from === selectedNode.id ? nextId : connection.from,
                      to: connection.to === selectedNode.id ? nextId : connection.to,
                    }));
                    return {
                      ...next,
                      flow: {
                        ...next.flow,
                        start_node_id:
                          next.flow.start_node_id === selectedNode.id
                            ? nextId
                            : next.flow.start_node_id,
                        nodes: nextNodes,
                        connections: nextConnections,
                      },
                    };
                  })
                }
              />
              <TextField
                label="Title"
                value={selectedNode.title ?? ""}
                onChange={(value) =>
                  updateSelectedQuest((quest) =>
                    updateQuestNode(quest, selectedNode.id, (node) => ({ ...node, title: value })),
                  )
                }
              />
              {selectedNode.type === "objective" ? (
                <>
                  <SelectField
                    label="Objective type"
                    allowBlank={false}
                    value={selectedNode.objective_type ?? "travel"}
                    options={workspace.catalogs.objectiveTypes}
                    onChange={(value) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({
                          ...node,
                          objective_type: value,
                        })),
                      )
                    }
                  />
                  <TextareaField
                    label="Description"
                    value={selectedNode.description ?? ""}
                    onChange={(value) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({
                          ...node,
                          description: value,
                        })),
                      )
                    }
                  />
                  <TextField
                    label="Target"
                    value={selectedNode.target ?? ""}
                    onChange={(value) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({ ...node, target: value })),
                      )
                    }
                  />
                  <NumberField
                    label="Item ID"
                    value={selectedNode.item_id ?? 0}
                    onChange={(value) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({
                          ...node,
                          item_id: value > 0 ? value : null,
                        })),
                      )
                    }
                  />
                  <NumberField
                    label="Count"
                    value={selectedNode.count ?? 1}
                    min={1}
                    onChange={(value) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({
                          ...node,
                          count: Math.max(1, value),
                        })),
                      )
                    }
                  />
                </>
              ) : null}
              {selectedNode.type === "dialog" ? (
                <>
                  <TextField
                    label="Dialog ID"
                    value={selectedNode.dialog_id ?? ""}
                    onChange={(value) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({ ...node, dialog_id: value.trim() })),
                      )
                    }
                  />
                  <TokenListField
                    label="Branch labels"
                    values={Array.isArray(selectedNode.branch_labels) ? (selectedNode.branch_labels as string[]) : []}
                    onChange={(values) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({
                          ...node,
                          branch_labels: values,
                        })),
                      )
                    }
                  />
                </>
              ) : null}
              {selectedNode.type === "choice" ? (
                <TextareaField
                  label="Options"
                  hint="One per line: text => nextNodeId"
                  value={formatChoiceOptions(selectedNode.options)}
                  onChange={(value) =>
                    updateSelectedQuest((quest) =>
                      updateQuestNode(quest, selectedNode.id, (node) => ({
                        ...node,
                        options: parseChoiceOptions(value),
                      })),
                    )
                  }
                />
              ) : null}
              {selectedNode.type === "reward" ? (
                <>
                  <TextareaField
                    label="Reward items"
                    hint="One per line: itemId=count"
                    value={formatRewardItems(selectedNode)}
                    onChange={(value) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({
                          ...node,
                          rewards: {
                            ...(node.rewards ?? defaultReward()),
                            items: parseRewardItems(value),
                          },
                        })),
                      )
                    }
                  />
                  <NumberField
                    label="Experience"
                    value={selectedNode.rewards?.experience ?? 0}
                    onChange={(value) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({
                          ...node,
                          rewards: { ...(node.rewards ?? defaultReward()), experience: value },
                        })),
                      )
                    }
                  />
                  <NumberField
                    label="Skill points"
                    value={selectedNode.rewards?.skill_points ?? 0}
                    onChange={(value) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({
                          ...node,
                          rewards: { ...(node.rewards ?? defaultReward()), skill_points: value },
                        })),
                      )
                    }
                  />
                  <TextField
                    label="Unlock location"
                    value={selectedNode.rewards?.unlock_location ?? ""}
                    onChange={(value) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({
                          ...node,
                          rewards: { ...(node.rewards ?? defaultReward()), unlock_location: value.trim() },
                        })),
                      )
                    }
                  />
                  <TokenListField
                    label="Unlock recipes"
                    values={selectedNode.rewards?.unlock_recipes ?? []}
                    onChange={(values) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({
                          ...node,
                          rewards: { ...(node.rewards ?? defaultReward()), unlock_recipes: values },
                        })),
                      )
                    }
                  />
                  <TextField
                    label="Reward title"
                    value={selectedNode.rewards?.title ?? ""}
                    onChange={(value) =>
                      updateSelectedQuest((quest) =>
                        updateQuestNode(quest, selectedNode.id, (node) => ({
                          ...node,
                          rewards: { ...(node.rewards ?? defaultReward()), title: value },
                        })),
                      )
                    }
                  />
                </>
              ) : null}
            </PanelSection>
          ) : null}

          <ValidationPanel issues={selectedIssues} />

          <PanelSection label="Selection" title="Quest focus" compact>
            <div className="toolbar-summary">
              <Badge tone={viewMode === "flow" && flowSelection.nodeId ? "accent" : "muted"}>
                node: {viewMode === "flow" ? flowSelection.nodeId ?? "none" : relationshipSelection.nodeId ?? "none"}
              </Badge>
              <Badge tone={viewMode === "flow" && flowSelection.edgeId ? "accent" : "muted"}>
                edge: {viewMode === "flow" ? flowSelection.edgeId ?? "none" : relationshipSelection.edgeId ?? "none"}
              </Badge>
              <Badge tone={dirtyCount > 0 ? "warning" : "muted"}>{dirtyCount} dirty docs</Badge>
              <Badge tone={totalIssues.errors > 0 ? "danger" : "success"}>
                {totalIssues.errors} errors
              </Badge>
            </div>
          </PanelSection>
        </aside>
      </div>

      {aiOpen ? (
        <AiGeneratePanel<QuestData>
          open={aiOpen}
          title="Quest AI Generate"
          targetType="quest"
          targetId={selectedDocument?.quest.quest_id ?? ""}
          currentRecord={selectedDocument?.quest ?? emptyQuestRecord}
          emptyRecord={emptyQuestRecord}
          onClose={() => setAiOpen(false)}
          onGenerate={(request) =>
            invokeCommand<AiGenerationResponse<QuestData>>("generate_quest_draft", { request })
          }
          onLoadSettings={() => invokeCommand<AiSettings>("load_ai_settings")}
          onSaveSettings={(settings) => invokeCommand<AiSettings>("save_ai_settings", { settings })}
          onTestSettings={(settings) =>
            invokeCommand<AiConnectionTestResult>("test_ai_provider", { settings })
          }
          onApply={applyAiDraft}
        />
      ) : null}
    </div>
  );
}
