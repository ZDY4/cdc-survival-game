import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { Badge } from "../../components/Badge";
import { SelectField, TextareaField, TextField, TokenListField } from "../../components/fields";
import { PanelSection } from "../../components/PanelSection";
import { Toolbar } from "../../components/Toolbar";
import { openOrFocusSettingsWindow } from "../../lib/editorWindows";
import { invokeCommand, isTauriRuntime } from "../../lib/tauri";
import { useRegisterEditorMenuCommands } from "../../menu/editorCommandRegistry";
import { EDITOR_MENU_COMMANDS } from "../../menu/menuCommands";
import type {
  AiSettings,
  EditorMenuSelfTestScenario,
  NarrativeAction,
  NarrativeAppSettings,
  NarrativeDocType,
  NarrativeDocumentPayload,
  NarrativeGenerateRequest,
  NarrativeGenerateResponse,
  NarrativeSelectionRange,
  NarrativeWorkspacePayload,
  SaveNarrativeDocumentResult,
  StructuringBundlePayload,
} from "../../types";
import { applySelectionRange, narrativeDiffSummary, toUtf8SelectionRange } from "./narrativeEditing";
import { runNarrativeMenuSelfTest } from "./narrativeMenuSelfTest";
import {
  defaultNarrativeMarkdown,
  defaultNarrativeTitle,
  docTypeDirectory,
  docTypeLabel,
  fallbackNarrativeMeta,
} from "./narrativeTemplates";
import { SETTINGS_CHANGED_EVENT } from "../settings/settingsWindowing";

type EditableNarrativeDocument = NarrativeDocumentPayload & {
  savedSnapshot: string;
  dirty: boolean;
  isDraft: boolean;
};

type NarrativeWorkspaceProps = {
  workspace: NarrativeWorkspacePayload;
  appSettings: NarrativeAppSettings;
  canPersist: boolean;
  startupReady: boolean;
  selfTestScenario: EditorMenuSelfTestScenario | null;
  onStatusChange: (status: string) => void;
  onReload: () => Promise<void>;
  onOpenWorkspace: (workspaceRoot: string) => Promise<void>;
  onConnectProject: (projectRoot: string | null) => Promise<void>;
  onSaveAppSettings: (settings: NarrativeAppSettings) => Promise<NarrativeAppSettings>;
};

type ReviewMode = "diff" | "draft" | "original";
type NarrativeEditorView = "edit" | "preview";

const ACTION_OPTIONS: Array<{ value: NarrativeAction; label: string }> = [
  { value: "create", label: "Create new draft" },
  { value: "revise_document", label: "Revise current document" },
  { value: "rewrite_selection", label: "Rewrite selected passage" },
  { value: "expand_selection", label: "Expand selected passage" },
  { value: "insert_after_selection", label: "Insert after selection" },
  { value: "derive_new_doc", label: "Derive as new document" },
];

function snapshotDocument(document: NarrativeDocumentPayload) {
  return JSON.stringify({ meta: document.meta, markdown: document.markdown });
}

function hydrateDocuments(documents: NarrativeDocumentPayload[]): EditableNarrativeDocument[] {
  return documents.map((document) => ({
    ...document,
    savedSnapshot: snapshotDocument(document),
    dirty: false,
    isDraft: false,
  }));
}

function documentDirty(document: NarrativeDocumentPayload, savedSnapshot: string) {
  return snapshotDocument(document) !== savedSnapshot;
}

function createFallbackDraft(docType: NarrativeDocType, slug: string): EditableNarrativeDocument {
  const meta = fallbackNarrativeMeta(docType, slug);
  return {
    documentKey: slug,
    originalSlug: slug,
    fileName: `${slug}.md`,
    relativePath: `narrative/${docTypeDirectory(docType)}/${slug}.md`,
    meta,
    markdown: defaultNarrativeMarkdown(docType, defaultNarrativeTitle(docType)),
    validation: [],
    savedSnapshot: "",
    dirty: true,
    isDraft: true,
  };
}

function defaultAiSettings(): AiSettings {
  return {
    baseUrl: "https://api.openai.com/v1",
    model: "gpt-4.1-mini",
    apiKey: "",
    timeoutSec: 45,
    maxContextRecords: 24,
  };
}

export function NarrativeWorkspace({
  workspace,
  appSettings,
  canPersist,
  startupReady,
  selfTestScenario,
  onStatusChange,
  onReload,
}: NarrativeWorkspaceProps) {
  const [documents, setDocuments] = useState<EditableNarrativeDocument[]>(hydrateDocuments(workspace.documents));
  const [selectedKey, setSelectedKey] = useState(workspace.documents[0]?.documentKey ?? "");
  const [searchText, setSearchText] = useState("");
  const [filterDocType, setFilterDocType] = useState("");
  const [busy, setBusy] = useState(false);
  const [aiAction, setAiAction] = useState<NarrativeAction>("revise_document");
  const [targetDocType, setTargetDocType] = useState<NarrativeDocType>("branch_sheet");
  const [userPrompt, setUserPrompt] = useState("");
  const [editorInstruction, setEditorInstruction] = useState("");
  const [response, setResponse] = useState<NarrativeGenerateResponse | null>(null);
  const [lastRequest, setLastRequest] = useState<NarrativeGenerateRequest | null>(null);
  const [reviewMode, setReviewMode] = useState<ReviewMode>("diff");
  const [editorView, setEditorView] = useState<NarrativeEditorView>("edit");
  const [selectionRange, setSelectionRange] = useState<NarrativeSelectionRange | null>(null);
  const [selectionText, setSelectionText] = useState("");
  const [bundleSelection, setBundleSelection] = useState<string[]>([]);
  const [bundleResult, setBundleResult] = useState<StructuringBundlePayload | null>(null);
  const [aiSettings, setAiSettings] = useState<AiSettings>(defaultAiSettings());
  const [inspectorExpanded, setInspectorExpanded] = useState(true);
  const [agentRunsExpanded, setAgentRunsExpanded] = useState(false);
  const editorRef = useRef<HTMLTextAreaElement | null>(null);
  const deferredSearch = useDeferredValue(searchText);
  const selfTestStartedRef = useRef(false);

  useEffect(() => {
    setDocuments(hydrateDocuments(workspace.documents));
    setSelectedKey((current) =>
      workspace.documents.some((document) => document.documentKey === current)
        ? current
        : workspace.documents[0]?.documentKey ?? "",
    );
    setBundleSelection([]);
    setBundleResult(null);
  }, [workspace]);

  useEffect(() => {
    setSelectionRange(null);
    setSelectionText("");
    setReviewMode("diff");
    setEditorView("edit");
  }, [selectedKey]);

  useEffect(() => {
    void invokeCommand<AiSettings>("load_ai_settings")
      .then(setAiSettings)
      .catch((error) => {
        onStatusChange(`Failed to load AI settings: ${String(error)}`);
      });
  }, [onStatusChange]);

  useEffect(() => {
    if (!isTauriRuntime()) {
      return;
    }

    let unlisten: (() => void) | undefined;
    void getCurrentWindow()
      .listen<{ section?: string }>(SETTINGS_CHANGED_EVENT, (event) => {
        if (event.payload.section === "ai") {
          void invokeCommand<AiSettings>("load_ai_settings")
            .then((settings) => {
              setAiSettings(settings);
              onStatusChange("AI settings refreshed.");
            })
            .catch((error) => {
              onStatusChange(`Failed to refresh AI settings: ${String(error)}`);
            });
        }
        if (event.payload.section === "workspace") {
          onStatusChange("Workspace settings updated. Reload the current workspace to pick up path changes.");
        }
      })
      .then((dispose) => {
        unlisten = dispose;
      });

    return () => {
      unlisten?.();
    };
  }, [onStatusChange]);

  const filteredDocuments = useMemo(
    () =>
      documents.filter((document) => {
        if (filterDocType && document.meta.docType !== filterDocType) {
          return false;
        }
        if (!deferredSearch.trim()) {
          return true;
        }
        const haystack = `${document.meta.slug} ${document.meta.title} ${document.meta.docType} ${document.meta.tags.join(" ")}`.toLowerCase();
        return haystack.includes(deferredSearch.trim().toLowerCase());
      }),
    [deferredSearch, documents, filterDocType],
  );

  const selectedDocument = documents.find((document) => document.documentKey === selectedKey) ?? null;
  const dirtyCount = documents.filter((document) => document.dirty).length;
  const hasSelection = Boolean(selectionText.trim()) && Boolean(selectionRange);
  const hasActiveWorkspace = Boolean(workspace.workspaceRoot.trim());
  const reviewText = selectedDocument
    ? reviewMode === "original"
      ? selectedDocument.markdown
      : reviewMode === "draft"
        ? response?.draftMarkdown ?? ""
        : narrativeDiffSummary(selectedDocument.markdown, response, selectionText)
    : "";

  async function promptConfigureWorkspace(actionLabel: string) {
    await openOrFocusSettingsWindow("workspace");
    onStatusChange(
      `Cannot ${actionLabel} because no narrative workspace is configured. Opened Settings > Workspace.`,
    );
  }

  function updateSelectedDocument(
    transform: (document: NarrativeDocumentPayload) => NarrativeDocumentPayload,
  ) {
    setDocuments((current) =>
      current.map((document) => {
        if (document.documentKey !== selectedKey) {
          return document;
        }
        const next = transform(document);
        return {
          ...next,
          dirty: documentDirty(next, document.savedSnapshot),
          savedSnapshot: document.savedSnapshot,
          isDraft: document.isDraft,
        };
      }),
    );
  }

  function updateSelectionFromEditor() {
    const editor = editorRef.current;
    const document = selectedDocument;
    if (!editor || !document) {
      return;
    }
    if (editor.selectionStart === editor.selectionEnd) {
      setSelectionRange(null);
      setSelectionText("");
      return;
    }
    const selected = document.markdown.slice(editor.selectionStart, editor.selectionEnd);
    setSelectionText(selected);
    setSelectionRange(toUtf8SelectionRange(document.markdown, editor.selectionStart, editor.selectionEnd));
  }

  async function createDraft(docType: NarrativeDocType) {
    if (!hasActiveWorkspace) {
      await promptConfigureWorkspace("create a draft");
      return;
    }

    setBusy(true);
    try {
      let draft: EditableNarrativeDocument;
      if (canPersist) {
        const payload = await invokeCommand<NarrativeDocumentPayload>("create_narrative_document", {
          workspaceRoot: workspace.workspaceRoot,
          input: { docType, title: defaultNarrativeTitle(docType) },
        });
        draft = { ...payload, savedSnapshot: "", dirty: true, isDraft: true };
      } else {
        draft = createFallbackDraft(docType, `${docType}-${Date.now()}`);
      }

      setDocuments((current) => [draft, ...current]);
      setSelectedKey(draft.documentKey);
      setAiAction("revise_document");
      setResponse(null);
      setLastRequest(null);
      onStatusChange(`Created ${docTypeLabel(docType)} draft ${draft.meta.slug}.`);
    } catch (error) {
      onStatusChange(`Failed to create draft: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function saveAll() {
    const dirtyDocuments = documents.filter((document) => document.dirty);
    if (!dirtyDocuments.length) {
      onStatusChange("No unsaved narrative changes.");
      return;
    }
    if (!canPersist) {
      onStatusChange("Cannot save narrative documents in UI fallback mode.");
      return;
    }
    if (!hasActiveWorkspace) {
      onStatusChange("Open or configure a narrative workspace before saving.");
      return;
    }

    setBusy(true);
    try {
      for (const document of dirtyDocuments) {
        await invokeCommand<SaveNarrativeDocumentResult>("save_narrative_document", {
          workspaceRoot: workspace.workspaceRoot,
          input: {
            originalSlug: document.isDraft ? null : document.originalSlug,
            document,
          },
        });
      }
      await onReload();
      onStatusChange(`Saved ${dirtyDocuments.length} narrative documents.`);
    } catch (error) {
      onStatusChange(`Narrative save failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function deleteCurrent() {
    if (!selectedDocument) {
      onStatusChange("Select a narrative document first.");
      return;
    }

    if (selectedDocument.isDraft) {
      const remaining = documents.filter((document) => document.documentKey !== selectedDocument.documentKey);
      setDocuments(remaining);
      setSelectedKey(remaining[0]?.documentKey ?? "");
      onStatusChange("Removed unsaved narrative draft.");
      return;
    }

    if (!canPersist) {
      onStatusChange("Cannot delete project files in UI fallback mode.");
      return;
    }

    setBusy(true);
    try {
      await invokeCommand("delete_narrative_document", {
        workspaceRoot: workspace.workspaceRoot,
        slug: selectedDocument.meta.slug,
      });
      await onReload();
      onStatusChange(`Deleted narrative document ${selectedDocument.meta.slug}.`);
    } catch (error) {
      onStatusChange(`Narrative delete failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function runGeneration() {
    if (!hasActiveWorkspace) {
      onStatusChange("Open or configure a narrative workspace before using AI.");
      return;
    }

    const currentDocType =
      selectedDocument?.meta.docType ?? targetDocType ?? workspace.docTypes[0]?.value ?? "project_brief";
    const currentSlug = selectedDocument?.meta.slug ?? `${currentDocType}-${Date.now()}`;
    const currentMarkdown =
      selectedDocument?.markdown ??
      defaultNarrativeMarkdown(currentDocType, defaultNarrativeTitle(currentDocType));

    if (
      (aiAction === "rewrite_selection" ||
        aiAction === "expand_selection" ||
        aiAction === "insert_after_selection") &&
      !hasSelection
    ) {
      onStatusChange("Select a passage before running a selection-only AI action.");
      return;
    }

    const request: NarrativeGenerateRequest = {
      docType: aiAction === "create" || aiAction === "derive_new_doc" ? targetDocType : currentDocType,
      targetSlug: currentSlug,
      action: aiAction,
      userPrompt,
      editorInstruction,
      currentMarkdown,
      selectedRange: selectionRange,
      selectedText: selectionText,
      relatedDocSlugs: selectedDocument?.meta.relatedDocs ?? [],
      derivedTargetDocType:
        aiAction === "create" || aiAction === "derive_new_doc" ? targetDocType : null,
    };

    setBusy(true);
    try {
      const command = aiAction === "create" ? "generate_narrative_draft" : "revise_narrative_draft";
      const next = await invokeCommand<NarrativeGenerateResponse>(command, {
        workspaceRoot: workspace.workspaceRoot,
        projectRoot: workspace.connectedProjectRoot ?? null,
        request,
      });
      setResponse(next);
      setLastRequest(request);
      setReviewMode("diff");
      onStatusChange(next.providerError || next.summary || "Narrative draft ready for review.");
    } catch (error) {
      onStatusChange(`Narrative generation failed: ${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function prepareBundle() {
    if (!hasActiveWorkspace) {
      onStatusChange("Open or configure a narrative workspace before exporting a structuring bundle.");
      return;
    }

    const documentSlugs = bundleSelection.length
      ? bundleSelection
      : selectedDocument
        ? [selectedDocument.meta.slug]
        : [];

    if (!documentSlugs.length) {
      onStatusChange("Select one or more documents for structuring export.");
      return;
    }

    try {
      const next = await invokeCommand<StructuringBundlePayload>("prepare_structuring_bundle", {
        workspaceRoot: workspace.workspaceRoot,
        projectRoot: workspace.connectedProjectRoot ?? null,
        input: { documentSlugs },
      });
      setBundleResult(next);
      onStatusChange(`Prepared structuring bundle for ${next.documentSlugs.length} documents.`);
    } catch (error) {
      onStatusChange(`Failed to prepare structuring bundle: ${String(error)}`);
    }
  }

  async function applyDraft(mode: "auto" | "new_doc" = "auto") {
    if (!response) {
      onStatusChange("Run AI generation first.");
      return;
    }
    if (response.providerError || !response.draftMarkdown.trim()) {
      onStatusChange("Current draft cannot be applied.");
      return;
    }

    const targetMode = mode === "new_doc" ? "new_doc" : response.changeScope;
    if (targetMode === "new_doc") {
      const nextDocType = lastRequest?.derivedTargetDocType ?? targetDocType;
      const nextDraft = canPersist
        ? {
            ...(await invokeCommand<NarrativeDocumentPayload>("create_narrative_document", {
              workspaceRoot: workspace.workspaceRoot,
              input: { docType: nextDocType, title: defaultNarrativeTitle(nextDocType) },
            })),
            savedSnapshot: "",
            dirty: true,
            isDraft: true,
          }
        : createFallbackDraft(nextDocType, `${nextDocType}-${Date.now()}`);
      nextDraft.markdown = response.draftMarkdown;
      nextDraft.meta.docType = nextDocType;
      setDocuments((current) => [nextDraft, ...current]);
      setSelectedKey(nextDraft.documentKey);
      setResponse(null);
      setLastRequest(null);
      onStatusChange("Applied AI draft as a new document. Remember to save.");
      return;
    }

    if (!selectedDocument) {
      onStatusChange("Select a narrative document before applying the draft.");
      return;
    }

    updateSelectedDocument((document) => {
      let nextMarkdown = document.markdown;
      if (targetMode === "document") {
        nextMarkdown = response.draftMarkdown;
      } else if ((targetMode === "selection" || targetMode === "insertion") && lastRequest?.selectedRange) {
        nextMarkdown = applySelectionRange(
          document.markdown,
          lastRequest.selectedRange,
          response.draftMarkdown,
          targetMode === "selection" ? "replace" : "insert_after",
        );
      }
      return { ...document, markdown: nextMarkdown };
    });
    setResponse(null);
    setLastRequest(null);
    onStatusChange("Applied AI draft to the current editor.");
  }

  const actions = [
    {
      id: "new",
      label: "New doc",
      tone: "accent" as const,
      disabled: busy || !hasActiveWorkspace,
      onClick: () => {
        void createDraft(targetDocType);
      },
    },
    {
      id: "ai",
      label: "Run AI",
      disabled: busy || !hasActiveWorkspace,
      onClick: () => {
        void runGeneration();
      },
    },
    {
      id: "save",
      label: "Save all",
      disabled: busy || dirtyCount === 0,
      onClick: () => {
        void saveAll();
      },
    },
    {
      id: "bundle",
      label: "Prepare bundle",
      disabled: busy || (!selectedDocument && bundleSelection.length === 0),
      onClick: () => {
        void prepareBundle();
      },
    },
    {
      id: "settings",
      label: "Settings",
      onClick: () => {
        void openOrFocusSettingsWindow("workspace");
      },
    },
    {
      id: "reload",
      label: "Reload",
      disabled: busy,
      onClick: () => {
        void onReload();
      },
    },
    {
      id: "delete",
      label: "Delete current",
      tone: "danger" as const,
      disabled: busy || !selectedDocument,
      onClick: () => {
        void deleteCurrent();
      },
    },
  ];

  const menuCommands = useMemo(
    () => ({
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: {
        execute: async () => {
          await createDraft(targetDocType);
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
      [EDITOR_MENU_COMMANDS.AI_GENERATE]: {
        execute: async () => {
          await runGeneration();
        },
        isEnabled: () => !busy && hasActiveWorkspace,
      },
      [EDITOR_MENU_COMMANDS.AI_TEST_PROVIDER_CONNECTION]: {
        execute: async () => {
          await openOrFocusSettingsWindow("ai");
          onStatusChange("Opened AI settings to test the provider connection.");
        },
      },
      [EDITOR_MENU_COMMANDS.AI_OPEN_PROVIDER_SETTINGS]: {
        execute: async () => {
          await openOrFocusSettingsWindow("ai");
          onStatusChange("Opened AI provider settings.");
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_RESET_LAYOUT]: {
        execute: () => {
          setInspectorExpanded(true);
          setAgentRunsExpanded(false);
          setReviewMode("diff");
          onStatusChange("Reset the Narrative Lab inspector layout.");
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_RESTORE_DEFAULT_LAYOUT]: {
        execute: () => {
          setInspectorExpanded(true);
          setAgentRunsExpanded(false);
          setReviewMode("diff");
          onStatusChange("Restored the default Narrative Lab workbench.");
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_COLLAPSE_ADVANCED_PANELS]: {
        execute: () => {
          setInspectorExpanded(false);
          setAgentRunsExpanded(false);
          onStatusChange("Collapsed advanced review panels.");
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_EXPAND_ALL_PANELS]: {
        execute: () => {
          setInspectorExpanded(true);
          setAgentRunsExpanded(true);
          onStatusChange("Expanded inspector review panels.");
        },
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_PROJECT_BRIEF]: {
        execute: async () => {
          await createDraft("project_brief");
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHARACTER_CARD]: {
        execute: async () => {
          await createDraft("character_card");
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHAPTER_OUTLINE]: {
        execute: async () => {
          await createDraft("chapter_outline");
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_BRANCH_SHEET]: {
        execute: async () => {
          await createDraft("branch_sheet");
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_SCENE_DRAFT]: {
        execute: async () => {
          await createDraft("scene_draft");
        },
        isEnabled: () => !busy,
      },
    }),
    [busy, dirtyCount, hasActiveWorkspace, onReload, onStatusChange, selectedDocument, targetDocType],
  );

  useRegisterEditorMenuCommands(menuCommands);

  useEffect(() => {
    if (!startupReady || selfTestScenario !== "narrative-menu" || selfTestStartedRef.current) {
      return;
    }

    selfTestStartedRef.current = true;
    void runNarrativeMenuSelfTest({
      hasActiveWorkspace,
      onStatusChange,
      windowLabel: "narrative-lab",
    }).then((result) => {
      onStatusChange(result.summary);
    });
  }, [hasActiveWorkspace, onStatusChange, selfTestScenario, startupReady]);

  if (!startupReady) {
    return (
      <div className="workspace">
        <PanelSection label="Startup" title="Loading Narrative Lab">
          <div className="empty-state">
            <Badge tone="muted">Loading</Badge>
            <p>Preparing narrative workspace and settings...</p>
          </div>
        </PanelSection>
      </div>
    );
  }

  return (
    <div className="workspace narrative-workspace">
      <Toolbar actions={actions}>
        <div className="toolbar-summary">
          <Badge tone={hasActiveWorkspace ? "accent" : "warning"}>
            {hasActiveWorkspace ? "workspace ready" : "workspace missing"}
          </Badge>
          <Badge tone="accent">{documents.length} docs</Badge>
          <Badge tone={dirtyCount > 0 ? "warning" : "muted"}>{dirtyCount} dirty</Badge>
          <Badge tone={response?.providerError ? "danger" : response ? "success" : "muted"}>
            {response?.providerError ? "AI blocked" : response ? "draft ready" : "no draft"}
          </Badge>
          <button type="button" className="toolbar-button" onClick={() => void openOrFocusSettingsWindow("ai")}>
            AI settings
          </button>
        </div>
      </Toolbar>

      <div className="workspace-grid narrative-grid">
        <aside className="column">
          <PanelSection
            label="Narrative Index"
            title={workspace.workspaceName ? `Narrative Lab · ${workspace.workspaceName}` : "Narrative Lab"}
            summary={
              <div className="toolbar-summary">
                <Badge tone="muted">{filteredDocuments.length} visible</Badge>
                <Badge tone="muted">{filterDocType || "all types"}</Badge>
              </div>
            }
          >
            <TextField
              label="Search"
              value={searchText}
              onChange={setSearchText}
              placeholder="Filter by slug, title, tag, or type"
            />
            <SelectField
              label="Doc type filter"
              value={filterDocType}
              onChange={setFilterDocType}
              options={workspace.docTypes}
            />
            <div className="item-list narrative-item-list">
              {!hasActiveWorkspace ? (
                <div className="empty-state">
                  <Badge tone="warning">Workspace</Badge>
                  <p>Open the settings window and configure a workspace root to start writing.</p>
                  <button
                    type="button"
                    className="toolbar-button toolbar-accent"
                    onClick={() => void openOrFocusSettingsWindow("workspace")}
                  >
                    Open workspace settings
                  </button>
                </div>
              ) : null}
              {hasActiveWorkspace && filteredDocuments.length === 0 ? (
                <div className="empty-state">
                  <Badge tone="muted">Empty</Badge>
                  <p>Create your first narrative draft from the toolbar.</p>
                </div>
              ) : null}
              {filteredDocuments.map((document) => (
                <button
                  key={document.documentKey}
                  type="button"
                  className={`item-row ${document.documentKey === selectedKey ? "item-row-active" : ""}`}
                  onClick={() => setSelectedKey(document.documentKey)}
                >
                  <div className="item-row-top">
                    <strong>{document.meta.title}</strong>
                    {document.dirty ? <Badge tone="warning">Dirty</Badge> : null}
                  </div>
                  <p>{document.meta.slug}</p>
                  <div className="row-badges">
                    <Badge tone="muted">{docTypeLabel(document.meta.docType)}</Badge>
                    <Badge tone="muted">{document.meta.status || "draft"}</Badge>
                    <label className="narrative-pick">
                      <input
                        type="checkbox"
                        checked={bundleSelection.includes(document.meta.slug)}
                        onChange={(event) => {
                          event.stopPropagation();
                          setBundleSelection((current) =>
                            event.target.checked
                              ? [...current, document.meta.slug]
                              : current.filter((slug) => slug !== document.meta.slug),
                          );
                        }}
                        onClick={(event) => event.stopPropagation()}
                      />
                      Bundle
                    </label>
                  </div>
                </button>
              ))}
            </div>
          </PanelSection>
        </aside>
        <main className="column column-main narrative-main-column">
          {selectedDocument ? (
            <>
              <PanelSection
                label="Writing"
                title={selectedDocument.meta.title || "Untitled document"}
                summary={
                  <div className="toolbar-summary">
                    <Badge tone="accent">{docTypeLabel(selectedDocument.meta.docType)}</Badge>
                    <Badge tone="muted">{selectedDocument.meta.slug}</Badge>
                    <Badge tone={selectedDocument.dirty ? "warning" : "success"}>
                      {selectedDocument.dirty ? "Unsaved" : "Saved"}
                    </Badge>
                  </div>
                }
              >
                <div className="narrative-writing-header">
                  <TextField
                    label="Title"
                    value={selectedDocument.meta.title}
                    onChange={(value) =>
                      updateSelectedDocument((document) => ({
                        ...document,
                        meta: { ...document.meta, title: value },
                      }))
                    }
                  />
                  <TextField
                    label="Status"
                    value={selectedDocument.meta.status}
                    onChange={(value) =>
                      updateSelectedDocument((document) => ({
                        ...document,
                        meta: { ...document.meta, status: value },
                      }))
                    }
                  />
                </div>

                <div className="narrative-selection-summary">
                  <Badge tone={hasSelection ? "accent" : "muted"}>
                    {hasSelection ? "selection active" : "no selection"}
                  </Badge>
                  <Badge tone="muted">
                    {selectionRange ? `${selectionRange.start}..${selectionRange.end}` : "full document"}
                  </Badge>
                  <button type="button" className="toolbar-button" onClick={() => setEditorView("edit")}>
                    Edit
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => setEditorView("preview")}>
                    Preview
                  </button>
                </div>

                {editorView === "edit" ? (
                  <label className="field">
                    <span className="field-label">Markdown editor</span>
                    <textarea
                      ref={editorRef}
                      className="field-input field-textarea field-code narrative-editor narrative-editor-single"
                      value={selectedDocument.markdown}
                      onChange={(event) =>
                        updateSelectedDocument((document) => ({
                          ...document,
                          markdown: event.target.value,
                        }))
                      }
                      onSelect={updateSelectionFromEditor}
                      onKeyUp={updateSelectionFromEditor}
                      onMouseUp={updateSelectionFromEditor}
                    />
                  </label>
                ) : (
                  <label className="field">
                    <span className="field-label">Preview</span>
                    <textarea
                      className="field-input field-textarea ai-readonly narrative-preview narrative-editor-single"
                      readOnly
                      value={selectedDocument.markdown}
                    />
                  </label>
                )}
              </PanelSection>

              <PanelSection
                label="AI Task"
                title="Write, revise, and derive"
                summary={
                  <div className="toolbar-summary">
                    <Badge tone="accent">{aiSettings.model || "No model"}</Badge>
                    <Badge tone="muted">{aiAction}</Badge>
                  </div>
                }
              >
                <div className="form-grid">
                  <SelectField
                    label="Action"
                    value={aiAction}
                    onChange={(value) => setAiAction((value as NarrativeAction) || "revise_document")}
                    allowBlank={false}
                    options={ACTION_OPTIONS}
                  />
                  <SelectField
                    label="Target doc type"
                    value={targetDocType}
                    onChange={(value) => setTargetDocType((value as NarrativeDocType) || "branch_sheet")}
                    allowBlank={false}
                    options={workspace.docTypes}
                  />
                </div>
                <TextareaField
                  label="Main prompt"
                  value={userPrompt}
                  onChange={setUserPrompt}
                  placeholder="Describe the scene, beat, tone, revision goal, or export intent."
                />
                <TextareaField
                  label="Editor instruction"
                  value={editorInstruction}
                  onChange={setEditorInstruction}
                  placeholder="Constrain POV, pacing, references, continuity, or structural rules."
                />
                <div className="toolbar-actions">
                  <button type="button" className="toolbar-button toolbar-accent" onClick={() => void runGeneration()} disabled={busy}>
                    Run AI
                  </button>
                  <button
                    type="button"
                    className="toolbar-button"
                    onClick={() => void applyDraft("auto")}
                    disabled={!response || Boolean(response.providerError)}
                  >
                    Apply result
                  </button>
                  <button
                    type="button"
                    className="toolbar-button"
                    onClick={() => void applyDraft("new_doc")}
                    disabled={!response || Boolean(response.providerError)}
                  >
                    Apply as new doc
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => void openOrFocusSettingsWindow("ai")}>
                    Open AI settings
                  </button>
                </div>
              </PanelSection>
            </>
          ) : (
            <div className="workspace-empty">
              <Badge tone="muted">Narrative</Badge>
              <p>Select a document from the left column or create a new one.</p>
            </div>
          )}
        </main>

        <aside className={`column narrative-inspector ${inspectorExpanded ? "" : "narrative-inspector-collapsed"}`.trim()}>
          {selectedDocument ? (
            <>
              <PanelSection
                label="Metadata"
                title="Document inspector"
                compact
                summary={
                  <div className="toolbar-summary">
                    <Badge tone="accent">{selectedDocument.fileName}</Badge>
                    <Badge tone="muted">{selectedDocument.validation.length} issues</Badge>
                  </div>
                }
              >
                <TextField
                  label="Slug"
                  value={selectedDocument.meta.slug}
                  onChange={(value) =>
                    updateSelectedDocument((document) => ({
                      ...document,
                      meta: { ...document.meta, slug: value },
                    }))
                  }
                />
                <TokenListField
                  label="Tags"
                  values={selectedDocument.meta.tags}
                  onChange={(values) =>
                    updateSelectedDocument((document) => ({
                      ...document,
                      meta: { ...document.meta, tags: values.filter(Boolean) },
                    }))
                  }
                />
                <TokenListField
                  label="Related docs"
                  values={selectedDocument.meta.relatedDocs}
                  onChange={(values) =>
                    updateSelectedDocument((document) => ({
                      ...document,
                      meta: { ...document.meta, relatedDocs: values.filter(Boolean) },
                    }))
                  }
                />
                <TokenListField
                  label="Source refs"
                  values={selectedDocument.meta.sourceRefs}
                  onChange={(values) =>
                    updateSelectedDocument((document) => ({
                      ...document,
                      meta: { ...document.meta, sourceRefs: values.filter(Boolean) },
                    }))
                  }
                />
                <label className="field">
                  <span className="field-label">File</span>
                  <textarea
                    className="field-input field-textarea ai-readonly narrative-readonly-compact"
                    readOnly
                    value={selectedDocument.relativePath}
                  />
                </label>
              </PanelSection>

              <PanelSection
                label="Review"
                title="AI review and revision"
                compact
                summary={
                  <div className="toolbar-summary">
                    <Badge tone={response?.providerError ? "danger" : response ? "success" : "muted"}>
                      {response?.providerError ? "provider error" : response ? "result ready" : "idle"}
                    </Badge>
                    <Badge tone="muted">{reviewMode}</Badge>
                  </div>
                }
              >
                <div className="toolbar-actions">
                  <button type="button" className="toolbar-button" onClick={() => setReviewMode("diff")}>
                    Diff
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => setReviewMode("draft")}>
                    Draft
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => setReviewMode("original")}>
                    Original
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => setAgentRunsExpanded((current) => !current)}>
                    {agentRunsExpanded ? "Hide agents" : "Show agents"}
                  </button>
                </div>
                <label className="field">
                  <span className="field-label">Summary</span>
                  <textarea
                    className="field-input field-textarea ai-readonly narrative-readonly-compact"
                    readOnly
                    value={response?.summary ?? response?.providerError ?? "No AI result yet."}
                  />
                </label>
                <label className="field">
                  <span className="field-label">Review notes</span>
                  <textarea
                    className="field-input field-textarea ai-readonly narrative-readonly-compact"
                    readOnly
                    value={[...(response?.reviewNotes ?? []), ...(response?.synthesisNotes ?? [])].join("\n")}
                  />
                </label>
                <label className="field">
                  <span className="field-label">Preview</span>
                  <textarea
                    className="field-input field-textarea field-code ai-readonly narrative-review-output"
                    readOnly
                    value={reviewText}
                  />
                </label>
                {agentRunsExpanded && response?.agentRuns.length ? (
                  <div className="agent-run-list">
                    {response.agentRuns.map((agent) => (
                      <article key={agent.agentId} className="agent-run-card">
                        <div className="agent-run-header">
                          <strong>{agent.label}</strong>
                          <Badge tone={agent.status === "failed" ? "danger" : "success"}>
                            {agent.status}
                          </Badge>
                        </div>
                        <p className="agent-run-focus">{agent.focus}</p>
                        <p className="agent-run-focus">{agent.summary}</p>
                      </article>
                    ))}
                  </div>
                ) : null}
              </PanelSection>

              <PanelSection
                label="Export"
                title="Structuring bundle"
                compact
                summary={
                  <div className="toolbar-summary">
                    <Badge tone="muted">{bundleSelection.length || (selectedDocument ? 1 : 0)} selected</Badge>
                    <Badge tone="muted">{bundleResult?.documentSlugs.length ?? 0} bundled</Badge>
                  </div>
                }
              >
                <div className="toolbar-actions">
                  <button type="button" className="toolbar-button toolbar-accent" onClick={() => void prepareBundle()}>
                    Prepare bundle
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => void openOrFocusSettingsWindow("workspace")}>
                    Workspace settings
                  </button>
                </div>
                <label className="field">
                  <span className="field-label">Bundle summary</span>
                  <textarea
                    className="field-input field-textarea ai-readonly narrative-readonly-compact"
                    readOnly
                    value={bundleResult?.summary ?? ""}
                  />
                </label>
                <label className="field">
                  <span className="field-label">Suggested targets</span>
                  <textarea
                    className="field-input field-textarea ai-readonly narrative-readonly-compact"
                    readOnly
                    value={bundleResult?.suggestedTargets.join("\n") ?? ""}
                  />
                </label>
                <label className="field">
                  <span className="field-label">Export path</span>
                  <textarea
                    className="field-input field-textarea ai-readonly narrative-readonly-compact"
                    readOnly
                    value={bundleResult?.exportPath ?? ""}
                  />
                </label>
              </PanelSection>
            </>
          ) : null}

          <PanelSection label="Workspace" title="Current session" compact>
            <div className="list-summary">
              <div className="summary-row summary-row-compact">
                <div className="summary-row-main">
                  <strong>Workspace root</strong>
                  <p>{workspace.workspaceRoot || appSettings.lastWorkspace || "Not configured"}</p>
                </div>
              </div>
              <div className="summary-row summary-row-compact">
                <div className="summary-row-main">
                  <strong>Project root</strong>
                  <p>{workspace.connectedProjectRoot || appSettings.connectedProjectRoot || "Not connected"}</p>
                </div>
              </div>
              <div className="summary-row summary-row-compact">
                <div className="summary-row-main">
                  <strong>AI provider</strong>
                  <p>{aiSettings.model || "Not configured"} · {aiSettings.baseUrl || "No endpoint"}</p>
                </div>
              </div>
            </div>
          </PanelSection>
        </aside>
      </div>
    </div>
  );
}
