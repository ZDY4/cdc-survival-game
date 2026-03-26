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
  docTypeSummary,
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

type AiChatMessage = {
  id: string;
  role: "user" | "assistant" | "context";
  label: string;
  content: string;
  meta?: string[];
  tone?: "accent" | "muted" | "warning" | "danger" | "success";
};

const ACTION_OPTIONS: Array<{ value: NarrativeAction; label: string }> = [
  { value: "create", label: "新建草稿" },
  { value: "revise_document", label: "修订当前文档" },
  { value: "rewrite_selection", label: "重写所选段落" },
  { value: "expand_selection", label: "扩写所选段落" },
  { value: "insert_after_selection", label: "在选区后插入" },
  { value: "derive_new_doc", label: "派生为新文档" },
];

const INSPECTOR_TABS: Array<{ value: InspectorTab; label: string }> = [
  { value: "inspector", label: "检查器" },
  { value: "review", label: "审阅" },
  { value: "bundle", label: "打包" },
  { value: "session", label: "会话" },
];

const BOTTOM_PANEL_TABS: Array<{ value: NarrativeBottomPanelView; label: string }> = [
  { value: "problems", label: "问题" },
  { value: "ai_runs", label: "AI 运行" },
  { value: "prompt_debug", label: "提示调试" },
  { value: "bundle_preview", label: "打包预览" },
];

const REVIEW_MODE_OPTIONS: Array<{ value: ReviewMode; label: string }> = [
  { value: "diff", label: "差异" },
  { value: "draft", label: "草稿" },
  { value: "original", label: "原文" },
];

const EDITOR_VIEW_OPTIONS: Array<{ value: NarrativeEditorView; label: string }> = [
  { value: "edit", label: "编辑" },
  { value: "preview", label: "预览" },
  { value: "diff", label: "差异" },
];

const ACTIVITY_ITEMS: WorkbenchActivityItem[] = [
  { id: "explorer", label: "资源", glyph: "EX" },
  { id: "search", label: "搜索", glyph: "SR" },
  { id: "outline", label: "提纲", glyph: "OL" },
  { id: "ai", label: "AI", glyph: "AI" },
  { id: "session", label: "会话", glyph: "SE" },
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
      return "从零开始起草一份新的叙事文档。";
    case "revise_document":
      return "在保持连续性的前提下修订当前文档。";
    case "rewrite_selection":
      return "仅替换当前选中的段落。";
    case "expand_selection":
      return "延展或加深当前选中的段落。";
    case "insert_after_selection":
      return "在当前选区之后追加新内容。";
    case "derive_new_doc":
      return "从当前文档派生出一份独立文档。";
    default:
      return "准备一次叙事写作处理。";
  }
}

function labelForAction(action: NarrativeAction) {
  return ACTION_OPTIONS.find((option) => option.value === action)?.label ?? action;
}

function labelForChangeScope(scope: NarrativeGenerateResponse["changeScope"]) {
  switch (scope) {
    case "document":
      return "整篇文档";
    case "selection":
      return "替换选区";
    case "insertion":
      return "选区后插入";
    case "new_doc":
      return "生成新文档";
    default:
      return scope;
  }
}

function clipChatContext(text: string, maxLength = 1200) {
  const trimmed = text.trim();
  if (trimmed.length <= maxLength) {
    return trimmed;
  }

  const headLength = Math.floor(maxLength * 0.65);
  const tailLength = maxLength - headLength;
  return `${trimmed.slice(0, headLength)}\n...\n${trimmed.slice(-tailLength)}`;
}

function buildNarrativeChatPrompt(
  input: string,
  history: AiChatMessage[],
  selectionText: string,
  selectedDocument: EditableNarrativeDocument | null,
) {
  const sections: string[] = [];
  const turns = history
    .filter((message) => message.role === "user" || message.role === "assistant")
    .slice(-6);

  if (selectedDocument) {
    sections.push(`当前文档：${selectedDocument.meta.title || selectedDocument.meta.slug}`);
  }

  if (turns.length) {
    sections.push(
      [
        "最近对话上下文：",
        ...turns.map((message) => `${message.role === "user" ? "用户" : "AI"}：${message.content}`),
      ].join("\n"),
    );
  }

  if (selectionText.trim()) {
    sections.push(`当前选中文本（自动作为聊天上下文）：\n${clipChatContext(selectionText)}`);
  }

  sections.push(`本次请求：${input.trim() || "请根据当前文档和上下文继续处理。"}`);
  return sections.join("\n\n");
}

function summarizeResponseForChat(response: NarrativeGenerateResponse) {
  const summary = response.providerError.trim() || response.summary.trim() || "AI 已返回结果。";
  const notes = [...response.reviewNotes, ...response.synthesisNotes]
    .map((note) => note.trim())
    .filter(Boolean)
    .slice(0, 3);

  if (!notes.length) {
    return summary;
  }

  return [summary, ...notes.map((note, index) => `要点 ${index + 1}：${note}`)].join("\n\n");
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
      return "还没有 AI 草稿。先运行一次修订，这里会显示差异结果。";
    }
    if (reviewMode === "original") {
      return selectedDocument.markdown;
    }
    if (reviewMode === "draft") {
      return response.draftMarkdown || "提供方返回了空草稿。";
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
  const [templatePickerVisible, setTemplatePickerVisible] = useState(false);
  const [templatePickerQuery, setTemplatePickerQuery] = useState("");
  const [recentCommands, setRecentCommands] = useState<EditorMenuCommandId[]>([]);
  const [recentDocumentKeys, setRecentDocumentKeys] = useState<string[]>([]);
  const [collapsedGroups, setCollapsedGroups] = useState<Record<string, boolean>>({});
  const [statusBarVisible, setStatusBarVisible] = useState(true);
  const [bulkSelectEnabled, setBulkSelectEnabled] = useState(false);
  const [agentRunsExpanded, setAgentRunsExpanded] = useState(false);
  const [aiChatMessages, setAiChatMessages] = useState<AiChatMessage[]>([]);
  const editorRef = useRef<HTMLTextAreaElement | null>(null);
  const aiChatScrollRef = useRef<HTMLDivElement | null>(null);
  const selfTestStartedRef = useRef(false);
  const lastPersistedLayoutRef = useRef("");
  const deferredExplorerFilter = useDeferredValue(explorerFilter);
  const deferredSearchActivityQuery = useDeferredValue(searchActivityQuery);
  const deferredTopbarQuery = useDeferredValue(topbarQuery);
  const deferredCommandQuery = useDeferredValue(commandPaletteQuery);
  const deferredTemplatePickerQuery = useDeferredValue(templatePickerQuery);

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
    setRecentDocumentKeys((current) => {
      const validKeys = new Set(nextDocuments.map((document) => document.documentKey));
      const nextRecent = current.filter((documentKey) => validKeys.has(documentKey));
      for (const documentKey of nextLayout.openDocumentKeys) {
        if (!nextRecent.includes(documentKey)) {
          nextRecent.push(documentKey);
        }
      }
      if (nextLayout.activeDocumentKey && !nextRecent.includes(nextLayout.activeDocumentKey)) {
        nextRecent.unshift(nextLayout.activeDocumentKey);
      }
      if (!nextRecent.length && nextDocuments[0]?.documentKey) {
        nextRecent.push(nextDocuments[0].documentKey);
      }
      return nextRecent.slice(0, 12);
    });
    setBundleSelection([]);
    setBundleResult(null);
    setAiChatMessages([]);
    setUserPrompt("");
    setEditorInstruction("");
  }, [workspace]);

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
        onStatusChange(`加载 AI 设置失败：${String(error)}`);
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
              onStatusChange("AI 设置已刷新。");
            })
            .catch((error) => {
              onStatusChange(`刷新 AI 设置失败：${String(error)}`);
            });
        }
        if (event.payload.section === "workspace") {
          onStatusChange("工作区设置已更新。重新加载当前工作区后会应用路径变更。");
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
          onStatusChange(`保存工作台布局失败：${String(error)}`);
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
        if (templatePickerVisible) {
          event.preventDefault();
          setTemplatePickerVisible(false);
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

      if (event.key.toLowerCase() === "n" && !event.shiftKey) {
        event.preventDefault();
        void dispatchEditorMenuCommand(EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT);
        return;
      }

      if (event.key.toLowerCase() === "s" && !event.shiftKey) {
        event.preventDefault();
        void dispatchEditorMenuCommand(EDITOR_MENU_COMMANDS.FILE_SAVE_ALL);
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
  }, [commandPaletteVisible, quickOpenVisible, templatePickerVisible]);

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
  const explorerDocumentGroups = useMemo(
    () => explorerGroups.filter((group) => group.documents.length > 0),
    [explorerGroups],
  );
  const explorerQuickCreateTypes = useMemo(() => {
    const existingDocTypes = new Set(documents.map((document) => document.meta.docType));
    return workspace.docTypes.filter((entry) => {
      if (filterDocType && entry.value !== filterDocType) {
        return false;
      }
      if (deferredExplorerFilter.trim()) {
        const haystack = `${entry.label} ${entry.value} ${entry.directory}`.toLowerCase();
        if (!haystack.includes(deferredExplorerFilter.trim().toLowerCase())) {
          return false;
        }
      }
      return !existingDocTypes.has(entry.value);
    });
  }, [deferredExplorerFilter, documents, filterDocType, workspace.docTypes]);
  const searchResults = useMemo(
    () => documents.filter((document) => matchesDocumentQuery(document, deferredSearchActivityQuery)),
    [deferredSearchActivityQuery, documents],
  );
  const quickOpenResults = useMemo(() => {
    const recentOrder = new Map(recentDocumentKeys.map((documentKey, index) => [documentKey, index]));
    return documents
      .filter((document) => matchesDocumentQuery(document, deferredTopbarQuery))
      .sort((left, right) => {
        const leftRecent = recentOrder.get(left.documentKey) ?? Number.MAX_SAFE_INTEGER;
        const rightRecent = recentOrder.get(right.documentKey) ?? Number.MAX_SAFE_INTEGER;
        if (leftRecent !== rightRecent) {
          return leftRecent - rightRecent;
        }
        return left.meta.title.localeCompare(right.meta.title);
      })
      .slice(0, 12);
  }, [deferredTopbarQuery, documents, recentDocumentKeys]);
  const outlineHeadings = useMemo(
    () => (selectedDocument ? parseHeadings(selectedDocument.markdown) : []),
    [selectedDocument],
  );
  const recentDocuments = useMemo(() => {
    const documentsByKey = new Map(documents.map((document) => [document.documentKey, document]));
    const ordered = recentDocumentKeys
      .map((documentKey) => documentsByKey.get(documentKey) ?? null)
      .filter(Boolean) as EditableNarrativeDocument[];
    if (ordered.length >= 6) {
      return ordered.slice(0, 6);
    }
    for (const document of documents) {
      if (!ordered.find((entry) => entry.documentKey === document.documentKey)) {
        ordered.push(document);
      }
      if (ordered.length >= 6) {
        break;
      }
    }
    return ordered;
  }, [documents, recentDocumentKeys]);
  const explorerHasFilter = Boolean(deferredExplorerFilter.trim()) || Boolean(filterDocType);
  const rightSidebarHasContext =
    Boolean(selectedDocument) || Boolean(response) || Boolean(bundleResult) || inspectorTab === "session";
  const templatePickerEntries = useMemo(() => {
    const query = deferredTemplatePickerQuery.trim().toLowerCase();
    const docCounts = new Map<NarrativeDocType, number>();
    for (const document of documents) {
      docCounts.set(document.meta.docType, (docCounts.get(document.meta.docType) ?? 0) + 1);
    }

    return workspace.docTypes
      .filter((entry) => {
        if (!query) {
          return true;
        }
        const haystack = `${entry.label} ${entry.value} ${entry.directory} ${docTypeSummary(entry.value)}`.toLowerCase();
        return haystack.includes(query);
      })
      .map((entry) => ({
        entry,
        docCount: docCounts.get(entry.value) ?? 0,
      }))
      .sort((left, right) => {
        if (left.entry.value === targetDocType) {
          return -1;
        }
        if (right.entry.value === targetDocType) {
          return 1;
        }
        if (right.docCount !== left.docCount) {
          return right.docCount - left.docCount;
        }
        return left.entry.label.localeCompare(right.entry.label);
      });
  }, [deferredTemplatePickerQuery, documents, targetDocType, workspace.docTypes]);
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

  useEffect(() => {
    if (!selectedDocument && !response && !bundleResult && inspectorTab === "inspector" && workbenchLayout.rightSidebarVisible) {
      updateLayout((current) =>
        current.rightSidebarVisible
          ? {
              ...current,
              rightSidebarVisible: false,
            }
          : current,
      );
    }
  }, [bundleResult, inspectorTab, response, selectedDocument, workbenchLayout.rightSidebarVisible]);

  useEffect(() => {
    const chatLog = aiChatScrollRef.current;
    if (!chatLog) {
      return;
    }
    chatLog.scrollTop = chatLog.scrollHeight;
  }, [aiChatMessages, busy]);

  function rememberCommand(commandId: EditorMenuCommandId) {
    setRecentCommands((current) => [commandId, ...current.filter((entry) => entry !== commandId)].slice(0, 16));
  }

  function rememberRecentDocument(documentKey: string) {
    setRecentDocumentKeys((current) => [documentKey, ...current.filter((entry) => entry !== documentKey)].slice(0, 12));
  }

  function appendAiChatMessage(message: AiChatMessage) {
    setAiChatMessages((current) => [...current, message]);
  }

  function clearAiChatSession() {
    setAiChatMessages([]);
    setUserPrompt("");
    setResponse(null);
    setLastRequest(null);
    setAgentRunsExpanded(false);
    onStatusChange("已清空 AI 会话。");
  }

  async function runCommand(commandId: EditorMenuCommandId) {
    rememberCommand(commandId);
    const result = await dispatchEditorMenuCommand(commandId);
    if (!result.ok) {
      onStatusChange(
        result.reason === "disabled"
          ? `${formatEditorMenuCommandLabel(commandId)} 在当前上下文中不可用。`
          : `${formatEditorMenuCommandLabel(commandId)} 在这里不受支持。`,
      );
      return;
    }
    setCommandPaletteVisible(false);
  }

  function openTemplatePicker(preferredDocType?: NarrativeDocType) {
    if (preferredDocType) {
      setTargetDocType(preferredDocType);
    }
    setQuickOpenVisible(false);
    setCommandPaletteVisible(false);
    setTemplatePickerQuery("");
    setTemplatePickerVisible(true);
  }

  async function createDraftFromTemplate(docType: NarrativeDocType) {
    setTemplatePickerVisible(false);
    setTargetDocType(docType);
    await createDraft(docType);
  }

  function openQuickOpenPanel(nextQuery?: string) {
    setTemplatePickerVisible(false);
    setCommandPaletteVisible(false);
    if (typeof nextQuery === "string") {
      setTopbarQuery(nextQuery);
    }
    setQuickOpenVisible(true);
  }

  function openCommandPalettePanel() {
    setTemplatePickerVisible(false);
    setQuickOpenVisible(false);
    setCommandPaletteVisible(true);
  }

  async function promptConfigureWorkspace(actionLabel: string) {
    await openOrFocusSettingsWindow("workspace");
    onStatusChange(
      `无法${actionLabel}，因为当前还没有配置叙事工作区。已打开“设置 > 工作区”。`,
    );
  }

  function activateDocument(documentKey: string) {
    setOpenTabs((current) => (current.includes(documentKey) ? current : [...current, documentKey]));
    setSelectedKey(documentKey);
    rememberRecentDocument(documentKey);
    setQuickOpenVisible(false);
    setTopbarQuery("");
  }

  function closeDocumentTab(documentKey: string) {
    const document = documents.find((entry) => entry.documentKey === documentKey);
    if (!document) {
      return;
    }
    if (document.dirty) {
      onStatusChange(`请先保存或还原 ${document.meta.slug}，再关闭它的标签页。`);
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
      await promptConfigureWorkspace("创建草稿");
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
      onStatusChange(`已创建 ${docTypeLabel(docType)} 草稿 ${draft.meta.slug}。`);
    } catch (error) {
      onStatusChange(`创建草稿失败：${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function saveAll() {
    const dirtyDocuments = documents.filter((document) => document.dirty);
    if (!dirtyDocuments.length) {
      onStatusChange("当前没有未保存的叙事修改。");
      return;
    }
    if (!canPersist) {
      onStatusChange("界面回退模式下无法保存叙事文档。");
      return;
    }
    if (!hasActiveWorkspace) {
      onStatusChange("请先打开或配置叙事工作区，再执行保存。");
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
      onStatusChange(`已保存 ${dirtyDocuments.length} 份叙事文档。`);
    } catch (error) {
      onStatusChange(`叙事文档保存失败：${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function deleteCurrent() {
    if (!selectedDocument) {
      onStatusChange("请先选择一份叙事文档。");
      return;
    }

    if (selectedDocument.isDraft) {
      const remaining = documents.filter((document) => document.documentKey !== selectedDocument.documentKey);
      setDocuments(remaining);
      setOpenTabs((current) => current.filter((entry) => entry !== selectedDocument.documentKey));
      setSelectedKey(remaining[0]?.documentKey ?? "");
      onStatusChange("已移除未保存的叙事草稿。");
      return;
    }

    if (!canPersist) {
      onStatusChange("界面回退模式下无法删除项目文件。");
      return;
    }

    setBusy(true);
    try {
      await invokeCommand("delete_narrative_document", {
        workspaceRoot: workspace.workspaceRoot,
        slug: selectedDocument.meta.slug,
      });
      await onReload();
      onStatusChange(`已删除叙事文档 ${selectedDocument.meta.slug}。`);
    } catch (error) {
      onStatusChange(`删除叙事文档失败：${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function runGeneration() {
    if (!hasActiveWorkspace) {
      onStatusChange("请先打开或配置叙事工作区，再使用 AI。");
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
      onStatusChange("执行仅作用于选区的 AI 动作前，请先选中文本段落。");
      return;
    }

    const submittedPrompt =
      userPrompt.trim() ||
      (hasSelection
        ? "请围绕当前选区继续处理。"
        : selectedDocument
          ? `请继续处理《${selectedDocument.meta.title || selectedDocument.meta.slug}》。`
          : "请根据当前上下文继续处理。");
    const promptWithHistory = buildNarrativeChatPrompt(
      submittedPrompt,
      aiChatMessages,
      selectionText,
      selectedDocument,
    );
    const nextInstruction = [
      editorInstruction.trim(),
      hasSelection ? "当前编辑器中有选中文本，请将其视为本轮对话的重点上下文。" : "",
    ]
      .filter(Boolean)
      .join("\n\n");
    const selectionLength = selectionText.trim().length;

    const request: NarrativeGenerateRequest = {
      docType: aiAction === "create" || aiAction === "derive_new_doc" ? targetDocType : currentDocType,
      targetSlug: currentSlug,
      action: aiAction,
      userPrompt: promptWithHistory,
      editorInstruction: nextInstruction,
      currentMarkdown,
      selectedRange: selectionRange,
      selectedText: selectionText,
      relatedDocSlugs: selectedDocument?.meta.relatedDocs ?? [],
      derivedTargetDocType:
        aiAction === "create" || aiAction === "derive_new_doc" ? targetDocType : null,
    };

    appendAiChatMessage({
      id: `user-${Date.now()}`,
      role: "user",
      label: "你",
      content: submittedPrompt,
      meta: [
        `动作：${labelForAction(aiAction)}`,
        `目标：${docTypeLabel(request.docType)}`,
        selectedDocument ? `文档：${selectedDocument.meta.title || selectedDocument.meta.slug}` : "当前未打开文档",
        hasSelection ? `自动附带选区 ${selectionLength} 字` : "无选区上下文",
      ],
      tone: "accent",
    });
    setUserPrompt("");
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
      appendAiChatMessage({
        id: `assistant-${Date.now()}`,
        role: "assistant",
        label: "AI",
        content: summarizeResponseForChat(next),
        meta: [
          `作用范围：${labelForChangeScope(next.changeScope)}`,
          `代理运行：${next.agentRuns.length}`,
          next.providerError ? "本轮返回了提供方错误" : "草稿可用于继续审阅",
        ],
        tone: next.providerError ? "danger" : "success",
      });
      onStatusChange(next.providerError || next.summary || "叙事草稿已生成，可开始审阅。");
    } catch (error) {
      appendAiChatMessage({
        id: `assistant-error-${Date.now()}`,
        role: "assistant",
        label: "AI",
        content: `本次执行失败：${String(error)}`,
        meta: ["请检查 AI 设置、工作区路径或网络连接。"],
        tone: "danger",
      });
      onStatusChange(`叙事生成失败：${String(error)}`);
    } finally {
      setBusy(false);
    }
  }

  async function prepareBundle() {
    if (!hasActiveWorkspace) {
      onStatusChange("请先打开或配置叙事工作区，再导出结构打包。");
      return;
    }

    const documentSlugs = bundleScope;
    if (!documentSlugs.length) {
      onStatusChange("请至少选择一份文档用于结构导出。");
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
      onStatusChange(`已为 ${next.documentSlugs.length} 份文档准备结构打包。`);
    } catch (error) {
      onStatusChange(`准备结构打包失败：${String(error)}`);
    }
  }

  async function applyDraft(mode: "auto" | "new_doc" = "auto") {
    if (!response) {
      onStatusChange("请先运行一次 AI 生成。");
      return;
    }
    if (response.providerError || !response.draftMarkdown.trim()) {
      onStatusChange("当前草稿无法应用。");
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
      appendAiChatMessage({
        id: `context-new-doc-${Date.now()}`,
        role: "context",
        label: "系统",
        content: "已将最新 AI 草稿应用为新文档。",
        meta: [`文档类型：${docTypeLabel(nextDocType)}`],
        tone: "success",
      });
      onStatusChange("已将 AI 草稿应用为新文档，记得保存。");
      return;
    }

    if (!selectedDocument) {
      onStatusChange("应用草稿前，请先选择一份叙事文档。");
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
    appendAiChatMessage({
      id: `context-apply-${Date.now()}`,
      role: "context",
      label: "系统",
      content: "已将最新 AI 草稿应用到当前文档。",
      meta: [selectedDocument.meta.title || selectedDocument.meta.slug],
      tone: "success",
    });
    onStatusChange("已将 AI 草稿应用到当前编辑器。");
  }

  const menuCommands = useMemo(
    () => ({
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT);
          openTemplatePicker(targetDocType);
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
          openCommandPalettePanel();
        },
      },
      [EDITOR_MENU_COMMANDS.WORKBENCH_QUICK_OPEN]: {
        execute: () => {
          rememberCommand(EDITOR_MENU_COMMANDS.WORKBENCH_QUICK_OPEN);
          openQuickOpenPanel();
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
          onStatusChange("已重置叙事实验室工作区布局。");
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
          onStatusChange("已恢复叙事实验室默认工作台布局。");
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
          onStatusChange("已收起高级面板。");
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
          onStatusChange("已展开所有工作台面板。");
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
          onStatusChange("焦点已切换到编辑器。");
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
          onStatusChange(workbenchLayout.zenMode ? "已退出专注模式。" : "已进入专注模式。");
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
          onStatusChange("已打开 AI 设置，可用于测试提供方连接。");
        },
      },
      [EDITOR_MENU_COMMANDS.AI_OPEN_PROVIDER_SETTINGS]: {
        execute: async () => {
          rememberCommand(EDITOR_MENU_COMMANDS.AI_OPEN_PROVIDER_SETTINGS);
          await openOrFocusSettingsWindow("ai");
          onStatusChange("已打开 AI 提供方设置。");
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
          <Badge tone="muted">加载中</Badge>
          <p>正在准备叙事工作区和设置...</p>
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
      label: hasActiveWorkspace ? "工作区就绪" : "工作区未配置",
      tone: hasActiveWorkspace ? "success" : "warning",
    },
    { id: "doc", label: selectedDocument ? selectedDocument.meta.slug : "无文档", tone: "muted" as const },
    { id: "dirty", label: `${dirtyCount} 个未保存`, tone: dirtyCount > 0 ? "warning" : "muted" as const },
    {
      id: "selection",
      label: hasSelection ? `已选中 ${selectionText.length} 字` : "未选中文本",
      tone: hasSelection ? "accent" : "muted",
    },
    { id: "ai", label: aiSettings.model || "AI 未配置", tone: "muted" as const },
    { id: "mode", label: workbenchLayout.zenMode ? "专注模式" : "工作台", tone: "muted" as const },
  ];

  const leftSidebar = (
    <div className="narrative-workbench-panel">
      {activeActivity === "explorer" ? (
        <>
          <div className="narrative-workbench-panel-header">
            <div>
              <span className="section-label">资源</span>
              <h3 className="panel-title">叙事文档</h3>
            </div>
            <Badge tone="muted">{documents.length}</Badge>
          </div>

          <div className="narrative-sidebar-controls">
            <input
              className="field-input"
              type="text"
              value={explorerFilter}
              onChange={(event) => setExplorerFilter(event.target.value)}
              placeholder="筛选标题、标签和路径"
            />
            <select
              className="field-input"
              value={filterDocType}
              onChange={(event) => setFilterDocType(event.target.value)}
            >
              <option value="">全部文档类型</option>
              {workspace.docTypes.map((entry) => (
                <option key={entry.value} value={entry.value}>
                  {entry.label}
                </option>
              ))}
            </select>
            <button
              type="button"
              className="toolbar-button toolbar-accent"
              onClick={() => openTemplatePicker(targetDocType)}
              disabled={busy || !hasActiveWorkspace}
            >
              <span className="toolbar-button-main">新建文档</span>
              <span className="toolbar-button-hint">{docTypeLabel(targetDocType)}</span>
            </button>
          </div>

          {explorerDocumentGroups.length ? (
            <div className="narrative-explorer-tree">
              {explorerDocumentGroups.map((group) => {
                const issueCount = group.documents.reduce((count, document) => count + document.validation.length, 0);
                const dirtyGroupCount = group.documents.filter((document) => document.dirty).length;
                const collapsed = collapsedGroups[group.entry.value] ?? false;
                const isTargetDocType = targetDocType === group.entry.value;
                return (
                  <section key={group.entry.value} className="narrative-explorer-group">
                    <div
                      className={`narrative-explorer-group-toggle ${
                        isTargetDocType ? "narrative-explorer-group-toggle-active" : ""
                      }`.trim()}
                    >
                      <button
                        type="button"
                        className="narrative-explorer-group-main"
                        onClick={() => setTargetDocType(group.entry.value)}
                      >
                        <div className="narrative-explorer-group-copy">
                          <strong>{group.entry.label}</strong>
                          <span>{group.documents.length} 份文档</span>
                        </div>
                      </button>
                      <div className="narrative-explorer-group-actions">
                        {isTargetDocType ? <Badge tone="accent">当前新建目标</Badge> : null}
                        <div className="toolbar-summary">
                          {dirtyGroupCount > 0 ? <Badge tone="warning">{dirtyGroupCount} 个未保存</Badge> : null}
                          {issueCount > 0 ? <Badge tone="warning">{issueCount} 个问题</Badge> : null}
                        </div>
                        <button
                          type="button"
                          className="narrative-explorer-group-chevron"
                          aria-label={collapsed ? `展开 ${group.entry.label}` : `折叠 ${group.entry.label}`}
                          title={collapsed ? `展开 ${group.entry.label}` : `折叠 ${group.entry.label}`}
                          onClick={() =>
                            setCollapsedGroups((current) => ({
                              ...current,
                              [group.entry.value]: !collapsed,
                            }))
                          }
                        >
                          {collapsed ? "+" : "-"}
                        </button>
                      </div>
                    </div>

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
                                  {document.dirty ? <Badge tone="warning">未保存</Badge> : null}
                                  {document.validation.length ? (
                                    <Badge tone="warning">{document.validation.length}</Badge>
                                  ) : null}
                                </div>
                              </div>
                              <p>{document.relativePath}</p>
                              <span>{firstNonEmptyLine(document.markdown) || "正文还没有内容。"}</span>
                            </div>
                            <div className="narrative-document-side">
                              <Badge tone="muted">{document.meta.status || "草稿"}</Badge>
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
                                  打包
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
          ) : (
            <div className="workspace-empty settings-empty-inline narrative-explorer-empty-state">
              <p>
                {explorerHasFilter
                  ? "没有文档符合当前筛选条件。"
                  : "还没有叙事文档。可以从模板开始，或直接使用中间画布。"}
              </p>
            </div>
          )}

          {explorerQuickCreateTypes.length ? (
            <div className="narrative-start-section narrative-start-section-compact">
              <div className="narrative-start-section-header">
                <div>
                  <span className="section-label">快速新建</span>
                  <h3 className="panel-title">从模板开始</h3>
                </div>
              </div>
              <div className="narrative-template-grid narrative-template-grid-compact">
                {explorerQuickCreateTypes.map((entry) => (
                  <button
                    key={entry.value}
                    type="button"
                    className={`narrative-template-card narrative-template-card-compact ${
                      targetDocType === entry.value ? "narrative-template-card-active" : ""
                    }`.trim()}
                    onClick={() => {
                      setTargetDocType(entry.value);
                      void createDraft(entry.value);
                    }}
                    disabled={busy || !hasActiveWorkspace}
                  >
                    <strong>{entry.label}</strong>
                    <span>{docTypeSummary(entry.value)}</span>
                  </button>
                ))}
              </div>
            </div>
          ) : null}
        </>
      ) : null}

      {activeActivity === "search" ? (
        <>
          <div className="narrative-workbench-panel-header">
            <div>
              <span className="section-label">搜索</span>
              <h3 className="panel-title">工作区搜索</h3>
            </div>
            <Badge tone="muted">{searchResults.length}</Badge>
          </div>
          <input
            className="field-input"
            type="text"
            value={searchActivityQuery}
            onChange={(event) => setSearchActivityQuery(event.target.value)}
            placeholder="搜索标题、标签、slug 和路径"
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
                <p>还没有匹配的文档。</p>
              </div>
            ) : null}
          </div>
        </>
      ) : null}

      {activeActivity === "outline" ? (
        <>
          <div className="narrative-workbench-panel-header">
            <div>
              <span className="section-label">提纲</span>
              <h3 className="panel-title">当前文档标题结构</h3>
            </div>
            <Badge tone="muted">{outlineHeadings.length}</Badge>
          </div>
          <div className="narrative-list narrative-scroll">
            {outlineHeadings.map((heading, index) => (
              <div key={`${heading}-${index}`} className="summary-row summary-row-compact">
                <div className="summary-row-main">
                  <strong>章节 {index + 1}</strong>
                  <p>{heading}</p>
                </div>
              </div>
            ))}
            {!outlineHeadings.length ? (
              <div className="workspace-empty settings-empty-inline">
                <p>选择一份带有 Markdown 标题的文档后，这里会显示提纲。</p>
              </div>
            ) : null}
          </div>
        </>
      ) : null}

      {activeActivity === "ai" ? (
        <>
          <div className="narrative-workbench-panel-header">
            <div>
              <span className="section-label">AI 任务</span>
              <h3 className="panel-title">聊天协作</h3>
            </div>
            <div className="toolbar-summary">
              <Badge tone="accent">{aiSettings.model || "未配置模型"}</Badge>
              <button type="button" className="toolbar-button" onClick={() => clearAiChatSession()}>
                清空会话
              </button>
            </div>
          </div>

          <div className="summary-row summary-row-compact">
            <div className="summary-row-main">
              <strong>当前动作</strong>
              <p>{copyForAction(aiAction)}</p>
            </div>
          </div>

          <div className="narrative-sidebar-stack">
            <div className="form-grid">
              <SelectField
                label="动作"
                value={aiAction}
                onChange={(value) => setAiAction((value as NarrativeAction) || "revise_document")}
                allowBlank={false}
                options={ACTION_OPTIONS}
              />
              <SelectField
                label="目标文档类型"
                value={targetDocType}
                onChange={(value) => setTargetDocType((value as NarrativeDocType) || "branch_sheet")}
                allowBlank={false}
                options={workspace.docTypes}
              />
            </div>

            <div className="toolbar-summary">
              <Badge tone={selectedDocument ? "accent" : "muted"}>
                {selectedDocument ? `当前文档：${selectedDocument.meta.title || selectedDocument.meta.slug}` : "当前未打开文档"}
              </Badge>
              <Badge tone={hasSelection ? "accent" : "muted"}>
                {hasSelection ? `自动附带选区 ${selectionText.trim().length} 字` : "无选区上下文"}
              </Badge>
              <Badge tone="muted">{`目标：${docTypeLabel(targetDocType)}`}</Badge>
            </div>

            {hasSelection ? (
              <div className="narrative-ai-context-card">
                <span className="field-label">当前选区预览</span>
                <pre className="narrative-ai-selection-preview">{clipChatContext(selectionText, 420)}</pre>
              </div>
            ) : null}

            <TextareaField
              label="长期约束"
              value={editorInstruction}
              onChange={setEditorInstruction}
              placeholder="连续性、节奏、视角、限制、文风或输出格式。"
            />

            <div className="narrative-ai-chat-shell">
              <div ref={aiChatScrollRef} className="narrative-ai-chat-log narrative-scroll">
                {aiChatMessages.length ? (
                  aiChatMessages.map((message) => (
                    <article
                      key={message.id}
                      className={`narrative-ai-message narrative-ai-message-${message.role}`.trim()}
                    >
                      <div className="narrative-ai-message-header">
                        <strong>{message.label}</strong>
                        {message.tone ? <Badge tone={message.tone}>{message.role === "assistant" ? "回复" : message.label}</Badge> : null}
                      </div>
                      <p>{message.content}</p>
                      {message.meta?.length ? (
                        <div className="toolbar-summary">
                          {message.meta.map((item) => (
                            <Badge key={`${message.id}-${item}`} tone="muted">
                              {item}
                            </Badge>
                          ))}
                        </div>
                      ) : null}
                    </article>
                  ))
                ) : (
                  <div className="workspace-empty settings-empty-inline narrative-ai-chat-empty">
                    <p>像聊天一样告诉 AI 你要改什么。当前文档和编辑器选区会自动作为上下文带上。</p>
                  </div>
                )}
                {busy ? (
                  <div className="narrative-ai-message narrative-ai-message-context narrative-ai-message-pending">
                    <div className="narrative-ai-message-header">
                      <strong>AI</strong>
                      <Badge tone="warning">思考中</Badge>
                    </div>
                    <p>正在根据当前文档、选区和最近对话生成结果...</p>
                  </div>
                ) : null}
              </div>

              <div className="narrative-ai-composer">
                <span className="field-label">聊天输入</span>
                <textarea
                  className="field-input field-textarea narrative-ai-composer-input"
                  value={userPrompt}
                  onChange={(event) => setUserPrompt(event.target.value)}
                  onKeyDown={(event) => {
                    if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
                      event.preventDefault();
                      if (!busy && hasActiveWorkspace) {
                        void runGeneration();
                      }
                    }
                  }}
                  placeholder={
                    hasSelection
                      ? "描述你想如何处理当前选区。Enter 发送，Shift+Enter 换行。"
                      : "像聊天一样告诉 AI 你要写什么、改什么或检查什么。Enter 发送，Shift+Enter 换行。"
                  }
                />
                <div className="narrative-ai-composer-footer">
                  <div className="toolbar-summary">
                    <Badge tone="muted">{labelForAction(aiAction)}</Badge>
                    <Badge tone="muted">{selectedDocument ? "会参考当前文档全文" : "可用于新建文档"}</Badge>
                    {hasSelection ? <Badge tone="accent">选区优先</Badge> : null}
                  </div>
                  <button
                    type="button"
                    className="toolbar-button toolbar-accent"
                    onClick={() => void runGeneration()}
                    disabled={busy || !hasActiveWorkspace}
                  >
                    发送给 AI
                  </button>
                </div>
              </div>
            </div>

            <div className="toolbar-actions">
              <button
                type="button"
                className="toolbar-button"
                onClick={() => void applyDraft("auto")}
                disabled={!response || Boolean(response.providerError)}
              >
                应用结果
              </button>
              <button
                type="button"
                className="toolbar-button"
                onClick={() => void applyDraft("new_doc")}
                disabled={!response || Boolean(response.providerError)}
              >
                另存为新文档
              </button>
              <button
                type="button"
                className="toolbar-button"
                onClick={() => void openOrFocusSettingsWindow("ai")}
              >
                提供方设置
              </button>
            </div>
          </div>
        </>
      ) : null}

      {activeActivity === "session" ? (
        <>
          <div className="narrative-workbench-panel-header">
            <div>
              <span className="section-label">会话</span>
              <h3 className="panel-title">工作区上下文</h3>
            </div>
            <Badge tone={hasActiveWorkspace ? "success" : "warning"}>
              {hasActiveWorkspace ? "就绪" : "待配置"}
            </Badge>
          </div>

          <div className="narrative-sidebar-stack narrative-scroll">
            <div className="summary-row summary-row-compact">
              <div className="summary-row-main">
                <strong>工作区根目录</strong>
                <p>{workspace.workspaceRoot || appSettings.lastWorkspace || "未配置"}</p>
              </div>
            </div>
            <div className="summary-row summary-row-compact">
              <div className="summary-row-main">
                <strong>项目根目录</strong>
                <p>{workspace.connectedProjectRoot || appSettings.connectedProjectRoot || "未连接"}</p>
              </div>
            </div>
            <div className="summary-row summary-row-compact">
              <div className="summary-row-main">
                <strong>项目上下文</strong>
                <p>{workspace.projectContextStatus || "尚未加载上下文快照。"}</p>
              </div>
            </div>
            <div className="toolbar-actions">
              <button type="button" className="toolbar-button" onClick={() => void openOrFocusSettingsWindow("workspace")}>
                工作区设置
              </button>
              <button type="button" className="toolbar-button" onClick={() => void openOrFocusSettingsWindow("ai")}>
                AI 设置
              </button>
              <button type="button" className="toolbar-button" onClick={() => void onReload()} disabled={busy}>
                重新加载工作区
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
          <span className="section-label">上下文</span>
          <h3 className="panel-title">检查与审阅</h3>
        </div>
        <Badge tone="muted">{inspectorTab}</Badge>
      </div>

      <div className="segmented-control narrative-tab-strip" aria-label="检查器标签">
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
                label="关联文档"
                values={selectedDocument.meta.relatedDocs}
                onChange={(values) =>
                  updateSelectedDocument((document) => ({
                    ...document,
                    meta: { ...document.meta, relatedDocs: values.filter(Boolean) },
                  }))
                }
              />
              <TokenListField
                label="来源引用"
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
                  <strong>文件</strong>
                  <p>{selectedDocument.relativePath}</p>
                </div>
              </div>
              <div className="summary-row summary-row-compact">
                <div className="summary-row-main">
                  <strong>校验</strong>
                  <p>
                    {selectedDocument.validation.length
                      ? `${selectedDocument.validation.length} 个问题待处理`
                      : "没有校验问题。"}
                  </p>
                </div>
              </div>
            </>
          ) : (
            <div className="workspace-empty settings-empty-inline">
              <p>选择一份文档后，可在这里检查元数据。</p>
            </div>
          )
        ) : null}

        {inspectorTab === "review" ? (
          response ? (
            <>
              <div className="narrative-review-topbar">
                <div className="segmented-control" aria-label="审阅模式">
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
                  {agentRunsExpanded ? "隐藏代理过程" : "显示代理过程"}
                </button>
              </div>
              <div className="summary-row summary-row-compact">
                <div className="summary-row-main">
                  <strong>摘要</strong>
                  <p>{response.summary || response.providerError || "还没有 AI 结果。"}</p>
                </div>
              </div>
              {[...response.reviewNotes, ...response.synthesisNotes, ...notesFromIssues(selectedDocument?.validation ?? [])].map(
                (note, index) => (
                  <div key={`${note}-${index}`} className="summary-row summary-row-compact">
                    <div className="summary-row-main">
                      <strong>说明 {index + 1}</strong>
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
              <p>运行 AI 后，这里会显示草稿检查结果和审阅摘要。</p>
            </div>
          )
        ) : null}

        {inspectorTab === "bundle" ? (
          <>
            <div className="summary-row summary-row-compact">
              <div className="summary-row-main">
                <strong>选择范围</strong>
                <p>
                  {bundleScope.length
                    ? `${bundleScope.length} 份文档已准备好导出`
                    : "还没有选中文档。"}
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
                准备打包
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
                {bulkSelectEnabled ? "完成选择" : "选择多份文档"}
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
                    <strong>打包摘要</strong>
                    <p>{bundleResult.summary}</p>
                  </div>
                </div>
                {bundleResult.exportPath ? (
                  <div className="summary-row summary-row-compact">
                    <div className="summary-row-main">
                      <strong>导出路径</strong>
                      <p>{bundleResult.exportPath}</p>
                    </div>
                  </div>
                ) : null}
              </>
            ) : (
              <div className="workspace-empty settings-empty-inline">
                <p>先准备打包，这里会显示导出目标和合并后的 Markdown 内容。</p>
              </div>
            )}
          </>
        ) : null}

        {inspectorTab === "session" ? (
          <>
            <div className="summary-row summary-row-compact">
              <div className="summary-row-main">
                <strong>工作区根目录</strong>
                <p>{workspace.workspaceRoot || appSettings.lastWorkspace || "未配置"}</p>
              </div>
            </div>
            <div className="summary-row summary-row-compact">
              <div className="summary-row-main">
                <strong>项目根目录</strong>
                <p>{workspace.connectedProjectRoot || appSettings.connectedProjectRoot || "未连接"}</p>
              </div>
            </div>
            <div className="summary-row summary-row-compact">
              <div className="summary-row-main">
                <strong>AI 提供方</strong>
                <p>{aiSettings.model || "未配置"} · {aiSettings.baseUrl || "无接口地址"}</p>
              </div>
            </div>
            <div className="summary-row summary-row-compact">
              <div className="summary-row-main">
                <strong>项目上下文</strong>
                <p>{workspace.projectContextStatus || "尚未加载上下文快照。"}</p>
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
          <span className="section-label">输出</span>
          <h3 className="panel-title">问题与结果</h3>
        </div>
      </div>

      <div className="segmented-control narrative-tab-strip" aria-label="底部面板标签">
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
              <p>当前打开的工作区中没有校验问题。</p>
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
                    <Badge tone={agent.status === "failed" ? "danger" : "success"}>
                      {agent.status === "failed" ? "失败" : "完成"}
                    </Badge>
                  </div>
                  <p className="agent-run-focus">{agent.focus}</p>
                  <p className="agent-run-focus">{agent.summary}</p>
                </article>
              ))}
            </div>
          ) : (
            <div className="workspace-empty settings-empty-inline">
              <p>运行 AI 后，这里会显示代理过程和综合输出。</p>
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
              <p>运行 AI 后，这里会填充提示调试输出。</p>
            </div>
          )
        ) : null}

        {activeBottomPanel === "bundle_preview" ? (
          bundleResult ? (
            <pre className="narrative-code-block narrative-bundle-block">{bundleResult.combinedMarkdown}</pre>
          ) : (
            <div className="workspace-empty settings-empty-inline">
              <p>先准备打包，这里会预览合并后的 Markdown 导出内容。</p>
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
              <span className="section-label">编辑器</span>
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
                placeholder="文档标题"
              />
              <div className="toolbar-summary">
                <Badge tone="accent">{docTypeLabel(selectedDocument.meta.docType)}</Badge>
                <Badge tone={selectedDocument.dirty ? "warning" : "success"}>
                  {selectedDocument.dirty ? "未保存" : "已保存"}
                </Badge>
                <Badge tone={selectedDocument.validation.length ? "warning" : "muted"}>
                  {selectedDocument.validation.length} 个问题
                </Badge>
                <Badge tone={hasSelection ? "accent" : "muted"}>
                  {hasSelection ? "已选中文本" : "未选中文本"}
                </Badge>
              </div>
            </div>

            <div className="narrative-editor-sidebar">
              <div className="narrative-editor-field">
                <span className="field-label">状态</span>
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
                  placeholder="草稿 / 审阅 / 已批准"
                />
              </div>

              <div className="segmented-control" aria-label="编辑器视图">
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
        <div className="panel narrative-start-page">
          <div className="narrative-start-hero">
            <div className="narrative-start-hero-copy">
              <Badge tone="accent">叙事工作区</Badge>
              <h3 className="panel-title">把注意力放在写作上，而不是空面板管理上</h3>
              <p>
                选择一个文档模板开始，或从最近列表中重新打开已有草稿。
                叙事实验室应该让你一进来就能直接开始写。
              </p>
            </div>
            <div className="narrative-start-hero-actions">
              <button
                type="button"
                className="toolbar-button toolbar-accent"
                onClick={() => openTemplatePicker(targetDocType)}
                disabled={busy || !hasActiveWorkspace}
              >
                <span className="toolbar-button-main">新建文档</span>
                <span className="toolbar-button-hint">{docTypeLabel(targetDocType)}</span>
              </button>
              <button type="button" className="toolbar-button" onClick={() => openQuickOpenPanel()}>
                快速打开
              </button>
              <button
                type="button"
                className="toolbar-button"
                onClick={() => void openOrFocusSettingsWindow("workspace")}
              >
                工作区设置
              </button>
            </div>
          </div>

          {recentDocuments.length ? (
            <section className="narrative-start-section">
              <div className="narrative-start-section-header">
                <div>
                  <span className="section-label">最近</span>
                  <h3 className="panel-title">继续上次的工作</h3>
                </div>
                <Badge tone="muted">{recentDocuments.length}</Badge>
              </div>
              <div className="narrative-start-recent-list">
                {recentDocuments.map((document) => (
                  <button
                    key={document.documentKey}
                    type="button"
                    className="narrative-start-recent-card"
                    onClick={() => activateDocument(document.documentKey)}
                  >
                    <div className="narrative-start-recent-copy">
                      <strong>{document.meta.title || document.meta.slug}</strong>
                      <span>{document.relativePath}</span>
                    </div>
                    <Badge tone="muted">{docTypeLabel(document.meta.docType)}</Badge>
                  </button>
                ))}
              </div>
            </section>
          ) : null}

          <section className="narrative-start-section">
            <div className="narrative-start-section-header">
              <div>
                <span className="section-label">模板</span>
                <h3 className="panel-title">创建新的叙事文档</h3>
              </div>
              <Badge tone="accent">{docTypeLabel(targetDocType)}</Badge>
            </div>
            <div className="narrative-template-grid">
              {workspace.docTypes.map((entry) => (
                <button
                  key={entry.value}
                  type="button"
                  className={`narrative-template-card ${
                    targetDocType === entry.value ? "narrative-template-card-active" : ""
                  }`.trim()}
                  onClick={() => {
                    setTargetDocType(entry.value);
                    void createDraft(entry.value);
                  }}
                  disabled={busy || !hasActiveWorkspace}
                >
                  <div className="narrative-template-card-copy">
                    <strong>{entry.label}</strong>
                    <p>{docTypeSummary(entry.value)}</p>
                  </div>
                  <div className="narrative-template-card-meta">
                    <Badge tone={targetDocType === entry.value ? "accent" : "muted"}>
                      {entry.directory}
                    </Badge>
                    <span>单击即可创建</span>
                  </div>
                </button>
              ))}
            </div>
          </section>
        </div>
      )}
    </div>
  );

  const overlays = (
    <>
      {templatePickerVisible ? (
        <div className="narrative-overlay">
          <div className="narrative-overlay-backdrop" onClick={() => setTemplatePickerVisible(false)} />
          <div className="narrative-overlay-panel narrative-overlay-panel-wide">
            <div className="narrative-workbench-panel-header">
              <div>
                <span className="section-label">新建文档</span>
                <h3 className="panel-title">选择叙事模板</h3>
              </div>
              <Badge tone="accent">{docTypeLabel(targetDocType)}</Badge>
            </div>
            <input
              className="field-input"
              type="text"
              value={templatePickerQuery}
              onChange={(event) => setTemplatePickerQuery(event.target.value)}
              placeholder="按标题、ID 或目录筛选模板"
              autoFocus
            />
            <div className="narrative-overlay-body narrative-scroll">
              <div className="narrative-template-grid">
                {templatePickerEntries.map(({ entry, docCount }) => (
                  <button
                    key={entry.value}
                    type="button"
                    className={`narrative-template-card ${
                      targetDocType === entry.value ? "narrative-template-card-active" : ""
                    }`.trim()}
                    onClick={() => void createDraftFromTemplate(entry.value)}
                    disabled={busy || !hasActiveWorkspace}
                  >
                    <div className="narrative-template-card-copy">
                      <strong>{entry.label}</strong>
                      <p>{docTypeSummary(entry.value)}</p>
                    </div>
                    <div className="narrative-template-card-meta">
                      <Badge tone={docCount > 0 ? "muted" : "accent"}>
                        {docCount > 0 ? `${docCount} 个现有` : "全新"}
                      </Badge>
                      <span>{entry.directory}</span>
                    </div>
                  </button>
                ))}
              </div>
              {!templatePickerEntries.length ? (
                <div className="workspace-empty settings-empty-inline">
                  <p>没有模板符合当前筛选条件。</p>
                </div>
              ) : null}
            </div>
          </div>
        </div>
      ) : null}

      {quickOpenVisible ? (
        <div className="narrative-overlay">
          <div className="narrative-overlay-backdrop" onClick={() => setQuickOpenVisible(false)} />
          <div className="narrative-overlay-panel">
            <div className="narrative-workbench-panel-header">
              <div>
                <span className="section-label">快速打开</span>
                <h3 className="panel-title">跳转到文档</h3>
              </div>
              <Badge tone="muted">{quickOpenResults.length}</Badge>
            </div>
            <input
              className="field-input"
              type="text"
              value={topbarQuery}
              onChange={(event) => setTopbarQuery(event.target.value)}
              placeholder="输入标题、slug 或路径"
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
                  <p>没有匹配的文档。</p>
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
                <span className="section-label">命令面板</span>
                <h3 className="panel-title">执行工作台命令</h3>
              </div>
              <Badge tone="muted">{commandPaletteEntries.length}</Badge>
            </div>
            <input
              className="field-input"
              type="text"
              value={commandPaletteQuery}
              onChange={(event) => setCommandPaletteQuery(event.target.value)}
              placeholder="搜索命令"
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
                  {entry.recentIndex !== -1 ? <Badge tone="accent">最近</Badge> : null}
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
      title="叙事实验室"
      workspaceLabel={workspace.workspaceRoot || "未选择工作区"}
      runtimeLabel={runtimeLabel}
      topbarSearchValue={topbarQuery}
      topbarSearchPlaceholder="按标题、slug 或路径快速打开"
      onTopbarSearchChange={(value) => {
        openQuickOpenPanel(value);
      }}
      onOpenQuickOpen={() => openQuickOpenPanel()}
      onOpenCommandPalette={() => openCommandPalettePanel()}
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
      rightSidebarVisible={workbenchLayout.rightSidebarVisible && rightSidebarHasContext}
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
          <button type="button" className="toolbar-button toolbar-accent" onClick={() => openTemplatePicker(targetDocType)}>
            <span className="toolbar-button-main">新建</span>
            <span className="toolbar-button-hint">Ctrl+N</span>
          </button>
          <button type="button" className="toolbar-button" onClick={() => void saveAll()} disabled={busy || dirtyCount === 0}>
            <span className="toolbar-button-main">保存</span>
            <span className="toolbar-button-hint">Ctrl+S</span>
          </button>
          <button type="button" className="toolbar-button" onClick={() => void runGeneration()} disabled={busy || !hasActiveWorkspace}>
            运行 AI
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
            {workbenchLayout.zenMode ? "退出专注" : "专注"}
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
