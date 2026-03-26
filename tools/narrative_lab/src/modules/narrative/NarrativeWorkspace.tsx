import { useDeferredValue, useEffect, useMemo, useRef, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { Badge } from "../../components/Badge";
import {
  IDEWorkbenchShell,
  type WorkbenchActivityItem,
  type WorkbenchStatusItem,
} from "../../components/IDEWorkbenchShell";
import { SelectField, TextareaField, TextField, TokenListField } from "../../components/fields";
import { openOrFocusSettingsWindow } from "../../lib/editorWindows";
import { invokeCommand, isTauriRuntime } from "../../lib/tauri";
import {
  dispatchEditorMenuCommand,
  inspectEditorMenuCommand,
  useRegisterEditorMenuCommands,
} from "../../menu/editorCommandRegistry";
import {
  EDITOR_MENU_COMMANDS,
  formatEditorMenuCommandLabel,
  type EditorMenuCommandId,
} from "../../menu/menuCommands";
import type {
  AiSettings,
  EditorMenuSelfTestScenario,
  NarrativeAction,
  NarrativeActivityView,
  NarrativeAppSettings,
  NarrativeBottomPanelView,
  NarrativeDocType,
  NarrativeDocumentPayload,
  NarrativeGenerateRequest,
  NarrativeGenerateResponse,
  NarrativeSelectionRange,
  NarrativeSidePanelView,
  NarrativeWorkspaceLayout,
  NarrativeWorkspacePayload,
  SaveNarrativeDocumentResult,
  StructuringBundlePayload,
  ValidationIssue,
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
  status: string;
  runtimeLabel: string;
  onStatusChange: (status: string) => void;
  onReload: () => Promise<void>;
  onOpenWorkspace: (workspaceRoot: string) => Promise<void>;
  onConnectProject: (projectRoot: string | null) => Promise<void>;
  onSaveAppSettings: (settings: NarrativeAppSettings) => Promise<NarrativeAppSettings>;
};

type ReviewMode = "diff" | "draft" | "original";
type NarrativeEditorView = "edit" | "preview" | "diff";
type InspectorTab = NarrativeSidePanelView;

type ProblemEntry = {
  slug: string;
  documentKey: string;
  title: string;
  issue: ValidationIssue;
};

const ACTION_OPTIONS: Array<{ value: NarrativeAction; label: string }> = [
  { value: "create", label: "Create new draft" },
  { value: "revise_document", label: "Revise current document" },
  { value: "rewrite_selection", label: "Rewrite selected passage" },
  { value: "expand_selection", label: "Expand selected passage" },
  { value: "insert_after_selection", label: "Insert after selection" },
  { value: "derive_new_doc", label: "Derive as new document" },
];

const INSPECTOR_TABS: Array<{ value: InspectorTab; label: string }> = [
  { value: "inspector", label: "Inspector" },
  { value: "review", label: "Review" },
  { value: "bundle", label: "Bundle" },
  { value: "session", label: "Session" },
];

const BOTTOM_PANEL_TABS: Array<{ value: NarrativeBottomPanelView; label: string }> = [
  { value: "problems", label: "Problems" },
  { value: "ai_runs", label: "AI Runs" },
  { value: "prompt_debug", label: "Prompt Debug" },
  { value: "bundle_preview", label: "Bundle Preview" },
];

const REVIEW_MODE_OPTIONS: Array<{ value: ReviewMode; label: string }> = [
  { value: "diff", label: "Diff" },
  { value: "draft", label: "Draft" },
  { value: "original", label: "Original" },
];

const EDITOR_VIEW_OPTIONS: Array<{ value: NarrativeEditorView; label: string }> = [
  { value: "edit", label: "Edit" },
  { value: "preview", label: "Preview" },
  { value: "diff", label: "Diff" },
];

const ACTIVITY_ITEMS: WorkbenchActivityItem[] = [
  { id: "explorer", label: "Explorer", glyph: "EX" },
  { id: "search", label: "Search", glyph: "SR" },
  { id: "outline", label: "Outline", glyph: "OL" },
  { id: "ai", label: "AI", glyph: "AI" },
  { id: "session", label: "Session", glyph: "SE" },
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

function defaultWorkbenchLayout(activeDocumentKey?: string | null): NarrativeWorkspaceLayout {
  return {
    version: 2,
    leftSidebarVisible: true,
    leftSidebarWidth: 300,
    leftSidebarView: "explorer",
    rightSidebarVisible: true,
    rightSidebarWidth: 320,
    rightSidebarView: "inspector",
    bottomPanelVisible: true,
    bottomPanelHeight: 220,
    bottomPanelView: "problems",
    openDocumentKeys: activeDocumentKey ? [activeDocumentKey] : [],
    activeDocumentKey: activeDocumentKey ?? null,
    zenMode: false,
  };
}

function resolveWorkbenchLayout(
  layout: NarrativeWorkspaceLayout | undefined,
  documents: EditableNarrativeDocument[],
): NarrativeWorkspaceLayout {
  const fallbackActive = documents[0]?.documentKey ?? null;
  const fallback = defaultWorkbenchLayout(fallbackActive);
  const documentKeys = new Set(documents.map((document) => document.documentKey));

  if (!layout) {
    return fallback;
  }

  const openDocumentKeys = layout.openDocumentKeys.filter((documentKey) => documentKeys.has(documentKey));
  const activeDocumentKey =
    layout.activeDocumentKey && documentKeys.has(layout.activeDocumentKey)
      ? layout.activeDocumentKey
      : openDocumentKeys[0] ?? fallbackActive;

  return {
    version: 2,
    leftSidebarVisible: layout.leftSidebarVisible ?? fallback.leftSidebarVisible,
    leftSidebarWidth: Math.max(220, Math.min(460, layout.leftSidebarWidth ?? fallback.leftSidebarWidth)),
    leftSidebarView: layout.leftSidebarView ?? fallback.leftSidebarView,
    rightSidebarVisible: layout.rightSidebarVisible ?? fallback.rightSidebarVisible,
    rightSidebarWidth: Math.max(260, Math.min(520, layout.rightSidebarWidth ?? fallback.rightSidebarWidth)),
    rightSidebarView: layout.rightSidebarView ?? fallback.rightSidebarView,
    bottomPanelVisible: layout.bottomPanelVisible ?? fallback.bottomPanelVisible,
    bottomPanelHeight: Math.max(180, Math.min(440, layout.bottomPanelHeight ?? fallback.bottomPanelHeight)),
    bottomPanelView: layout.bottomPanelView ?? fallback.bottomPanelView,
    openDocumentKeys: openDocumentKeys.length ? openDocumentKeys : activeDocumentKey ? [activeDocumentKey] : [],
    activeDocumentKey,
    zenMode: layout.zenMode ?? fallback.zenMode,
  };
}

function firstNonEmptyLine(markdown: string) {
  return (
    markdown
      .split(/\r?\n/)
      .map((line) => line.trim())
      .find(Boolean) ?? ""
  );
}

function parseHeadings(markdown: string) {
  return markdown
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith("#"))
    .map((line) => line.replace(/^#+\s*/, ""))
    .filter(Boolean);
}

function notesFromIssues(issues: ValidationIssue[]) {
  return issues.map((issue) => `${issue.severity.toUpperCase()} · ${issue.field}: ${issue.message}`);
}

function copyForAction(action: NarrativeAction) {
  switch (action) {
    case "create":
      return "Draft a new narrative document from scratch.";
    case "revise_document":
      return "Revise the active document while keeping continuity intact.";
    case "rewrite_selection":
      return "Replace only the selected passage.";
    case "expand_selection":
      return "Continue or deepen the selected passage.";
    case "insert_after_selection":
      return "Append new material right after the selection.";
    case "derive_new_doc":
      return "Spin the current document into a separate artifact.";
    default:
      return "Prepare a narrative drafting pass.";
  }
}

function previewForEditorView(
  editorView: NarrativeEditorView,
  selectedDocument: EditableNarrativeDocument | null,
  response: NarrativeGenerateResponse | null,
  reviewMode: ReviewMode,
  selectionText: string,
) {
  if (!selectedDocument) {
    return "";
  }
  if (editorView === "preview") {
    return selectedDocument.markdown;
  }
  if (editorView === "diff") {
    if (!response) {
      return "No AI draft yet. Run a revision to inspect diff output here.";
    }
    if (reviewMode === "original") {
      return selectedDocument.markdown;
    }
    if (reviewMode === "draft") {
      return response.draftMarkdown || "The provider returned an empty draft.";
    }
    return narrativeDiffSummary(selectedDocument.markdown, response, selectionText);
  }
  return selectedDocument.markdown;
}

function matchesDocumentQuery(document: EditableNarrativeDocument, query: string, docType = "") {
  if (docType && document.meta.docType !== docType) {
    return false;
  }
  if (!query.trim()) {
    return true;
  }
  const haystack =
    `${document.meta.slug} ${document.meta.title} ${document.meta.docType} ${document.meta.tags.join(" ")} ${document.relativePath}`.toLowerCase();
  return haystack.includes(query.trim().toLowerCase());
}

export function NarrativeWorkspace({
  workspace,
  appSettings,
  canPersist,
  startupReady,
  selfTestScenario,
  status,
  runtimeLabel,
  onStatusChange,
  onReload,
  onOpenWorkspace: _onOpenWorkspace,
  onConnectProject: _onConnectProject,
  onSaveAppSettings,
}: NarrativeWorkspaceProps) {
  const initialDocuments = useMemo(() => hydrateDocuments(workspace.documents), [workspace.documents]);
  const [documents, setDocuments] = useState<EditableNarrativeDocument[]>(initialDocuments);
  const [selectedKey, setSelectedKey] = useState(workspace.documents[0]?.documentKey ?? "");
  const [openTabs, setOpenTabs] = useState<string[]>(workspace.documents[0] ? [workspace.documents[0].documentKey] : []);
  const [explorerFilter, setExplorerFilter] = useState("");
  const [filterDocType, setFilterDocType] = useState("");
  const [searchActivityQuery, setSearchActivityQuery] = useState("");
  const [topbarQuery, setTopbarQuery] = useState("");
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
  const [inspectorTab, setInspectorTab] = useState<InspectorTab>("inspector");
  const [activeActivity, setActiveActivity] = useState<NarrativeActivityView>("explorer");
  const [activeBottomPanel, setActiveBottomPanel] = useState<NarrativeBottomPanelView>("problems");
  const [workbenchLayout, setWorkbenchLayout] = useState<NarrativeWorkspaceLayout>(
    defaultWorkbenchLayout(workspace.documents[0]?.documentKey ?? null),
  );
  const [quickOpenVisible, setQuickOpenVisible] = useState(false);
  const [commandPaletteVisible, setCommandPaletteVisible] = useState(false);
  const [commandPaletteQuery, setCommandPaletteQuery] = useState("");
  const [recentCommands, setRecentCommands] = useState<EditorMenuCommandId[]>([]);
  const [collapsedGroups, setCollapsedGroups] = useState<Record<string, boolean>>({});
  const [statusBarVisible, setStatusBarVisible] = useState(true);
  const [bulkSelectEnabled, setBulkSelectEnabled] = useState(false);
  const [agentRunsExpanded, setAgentRunsExpanded] = useState(false);
  const editorRef = useRef<HTMLTextAreaElement | null>(null);
  const selfTestStartedRef = useRef(false);
  const lastPersistedLayoutRef = useRef("");
  const deferredExplorerFilter = useDeferredValue(explorerFilter);
  const deferredSearchActivityQuery = useDeferredValue(searchActivityQuery);
  const deferredTopbarQuery = useDeferredValue(topbarQuery);
  const deferredCommandQuery = useDeferredValue(commandPaletteQuery);

  useEffect(() => {
    const nextDocuments = hydrateDocuments(workspace.documents);
    const nextLayout = resolveWorkbenchLayout(
      workspace.workspaceRoot ? appSettings.workspaceLayouts?.[workspace.workspaceRoot] : undefined,
      nextDocuments,
    );
    lastPersistedLayoutRef.current = JSON.stringify(nextLayout);
    setDocuments(nextDocuments);
    setWorkbenchLayout(nextLayout);
    setActiveActivity(nextLayout.leftSidebarView);
    setActiveBottomPanel(nextLayout.bottomPanelView);
    setOpenTabs(nextLayout.openDocumentKeys);
    setSelectedKey(nextLayout.activeDocumentKey ?? "");
    setBundleSelection([]);
    setBundleResult(null);
  }, [appSettings.workspaceLayouts, workspace]);

  useEffect(() => {
    setSelectionRange(null);
    setSelectionText("");
    setReviewMode("diff");
    setEditorView("edit");
    setResponse(null);
    setLastRequest(null);
    setAgentRunsExpanded(false);
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

  useEffect(() => {
    const nextLayout: NarrativeWorkspaceLayout = {
      ...workbenchLayout,
      leftSidebarView: activeActivity,
      rightSidebarView: inspectorTab,
      bottomPanelView: activeBottomPanel,
      openDocumentKeys: openTabs,
      activeDocumentKey: selectedKey || null,
    };
    const serialized = JSON.stringify(nextLayout);
    if (!canPersist || !workspace.workspaceRoot.trim() || serialized === lastPersistedLayoutRef.current) {
      return;
    }

    const timeout = window.setTimeout(() => {
      void onSaveAppSettings({
        ...appSettings,
        workspaceLayouts: {
          ...(appSettings.workspaceLayouts ?? {}),
          [workspace.workspaceRoot]: nextLayout,
        },
      })
        .then(() => {
          lastPersistedLayoutRef.current = serialized;
        })
        .catch((error) => {
          onStatusChange(`Failed to persist workbench layout: ${String(error)}`);
        });
    }, 220);

    return () => {
      window.clearTimeout(timeout);
    };
  }, [
    activeActivity,
    activeBottomPanel,
    appSettings,
    canPersist,
    inspectorTab,
    onSaveAppSettings,
    onStatusChange,
    openTabs,
    selectedKey,
    workbenchLayout,
    workspace.workspaceRoot,
  ]);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const modifier = event.ctrlKey || event.metaKey;

      if (event.key === "Escape") {
        if (commandPaletteVisible) {
          event.preventDefault();
          setCommandPaletteVisible(false);
        }
        if (quickOpenVisible) {
          event.preventDefault();
          setQuickOpenVisible(false);
        }
        return;
      }

      if (!modifier) {
        return;
      }

      if (event.key.toLowerCase() === "p") {
        event.preventDefault();
        void dispatchEditorMenuCommand(
          event.shiftKey
            ? EDITOR_MENU_COMMANDS.WORKBENCH_COMMAND_PALETTE
            : EDITOR_MENU_COMMANDS.WORKBENCH_QUICK_OPEN,
        );
        return;
      }

      if (event.key.toLowerCase() === "w") {
        event.preventDefault();
        void dispatchEditorMenuCommand(EDITOR_MENU_COMMANDS.NAVIGATION_CLOSE_ACTIVE_TAB);
        return;
      }

      if (event.key === "Tab") {
        event.preventDefault();
        void dispatchEditorMenuCommand(
          event.shiftKey
            ? EDITOR_MENU_COMMANDS.NAVIGATION_PREV_TAB
            : EDITOR_MENU_COMMANDS.NAVIGATION_NEXT_TAB,
        );
      }
    };

    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [commandPaletteVisible, quickOpenVisible]);

  const selectedDocument = documents.find((document) => document.documentKey === selectedKey) ?? null;
  const dirtyCount = documents.filter((document) => document.dirty).length;
  const hasSelection = Boolean(selectionText.trim()) && Boolean(selectionRange);
  const hasActiveWorkspace = Boolean(workspace.workspaceRoot.trim());
  const bundleScope = bundleSelection.length ? bundleSelection : selectedDocument ? [selectedDocument.meta.slug] : [];
  const editorPreview = previewForEditorView(
    editorView,
    selectedDocument,
    response,
    reviewMode,
    selectionText,
  );
  const explorerGroups = useMemo(
    () =>
      workspace.docTypes
        .map((entry) => ({
          entry,
          documents: documents.filter((document) =>
            matchesDocumentQuery(document, deferredExplorerFilter, filterDocType || entry.value),
          ),
        }))
        .filter((group) =>
          filterDocType ? group.entry.value === filterDocType : group.documents.length > 0 || !deferredExplorerFilter.trim(),
        ),
    [deferredExplorerFilter, documents, filterDocType, workspace.docTypes],
  );
  const searchResults = useMemo(
    () => documents.filter((document) => matchesDocumentQuery(document, deferredSearchActivityQuery)),
    [deferredSearchActivityQuery, documents],
  );
  const quickOpenResults = useMemo(
    () => documents.filter((document) => matchesDocumentQuery(document, deferredTopbarQuery)).slice(0, 12),
    [deferredTopbarQuery, documents],
  );
  const outlineHeadings = useMemo(
    () => (selectedDocument ? parseHeadings(selectedDocument.markdown) : []),
    [selectedDocument],
  );
  const problemEntries = useMemo<ProblemEntry[]>(
    () =>
      documents.flatMap((document) =>
        document.validation.map((issue) => ({
          slug: document.meta.slug,
          documentKey: document.documentKey,
          title: document.meta.title,
          issue,
        })),
      ),
    [documents],
  );
  const commandPaletteEntries = useMemo(() => {
    const commands = (Object.values(EDITOR_MENU_COMMANDS) as EditorMenuCommandId[])
      .map((commandId) => {
        const inspection = inspectEditorMenuCommand(commandId);
        if (inspection.reason === "missing") {
          return null;
        }
        const label = formatEditorMenuCommandLabel(commandId);
        const haystack = `${label} ${commandId}`.toLowerCase();
        if (deferredCommandQuery.trim() && !haystack.includes(deferredCommandQuery.trim().toLowerCase())) {
          return null;
        }
        return {
          commandId,
          label,
          disabled: inspection.reason === "disabled",
          recentIndex: recentCommands.indexOf(commandId),
        };
      })
      .filter(Boolean) as Array<{
      commandId: EditorMenuCommandId;
      label: string;
      disabled: boolean;
      recentIndex: number;
    }>;

    return commands.sort((left, right) => {
      const leftRecent = left.recentIndex === -1 ? Number.MAX_SAFE_INTEGER : left.recentIndex;
      const rightRecent = right.recentIndex === -1 ? Number.MAX_SAFE_INTEGER : right.recentIndex;
      if (leftRecent !== rightRecent) {
        return leftRecent - rightRecent;
      }
      return left.label.localeCompare(right.label);
    });
  }, [deferredCommandQuery, recentCommands]);

  function rememberCommand(commandId: EditorMenuCommandId) {
    setRecentCommands((current) => [commandId, ...current.filter((entry) => entry !== commandId)].slice(0, 16));
  }

  async function runCommand(commandId: EditorMenuCommandId) {
    rememberCommand(commandId);
    const result = await dispatchEditorMenuCommand(commandId);
    if (!result.ok) {
      onStatusChange(
        result.reason === "disabled"
          ? `${formatEditorMenuCommandLabel(commandId)} is unavailable in the current context.`
          : `${formatEditorMenuCommandLabel(commandId)} is not supported here.`,
      );
      return;
    }
    setCommandPaletteVisible(false);
  }

  async function promptConfigureWorkspace(actionLabel: string) {
    await openOrFocusSettingsWindow("workspace");
    onStatusChange(
      `Cannot ${actionLabel} because no narrative workspace is configured. Opened Settings > Workspace.`,
    );
  }

  function activateDocument(documentKey: string) {
    setOpenTabs((current) => (current.includes(documentKey) ? current : [...current, documentKey]));
    setSelectedKey(documentKey);
    setQuickOpenVisible(false);
    setTopbarQuery("");
  }

  function closeDocumentTab(documentKey: string) {
    const document = documents.find((entry) => entry.documentKey === documentKey);
    if (!document) {
      return;
    }
    if (document.dirty) {
      onStatusChange(`Save or revert ${document.meta.slug} before closing its tab.`);
      return;
    }

    setOpenTabs((current) => {
      const next = current.filter((entry) => entry !== documentKey);
      if (selectedKey === documentKey) {
        setSelectedKey(next[next.length - 1] ?? documents.find((entry) => entry.documentKey !== documentKey)?.documentKey ?? "");
      }
      return next;
    });
  }

  function cycleTabs(direction: 1 | -1) {
    if (!openTabs.length) {
      return;
    }
    const currentIndex = openTabs.indexOf(selectedKey);
    const nextIndex = currentIndex === -1 ? 0 : (currentIndex + direction + openTabs.length) % openTabs.length;
    setSelectedKey(openTabs[nextIndex]);
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

  function updateLayout(transform: (layout: NarrativeWorkspaceLayout) => NarrativeWorkspaceLayout) {
    setWorkbenchLayout((current) => transform(current));
  }

  function toggleBundleDocument(slug: string, enabled: boolean) {
    setBundleSelection((current) =>
      enabled ? [...new Set([...current, slug])] : current.filter((entry) => entry !== slug),
    );
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
      activateDocument(draft.documentKey);
      setTargetDocType(docType);
      setActiveActivity("explorer");
      updateLayout((current) => ({
        ...current,
        leftSidebarVisible: true,
        leftSidebarView: "explorer",
        zenMode: false,
      }));
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
      setOpenTabs((current) => current.filter((entry) => entry !== selectedDocument.documentKey));
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
      setEditorView("diff");
      setInspectorTab("review");
      setActiveBottomPanel("ai_runs");
      updateLayout((current) => ({
        ...current,
        zenMode: false,
        rightSidebarVisible: true,
        rightSidebarView: "review",
        bottomPanelVisible: true,
        bottomPanelView: "ai_runs",
      }));
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

    const documentSlugs = bundleScope;
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
      setInspectorTab("bundle");
      setActiveBottomPanel("bundle_preview");
      updateLayout((current) => ({
        ...current,
        rightSidebarVisible: true,
        rightSidebarView: "bundle",
        bottomPanelVisible: true,
        bottomPanelView: "bundle_preview",
      }));
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
      activateDocument(nextDraft.documentKey);
      setResponse(null);
      setLastRequest(null);
      updateLayout((current) => ({ ...current, zenMode: false }));
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
    setEditorView("edit");
    setInspectorTab("inspector");
    onStatusChange("Applied AI draft to the current editor.");
  }

  const menuCommands = useMemo(
    () => ({
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT);
          await createDraft(targetDocType);
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.FILE_SAVE_ALL]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.FILE_SAVE_ALL);
          await saveAll();
        },
        isEnabled: () => !busy && dirtyCount > 0,
      },
      [EDITOR_MENU_COMMANDS.FILE_RELOAD]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.FILE_RELOAD);
          await onReload();
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.FILE_DELETE_CURRENT]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.FILE_DELETE_CURRENT);
          await deleteCurrent();
        },
        isEnabled: () => !busy && Boolean(selectedDocument),
      },
      [EDITOR_MENU_COMMANDS.WORKBENCH_COMMAND_PALETTE]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.WORKBENCH_COMMAND_PALETTE);
          setQuickOpenVisible(false);
          setCommandPaletteVisible(true);
        },
      },
      [EDITOR_MENU_COMMANDS.WORKBENCH_QUICK_OPEN]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.WORKBENCH_QUICK_OPEN);
          setCommandPaletteVisible(false);
          setQuickOpenVisible(true);
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_SIDEBAR]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_TOGGLE_SIDEBAR);
          updateLayout((current) => ({
            ...current,
            leftSidebarVisible: !current.leftSidebarVisible,
            zenMode: false,
          }));
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_LEFT_SIDEBAR]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_TOGGLE_LEFT_SIDEBAR);
          updateLayout((current) => ({
            ...current,
            leftSidebarVisible: !current.leftSidebarVisible,
            zenMode: false,
          }));
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_RIGHT_SIDEBAR]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_TOGGLE_RIGHT_SIDEBAR);
          updateLayout((current) => ({
            ...current,
            rightSidebarVisible: !current.rightSidebarVisible,
            zenMode: false,
          }));
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_BOTTOM_PANEL]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_TOGGLE_BOTTOM_PANEL);
          updateLayout((current) => ({
            ...current,
            bottomPanelVisible: !current.bottomPanelVisible,
            zenMode: false,
          }));
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_STATUS_BAR]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_TOGGLE_STATUS_BAR);
          setStatusBarVisible((current) => !current);
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_RESET_LAYOUT]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_RESET_LAYOUT);
          const nextLayout = defaultWorkbenchLayout((selectedKey || documents[0]?.documentKey) ?? null);
          nextLayout.openDocumentKeys = openTabs.length ? openTabs : nextLayout.openDocumentKeys;
          nextLayout.activeDocumentKey = selectedKey || nextLayout.activeDocumentKey;
          setWorkbenchLayout(nextLayout);
          setActiveActivity(nextLayout.leftSidebarView);
          setActiveBottomPanel(nextLayout.bottomPanelView);
          setInspectorTab(nextLayout.rightSidebarView);
          onStatusChange("Reset the Narrative Lab workspace layout.");
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_RESTORE_DEFAULT_LAYOUT]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_RESTORE_DEFAULT_LAYOUT);
          const nextLayout = defaultWorkbenchLayout((selectedKey || documents[0]?.documentKey) ?? null);
          nextLayout.openDocumentKeys = openTabs;
          nextLayout.activeDocumentKey = selectedKey || null;
          setWorkbenchLayout(nextLayout);
          setActiveActivity(nextLayout.leftSidebarView);
          setActiveBottomPanel(nextLayout.bottomPanelView);
          setInspectorTab(nextLayout.rightSidebarView);
          onStatusChange("Restored the default Narrative Lab workbench.");
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_COLLAPSE_ADVANCED_PANELS]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_COLLAPSE_ADVANCED_PANELS);
          updateLayout((current) => ({
            ...current,
            rightSidebarVisible: false,
            bottomPanelVisible: false,
            leftSidebarVisible: true,
            leftSidebarView: "explorer",
            zenMode: false,
          }));
          setActiveActivity("explorer");
          onStatusChange("Collapsed advanced panels.");
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_EXPAND_ALL_PANELS]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_EXPAND_ALL_PANELS);
          updateLayout((current) => ({
            ...current,
            leftSidebarVisible: true,
            rightSidebarVisible: true,
            bottomPanelVisible: true,
            zenMode: false,
          }));
          onStatusChange("Expanded all workbench panels.");
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_INSPECTOR]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_TOGGLE_INSPECTOR);
          updateLayout((current) => ({
            ...current,
            rightSidebarVisible: !current.rightSidebarVisible,
            zenMode: false,
          }));
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_FOCUS_EXPLORER]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_FOCUS_EXPLORER);
          setActiveActivity("explorer");
          updateLayout((current) => ({
            ...current,
            leftSidebarVisible: true,
            leftSidebarView: "explorer",
            zenMode: false,
          }));
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_FOCUS_EDITOR]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_FOCUS_EDITOR);
          editorRef.current?.focus();
          onStatusChange("Focused the editor.");
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_FOCUS_PROBLEMS]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_FOCUS_PROBLEMS);
          setActiveBottomPanel("problems");
          updateLayout((current) => ({
            ...current,
            bottomPanelVisible: true,
            bottomPanelView: "problems",
            zenMode: false,
          }));
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_ZEN_MODE]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.VIEW_ZEN_MODE);
          updateLayout((current) => ({ ...current, zenMode: !current.zenMode }));
          onStatusChange(workbenchLayout.zenMode ? "Exited zen mode." : "Entered zen mode.");
        },
      },
      [EDITOR_MENU_COMMANDS.AI_GENERATE]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.AI_GENERATE);
          await runGeneration();
        },
        isEnabled: () => !busy && hasActiveWorkspace,
      },
      [EDITOR_MENU_COMMANDS.AI_TEST_PROVIDER_CONNECTION]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.AI_TEST_PROVIDER_CONNECTION);
          await openOrFocusSettingsWindow("ai");
          onStatusChange("Opened AI settings to test the provider connection.");
        },
      },
      [EDITOR_MENU_COMMANDS.AI_OPEN_PROVIDER_SETTINGS]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.AI_OPEN_PROVIDER_SETTINGS);
          await openOrFocusSettingsWindow("ai");
          onStatusChange("Opened AI provider settings.");
        },
      },
      [EDITOR_MENU_COMMANDS.NAVIGATION_NEXT_TAB]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.NAVIGATION_NEXT_TAB);
          cycleTabs(1);
        },
        isEnabled: () => openTabs.length > 1,
      },
      [EDITOR_MENU_COMMANDS.NAVIGATION_PREV_TAB]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.NAVIGATION_PREV_TAB);
          cycleTabs(-1);
        },
        isEnabled: () => openTabs.length > 1,
      },
      [EDITOR_MENU_COMMANDS.NAVIGATION_CLOSE_ACTIVE_TAB]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.NAVIGATION_CLOSE_ACTIVE_TAB);
          if (selectedKey) {
            closeDocumentTab(selectedKey);
          }
        },
        isEnabled: () => Boolean(selectedKey),
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_PROJECT_BRIEF]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.NARRATIVE_NEW_PROJECT_BRIEF);
          await createDraft("project_brief");
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHARACTER_CARD]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHARACTER_CARD);
          await createDraft("character_card");
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHAPTER_OUTLINE]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHAPTER_OUTLINE);
          await createDraft("chapter_outline");
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_BRANCH_SHEET]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.NARRATIVE_NEW_BRANCH_SHEET);
          await createDraft("branch_sheet");
        },
        isEnabled: () => !busy,
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_SCENE_DRAFT]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.NARRATIVE_NEW_SCENE_DRAFT);
          await createDraft("scene_draft");
        },
        isEnabled: () => !busy,
      },
    }),
    [
      busy,
      dirtyCount,
      documents,
      hasActiveWorkspace,
      onReload,
      onStatusChange,
      openTabs,
      selectedDocument,
      selectedKey,
      targetDocType,
      workbenchLayout.zenMode,
    ],
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
      windowLabel: "main",
    }).then((result) => {
      onStatusChange(result.summary);
    });
  }, [hasActiveWorkspace, onStatusChange, selfTestScenario, startupReady]);

  if (!startupReady) {
    return (
      <div className="workspace">
        <div className="panel empty-state">
          <Badge tone="muted">Loading</Badge>
          <p>Preparing narrative workspace and settings...</p>
        </div>
      </div>
    );
  }

  const activityItems = ACTIVITY_ITEMS.map((item) =>
    item.id === "explorer"
      ? { ...item, badge: documents.length }
      : item.id === "search"
        ? { ...item, badge: searchResults.length }
        : item.id === "outline"
          ? { ...item, badge: outlineHeadings.length }
          : item.id === "ai"
            ? { ...item, badge: response ? "!" : null }
            : item.id === "session"
              ? { ...item, badge: hasActiveWorkspace ? null : "!" }
              : item,
  );

  const statusItems: WorkbenchStatusItem[] = [
    {
      id: "workspace",
      label: hasActiveWorkspace ? "workspace ready" : "workspace missing",
      tone: hasActiveWorkspace ? "success" : "warning",
    },
    { id: "doc", label: selectedDocument ? selectedDocument.meta.slug : "no document", tone: "muted" as const },
    { id: "dirty", label: `${dirtyCount} dirty`, tone: dirtyCount > 0 ? "warning" : "muted" as const },
    {
      id: "selection",
      label: hasSelection ? `${selectionText.length} chars selected` : "no selection",
      tone: hasSelection ? "accent" : "muted",
    },
    { id: "ai", label: aiSettings.model || "AI not configured", tone: "muted" as const },
    { id: "mode", label: workbenchLayout.zenMode ? "zen mode" : "workbench", tone: "muted" as const },
  ];

  const leftSidebar = (
    <div className="narrative-workbench-panel">
      {activeActivity === "explorer" ? (
        <>
          <div className="narrative-workbench-panel-header">
            <div>
              <span className="section-label">Explorer</span>
              <h3 className="panel-title">Narrative documents</h3>
            </div>
            <Badge tone="muted">{documents.length}</Badge>
          </div>

          <div className="narrative-sidebar-controls">
            <input
              className="field-input"
              type="text"
              value={explorerFilter}
              onChange={(event) => setExplorerFilter(event.target.value)}
              placeholder="Filter titles, tags, and paths"
            />
            <select
              className="field-input"
              value={filterDocType}
              onChange={(event) => setFilterDocType(event.target.value)}
            >
              <option value="">All doc types</option>
              {workspace.docTypes.map((entry) => (
                <option key={entry.value} value={entry.value}>
                  {entry.label}
                </option>
              ))}
            </select>
            <button
              type="button"
              className="toolbar-button toolbar-accent"
              onClick={() => void createDraft(targetDocType)}
              disabled={busy || !hasActiveWorkspace}
            >
              New {docTypeLabel(targetDocType)}
            </button>
          </div>

          <div className="narrative-explorer-tree">
            {explorerGroups.map((group) => {
              const issueCount = group.documents.reduce((count, document) => count + document.validation.length, 0);
              const dirtyGroupCount = group.documents.filter((document) => document.dirty).length;
              const collapsed = collapsedGroups[group.entry.value] ?? false;
              return (
                <section key={group.entry.value} className="narrative-explorer-group">
                  <button
                    type="button"
                    className="narrative-explorer-group-toggle"
                    onClick={() =>
                      setCollapsedGroups((current) => ({
                        ...current,
                        [group.entry.value]: !collapsed,
                      }))
                    }
                  >
                    <div className="narrative-explorer-group-copy">
                      <strong>{group.entry.label}</strong>
                      <span>{group.documents.length} docs</span>
                    </div>
                    <div className="toolbar-summary">
                      {dirtyGroupCount > 0 ? <Badge tone="warning">{dirtyGroupCount} dirty</Badge> : null}
                      {issueCount > 0 ? <Badge tone="warning">{issueCount} issues</Badge> : null}
                    </div>
                  </button>

                  {!collapsed ? (
                    <div className="narrative-explorer-group-list">
                      {group.documents.map((document) => (
                        <button
                          key={document.documentKey}
                          type="button"
                          className={`narrative-document-row ${
                            document.documentKey === selectedKey ? "narrative-document-row-active" : ""
                          }`.trim()}
                          onClick={() => activateDocument(document.documentKey)}
                        >
                          <div className="narrative-document-main">
                            <div className="narrative-document-head">
                              <strong>{document.meta.title || document.meta.slug}</strong>
                              <div className="toolbar-summary">
                                {document.dirty ? <Badge tone="warning">Dirty</Badge> : null}
                                {document.validation.length ? (
                                  <Badge tone="warning">{document.validation.length}</Badge>
                                ) : null}
                              </div>
                            </div>
                            <p>{document.relativePath}</p>
                            <span>{firstNonEmptyLine(document.markdown) || "No body content yet."}</span>
                          </div>
                          <div className="narrative-document-side">
                            <Badge tone="muted">{document.meta.status || "draft"}</Badge>
                            {bulkSelectEnabled ? (
                              <label className="narrative-pick">
                                <input
                                  type="checkbox"
                                  checked={bundleSelection.includes(document.meta.slug)}
                                  onChange={(event) => {
                                    event.stopPropagation();
                                    toggleBundleDocument(document.meta.slug, event.target.checked);
                                  }}
                                  onClick={(event) => event.stopPropagation()}
                                />
                                Bundle
                              </label>
                            ) : null}
                          </div>
                        </button>
                      ))}
                    </div>
                  ) : null}
                </section>
              );
            })}
          </div>
        </>
      ) : null}

      {activeActivity === "search" ? (
        <>
          <div className="narrative-workbench-panel-header">
            <div>
              <span className="section-label">Search</span>
              <h3 className="panel-title">Workspace search</h3>
            </div>
            <Badge tone="muted">{searchResults.length}</Badge>
          </div>
          <input
            className="field-input"
            type="text"
            value={searchActivityQuery}
            onChange={(event) => setSearchActivityQuery(event.target.value)}
            placeholder="Search titles, tags, slugs, and paths"
          />
          <div className="narrative-list narrative-scroll">
            {searchResults.map((document) => (
              <button
                key={document.documentKey}
                type="button"
                className={`narrative-search-result ${
                  document.documentKey === selectedKey ? "narrative-search-result-active" : ""
                }`.trim()}
                onClick={() => activateDocument(document.documentKey)}
              >
                <strong>{document.meta.title || document.meta.slug}</strong>
                <span>{document.relativePath}</span>
              </button>
            ))}
            {!searchResults.length ? (
              <div className="workspace-empty settings-empty-inline">
                <p>No matching documents yet.</p>
              </div>
            ) : null}
          </div>
        </>
      ) : null}

      {activeActivity === "outline" ? (
        <>
          <div className="narrative-workbench-panel-header">
            <div>
              <span className="section-label">Outline</span>
              <h3 className="panel-title">Current document headings</h3>
            </div>
            <Badge tone="muted">{outlineHeadings.length}</Badge>
          </div>
          <div className="narrative-list narrative-scroll">
            {outlineHeadings.map((heading, index) => (
              <div key={`${heading}-${index}`} className="summary-row summary-row-compact">
                <div className="summary-row-main">
                  <strong>Section {index + 1}</strong>
                  <p>{heading}</p>
                </div>
              </div>
            ))}
            {!outlineHeadings.length ? (
              <div className="workspace-empty settings-empty-inline">
                <p>Select a document with markdown headings to see its outline.</p>
              </div>
            ) : null}
          </div>
        </>
      ) : null}

      {activeActivity === "ai" ? (
        <>
          <div className="narrative-workbench-panel-header">
            <div>
              <span className="section-label">AI Task</span>
              <h3 className="panel-title">Compose and revise</h3>
            </div>
            <Badge tone="accent">{aiSettings.model || "No model"}</Badge>
          </div>

          <div className="summary-row summary-row-compact">
            <div className="summary-row-main">
              <strong>Current action</strong>
              <p>{copyForAction(aiAction)}</p>
            </div>
          </div>

          <div className="narrative-sidebar-stack narrative-scroll">
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
              placeholder="Describe the beat, intent, revision goal, or export target."
            />
            <TextareaField
              label="Editor instruction"
              value={editorInstruction}
              onChange={setEditorInstruction}
              placeholder="Continuity, pacing, POV, constraints, or structure."
            />
            <div className="toolbar-actions">
              <button
                type="button"
                className="toolbar-button toolbar-accent"
                onClick={() => void runGeneration()}
                disabled={busy || !hasActiveWorkspace}
              >
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
              <button
                type="button"
                className="toolbar-button"
                onClick={() => void openOrFocusSettingsWindow("ai")}
              >
                Provider settings
              </button>
            </div>
          </div>
        </>
      ) : null}

      {activeActivity === "session" ? (
        <>
          <div className="narrative-workbench-panel-header">
            <div>
              <span className="section-label">Session</span>
              <h3 className="panel-title">Workspace context</h3>
            </div>
            <Badge tone={hasActiveWorkspace ? "success" : "warning"}>
              {hasActiveWorkspace ? "ready" : "setup"}
            </Badge>
          </div>

          <div className="narrative-sidebar-stack narrative-scroll">
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
                <strong>Project context</strong>
                <p>{workspace.projectContextStatus || "No context snapshot loaded."}</p>
              </div>
            </div>
            <div className="toolbar-actions">
              <button type="button" className="toolbar-button" onClick={() => void openOrFocusSettingsWindow("workspace")}>
                Workspace settings
              </button>
              <button type="button" className="toolbar-button" onClick={() => void openOrFocusSettingsWindow("ai")}>
                AI settings
              </button>
              <button type="button" className="toolbar-button" onClick={() => void onReload()} disabled={busy}>
                Reload workspace
              </button>
            </div>
          </div>
        </>
      ) : null}
    </div>
  );

  const rightSidebar = (
    <div className="narrative-workbench-panel">
      <div className="narrative-workbench-panel-header">
        <div>
          <span className="section-label">Context</span>
          <h3 className="panel-title">Inspector and review</h3>
        </div>
        <Badge tone="muted">{inspectorTab}</Badge>
      </div>

      <div className="segmented-control narrative-tab-strip" aria-label="Inspector tabs">
        {INSPECTOR_TABS.map((tab) => (
          <button
            key={tab.value}
            type="button"
            className={`segmented-control-item ${
              inspectorTab === tab.value ? "segmented-control-item-active" : ""
            }`.trim()}
            onClick={() => {
              setInspectorTab(tab.value);
              updateLayout((current) => ({
                ...current,
                rightSidebarView: tab.value,
                rightSidebarVisible: true,
                zenMode: false,
              }));
            }}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <div className="narrative-sidebar-stack narrative-scroll">
        {inspectorTab === "inspector" ? (
          selectedDocument ? (
            <>
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
              <div className="summary-row summary-row-compact">
                <div className="summary-row-main">
                  <strong>File</strong>
                  <p>{selectedDocument.relativePath}</p>
                </div>
              </div>
              <div className="summary-row summary-row-compact">
                <div className="summary-row-main">
                  <strong>Validation</strong>
                  <p>
                    {selectedDocument.validation.length
                      ? `${selectedDocument.validation.length} issues to resolve`
                      : "No validation issues."}
                  </p>
                </div>
              </div>
            </>
          ) : (
            <div className="workspace-empty settings-empty-inline">
              <p>Select a document to inspect metadata.</p>
            </div>
          )
        ) : null}

        {inspectorTab === "review" ? (
          response ? (
            <>
              <div className="narrative-review-topbar">
                <div className="segmented-control" aria-label="Review mode">
                  {REVIEW_MODE_OPTIONS.map((option) => (
                    <button
                      key={option.value}
                      type="button"
                      className={`segmented-control-item ${
                        reviewMode === option.value ? "segmented-control-item-active" : ""
                      }`.trim()}
                      onClick={() => {
                        setReviewMode(option.value);
                        setEditorView("diff");
                      }}
                    >
                      {option.label}
                    </button>
                  ))}
                </div>
                <button
                  type="button"
                  className="toolbar-button"
                  onClick={() => setAgentRunsExpanded((current) => !current)}
                >
                  {agentRunsExpanded ? "Hide agent passes" : "Show agent passes"}
                </button>
              </div>
              <div className="summary-row summary-row-compact">
                <div className="summary-row-main">
                  <strong>Summary</strong>
                  <p>{response.summary || response.providerError || "No AI result yet."}</p>
                </div>
              </div>
              {[...response.reviewNotes, ...response.synthesisNotes, ...notesFromIssues(selectedDocument?.validation ?? [])].map(
                (note, index) => (
                  <div key={`${note}-${index}`} className="summary-row summary-row-compact">
                    <div className="summary-row-main">
                      <strong>Note {index + 1}</strong>
                      <p>{note}</p>
                    </div>
                  </div>
                ),
              )}
              <pre className="narrative-code-block narrative-review-block">
                {previewForEditorView("diff", selectedDocument, response, reviewMode, selectionText)}
              </pre>
            </>
          ) : (
            <div className="workspace-empty settings-empty-inline">
              <p>Run AI to inspect a draft and review summary here.</p>
            </div>
          )
        ) : null}

        {inspectorTab === "bundle" ? (
          <>
            <div className="summary-row summary-row-compact">
              <div className="summary-row-main">
                <strong>Selection scope</strong>
                <p>
                  {bundleScope.length
                    ? `${bundleScope.length} document${bundleScope.length === 1 ? "" : "s"} ready for export`
                    : "No documents selected yet."}
                </p>
              </div>
            </div>
            <div className="toolbar-actions">
              <button
                type="button"
                className="toolbar-button toolbar-accent"
                onClick={() => void prepareBundle()}
                disabled={bundleScope.length === 0}
              >
                Prepare bundle
              </button>
              <button
                type="button"
                className="toolbar-button"
                onClick={() => {
                  setBulkSelectEnabled((current) => {
                    if (current) {
                      setBundleSelection([]);
                    }
                    return !current;
                  });
                }}
              >
                {bulkSelectEnabled ? "Finish selection" : "Select multiple docs"}
              </button>
            </div>
            {bundleScope.length ? (
              <div className="narrative-token-cloud">
                {bundleScope.map((slug) => (
                  <Badge key={slug} tone="muted">
                    {slug}
                  </Badge>
                ))}
              </div>
            ) : null}
            {bundleResult ? (
              <>
                <div className="summary-row summary-row-compact">
                  <div className="summary-row-main">
                    <strong>Bundle summary</strong>
                    <p>{bundleResult.summary}</p>
                  </div>
                </div>
                {bundleResult.exportPath ? (
                  <div className="summary-row summary-row-compact">
                    <div className="summary-row-main">
                      <strong>Export path</strong>
                      <p>{bundleResult.exportPath}</p>
                    </div>
                  </div>
                ) : null}
              </>
            ) : (
              <div className="workspace-empty settings-empty-inline">
                <p>Prepare a bundle to review export targets and combined markdown output.</p>
              </div>
            )}
          </>
        ) : null}

        {inspectorTab === "session" ? (
          <>
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
            <div className="summary-row summary-row-compact">
              <div className="summary-row-main">
                <strong>Project context</strong>
                <p>{workspace.projectContextStatus || "No context snapshot loaded."}</p>
              </div>
            </div>
          </>
        ) : null}
      </div>
    </div>
  );

  const bottomPanel = (
    <div className="narrative-workbench-panel">
      <div className="narrative-workbench-panel-header">
        <div>
          <span className="section-label">Output</span>
          <h3 className="panel-title">Problems and results</h3>
        </div>
      </div>

      <div className="segmented-control narrative-tab-strip" aria-label="Bottom panel tabs">
        {BOTTOM_PANEL_TABS.map((tab) => (
          <button
            key={tab.value}
            type="button"
            className={`segmented-control-item ${
              activeBottomPanel === tab.value ? "segmented-control-item-active" : ""
            }`.trim()}
            onClick={() => {
              setActiveBottomPanel(tab.value);
              updateLayout((current) => ({
                ...current,
                bottomPanelView: tab.value,
                bottomPanelVisible: true,
                zenMode: false,
              }));
            }}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <div className="narrative-bottom-panel-body narrative-scroll">
        {activeBottomPanel === "problems" ? (
          problemEntries.length ? (
            <div className="issue-list">
              {problemEntries.map((entry) => (
                <button
                  key={`${entry.documentKey}-${entry.issue.field}-${entry.issue.message}`}
                  type="button"
                  className={`issue issue-${entry.issue.severity}`.trim()}
                  onClick={() => {
                    activateDocument(entry.documentKey);
                    setInspectorTab("inspector");
                    updateLayout((current) => ({
                      ...current,
                      rightSidebarVisible: true,
                      rightSidebarView: "inspector",
                    }));
                  }}
                >
                  <div className="issue-head">
                    <strong>{entry.title || entry.slug}</strong>
                    <Badge tone={entry.issue.severity === "error" ? "danger" : "warning"}>
                      {entry.issue.field}
                    </Badge>
                  </div>
                  <p>{entry.issue.message}</p>
                </button>
              ))}
            </div>
          ) : (
            <div className="workspace-empty settings-empty-inline">
              <p>No validation issues across the open workspace.</p>
            </div>
          )
        ) : null}

        {activeBottomPanel === "ai_runs" ? (
          response?.agentRuns.length ? (
            <div className="agent-run-list">
              {response.agentRuns.map((agent) => (
                <article key={agent.agentId} className="agent-run-card">
                  <div className="agent-run-header">
                    <strong>{agent.label}</strong>
                    <Badge tone={agent.status === "failed" ? "danger" : "success"}>{agent.status}</Badge>
                  </div>
                  <p className="agent-run-focus">{agent.focus}</p>
                  <p className="agent-run-focus">{agent.summary}</p>
                </article>
              ))}
            </div>
          ) : (
            <div className="workspace-empty settings-empty-inline">
              <p>Run AI to inspect agent passes and synthesis output.</p>
            </div>
          )
        ) : null}

        {activeBottomPanel === "prompt_debug" ? (
          response ? (
            <pre className="narrative-code-block narrative-debug-block">
              {JSON.stringify(
                {
                  request: lastRequest,
                  promptDebug: response.promptDebug,
                },
                null,
                2,
              )}
            </pre>
          ) : (
            <div className="workspace-empty settings-empty-inline">
              <p>Run AI to populate prompt debug output.</p>
            </div>
          )
        ) : null}

        {activeBottomPanel === "bundle_preview" ? (
          bundleResult ? (
            <pre className="narrative-code-block narrative-bundle-block">{bundleResult.combinedMarkdown}</pre>
          ) : (
            <div className="workspace-empty settings-empty-inline">
              <p>Prepare a bundle to preview the combined markdown export.</p>
            </div>
          )
        ) : null}
      </div>
    </div>
  );

  const editorArea = (
    <div className="narrative-editor-workbench">
      <div className="narrative-tabbar">
        {openTabs.map((documentKey) => {
          const document = documents.find((entry) => entry.documentKey === documentKey);
          if (!document) {
            return null;
          }
          return (
            <button
              key={documentKey}
              type="button"
              className={`narrative-tab ${documentKey === selectedKey ? "narrative-tab-active" : ""}`.trim()}
              onClick={() => setSelectedKey(documentKey)}
            >
              <span>{document.meta.title || document.meta.slug}</span>
              {document.dirty ? <span className="narrative-tab-dirty" /> : null}
              <span
                className="narrative-tab-close"
                onClick={(event) => {
                  event.stopPropagation();
                  closeDocumentTab(documentKey);
                }}
              >
                x
              </span>
            </button>
          );
        })}
      </div>

      {selectedDocument ? (
        <section className="panel narrative-editor-surface narrative-editor-workbench-surface">
          <div className="narrative-editor-header">
            <div className="narrative-editor-heading">
              <span className="section-label">Editor</span>
              <input
                className="field-input narrative-title-input"
                type="text"
                value={selectedDocument.meta.title}
                onChange={(event) =>
                  updateSelectedDocument((document) => ({
                    ...document,
                    meta: { ...document.meta, title: event.target.value },
                  }))
                }
                placeholder="Document title"
              />
              <div className="toolbar-summary">
                <Badge tone="accent">{docTypeLabel(selectedDocument.meta.docType)}</Badge>
                <Badge tone={selectedDocument.dirty ? "warning" : "success"}>
                  {selectedDocument.dirty ? "Unsaved" : "Saved"}
                </Badge>
                <Badge tone={selectedDocument.validation.length ? "warning" : "muted"}>
                  {selectedDocument.validation.length} issues
                </Badge>
                <Badge tone={hasSelection ? "accent" : "muted"}>
                  {hasSelection ? "selection active" : "no selection"}
                </Badge>
              </div>
            </div>

            <div className="narrative-editor-sidebar">
              <div className="narrative-editor-field">
                <span className="field-label">Status</span>
                <input
                  className="field-input"
                  type="text"
                  value={selectedDocument.meta.status}
                  onChange={(event) =>
                    updateSelectedDocument((document) => ({
                      ...document,
                      meta: { ...document.meta, status: event.target.value },
                    }))
                  }
                  placeholder="draft / review / approved"
                />
              </div>

              <div className="segmented-control" aria-label="Editor view">
                {EDITOR_VIEW_OPTIONS.map((option) => (
                  <button
                    key={option.value}
                    type="button"
                    className={`segmented-control-item ${
                      editorView === option.value ? "segmented-control-item-active" : ""
                    }`.trim()}
                    onClick={() => setEditorView(option.value)}
                    disabled={option.value === "diff" && !response}
                  >
                    {option.label}
                  </button>
                ))}
              </div>
            </div>
          </div>

          <div className="narrative-editor-canvas">
            {editorView === "edit" ? (
              <textarea
                ref={editorRef}
                className="field-input field-textarea field-code narrative-editor-textarea"
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
            ) : (
              <pre className="narrative-code-block narrative-preview-block">{editorPreview}</pre>
            )}
          </div>
        </section>
      ) : (
        <div className="panel workspace-empty narrative-empty-panel">
          <Badge tone="muted">Narrative</Badge>
          <h3 className="panel-title">No document selected</h3>
          <p>Select a document from Explorer or create a new one.</p>
          <div className="toolbar-actions">
            <button
              type="button"
              className="toolbar-button toolbar-accent"
              onClick={() => void createDraft(targetDocType)}
              disabled={busy || !hasActiveWorkspace}
            >
              Create {docTypeLabel(targetDocType)}
            </button>
            <button
              type="button"
              className="toolbar-button"
              onClick={() => void openOrFocusSettingsWindow("workspace")}
            >
              Workspace settings
            </button>
          </div>
        </div>
      )}
    </div>
  );

  const overlays = (
    <>
      {quickOpenVisible ? (
        <div className="narrative-overlay">
          <div className="narrative-overlay-backdrop" onClick={() => setQuickOpenVisible(false)} />
          <div className="narrative-overlay-panel">
            <div className="narrative-workbench-panel-header">
              <div>
                <span className="section-label">Quick Open</span>
                <h3 className="panel-title">Jump to a document</h3>
              </div>
              <Badge tone="muted">{quickOpenResults.length}</Badge>
            </div>
            <input
              className="field-input"
              type="text"
              value={topbarQuery}
              onChange={(event) => setTopbarQuery(event.target.value)}
              placeholder="Type a title, slug, or path"
              autoFocus
            />
            <div className="narrative-list narrative-scroll">
              {quickOpenResults.map((document) => (
                <button
                  key={document.documentKey}
                  type="button"
                  className="narrative-search-result"
                  onClick={() => activateDocument(document.documentKey)}
                >
                  <strong>{document.meta.title || document.meta.slug}</strong>
                  <span>{document.relativePath}</span>
                </button>
              ))}
              {!quickOpenResults.length ? (
                <div className="workspace-empty settings-empty-inline">
                  <p>No matching documents.</p>
                </div>
              ) : null}
            </div>
          </div>
        </div>
      ) : null}

      {commandPaletteVisible ? (
        <div className="narrative-overlay">
          <div className="narrative-overlay-backdrop" onClick={() => setCommandPaletteVisible(false)} />
          <div className="narrative-overlay-panel">
            <div className="narrative-workbench-panel-header">
              <div>
                <span className="section-label">Command Palette</span>
                <h3 className="panel-title">Run a workbench command</h3>
              </div>
              <Badge tone="muted">{commandPaletteEntries.length}</Badge>
            </div>
            <input
              className="field-input"
              type="text"
              value={commandPaletteQuery}
              onChange={(event) => setCommandPaletteQuery(event.target.value)}
              placeholder="Search commands"
              autoFocus
            />
            <div className="narrative-list narrative-scroll">
              {commandPaletteEntries.map((entry) => (
                <button
                  key={entry.commandId}
                  type="button"
                  className={`narrative-command-entry ${entry.disabled ? "narrative-command-entry-disabled" : ""}`.trim()}
                  onClick={() => {
                    if (!entry.disabled) {
                      void runCommand(entry.commandId);
                    }
                  }}
                  disabled={entry.disabled}
                >
                  <div className="narrative-command-entry-copy">
                    <strong>{entry.label}</strong>
                    <span>{entry.commandId}</span>
                  </div>
                  {entry.recentIndex !== -1 ? <Badge tone="accent">recent</Badge> : null}
                </button>
              ))}
            </div>
          </div>
        </div>
      ) : null}
    </>
  );

  return (
    <IDEWorkbenchShell
      title="Narrative Lab"
      workspaceLabel={workspace.workspaceRoot || "No workspace selected"}
      runtimeLabel={runtimeLabel}
      topbarSearchValue={topbarQuery}
      topbarSearchPlaceholder="Quick open by title, slug, or path"
      onTopbarSearchChange={(value) => {
        setTopbarQuery(value);
        setQuickOpenVisible(true);
      }}
      onOpenQuickOpen={() => setQuickOpenVisible(true)}
      onOpenCommandPalette={() => setCommandPaletteVisible(true)}
      activities={activityItems}
      activeActivityId={activeActivity}
      onActivityChange={(activityId) => {
        setActiveActivity(activityId as NarrativeActivityView);
        updateLayout((current) => ({
          ...current,
          leftSidebarVisible: true,
          leftSidebarView: activityId as NarrativeActivityView,
          zenMode: false,
        }));
      }}
      leftSidebarVisible={workbenchLayout.leftSidebarVisible}
      leftSidebarWidth={workbenchLayout.leftSidebarWidth}
      onLeftSidebarWidthChange={(width) => updateLayout((current) => ({ ...current, leftSidebarWidth: width }))}
      onToggleLeftSidebar={() =>
        updateLayout((current) => ({
          ...current,
          leftSidebarVisible: !current.leftSidebarVisible,
          zenMode: false,
        }))
      }
      rightSidebarVisible={workbenchLayout.rightSidebarVisible}
      rightSidebarWidth={workbenchLayout.rightSidebarWidth}
      onRightSidebarWidthChange={(width) => updateLayout((current) => ({ ...current, rightSidebarWidth: width }))}
      onToggleRightSidebar={() =>
        updateLayout((current) => ({
          ...current,
          rightSidebarVisible: !current.rightSidebarVisible,
          zenMode: false,
        }))
      }
      bottomPanelVisible={workbenchLayout.bottomPanelVisible}
      bottomPanelHeight={workbenchLayout.bottomPanelHeight}
      onBottomPanelHeightChange={(height) => updateLayout((current) => ({ ...current, bottomPanelHeight: height }))}
      onToggleBottomPanel={() =>
        updateLayout((current) => ({
          ...current,
          bottomPanelVisible: !current.bottomPanelVisible,
          zenMode: false,
        }))
      }
      status={status}
      statusItems={statusItems}
      showStatusBar={statusBarVisible}
      zenMode={workbenchLayout.zenMode}
      topbarActions={
        <>
          <button type="button" className="toolbar-button toolbar-accent" onClick={() => void createDraft(targetDocType)}>
            New
          </button>
          <button type="button" className="toolbar-button" onClick={() => void saveAll()} disabled={busy || dirtyCount === 0}>
            Save
          </button>
          <button type="button" className="toolbar-button" onClick={() => void runGeneration()} disabled={busy || !hasActiveWorkspace}>
            Run AI
          </button>
          <button
            type="button"
            className="toolbar-button"
            onClick={() =>
              updateLayout((current) => ({
                ...current,
                zenMode: !current.zenMode,
              }))
            }
          >
            {workbenchLayout.zenMode ? "Exit Zen" : "Zen"}
          </button>
        </>
      }
      leftSidebar={leftSidebar}
      editorArea={editorArea}
      rightSidebar={rightSidebar}
      bottomPanel={bottomPanel}
      overlays={overlays}
    />
  );
}
