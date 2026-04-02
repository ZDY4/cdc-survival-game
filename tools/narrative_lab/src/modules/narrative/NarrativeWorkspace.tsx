import { type CSSProperties, useEffect, useMemo, useRef, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { Badge } from "../../components/Badge";
import { openOrFocusSettingsWindow } from "../../lib/editorWindows";
import { invokeCommand, isTauriRuntime } from "../../lib/tauri";
import {
  dispatchEditorMenuCommand,
  useRegisterEditorMenuCommands,
} from "../../menu/editorCommandRegistry";
import { EDITOR_MENU_COMMANDS } from "../../menu/menuCommands";
import type {
  AgentActionResult,
  AgentOption,
  AgentPlanStep,
  AgentQuestion,
  AiChatMessage,
  DocumentAgentSession,
  EditorMenuSelfTestScenario,
  NarrativeAppSettings,
  NarrativeDocType,
  NarrativeDocumentPayload,
  NarrativeRegressionCase,
  NarrativeRegressionSuiteResult,
  NarrativeDocumentViewMode,
  NarrativeGenerateRequest,
  NarrativeGenerationProgressEvent,
  NarrativeGenerateResponse,
  NarrativeTurnKind,
  NarrativeReviewQueueItem,
  NarrativeDocumentSummary,
  NarrativeSessionExportInput,
  NarrativeSessionExportResult,
  NarrativeWorkspaceLayout,
  NarrativeWorkspacePayload,
  SaveNarrativeDocumentResult,
} from "../../types";
import {
  applyNarrativePatch,
  buildNarrativePatchSet,
  normalizeNarrativeMarkdown,
  splitNarrativeMarkdownBlocks,
} from "./narrativePatches";
import {
  closeNarrativeTab,
  createDocumentAgentSession,
  ensureDocumentAgentSession,
  openNarrativeTab,
  updateDocumentAgentSession,
  type NarrativeTabState,
} from "./narrativeSessions";
import {
  buildReviewQueue,
  buildVersionSnapshot,
  buildWorkspaceAgentState,
  defaultNarrativeAgentStrategy,
  fromPersistedSessionState,
  getWorkspacePersistedAgentState,
  nowIso,
  snapshotBranch,
} from "./narrativeAgentState";
import {
  defaultNarrativeMarkdown,
  defaultNarrativeTitle,
  docTypeDirectory,
  docTypeLabel,
} from "./narrativeTemplates";

type EditableNarrativeDocument = NarrativeDocumentPayload & {
  savedSnapshot: string;
  dirty: boolean;
  isDraft: boolean;
};

type NarrativeDocContextMenuState = {
  documentKey: string;
  x: number;
  y: number;
};

type NarrativeWorkspaceProps = {
  workspace: NarrativeWorkspacePayload;
  appSettings: NarrativeAppSettings;
  canPersist: boolean;
  startupReady: boolean;
  selfTestScenario: EditorMenuSelfTestScenario | null;
  status: string;
  onStatusChange: (status: string) => void;
  onReload: () => Promise<void>;
  onOpenWorkspace: (workspaceRoot: string) => Promise<void>;
  onConnectProject: (projectRoot: string | null) => Promise<void>;
  onSaveAppSettings: (settings: NarrativeAppSettings) => Promise<NarrativeAppSettings>;
};

const DEFAULT_CHAT_PANEL_WIDTH = 440;
const MIN_CHAT_PANEL_WIDTH = 320;
const MAX_CHAT_PANEL_WIDTH = 720;
const MIN_DOCUMENT_PANEL_WIDTH = 360;
const PANEL_SPLITTER_WIDTH = 12;
const NARRATIVE_GENERATION_PROGRESS_EVENT = "narrative:generation-progress";
const NARRATIVE_REGRESSION_CASES: NarrativeRegressionCase[] = [
  {
    id: "clarification-missing-brief",
    label: "缺少核心信息时先提问",
    prompt: "我要写一个新篇章，但你先别动笔，先告诉我还缺哪些必要信息。",
    expectedTurnKinds: ["clarification", "options"],
  },
  {
    id: "options-branching",
    label: "有分叉时给方向",
    prompt: "基于当前文稿先给我三个截然不同的推进方向，不要直接改正文。",
    expectedTurnKinds: ["options", "plan"],
  },
  {
    id: "plan-complex-task",
    label: "复杂任务先给计划",
    prompt: "把当前文稿拆成一个分步骤执行计划，等我确认后再继续。",
    expectedTurnKinds: ["plan"],
  },
  {
    id: "final-answer-polish",
    label: "明确改写时直接产出",
    prompt: "在保持设定一致的前提下润色当前文稿，并直接给我可保存版本。",
    expectedTurnKinds: ["final_answer"],
  },
];

function snapshotDocument(document: NarrativeDocumentPayload) {
  return JSON.stringify({
    meta: document.meta,
    markdown: document.markdown,
  });
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

function defaultWorkspaceLayout(
  activeDocumentKey: string | null,
  openDocumentKeys: string[],
  leftSidebarVisible: boolean,
  chatPanelWidth = DEFAULT_CHAT_PANEL_WIDTH,
): NarrativeWorkspaceLayout {
  return {
    version: 2,
    leftSidebarVisible,
    leftSidebarWidth: 280,
    chatPanelWidth,
    leftSidebarView: "explorer",
    rightSidebarVisible: false,
    rightSidebarWidth: 320,
    rightSidebarView: "inspector",
    bottomPanelVisible: false,
    bottomPanelHeight: 220,
    bottomPanelView: "problems",
    openDocumentKeys,
    activeDocumentKey,
    zenMode: false,
  };
}

function buildNarrativeChatPrompt(
  input: string,
  history: AiChatMessage[],
  selectedDocument: EditableNarrativeDocument | null,
  pendingTurnContext?: string,
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

  if (pendingTurnContext?.trim()) {
    sections.push(pendingTurnContext.trim());
  }

  sections.push(`本次请求：${input.trim()}`);
  return sections.join("\n\n");
}

function extractDraftPreview(markdown: string, maxLength = 220) {
  const lines = markdown
    .replace(/\r/g, "")
    .split("\n")
    .map((line) => line.trim())
    .filter(
      (line) =>
        Boolean(line) &&
        line !== "---" &&
        line !== "***" &&
        !/^```/.test(line),
    );

  if (!lines.length) {
    return "";
  }

  const preview = lines
    .slice(0, 3)
    .join(" ")
    .replace(/^#{1,6}\s*/g, "")
    .replace(/\*\*(.*?)\*\*/g, "$1")
    .replace(/__(.*?)__/g, "$1")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\[([^\]]+)\]\([^)]+\)/g, "$1")
    .replace(/!\[[^\]]*\]\([^)]+\)/g, "")
    .replace(/[>*_~]/g, "")
    .replace(/\s+/g, " ")
    .trim();

  if (!preview) {
    return "";
  }

  if (preview.length <= maxLength) {
    return preview;
  }

  return `${preview.slice(0, maxLength).trimEnd()}...`;
}

function headlineNeedsDraftPreview(headline: string) {
  const trimmed = headline.trim();
  if (!trimmed) {
    return true;
  }

  return (
    /(?:如下|如下所示|如下内容|如下建议)(?:[：:]?)$/.test(trimmed) ||
    /(?:依据|建议|结果|内容|说明|分析)(?:[：:])$/.test(trimmed) ||
    trimmed === "AI 已返回结果。"
  );
}

function summarizeResponseForChat(response: {
  turnKind: NarrativeTurnKind;
  assistantMessage: string;
  draftMarkdown: string;
  providerError: string;
  summary: string;
  synthesisNotes: string[];
  questions: AgentQuestion[];
  options: AgentOption[];
  planSteps: AgentPlanStep[];
}) {
  const headline =
    response.providerError.trim() ||
    response.assistantMessage.trim() ||
    response.summary.trim() ||
    "AI 已返回结果。";
  const sections = [headline];

  if (!response.providerError.trim()) {
    if (response.turnKind === "clarification" && response.questions.length) {
      sections.push(
        [
          "还需要你补充这些信息：",
          ...response.questions.map(
            (question, index) => `${index + 1}. ${question.label}${question.required ? "（必填）" : ""}`,
          ),
        ].join("\n"),
      );
    }

    if (response.turnKind === "options" && response.options.length) {
      sections.push(
        [
          "我整理了这些可继续推进的方向：",
          ...response.options.map((option, index) =>
            [
              `${index + 1}. **${option.label}**`,
              option.description.trim() ? `   ${option.description.trim()}` : "",
            ]
              .filter(Boolean)
              .join("\n"),
          ),
        ].join("\n"),
      );
    }

    if (response.turnKind === "plan" && response.planSteps.length) {
      sections.push(
        [
          "建议按这个计划继续：",
          ...response.planSteps.map(
            (step, index) => `${index + 1}. ${step.label}${step.status === "completed" ? "（已完成）" : ""}`,
          ),
        ].join("\n"),
      );
    }
  }

  const notes = response.synthesisNotes.map((note) => note.trim()).filter(Boolean).slice(0, 2);
  if (notes.length) {
    sections.push(["补充说明：", ...notes.map((note) => `- ${note}`)].join("\n"));
  }
  const draftPreview = extractDraftPreview(response.draftMarkdown);
  const shouldAppendDraftPreview =
    !response.providerError.trim() &&
    response.turnKind === "final_answer" &&
    Boolean(response.draftMarkdown.trim()) &&
    (headlineNeedsDraftPreview(headline) || sections.join(" ").trim().length < 80);

  if (shouldAppendDraftPreview) {
    sections.push(
      draftPreview
        ? `内容预览：${draftPreview}`
        : "已生成具体内容，请查看右侧文档预览与建议区域。",
    );
  }

  return sections.join("\n\n");
}

function buildStrategyInstruction(session: DocumentAgentSession) {
  const intensityLabel =
    session.strategy.rewriteIntensity === "light"
      ? "保守改写"
      : session.strategy.rewriteIntensity === "aggressive"
        ? "激进重构"
        : "平衡改写";
  const priorityLabel =
    session.strategy.priority === "drama"
      ? "优先戏剧性"
      : session.strategy.priority === "speed"
        ? "优先速度"
        : "优先一致性";
  const questionLabel =
    session.strategy.questionBehavior === "ask_first"
      ? "信息不足时先提问"
      : session.strategy.questionBehavior === "direct"
        ? "尽量直接产出"
        : "先判断再决定是否提问";
  return [intensityLabel, priorityLabel, questionLabel].join("；");
}

function mergeRelatedDocSlugs(
  activeDocument: EditableNarrativeDocument,
  selectedContextDocuments: EditableNarrativeDocument[],
) {
  const slugs = [...activeDocument.meta.relatedDocs];
  for (const document of selectedContextDocuments) {
    if (!slugs.includes(document.meta.slug)) {
      slugs.push(document.meta.slug);
    }
  }
  return slugs;
}

function buildPendingTurnContext(session: DocumentAgentSession) {
  if (session.pendingQuestions.length) {
    return [
      "上一轮 AI 正在等待这些补充信息：",
      ...session.pendingQuestions.map((question, index) => `${index + 1}. ${question.label}`),
    ].join("\n");
  }

  if (session.pendingOptions.length) {
    return [
      "上一轮 AI 给出的候选方向：",
      ...session.pendingOptions.map((option, index) => `${index + 1}. ${option.label}：${option.description}`),
    ].join("\n");
  }

  if (session.pendingTurnKind === "plan" && session.lastPlan?.length) {
    return [
      "上一轮 AI 提出的执行计划：",
      ...session.lastPlan.map((step, index) => `${index + 1}. ${step.label}`),
      "如果本轮用户表示继续、确认或补充约束，应基于这个计划继续执行。",
    ].join("\n");
  }

  return "";
}

function responseMetaLabels(response: NarrativeGenerateResponse) {
  const turnLabelLookup: Record<NarrativeGenerateResponse["turnKind"], string> = {
    final_answer: "已生成结果",
    clarification: "等待补充",
    options: "等待选择",
    plan: "等待确认计划",
    blocked: "暂时阻塞",
  };

  return [
    response.providerError ? "提供方返回错误" : turnLabelLookup[response.turnKind],
    response.engineMode === "single_agent" ? "单文档助手" : "多 agent",
  ];
}

function assistantMessageIdForRequest(requestId: string) {
  return `assistant-${requestId}`;
}

function replaceChatMessage(
  messages: AiChatMessage[],
  messageId: string,
  nextMessage: AiChatMessage,
) {
  let replaced = false;
  const nextMessages = messages.map((message) => {
    if (message.id !== messageId) {
      return message;
    }
    replaced = true;
    return nextMessage;
  });

  return replaced ? nextMessages : [...nextMessages, nextMessage];
}

function upsertExecutionStep(
  steps: DocumentAgentSession["executionSteps"],
  event: NarrativeGenerationProgressEvent,
) {
  if (!event.stepId || !event.stepLabel || !event.stepStatus) {
    return steps;
  }

  const nextStep = {
    id: event.stepId,
    label: event.stepLabel,
    detail: event.status,
    status: event.stepStatus,
    previewText: event.previewText,
  };
  const existingIndex = steps.findIndex((step) => step.id === event.stepId);
  if (existingIndex === -1) {
    return [...steps, nextStep];
  }

  const nextSteps = [...steps];
  nextSteps[existingIndex] = nextStep;
  return nextSteps;
}

function sessionStatusFromProgress(event: NarrativeGenerationProgressEvent): DocumentAgentSession["status"] {
  if (event.stage === "error") {
    return "error";
  }
  if (event.stepId === "review-result") {
    return event.stepStatus === "completed" ? "completed" : "reviewing_result";
  }
  if (event.stepId) {
    return "executing_step";
  }
  return "thinking";
}

function actionHistoryMessage(result: AgentActionResult) {
  const lines = [result.summary];
  if (result.documentSummaries?.length) {
    lines.push(
      `涉及文稿：${result.documentSummaries
        .map((document) => document.title || document.slug)
        .join("、")}`,
    );
  }
  if (result.document?.meta.title) {
    lines.push(`目标文稿：${result.document.meta.title}`);
  }
  return lines.join("\n");
}

function extractTitleFromMarkdown(markdown: string, fallback: string) {
  const heading = markdown
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find((line) => line.startsWith("# "));
  return heading ? heading.replace(/^#\s+/, "").trim() || fallback : fallback;
}

function buildLocalDraft(
  docType: NarrativeDocType,
  title: string,
  markdown: string,
): EditableNarrativeDocument {
  const stamp = Date.now();
  const slug = `draft-${stamp}`;
  const document: NarrativeDocumentPayload = {
    documentKey: slug,
    originalSlug: slug,
    fileName: `${slug}.md`,
    relativePath: `narrative/${docTypeDirectory(docType)}/${slug}.md`,
    meta: {
      docType,
      slug,
      title,
      status: "draft",
      tags: [],
      relatedDocs: [],
      sourceRefs: [],
    },
    markdown,
    validation: [],
  };

  return {
    ...document,
    savedSnapshot: "",
    dirty: true,
    isDraft: true,
  };
}

function summarizeNarrativeDocumentPayload(
  document: NarrativeDocumentPayload,
): NarrativeDocumentSummary {
  const headings = document.markdown
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith("#"))
    .map((line) => line.replace(/^#+\s*/, "").trim())
    .filter(Boolean);
  const excerpt = document.markdown
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find((line) => line && !line.startsWith("#"))
    ?.slice(0, 120) ?? "";
  return {
    slug: document.meta.slug,
    title: document.meta.title,
    headingCount: headings.length,
    headings,
    excerpt,
  };
}

function toEditableSavedDocument(document: NarrativeDocumentPayload): EditableNarrativeDocument {
  const savedSnapshot = snapshotDocument(document);
  return {
    ...document,
    savedSnapshot,
    dirty: false,
    isDraft: false,
  };
}

function resolveInitialTabs(
  workspace: NarrativeWorkspacePayload,
  appSettings: NarrativeAppSettings,
  documents: EditableNarrativeDocument[],
): {
  tabState: NarrativeTabState;
  leftSidebarCollapsed: boolean;
  chatPanelWidth: number;
  layoutSnapshot: string;
} {
  const layout = workspace.workspaceRoot
    ? appSettings.workspaceLayouts?.[workspace.workspaceRoot]
    : undefined;
  const validKeys = new Set(documents.map((document) => document.documentKey));
  const openDocumentKeys = (layout?.openDocumentKeys ?? []).filter((documentKey) =>
    validKeys.has(documentKey),
  );

  if (!openDocumentKeys.length && documents[0]) {
    openDocumentKeys.push(documents[0].documentKey);
  }

  const activeDocumentKey =
    layout?.activeDocumentKey && validKeys.has(layout.activeDocumentKey)
      ? layout.activeDocumentKey
      : openDocumentKeys[0] ?? null;
  const persistedLayout = defaultWorkspaceLayout(
    activeDocumentKey,
    openDocumentKeys,
    layout?.leftSidebarVisible ?? true,
    layout?.chatPanelWidth ?? DEFAULT_CHAT_PANEL_WIDTH,
  );

  return {
    tabState: {
      openTabs: openDocumentKeys,
      activeTabKey: activeDocumentKey,
    },
    leftSidebarCollapsed: persistedLayout.leftSidebarVisible === false,
    chatPanelWidth: persistedLayout.chatPanelWidth,
    layoutSnapshot: JSON.stringify(persistedLayout),
  };
}

function restorePersistedDocumentSessions(
  appSettings: NarrativeAppSettings,
  workspace: NarrativeWorkspacePayload,
  documentKeys: Set<string>,
) {
  const persisted = getWorkspacePersistedAgentState(appSettings, workspace.workspaceRoot);
  if (!persisted) {
    return {};
  }

  return Object.fromEntries(
    Object.entries(persisted.sessions)
      .filter(([documentKey]) => documentKeys.has(documentKey))
      .map(([documentKey, snapshot]) => [
        documentKey,
        fromPersistedSessionState(snapshot, []),
      ]),
  ) as Record<string, DocumentAgentSession>;
}

function summarizeReviewQueue(queue: NarrativeReviewQueueItem[]) {
  if (!queue.length) {
    return "当前没有待审项。";
  }
  return queue.map((item) => `${item.title}：${item.description}`).join("\n");
}

function compactPathLabel(path: string | null | undefined) {
  if (!path?.trim()) {
    return "未选择工作区";
  }

  const normalized = path.replace(/\\/g, "/");
  const parts = normalized.split("/").filter(Boolean);
  if (parts.length <= 2) {
    return parts.join(" / ") || path;
  }
  return parts.slice(-2).join(" / ");
}

function clampChatPanelWidth(width: number, containerWidth: number) {
  const maxWidth = Math.min(
    MAX_CHAT_PANEL_WIDTH,
    Math.max(
      MIN_CHAT_PANEL_WIDTH,
      containerWidth - PANEL_SPLITTER_WIDTH - MIN_DOCUMENT_PANEL_WIDTH,
    ),
  );
  return Math.min(Math.max(width, MIN_CHAT_PANEL_WIDTH), maxWidth);
}

function MarkdownBlock({ markdown }: { markdown: string }) {
  return (
    <div className="narrative-markdown-block">
      <ReactMarkdown remarkPlugins={[remarkGfm]}>{markdown}</ReactMarkdown>
    </div>
  );
}

function ChatMessageContent({ message }: { message: AiChatMessage }) {
  if (message.role === "assistant" || message.role === "context") {
    return (
      <div className="narrative-chat-markdown">
        <ReactMarkdown remarkPlugins={[remarkGfm]}>{message.content}</ReactMarkdown>
      </div>
    );
  }

  return <p style={{ whiteSpace: "pre-wrap" }}>{message.content}</p>;
}

export function NarrativeWorkspace({
  workspace,
  appSettings,
  canPersist,
  startupReady,
  selfTestScenario: _selfTestScenario,
  status,
  onStatusChange,
  onReload,
  onOpenWorkspace: _onOpenWorkspace,
  onConnectProject: _onConnectProject,
  onSaveAppSettings,
}: NarrativeWorkspaceProps) {
  const [documents, setDocuments] = useState<EditableNarrativeDocument[]>(
    hydrateDocuments(workspace.documents),
  );
  const [tabState, setTabState] = useState<NarrativeTabState>({
    openTabs: workspace.documents[0] ? [workspace.documents[0].documentKey] : [],
    activeTabKey: workspace.documents[0]?.documentKey ?? null,
  });
  const [documentAgents, setDocumentAgents] = useState<Record<string, DocumentAgentSession>>({});
  const [leftSidebarCollapsed, setLeftSidebarCollapsed] = useState(false);
  const [chatPanelWidth, setChatPanelWidth] = useState(DEFAULT_CHAT_PANEL_WIDTH);
  const [searchQuery, setSearchQuery] = useState("");
  const [saving, setSaving] = useState(false);
  const [pendingRestoreSessions, setPendingRestoreSessions] = useState<
    Record<string, DocumentAgentSession> | null
  >(null);
  const [restoreStatus, setRestoreStatus] = useState("");
  const [showAdvancedPanel, setShowAdvancedPanel] = useState(false);
  const [docContextMenu, setDocContextMenu] = useState<NarrativeDocContextMenuState | null>(null);
  const [regressionStatus, setRegressionStatus] = useState("");
  const [regressionResult, setRegressionResult] = useState<NarrativeRegressionSuiteResult | null>(
    null,
  );
  const [exportStatus, setExportStatus] = useState("");
  const editorRef = useRef<HTMLTextAreaElement | null>(null);
  const editorPanelsRef = useRef<HTMLDivElement | null>(null);
  const isResizingPanelsRef = useRef(false);
  const documentsRef = useRef<EditableNarrativeDocument[]>(documents);
  const documentAgentsRef = useRef<Record<string, DocumentAgentSession>>(documentAgents);
  const tabStateRef = useRef<NarrativeTabState>(tabState);
  const workspaceRootRef = useRef("");
  const layoutSnapshotRef = useRef("");
  const agentSnapshotRef = useRef("");

  useEffect(() => {
    documentsRef.current = documents;
  }, [documents]);

  useEffect(() => {
    documentAgentsRef.current = documentAgents;
  }, [documentAgents]);

  useEffect(() => {
    tabStateRef.current = tabState;
  }, [tabState]);

  useEffect(() => {
    const nextDocuments = hydrateDocuments(workspace.documents);
    const initial = resolveInitialTabs(workspace, appSettings, nextDocuments);
    const validDocumentKeys = new Set(nextDocuments.map((document) => document.documentKey));
    const restoredSessions = restorePersistedDocumentSessions(
      appSettings,
      workspace,
      validDocumentKeys,
    );
    const hasRestorableSessions = Object.keys(restoredSessions).length > 0;

    setDocuments(nextDocuments);
    setTabState(initial.tabState);
    setLeftSidebarCollapsed(initial.leftSidebarCollapsed);
    setChatPanelWidth(initial.chatPanelWidth);
    layoutSnapshotRef.current = initial.layoutSnapshot;
    agentSnapshotRef.current = JSON.stringify(buildWorkspaceAgentState(restoredSessions));
    setDocumentAgents((current) => {
      const shouldRestore = appSettings.sessionRestoreMode === "always";
      const baseSessions =
        workspaceRootRef.current === workspace.workspaceRoot
          ? current
          : shouldRestore
            ? restoredSessions
            : {};
      const nextSessions = { ...baseSessions };
      for (const documentKey of initial.tabState.openTabs) {
        if (!nextSessions[documentKey]) {
          nextSessions[documentKey] = createDocumentAgentSession();
        }
      }
      return nextSessions;
    });
    setPendingRestoreSessions(
      appSettings.sessionRestoreMode === "ask" && hasRestorableSessions ? restoredSessions : null,
    );
    setRestoreStatus(
      hasRestorableSessions
        ? `检测到 ${Object.keys(restoredSessions).length} 个可恢复的 agent 会话。`
        : "",
    );
    workspaceRootRef.current = workspace.workspaceRoot;
  }, [workspace]);

  useEffect(() => {
    const handlePointerMove = (event: PointerEvent) => {
      if (!isResizingPanelsRef.current || !editorPanelsRef.current) {
        return;
      }

      const bounds = editorPanelsRef.current.getBoundingClientRect();
      setChatPanelWidth(clampChatPanelWidth(event.clientX - bounds.left, bounds.width));
    };

    const stopResizing = () => {
      if (!isResizingPanelsRef.current) {
        return;
      }

      isResizingPanelsRef.current = false;
      document.body.style.cursor = "";
      document.body.style.userSelect = "";
    };

    window.addEventListener("pointermove", handlePointerMove);
    window.addEventListener("pointerup", stopResizing);
    window.addEventListener("pointercancel", stopResizing);

    return () => {
      window.removeEventListener("pointermove", handlePointerMove);
      window.removeEventListener("pointerup", stopResizing);
      window.removeEventListener("pointercancel", stopResizing);
      stopResizing();
    };
  }, []);

  useEffect(() => {
    const activeTabKey = tabState.activeTabKey;
    if (!activeTabKey) {
      return;
    }

    setDocumentAgents((current) => ensureDocumentAgentSession(current, activeTabKey));
  }, [tabState.activeTabKey]);

  useEffect(() => {
    if (!docContextMenu) {
      return;
    }

    const closeMenu = () => {
      setDocContextMenu(null);
    };
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        closeMenu();
      }
    };

    window.addEventListener("pointerdown", closeMenu);
    window.addEventListener("blur", closeMenu);
    window.addEventListener("resize", closeMenu);
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      window.removeEventListener("pointerdown", closeMenu);
      window.removeEventListener("blur", closeMenu);
      window.removeEventListener("resize", closeMenu);
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [docContextMenu]);

  useEffect(() => {
    if (!isTauriRuntime()) {
      return;
    }

    let unlisten: (() => void) | undefined;
    void getCurrentWindow()
      .listen<NarrativeGenerationProgressEvent>(
        NARRATIVE_GENERATION_PROGRESS_EVENT,
        (event) => {
          const payload = event.payload;
          const assistantMessageId = assistantMessageIdForRequest(payload.requestId);

          setDocumentAgents((current) => {
            let nextSessions = current;
            let matched = false;

            for (const [documentKey, session] of Object.entries(current)) {
              if (session.inflightRequestId !== payload.requestId) {
                continue;
              }

              matched = true;
              nextSessions = updateDocumentAgentSession(nextSessions, documentKey, (currentSession) => ({
                ...currentSession,
                status: sessionStatusFromProgress(payload),
                executionSteps: upsertExecutionStep(currentSession.executionSteps, payload),
                currentStepId: payload.stepStatus === "completed" ? currentSession.currentStepId : payload.stepId ?? currentSession.currentStepId,
                chatMessages: replaceChatMessage(currentSession.chatMessages, assistantMessageId, {
                  id: assistantMessageId,
                  role: "assistant",
                  label: "AI",
                  content: payload.previewText,
                  meta: [payload.status],
                  tone: payload.stage === "error" ? "danger" : "muted",
                }),
              }));
            }

            return matched ? nextSessions : current;
          });

          onStatusChange(payload.status);
        },
      )
      .then((dispose) => {
        unlisten = dispose;
      });

    return () => {
      unlisten?.();
    };
  }, [onStatusChange]);

  useEffect(() => {
    if (!canPersist || !workspace.workspaceRoot.trim()) {
      return;
    }

    const persistedLayout = defaultWorkspaceLayout(
      tabState.activeTabKey,
      tabState.openTabs,
      !leftSidebarCollapsed,
      chatPanelWidth,
    );
    const serialized = JSON.stringify(persistedLayout);
    if (serialized === layoutSnapshotRef.current) {
      return;
    }

    const timeout = window.setTimeout(() => {
      void onSaveAppSettings({
        ...appSettings,
        workspaceLayouts: {
          ...(appSettings.workspaceLayouts ?? {}),
          [workspace.workspaceRoot]: persistedLayout,
        },
      })
        .then(() => {
          layoutSnapshotRef.current = serialized;
        })
        .catch((error) => {
          onStatusChange(`保存 Narrative Lab 布局失败：${String(error)}`);
        });
    }, 220);

    return () => {
      window.clearTimeout(timeout);
    };
  }, [
    appSettings,
    canPersist,
    chatPanelWidth,
    leftSidebarCollapsed,
    onSaveAppSettings,
    onStatusChange,
    tabState.activeTabKey,
    tabState.openTabs,
    workspace.workspaceRoot,
  ]);

  useEffect(() => {
    if (!canPersist || !workspace.workspaceRoot.trim()) {
      return;
    }

    const persistedAgentState = buildWorkspaceAgentState(documentAgents);
    const serialized = JSON.stringify(persistedAgentState);
    if (serialized === agentSnapshotRef.current) {
      return;
    }

    const timeout = window.setTimeout(() => {
      void onSaveAppSettings({
        ...appSettings,
        workspaceAgentSessions: {
          ...(appSettings.workspaceAgentSessions ?? {}),
          [workspace.workspaceRoot]: persistedAgentState,
        },
      })
        .then(() => {
          agentSnapshotRef.current = serialized;
        })
        .catch((error) => {
          onStatusChange(`保存 Narrative Lab agent 会话失败：${String(error)}`);
        });
    }, 260);

    return () => {
      window.clearTimeout(timeout);
    };
  }, [
    appSettings,
    canPersist,
    documentAgents,
    onSaveAppSettings,
    onStatusChange,
    workspace.workspaceRoot,
  ]);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      const modifier = event.ctrlKey || event.metaKey;
      if (!modifier) {
        return;
      }

      if (event.key.toLowerCase() === "s" && !event.shiftKey) {
        event.preventDefault();
        void dispatchEditorMenuCommand(EDITOR_MENU_COMMANDS.FILE_SAVE_ALL);
        return;
      }

      if (event.key.toLowerCase() === "n" && !event.shiftKey) {
        event.preventDefault();
        void dispatchEditorMenuCommand(EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT);
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
  }, []);

  const activeDocument = useMemo(
    () =>
      tabState.activeTabKey
        ? documents.find((document) => document.documentKey === tabState.activeTabKey) ?? null
        : null,
    [documents, tabState.activeTabKey],
  );
  const activeSession = activeDocument
    ? documentAgents[activeDocument.documentKey] ?? createDocumentAgentSession()
    : null;
  const pendingQuestions = activeSession?.pendingQuestions ?? [];
  const pendingOptions = activeSession?.pendingOptions ?? [];
  const pendingActions = activeSession?.pendingActionRequests ?? [];
  const activeReviewQueue = activeSession?.reviewQueue ?? [];
  const latestPlan = activeSession?.lastPlan ?? [];
  const latestTurnKind = activeSession?.lastResponse?.turnKind ?? null;
  const workspaceLabel = compactPathLabel(workspace.workspaceRoot);
  const selectedContextDocuments = useMemo(() => {
    if (!activeSession) {
      return [];
    }

    const documentMap = new Map(
      documents.map((document) => [document.documentKey, document] as const),
    );

    return activeSession.selectedContextDocKeys
      .filter((documentKey) => documentKey !== activeDocument?.documentKey)
      .map((documentKey) => documentMap.get(documentKey) ?? null)
      .filter(Boolean) as EditableNarrativeDocument[];
  }, [activeDocument?.documentKey, activeSession, documents]);
  const docContextMenuTarget = docContextMenu ? getDocument(docContextMenu.documentKey) : null;
  const canAddContextFromMenu = Boolean(
    activeDocument &&
      activeSession &&
      docContextMenuTarget &&
      docContextMenuTarget.documentKey !== activeDocument.documentKey &&
      !activeSession.selectedContextDocKeys.includes(docContextMenuTarget.documentKey),
  );
  const contextMenuAddLabel =
    !activeDocument || !activeSession
      ? "请先打开一个 AI 会话文档"
      : !docContextMenuTarget
        ? "文档不可用"
        : docContextMenuTarget.documentKey === activeDocument.documentKey
          ? "当前主文档已默认包含"
          : activeSession.selectedContextDocKeys.includes(docContextMenuTarget.documentKey)
            ? "已添加到当前对话上下文"
            : "添加当前对话上下文";
  const hasAdvancedPanelContent = Boolean(
    activeSession &&
      (activeSession.savedBranches.length ||
        activeReviewQueue.length ||
        regressionStatus ||
        regressionResult ||
        activeSession.lastResponse ||
        activeSession.executionSteps.length ||
        activeSession.actionHistory.length ||
        activeSession.versionHistory.length ||
        activeSession.pendingDerivedDocuments.length ||
        pendingActions.length),
  );
  const composerPlaceholder =
    activeSession?.status === "waiting_user" && pendingQuestions.length
      ? pendingQuestions[0]?.placeholder?.trim() || "先回答上面的问题，我会继续推进。"
      : activeSession?.status === "waiting_user" && pendingOptions.length
        ? "也可以直接点上面的方向按钮，或补充你想要的版本。"
        : activeSession?.status === "waiting_user" && activeSession.pendingTurnKind === "plan"
          ? "如果认可这个计划，可以直接回复“继续”或补充新的约束。"
        : "像聊天一样告诉 AI 你的修改或新文档需求。Enter 发送，Shift+Enter 换行。";
  const filteredDocuments = useMemo(() => {
    const query = searchQuery.trim().toLowerCase();
    if (!query) {
      return documents;
    }

    return documents.filter((document) => {
      const haystack = [
        document.meta.title,
        document.meta.slug,
        document.relativePath,
        document.meta.tags.join(" "),
      ]
        .join(" ")
        .toLowerCase();
      return haystack.includes(query);
    });
  }, [documents, searchQuery]);
  const dirtyCount = documents.filter((document) => document.dirty).length;
  const editorPanelsStyle = useMemo(
    () =>
      ({
        "--narrative-chat-panel-width": `${chatPanelWidth}px`,
      }) as CSSProperties,
    [chatPanelWidth],
  );

  function getDocument(documentKey: string) {
    return documentsRef.current.find((document) => document.documentKey === documentKey) ?? null;
  }

  function defaultDocType(): NarrativeDocType {
    return (
      activeDocument?.meta.docType ??
      workspace.docTypes.find((entry) => entry.value === "task_setup")?.value ??
      workspace.docTypes.find((entry) => entry.value === "location_note")?.value ??
      workspace.docTypes[0]?.value ??
      "task_setup"
    );
  }

  function remapDocumentKey(oldKey: string, nextDocument: EditableNarrativeDocument) {
    if (oldKey === nextDocument.documentKey) {
      return;
    }

    setTabState((current) => ({
      openTabs: current.openTabs.map((documentKey) =>
        documentKey === oldKey ? nextDocument.documentKey : documentKey,
      ),
      activeTabKey:
        current.activeTabKey === oldKey ? nextDocument.documentKey : current.activeTabKey,
    }));
    setDocumentAgents((current) => {
      const session = current[oldKey];
      if (!session) {
        return current;
      }

      const next = {
        ...current,
        [nextDocument.documentKey]: session,
      };
      delete next[oldKey];
      return next;
    });
  }

  function openDocument(documentKey: string) {
    setDocContextMenu(null);
    setTabState((current) => openNarrativeTab(current, documentKey));
    setDocumentAgents((current) => ensureDocumentAgentSession(current, documentKey));
  }

  function restorePersistedAgentSessions() {
    if (!pendingRestoreSessions) {
      return;
    }
    setDocumentAgents((current) => {
      const next = { ...current };
      for (const [documentKey, session] of Object.entries(pendingRestoreSessions)) {
        next[documentKey] = {
          ...session,
          busy: false,
          inflightRequestId: null,
          reviewQueue: buildReviewQueue(session),
        };
      }
      return next;
    });
    setPendingRestoreSessions(null);
    setRestoreStatus("已恢复上次 Narrative Lab agent 会话。");
    onStatusChange("已恢复上次 Narrative Lab agent 会话。");
  }

  function skipPersistedAgentSessions() {
    setPendingRestoreSessions(null);
    setRestoreStatus("本次仅恢复文档，不恢复 AI 会话。");
    onStatusChange("本次仅恢复文档，不恢复 AI 会话。");
  }

  function addContextDocument(documentKey: string) {
    if (!activeDocument) {
      onStatusChange("请先打开一个 AI 会话文档。");
      return;
    }
    if (documentKey === activeDocument.documentKey) {
      onStatusChange("当前主文档已经默认参与会话，不需要重复添加。");
      return;
    }

    const targetDocument = getDocument(documentKey);
    if (!targetDocument) {
      onStatusChange("要添加的上下文文档不存在。");
      return;
    }

    let added = false;
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        if (session.selectedContextDocKeys.includes(documentKey)) {
          return session;
        }

        added = true;
        const nextSession = {
          ...session,
          selectedContextDocKeys: [...session.selectedContextDocKeys, documentKey],
          updatedAt: nowIso(),
        };
        return {
          ...nextSession,
          reviewQueue: buildReviewQueue(nextSession),
        };
      }),
    );

    setDocContextMenu(null);
    onStatusChange(
      added
        ? `已将《${targetDocument.meta.title || targetDocument.meta.slug}》添加到当前对话上下文。`
        : `《${targetDocument.meta.title || targetDocument.meta.slug}》已在当前对话上下文中。`,
    );
  }

  function removeContextDocument(documentKey: string) {
    if (!activeDocument) {
      return;
    }

    const targetDocument = getDocument(documentKey);
    let removed = false;
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        if (!session.selectedContextDocKeys.includes(documentKey)) {
          return session;
        }

        removed = true;
        const nextSession = {
          ...session,
          selectedContextDocKeys: session.selectedContextDocKeys.filter(
            (entry) => entry !== documentKey,
          ),
          updatedAt: nowIso(),
        };
        return {
          ...nextSession,
          reviewQueue: buildReviewQueue(nextSession),
        };
      }),
    );

    if (removed && targetDocument) {
      onStatusChange(`已将《${targetDocument.meta.title || targetDocument.meta.slug}》移出当前对话上下文。`);
    }
  }

  function updateActiveStrategy(
    key: keyof DocumentAgentSession["strategy"],
    value: DocumentAgentSession["strategy"][typeof key],
  ) {
    if (!activeDocument) {
      return;
    }
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => ({
        ...session,
        updatedAt: nowIso(),
        strategy: {
          ...session.strategy,
          [key]: value,
        },
      })),
    );
  }

  function renameCurrentSession() {
    if (!activeDocument || !activeSession) {
      return;
    }
    const nextTitle = window.prompt("输入当前会话名称", activeSession.sessionTitle)?.trim();
    if (!nextTitle) {
      return;
    }
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => ({
        ...session,
        sessionTitle: nextTitle,
        updatedAt: nowIso(),
      })),
    );
    onStatusChange(`已将当前会话重命名为《${nextTitle}》。`);
  }

  function forkCurrentSession() {
    if (!activeDocument || !activeSession) {
      return;
    }
    const baseTitle = activeSession.sessionTitle || "当前会话";
    const nextTitle =
      window.prompt("输入新分支会话名称", `${baseTitle} 分支`)?.trim() || `${baseTitle} 分支`;
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        const savedBranch = snapshotBranch(session, session.sessionTitle, false);
        const nextSession = {
          ...session,
          sessionId: `${session.sessionId}-fork-${Date.now()}`,
          sessionTitle: nextTitle,
          branchOfSessionId: session.sessionId,
          updatedAt: nowIso(),
          savedBranches: [...session.savedBranches, savedBranch],
        };
        return {
          ...nextSession,
          reviewQueue: buildReviewQueue(nextSession),
        };
      }),
    );
    onStatusChange(`已基于当前会话创建分支《${nextTitle}》。`);
  }

  function archiveCurrentSession() {
    if (!activeDocument || !activeSession) {
      return;
    }
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        const archivedBranch = snapshotBranch(session, session.sessionTitle, true);
        return createDocumentAgentSession({
          mode: session.mode,
          documentViewMode: session.documentViewMode,
          savedBranches: [...session.savedBranches, archivedBranch],
        });
      }),
    );
    onStatusChange("已归档当前会话，并为该文档开启一条新的空白会话。");
  }

  function restoreSavedBranch(branchId: string) {
    if (!activeDocument || !activeSession) {
      return;
    }
    const branch = activeSession.savedBranches.find((entry) => entry.id === branchId);
    if (!branch) {
      return;
    }
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        const nextSession = {
          ...fromPersistedSessionState(branch.snapshot, session.savedBranches),
          sessionTitle: branch.title,
          updatedAt: nowIso(),
          savedBranches: session.savedBranches,
        };
        return {
          ...nextSession,
          reviewQueue: buildReviewQueue(nextSession),
        };
      }),
    );
    onStatusChange(`已恢复会话分支《${branch.title}》。`);
  }

  function clearPendingActionRequests() {
    if (!activeDocument) {
      return;
    }
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        const nextSession = {
          ...session,
          pendingActionRequests: [],
          updatedAt: nowIso(),
        };
        return {
          ...nextSession,
          reviewQueue: buildReviewQueue(nextSession),
        };
      }),
    );
    onStatusChange("已清空待批准动作。");
  }

  async function retryLastTurn() {
    if (!activeSession) {
      return;
    }
    const lastUserMessage = [...activeSession.chatMessages]
      .reverse()
      .find((message) => message.role === "user");
    if (!lastUserMessage) {
      onStatusChange("当前没有可重试的上一轮用户输入。");
      return;
    }
    await runGeneration(lastUserMessage.content);
  }

  async function retryCurrentStep() {
    await retryLastTurn();
  }

  async function approveAllPendingActions() {
    if (!activeSession?.pendingActionRequests.length) {
      return;
    }
    for (const action of [...activeSession.pendingActionRequests]) {
      // eslint-disable-next-line no-await-in-loop
      await approveActionRequest(action.id);
    }
  }

  function rejectAllPendingActions() {
    if (!activeSession?.pendingActionRequests.length) {
      return;
    }
    for (const action of [...activeSession.pendingActionRequests]) {
      rejectActionRequest(action.id);
    }
  }

  async function runRegressionSuite() {
    if (!activeDocument || !activeSession) {
      onStatusChange("请先打开一个文档，再运行 Narrative Lab 回归验证。");
      return;
    }

    setRegressionResult(null);
    setRegressionStatus("正在运行 Narrative Lab 行为回归验证...");
    const relatedDocSlugs = mergeRelatedDocSlugs(activeDocument, selectedContextDocuments);
    const results: NarrativeRegressionSuiteResult["results"] = [];

    try {
      for (const caseItem of NARRATIVE_REGRESSION_CASES) {
        const request: NarrativeGenerateRequest = {
          requestId: `regression-${caseItem.id}-${Date.now()}`,
          docType: activeDocument.meta.docType,
          targetSlug: activeDocument.meta.slug,
          action: "revise_document",
          userPrompt: buildNarrativeChatPrompt(
            caseItem.prompt,
            [],
            activeDocument,
            `回归验证要求：仅判断最合适的 turn_kind，避免受历史对话干扰。`,
          ),
          editorInstruction: `Regression suite\n${buildStrategyInstruction(activeSession)}`,
          currentMarkdown: activeDocument.markdown,
          relatedDocSlugs: relatedDocSlugs,
          derivedTargetDocType: null,
        };
        // eslint-disable-next-line no-await-in-loop
        const response = await invokeCommand<NarrativeGenerateResponse>(
          "revise_narrative_draft",
          {
            workspaceRoot: workspace.workspaceRoot,
            projectRoot: workspace.connectedProjectRoot ?? null,
            request,
          },
        );
        results.push({
          id: caseItem.id,
          label: caseItem.label,
          expectedTurnKinds: caseItem.expectedTurnKinds,
          actualTurnKind: response.turnKind,
          ok: caseItem.expectedTurnKinds.includes(response.turnKind),
          summary:
            response.summary.trim() ||
            response.assistantMessage.trim() ||
            response.providerError.trim() ||
            "无摘要",
        });
      }

      const ok = results.every((item) => item.ok);
      const summary = ok
        ? `回归验证通过，共 ${results.length} 项。`
        : `回归验证发现 ${results.filter((item) => !item.ok).length} 项漂移。`;
      setRegressionResult({ ok, results, summary });
      setRegressionStatus(summary);
      onStatusChange(summary);
    } catch (error) {
      const message = `运行 Narrative Lab 回归验证失败：${String(error)}`;
      setRegressionStatus(message);
      onStatusChange(message);
    }
  }

  async function exportCurrentSession() {
    if (!activeDocument || !activeSession) {
      onStatusChange("请先打开一个文档，再导出 Narrative Lab 会话。");
      return;
    }

    const input: NarrativeSessionExportInput = {
      sessionId: activeSession.sessionId,
      sessionTitle: activeSession.sessionTitle || "当前会话",
      workspaceName: workspace.workspaceName,
      activeDocument,
      selectedContextDocuments,
      strategySummary: buildStrategyInstruction(activeSession),
      latestTurnKind: activeSession.lastResponse?.turnKind ?? null,
      latestSummary:
        activeSession.lastResponse?.summary ||
        activeSession.lastResponse?.assistantMessage ||
        "",
      latestDraftMarkdown: activeSession.lastResponse?.draftMarkdown ?? "",
      sourceDocumentKeys: activeSession.lastResponse?.sourceDocumentKeys ?? [activeDocument.meta.slug],
      provenanceRefs: activeSession.lastResponse?.provenanceRefs ?? [],
      planSteps: latestPlan.map((step) => `${step.label} [${step.status}]`),
      reviewQueue: activeReviewQueue.map(
        (item) => `${item.title} [${item.kind} / ${item.status}] ${item.description}`,
      ),
      pendingActions: pendingActions.map(
        (action) =>
          `${action.title} [${action.actionType}${action.previewOnly ? " / preview" : ""}] ${
            action.description
          }`,
      ),
      actionHistory: activeSession.actionHistory.map(
        (result) => `${result.status} / ${result.actionType}: ${result.summary}`,
      ),
      versionHistory: activeSession.versionHistory.map(
        (snapshot) => `${snapshot.createdAt} ${snapshot.title}: ${snapshot.summary}`,
      ),
      recentMessages: activeSession.chatMessages
        .slice(-12)
        .map((message) => `${message.label}(${message.role}): ${message.content}`),
    };

    try {
      const result = await invokeCommand<NarrativeSessionExportResult>(
        "export_narrative_session_summary",
        {
          workspaceRoot: workspace.workspaceRoot,
          input,
        },
      );
      setExportStatus(`${result.summary} ${result.exportPath}`);
      onStatusChange(`${result.summary} ${result.exportPath}`);
    } catch (error) {
      const message = `导出 Narrative Lab 会话失败：${String(error)}`;
      setExportStatus(message);
      onStatusChange(message);
    }
  }

  function reviewDerivedDocument(slug: string) {
    const document = documentsRef.current.find((entry) => entry.meta.slug === slug);
    if (!document) {
      onStatusChange(`未找到待审派生文稿：${slug}`);
      return;
    }
    openDocument(document.documentKey);
    onStatusChange(`已打开派生文稿《${document.meta.title || document.meta.slug}》进行回看。`);
  }

  function markDerivedDocumentQueueItem(
    slug: string,
    outcome: "approved" | "rejected",
  ) {
    if (!activeDocument) {
      return;
    }
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        const target = session.pendingDerivedDocuments.find((item) => item.slug === slug);
        if (!target) {
          return session;
        }
        const tone: AiChatMessage["tone"] =
          outcome === "approved" ? "success" : "warning";
        const nextSession = {
          ...session,
          updatedAt: nowIso(),
          pendingDerivedDocuments: session.pendingDerivedDocuments.filter((item) => item.slug !== slug),
          chatMessages: [
            ...session.chatMessages,
            {
              id: `context-derived-${outcome}-${slug}-${Date.now()}`,
              role: "context" as const,
              label: "系统",
                content:
                  outcome === "approved"
                    ? `已将派生文稿《${target.title || target.slug}》标记为已审阅。`
                    : `已将派生文稿《${target.title || target.slug}》从待审列表移除。`,
                tone,
              },
            ],
          };
        return {
          ...nextSession,
          reviewQueue: buildReviewQueue(nextSession),
        };
      }),
    );
    onStatusChange(
      outcome === "approved"
        ? `已完成派生文稿 ${slug} 的审阅。`
        : `已将派生文稿 ${slug} 从待审列表移除。`,
    );
  }

  function reviewNextDerivedDocument() {
    const nextSlug = activeSession?.pendingDerivedDocuments[0]?.slug;
    if (!nextSlug) {
      onStatusChange("当前没有待回看的派生文稿。");
      return;
    }
    reviewDerivedDocument(nextSlug);
  }

  function approveAllDerivedDocuments() {
    if (!activeDocument || !activeSession?.pendingDerivedDocuments.length) {
      return;
    }
    const count = activeSession.pendingDerivedDocuments.length;
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        const nextSession = {
          ...session,
          updatedAt: nowIso(),
          pendingDerivedDocuments: [],
          chatMessages: [
            ...session.chatMessages,
            {
              id: `context-derived-approved-all-${Date.now()}`,
              role: "context" as const,
              label: "系统",
              content: `已批量完成 ${count} 份派生文稿的审阅。`,
              tone: "success" as const,
            },
          ],
        };
        return {
          ...nextSession,
          reviewQueue: buildReviewQueue(nextSession),
        };
      }),
    );
    onStatusChange(`已批量完成 ${count} 份派生文稿的审阅。`);
  }

  function rejectAllDerivedDocuments() {
    if (!activeDocument || !activeSession?.pendingDerivedDocuments.length) {
      return;
    }
    const count = activeSession.pendingDerivedDocuments.length;
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        const nextSession = {
          ...session,
          updatedAt: nowIso(),
          pendingDerivedDocuments: [],
          chatMessages: [
            ...session.chatMessages,
            {
              id: `context-derived-rejected-all-${Date.now()}`,
              role: "context" as const,
              label: "系统",
              content: `已将 ${count} 份派生文稿从待审列表移除，文稿本身仍保留在工作区。`,
              tone: "warning" as const,
            },
          ],
        };
        return {
          ...nextSession,
          reviewQueue: buildReviewQueue(nextSession),
        };
      }),
    );
    onStatusChange(`已将 ${count} 份派生文稿从待审列表移除。`);
  }

  function cycleTabs(direction: 1 | -1) {
    if (!tabStateRef.current.openTabs.length) {
      return;
    }

    const currentIndex = tabStateRef.current.openTabs.indexOf(tabStateRef.current.activeTabKey ?? "");
    const nextIndex =
      currentIndex === -1
        ? 0
        : (currentIndex + direction + tabStateRef.current.openTabs.length) %
          tabStateRef.current.openTabs.length;
    setTabState((current) => ({
      ...current,
      activeTabKey: current.openTabs[nextIndex] ?? null,
    }));
  }

  function closeTab(documentKey: string) {
    setDocContextMenu(null);
    const document = getDocument(documentKey);
    if (!document) {
      return;
    }
    if (document.dirty) {
      const confirmed = window.confirm(
        `《${document.meta.title || document.meta.slug}》有未保存修改。要放弃这些修改并关闭标签页吗？`,
      );
      if (!confirmed) {
        onStatusChange(`已取消关闭《${document.meta.title || document.meta.slug}》。`);
        return;
      }

      if (document.isDraft) {
        setDocuments((current) =>
          current.filter((entry) => entry.documentKey !== document.documentKey),
        );
        setDocumentAgents((current) => {
          const next = { ...current };
          delete next[document.documentKey];
          return next;
        });
        setTabState((current) => closeNarrativeTab(current, document.documentKey));
        onStatusChange(`已放弃本地草稿《${document.meta.title || document.meta.slug}》并关闭标签页。`);
        return;
      }

      const restoredSnapshot = JSON.parse(document.savedSnapshot) as Pick<
        NarrativeDocumentPayload,
        "meta" | "markdown"
      >;
      setDocuments((current) =>
        current.map((entry) => {
          if (entry.documentKey !== document.documentKey) {
            return entry;
          }
          return {
            ...entry,
            meta: restoredSnapshot.meta,
            markdown: restoredSnapshot.markdown,
            dirty: false,
          };
        }),
      );
      invalidateSuggestions(document.documentKey);
      setTabState((current) => closeNarrativeTab(current, document.documentKey));
      onStatusChange(`已放弃《${document.meta.title || document.meta.slug}》的未保存修改并关闭标签页。`);
      return;
    }

    setTabState((current) => closeNarrativeTab(current, documentKey));
  }

  async function deleteDocumentByKey(documentKey: string) {
    const document = getDocument(documentKey);
    if (!document) {
      onStatusChange("未找到要删除的文档。");
      return;
    }

    setDocContextMenu(null);

    if (document.isDraft) {
      setDocuments((current) =>
        current.filter((entry) => entry.documentKey !== document.documentKey),
      );
      setDocumentAgents((current) => {
        const next = { ...current };
        delete next[document.documentKey];
        return next;
      });
      setTabState((current) => closeNarrativeTab(current, document.documentKey));
      onStatusChange(`已移除本地草稿 ${document.meta.title || document.meta.slug}。`);
      return;
    }

    if (!canPersist) {
      onStatusChange("当前运行在回退模式，无法删除文档。");
      return;
    }

    try {
      await invokeCommand("delete_narrative_document", {
        workspaceRoot: workspace.workspaceRoot,
        slug: document.meta.slug,
      });
      setDocuments((current) =>
        current.filter((entry) => entry.documentKey !== document.documentKey),
      );
      setDocumentAgents((current) => {
        const next = { ...current };
        delete next[document.documentKey];
        return next;
      });
      setTabState((current) => closeNarrativeTab(current, document.documentKey));
      onStatusChange(`已删除文档 ${document.meta.title || document.meta.slug}。`);
    } catch (error) {
      onStatusChange(`删除文档失败：${String(error)}`);
    }
  }

  async function openDocumentFolder(documentKey: string) {
    const document = getDocument(documentKey);
    if (!document) {
      onStatusChange("未找到要打开文件夹的文档。");
      return;
    }

    setDocContextMenu(null);

    if (document.isDraft) {
      onStatusChange("本地草稿尚未保存到磁盘，暂时没有可打开的文件夹。");
      return;
    }

    if (!canPersist || !workspace.workspaceRoot.trim()) {
      onStatusChange("当前运行在回退模式，无法打开文档所在文件夹。");
      return;
    }

    try {
      await invokeCommand("open_narrative_document_folder", {
        workspaceRoot: workspace.workspaceRoot,
        slug: document.meta.slug,
      });
      onStatusChange(`已打开《${document.meta.title || document.meta.slug}》所在文件夹。`);
    } catch (error) {
      onStatusChange(`打开所在文件夹失败：${String(error)}`);
    }
  }

  function beginPanelResize(event: React.PointerEvent<HTMLButtonElement>) {
    if (!editorPanelsRef.current || window.innerWidth <= 900) {
      return;
    }

    event.preventDefault();
    isResizingPanelsRef.current = true;
    document.body.style.cursor = "col-resize";
    document.body.style.userSelect = "none";

    const bounds = editorPanelsRef.current.getBoundingClientRect();
    setChatPanelWidth(clampChatPanelWidth(event.clientX - bounds.left, bounds.width));
  }

  function resetPanelWidth() {
    if (!editorPanelsRef.current) {
      setChatPanelWidth(DEFAULT_CHAT_PANEL_WIDTH);
      return;
    }

    const bounds = editorPanelsRef.current.getBoundingClientRect();
    setChatPanelWidth(clampChatPanelWidth(DEFAULT_CHAT_PANEL_WIDTH, bounds.width));
  }

  function updateDocumentState(
    documentKey: string,
    transform: (document: EditableNarrativeDocument) => EditableNarrativeDocument,
  ) {
    setDocuments((current) =>
      current.map((document) => {
        if (document.documentKey !== documentKey) {
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

  function invalidateSuggestions(documentKey: string) {
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, documentKey, (session) => ({
        ...session,
        candidatePatchSet: null,
      })),
    );
  }

  async function createTypedDraft(docType: NarrativeDocType) {
    const title = defaultNarrativeTitle(docType);

    if (canPersist && workspace.workspaceRoot.trim()) {
      const created = await invokeCommand<NarrativeDocumentPayload>("create_narrative_document", {
        workspaceRoot: workspace.workspaceRoot,
        input: {
          docType,
          title,
        },
      });
      const draft = {
        ...created,
        savedSnapshot: "",
        dirty: true,
        isDraft: true,
      } satisfies EditableNarrativeDocument;

      setDocuments((current) => [draft, ...current]);
      openDocument(draft.documentKey);
      setDocumentAgents((current) =>
        ensureDocumentAgentSession(current, draft.documentKey, "edit"),
      );
      onStatusChange(`已新建${docTypeLabel(docType)}。`);
      return;
    }

    const draft = buildLocalDraft(
      docType,
      title,
      defaultNarrativeMarkdown(docType, title),
    );
    setDocuments((current) => [draft, ...current]);
    openDocument(draft.documentKey);
    setDocumentAgents((current) =>
      ensureDocumentAgentSession(current, draft.documentKey, "edit"),
    );
    onStatusChange(`已创建本地${docTypeLabel(docType)}草稿。`);
  }

  function createBlankDocument() {
    void createTypedDraft(defaultDocType());
  }

  async function saveDocument(documentKey: string) {
    const document = getDocument(documentKey);
    if (!document || !document.dirty) {
      return;
    }
    if (!canPersist) {
      onStatusChange("当前运行在回退模式，无法保存文档。");
      return;
    }
    if (!workspace.workspaceRoot.trim()) {
      onStatusChange("请先配置叙事工作区，再保存文档。");
      return;
    }

    const result = await invokeCommand<SaveNarrativeDocumentResult>("save_narrative_document", {
      workspaceRoot: workspace.workspaceRoot,
      input: {
        originalSlug: document.isDraft ? null : document.originalSlug,
        document,
      },
    });

    const savedSlug = result.savedSlug;
    const nextDocument: EditableNarrativeDocument = {
      ...document,
      documentKey: savedSlug,
      originalSlug: savedSlug,
      fileName: `${savedSlug}.md`,
      relativePath: `narrative/${docTypeDirectory(document.meta.docType)}/${savedSlug}.md`,
      meta: {
        ...document.meta,
        slug: savedSlug,
      },
      dirty: false,
      isDraft: false,
      savedSnapshot: "",
    };
    nextDocument.savedSnapshot = snapshotDocument(nextDocument);

    setDocuments((current) =>
      current.map((entry) => (entry.documentKey === documentKey ? nextDocument : entry)),
    );
    remapDocumentKey(documentKey, nextDocument);
  }

  async function saveAll() {
    const dirtyDocuments = documentsRef.current.filter((document) => document.dirty);
    if (!dirtyDocuments.length) {
      onStatusChange("当前没有未保存的文档。");
      return;
    }

    setSaving(true);
    try {
      for (const document of dirtyDocuments) {
        await saveDocument(document.documentKey);
      }
      onStatusChange(`已保存 ${dirtyDocuments.length} 份文档。`);
    } catch (error) {
      onStatusChange(`保存文档失败：${String(error)}`);
    } finally {
      setSaving(false);
    }
  }

  async function deleteCurrentDocument() {
    if (!activeDocument) {
      onStatusChange("请先打开一个文档标签。");
      return;
    }
    await deleteDocumentByKey(activeDocument.documentKey);
  }

  async function runGeneration(promptOverride?: string) {
    if (!activeDocument || !tabState.activeTabKey || !activeSession) {
      onStatusChange("请先打开一个文档标签，再和 AI 协作。");
      return;
    }

    const submittedPrompt = (promptOverride ?? activeSession.composerText).trim();
    if (!submittedPrompt) {
      onStatusChange("请输入本轮要告诉 AI 的内容。");
      return;
    }

    const activeDocumentKey = activeDocument.documentKey;
    const action = activeSession.mode;
    const relatedDocSlugs = mergeRelatedDocSlugs(activeDocument, selectedContextDocuments);
    const requestId = `generation-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const assistantMessageId = assistantMessageIdForRequest(requestId);
    const userMessage: AiChatMessage = {
      id: `user-${Date.now()}`,
      role: "user",
      label: "你",
      content: submittedPrompt,
      meta: [
        activeSession.status === "waiting_user"
          ? "补充上一轮信息"
          : action === "create"
            ? "生成新文档"
            : "修改当前文档",
      ],
      tone: "accent",
    };

    const request: NarrativeGenerateRequest = {
      requestId,
      docType: activeDocument.meta.docType,
      targetSlug:
        action === "create"
          ? `${activeDocument.meta.slug}-ai-${Date.now()}`
          : activeDocument.meta.slug,
      action,
      userPrompt: buildNarrativeChatPrompt(
        submittedPrompt,
        activeSession.chatMessages,
        activeDocument,
        buildPendingTurnContext(activeSession),
      ),
      editorInstruction: [
        `Agent strategy: ${buildStrategyInstruction(activeSession)}`,
        selectedContextDocuments.length
          ? `Selected context docs: ${selectedContextDocuments
              .map((document) => document.meta.slug)
              .join(", ")}`
          : "",
      ]
        .filter(Boolean)
        .join("\n"),
      currentMarkdown: activeDocument.markdown,
      relatedDocSlugs,
      derivedTargetDocType: null,
    };

    setDocumentAgents((current) =>
        updateDocumentAgentSession(current, activeDocumentKey, (session) => ({
          ...session,
          updatedAt: nowIso(),
          status: "thinking",
          executionSteps: [],
          currentStepId: null,
        busy: true,
        inflightRequestId: requestId,
        composerText: "",
        chatMessages: [
          ...session.chatMessages,
          userMessage,
          {
            id: assistantMessageId,
            role: "assistant",
            label: "AI",
            content: "正在准备生成内容...",
            meta: ["正在准备请求"],
            tone: "muted",
          },
        ],
      })),
    );

    try {
      const command =
        action === "create" ? "generate_narrative_draft" : "revise_narrative_draft";
      const narrativeResponse = await invokeCommand<NarrativeGenerateResponse>(command, {
        workspaceRoot: workspace.workspaceRoot,
        projectRoot: workspace.connectedProjectRoot ?? null,
        request,
      });

      const assistantMessage: AiChatMessage = {
        id: assistantMessageId,
        role: "assistant",
        label: "AI",
        content: summarizeResponseForChat(narrativeResponse),
        meta: responseMetaLabels(narrativeResponse),
        tone: narrativeResponse.providerError ? "danger" : "success",
      };

      if (
        narrativeResponse.turnKind === "final_answer" &&
        action === "create" &&
        narrativeResponse.draftMarkdown.trim() &&
        !narrativeResponse.providerError.trim()
      ) {
        const newTitle = extractTitleFromMarkdown(
          narrativeResponse.draftMarkdown,
          `${activeDocument.meta.title} AI 草稿`,
        );
        const draftDocument = buildLocalDraft(
          activeDocument.meta.docType,
          newTitle,
          narrativeResponse.draftMarkdown,
        );

        setDocuments((current) => [draftDocument, ...current]);
        setTabState((current) => openNarrativeTab(current, draftDocument.documentKey));
        setDocumentAgents((current) => {
          const nextStatus: DocumentAgentSession["status"] = narrativeResponse.requiresUserReply
            ? "waiting_user"
            : "completed";
          const next = updateDocumentAgentSession(current, activeDocumentKey, (session) => ({
            ...session,
            updatedAt: nowIso(),
            status: nextStatus,
            busy: false,
            inflightRequestId: null,
            lastRequest: request,
            lastResponse: narrativeResponse,
            candidatePatchSet: null,
            pendingQuestions: narrativeResponse.questions,
            pendingOptions: narrativeResponse.options,
            lastPlan: narrativeResponse.planSteps.length ? narrativeResponse.planSteps : session.lastPlan,
            pendingTurnKind: narrativeResponse.requiresUserReply ? narrativeResponse.turnKind : null,
            executionSteps: narrativeResponse.executionSteps,
            currentStepId: narrativeResponse.currentStepId ?? null,
            pendingActionRequests: narrativeResponse.requestedActions,
            chatMessages: [
              ...replaceChatMessage(session.chatMessages, assistantMessageId, assistantMessage),
              {
                id: `context-${Date.now()}`,
                role: "context" as const,
                label: "系统",
                content: `已为当前会话生成新文档《${newTitle}》。`,
                tone: "success" as const,
              },
            ],
          }));
          next[activeDocumentKey] = {
            ...next[activeDocumentKey],
            reviewQueue: buildReviewQueue(next[activeDocumentKey]),
          };

          next[draftDocument.documentKey] = {
            ...createDocumentAgentSession(),
            mode: "revise_document",
            updatedAt: nowIso(),
            sessionTitle: `来自 ${activeDocument.meta.title || activeDocument.meta.slug} 的派生会话`,
            chatMessages: [
              {
                id: `seed-${Date.now()}`,
                role: "context",
                label: "系统",
                content: `该文档由《${activeDocument.meta.title || activeDocument.meta.slug}》会话生成。`,
                tone: "muted",
              },
              userMessage,
              assistantMessage,
            ],
            lastRequest: request,
            lastResponse: narrativeResponse,
            candidatePatchSet: null,
            status: "idle" as const,
            pendingQuestions: [],
            pendingOptions: [],
            lastPlan: narrativeResponse.planSteps,
            pendingTurnKind: null,
            executionSteps: narrativeResponse.executionSteps,
            currentStepId: narrativeResponse.currentStepId ?? null,
            pendingActionRequests: narrativeResponse.requestedActions,
            reviewQueue: narrativeResponse.reviewQueueItems,
            selectedContextDocKeys: [activeDocument.documentKey],
            busy: false,
            inflightRequestId: null,
            documentViewMode: "preview" as const,
            composerText: "",
          } as DocumentAgentSession;
          next[draftDocument.documentKey] = {
            ...next[draftDocument.documentKey],
            reviewQueue: buildReviewQueue(next[draftDocument.documentKey]),
          };
          return next;
        });
        onStatusChange(`AI 已生成新文档《${newTitle}》，已打开新标签页。`);
        return;
      }

      const hasChanges =
        narrativeResponse.turnKind === "final_answer" &&
        !narrativeResponse.providerError.trim() &&
        normalizeNarrativeMarkdown(activeDocument.markdown) !==
          normalizeNarrativeMarkdown(narrativeResponse.draftMarkdown);
      const patchSet = hasChanges
        ? buildNarrativePatchSet(activeDocument.markdown, narrativeResponse.draftMarkdown)
        : null;

      setDocumentAgents((current) =>
        updateDocumentAgentSession(current, activeDocumentKey, (session) => {
          const nextStatus: DocumentAgentSession["status"] = narrativeResponse.requiresUserReply
            ? "waiting_user"
            : "completed";
          const nextSession: DocumentAgentSession = {
            ...session,
            updatedAt: nowIso(),
            status: nextStatus,
            busy: false,
            inflightRequestId: null,
            lastRequest: request,
            lastResponse: narrativeResponse,
            candidatePatchSet: patchSet,
            pendingQuestions: narrativeResponse.questions,
            pendingOptions: narrativeResponse.options,
            lastPlan: narrativeResponse.planSteps.length ? narrativeResponse.planSteps : session.lastPlan,
            pendingTurnKind: narrativeResponse.requiresUserReply ? narrativeResponse.turnKind : null,
            executionSteps: narrativeResponse.executionSteps,
            currentStepId: narrativeResponse.currentStepId ?? null,
            pendingActionRequests: narrativeResponse.requestedActions,
            documentViewMode: "preview",
            versionHistory:
              narrativeResponse.turnKind === "final_answer" &&
              patchSet &&
              !narrativeResponse.providerError.trim()
                ? [
                    buildVersionSnapshot(
                      activeDocument.markdown,
                      narrativeResponse.draftMarkdown,
                      narrativeResponse.summary || narrativeResponse.assistantMessage,
                      requestId,
                    ),
                    ...session.versionHistory,
                  ].slice(0, 12)
                : session.versionHistory,
            chatMessages: replaceChatMessage(session.chatMessages, assistantMessageId, assistantMessage),
          };
          return {
            ...nextSession,
            reviewQueue: buildReviewQueue(nextSession),
          };
        }),
      );
      onStatusChange(
        narrativeResponse.providerError ||
          narrativeResponse.assistantMessage ||
          narrativeResponse.summary ||
          "AI 已生成文档修改建议。",
      );
    } catch (error) {
      setDocumentAgents((current) =>
        updateDocumentAgentSession(current, activeDocumentKey, (session) => ({
          ...session,
          updatedAt: nowIso(),
          status: "error",
          busy: false,
          inflightRequestId: null,
          chatMessages: replaceChatMessage(session.chatMessages, assistantMessageId, {
            id: assistantMessageId,
            role: "assistant",
            label: "AI",
            content: `本次执行失败：${String(error)}`,
            meta: ["请检查 AI 设置、工作区路径或网络连接。"],
            tone: "danger",
          }),
        })),
      );
      onStatusChange(`AI 执行失败：${String(error)}`);
    }
  }

  function applyPatch(patchId: string) {
    if (!activeDocument || !activeSession?.candidatePatchSet || !activeSession.lastResponse) {
      return;
    }

    const patch = activeSession.candidatePatchSet.patches.find((entry) => entry.id === patchId);
    if (!patch) {
      return;
    }

    const nextMarkdown = applyNarrativePatch(activeDocument.markdown, patch);
    updateDocumentState(activeDocument.documentKey, (document) => ({
      ...document,
      markdown: nextMarkdown,
    }));

    const nextPatchSet = buildNarrativePatchSet(
      nextMarkdown,
      activeSession.lastResponse.draftMarkdown,
    );
    const isComplete =
      normalizeNarrativeMarkdown(nextMarkdown) ===
      normalizeNarrativeMarkdown(activeSession.lastResponse.draftMarkdown);

    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        const nextSession = {
          ...session,
          updatedAt: nowIso(),
          candidatePatchSet: isComplete ? null : nextPatchSet,
          chatMessages: [
            ...session.chatMessages,
            {
              id: `context-apply-${Date.now()}`,
              role: "context" as const,
              label: "系统",
              content: `已应用 ${patch.title}。`,
              tone: "success" as const,
            },
          ],
        };
        return {
          ...nextSession,
          reviewQueue: buildReviewQueue(nextSession),
        };
      }),
    );
    onStatusChange(`已应用 ${patch.title}。`);
  }

  function applyAllSuggestions() {
    if (!activeDocument || !activeSession?.lastResponse?.draftMarkdown.trim()) {
      return;
    }

    updateDocumentState(activeDocument.documentKey, (document) => ({
      ...document,
      markdown: activeSession.lastResponse?.draftMarkdown ?? document.markdown,
    }));
    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        const nextSession = {
          ...session,
          updatedAt: nowIso(),
          candidatePatchSet: null,
          chatMessages: [
            ...session.chatMessages,
            {
              id: `context-apply-all-${Date.now()}`,
              role: "context" as const,
              label: "系统",
              content: "已应用整篇 AI 建议。",
              tone: "success" as const,
            },
          ],
        };
        return {
          ...nextSession,
          reviewQueue: buildReviewQueue(nextSession),
        };
      }),
    );
    onStatusChange("已应用整篇 AI 建议。");
  }

  function discardCurrentSuggestions() {
    if (!activeDocument) {
      return;
    }

    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        const nextSession = {
          ...session,
          updatedAt: nowIso(),
          candidatePatchSet: null,
          chatMessages: [
            ...session.chatMessages,
            {
              id: `context-discard-suggestions-${Date.now()}`,
              role: "context" as const,
              label: "系统",
              content: "已清空当前 patch 建议。",
              tone: "warning" as const,
            },
          ],
        };
        return {
          ...nextSession,
          reviewQueue: buildReviewQueue(nextSession),
        };
      }),
    );
    onStatusChange("已清空当前 patch 建议。");
  }

  function applyAgentDocumentResult(result: AgentActionResult, requestId: string) {
    const derivedSummaries: NarrativeDocumentSummary[] = [];
    if (result.document) {
      derivedSummaries.push(summarizeNarrativeDocumentPayload(result.document));
    }
    if (result.documentSummaries?.length) {
      for (const summary of result.documentSummaries) {
        if (!derivedSummaries.some((entry) => entry.slug === summary.slug)) {
          derivedSummaries.push(summary);
        }
      }
    }

    if (derivedSummaries.length && activeDocument) {
      setDocumentAgents((current) =>
        updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
          const nextSession = {
            ...session,
            updatedAt: nowIso(),
            pendingDerivedDocuments: [
              ...session.pendingDerivedDocuments,
              ...derivedSummaries.filter(
                (summary) =>
                  !session.pendingDerivedDocuments.some((entry) => entry.slug === summary.slug),
              ),
            ],
          };
          return {
            ...nextSession,
            reviewQueue: buildReviewQueue(nextSession),
          };
        }),
      );
    }

    if (!result.document) {
      return;
    }

    const nextDocument = toEditableSavedDocument(result.document);
    const existing = documentsRef.current.find(
      (document) =>
        document.documentKey === nextDocument.documentKey ||
        document.originalSlug === nextDocument.originalSlug,
    );

    setDocuments((current) => {
      if (existing) {
        return current.map((document) =>
          document.documentKey === existing.documentKey ? nextDocument : document,
        );
      }
      return [nextDocument, ...current];
    });

    if (existing && existing.documentKey !== nextDocument.documentKey) {
      remapDocumentKey(existing.documentKey, nextDocument);
    } else {
      setDocumentAgents((current) =>
        ensureDocumentAgentSession(current, nextDocument.documentKey, "preview"),
      );
    }

    if (result.actionType === "create_derived_document") {
      setTabState((current) => openNarrativeTab(current, nextDocument.documentKey));
      setDocumentAgents((current) => {
        const next = ensureDocumentAgentSession(current, nextDocument.documentKey, "preview");
        return updateDocumentAgentSession(next, nextDocument.documentKey, (session) => ({
          ...session,
          chatMessages: [
            ...session.chatMessages,
            {
              id: `context-agent-created-${requestId}`,
              role: "context",
              label: "系统",
              content: `该文稿由 agent 动作创建：${result.summary}`,
              tone: "success",
            },
          ],
        }));
      });
    } else if (result.actionType === "split_plan_into_documents" && result.documentSummaries?.length) {
      const firstSummary = result.documentSummaries[0];
      if (firstSummary) {
        const firstDocument = documentsRef.current.find((document) => document.meta.slug === firstSummary.slug);
        if (firstDocument) {
          setTabState((current) => openNarrativeTab(current, firstDocument.documentKey));
        }
      }
    }
  }

  async function approveActionRequest(requestId: string) {
    if (!activeDocument || !activeSession) {
      return;
    }

    const request = activeSession.pendingActionRequests.find((entry) => entry.id === requestId);
    if (!request) {
      return;
    }

    const baseResult = {
      requestId,
      actionType: request.actionType,
    } as const;

    try {
      let result: AgentActionResult;
      if (request.actionType === "apply_candidate_patch") {
        const patchId =
          typeof request.payload.patchId === "string" ? request.payload.patchId : "";
        if (!patchId) {
          throw new Error("apply_candidate_patch 需要 patchId。");
        }
        applyPatch(patchId);
        result = {
          ...baseResult,
          status: "completed",
          summary: `已批准并执行 patch 动作：${patchId}。`,
        };
      } else if (request.actionType === "apply_all_patches") {
        applyAllSuggestions();
        result = {
          ...baseResult,
          status: "completed",
          summary: "已批准并应用当前整篇 AI 建议。",
        };
      } else {
        result = await invokeCommand<AgentActionResult>("execute_narrative_agent_action", {
          workspaceRoot: workspace.workspaceRoot,
          input: {
            requestId,
            actionType: request.actionType,
            payload: request.payload,
            currentDocument: activeDocument,
          },
        });

        if (result.openedSlug) {
          const existing = documentsRef.current.find((document) => document.meta.slug === result.openedSlug);
          if (existing) {
            openDocument(existing.documentKey);
          }
        }

        applyAgentDocumentResult(result, requestId);
      }

      setDocumentAgents((current) =>
        updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
          const actionTone: AiChatMessage["tone"] =
            result.status === "failed" ? "danger" : "success";
          const nextSession = {
            ...session,
            updatedAt: nowIso(),
            pendingActionRequests: session.pendingActionRequests.filter((entry) => entry.id !== requestId),
            actionHistory: [...session.actionHistory, result],
            chatMessages: [
              ...session.chatMessages,
              {
                id: `context-agent-action-${requestId}`,
                role: "context" as const,
                label: "系统",
                content: actionHistoryMessage(result),
                tone: actionTone,
              },
            ],
          };
          return {
            ...nextSession,
            reviewQueue: buildReviewQueue(nextSession),
          };
        }),
      );
      onStatusChange(result.summary);
    } catch (error) {
      const failedResult: AgentActionResult = {
        ...baseResult,
        status: "failed",
        summary: `agent 动作执行失败：${String(error)}`,
      };
      setDocumentAgents((current) =>
        updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
          const nextSession = {
            ...session,
            updatedAt: nowIso(),
            pendingActionRequests: session.pendingActionRequests.filter((entry) => entry.id !== requestId),
            actionHistory: [...session.actionHistory, failedResult],
            chatMessages: [
              ...session.chatMessages,
              {
                id: `context-agent-action-error-${requestId}`,
                role: "context" as const,
                label: "系统",
                content: failedResult.summary,
                tone: "danger" as const,
              },
            ],
          };
          return {
            ...nextSession,
            reviewQueue: buildReviewQueue(nextSession),
          };
        }),
      );
      onStatusChange(failedResult.summary);
    }
  }

  function rejectActionRequest(requestId: string) {
    if (!activeDocument || !activeSession) {
      return;
    }
    const request = activeSession.pendingActionRequests.find((entry) => entry.id === requestId);
    if (!request) {
      return;
    }

    const result: AgentActionResult = {
      requestId,
      actionType: request.actionType,
      status: "rejected",
      summary: `已拒绝 agent 动作《${request.title}》。`,
    };

    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => {
        const nextSession = {
          ...session,
          updatedAt: nowIso(),
          pendingActionRequests: session.pendingActionRequests.filter((entry) => entry.id !== requestId),
          actionHistory: [...session.actionHistory, result],
          chatMessages: [
            ...session.chatMessages,
            {
              id: `context-agent-action-reject-${requestId}`,
              role: "context" as const,
              label: "系统",
              content: result.summary,
              tone: "warning" as const,
            },
          ],
        };
        return {
          ...nextSession,
          reviewQueue: buildReviewQueue(nextSession),
        };
      }),
    );
    onStatusChange(result.summary);
  }

  function clearCurrentConversation() {
    if (!activeDocument) {
      return;
    }

    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) =>
        createDocumentAgentSession({
          mode: session.mode,
          documentViewMode: session.documentViewMode,
          sessionTitle: session.sessionTitle,
          strategy: session.strategy,
          selectedContextDocKeys: session.selectedContextDocKeys,
          savedBranches: session.savedBranches,
        }),
      ),
    );
    onStatusChange("已清空当前文档的 AI 会话。");
  }

  const menuCommands = useMemo(
    () => ({
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: {
        execute: async () => {
          await createTypedDraft(defaultDocType());
        },
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_TASK_SETUP]: {
        execute: async () => {
          await createTypedDraft("task_setup");
        },
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_LOCATION_NOTE]: {
        execute: async () => {
          await createTypedDraft("location_note");
        },
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHARACTER_CARD]: {
        execute: async () => {
          await createTypedDraft("character_card");
        },
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_MONSTER_NOTE]: {
        execute: async () => {
          await createTypedDraft("monster_note");
        },
      },
      [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_ITEM_NOTE]: {
        execute: async () => {
          await createTypedDraft("item_note");
        },
      },
      [EDITOR_MENU_COMMANDS.FILE_SAVE_ALL]: {
        execute: async () => {
          await saveAll();
        },
        isEnabled: () => !saving && dirtyCount > 0,
      },
      [EDITOR_MENU_COMMANDS.FILE_RELOAD]: {
        execute: async () => {
          await onReload();
        },
      },
      [EDITOR_MENU_COMMANDS.FILE_DELETE_CURRENT]: {
        execute: async () => {
          await deleteCurrentDocument();
        },
        isEnabled: () => Boolean(activeDocument),
      },
      [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_SIDEBAR]: {
        execute: () => {
          setLeftSidebarCollapsed((current) => !current);
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_LEFT_SIDEBAR]: {
        execute: () => {
          setLeftSidebarCollapsed((current) => !current);
        },
      },
      [EDITOR_MENU_COMMANDS.VIEW_FOCUS_EDITOR]: {
        execute: () => {
          editorRef.current?.focus();
        },
        isEnabled: () => activeSession?.documentViewMode === "edit",
      },
      [EDITOR_MENU_COMMANDS.AI_GENERATE]: {
        execute: async () => {
          await runGeneration();
        },
        isEnabled: () => Boolean(activeDocument) && !activeSession?.busy,
      },
      [EDITOR_MENU_COMMANDS.AI_OPEN_PROVIDER_SETTINGS]: {
        execute: async () => {
          await openOrFocusSettingsWindow("ai");
        },
      },
      [EDITOR_MENU_COMMANDS.AI_TEST_PROVIDER_CONNECTION]: {
        execute: async () => {
          await openOrFocusSettingsWindow("ai");
        },
      },
      [EDITOR_MENU_COMMANDS.NAVIGATION_NEXT_TAB]: {
        execute: () => {
          cycleTabs(1);
        },
        isEnabled: () => tabState.openTabs.length > 1,
      },
      [EDITOR_MENU_COMMANDS.NAVIGATION_PREV_TAB]: {
        execute: () => {
          cycleTabs(-1);
        },
        isEnabled: () => tabState.openTabs.length > 1,
      },
      [EDITOR_MENU_COMMANDS.NAVIGATION_CLOSE_ACTIVE_TAB]: {
        execute: () => {
          if (tabState.activeTabKey) {
            closeTab(tabState.activeTabKey);
          }
        },
        isEnabled: () => Boolean(tabState.activeTabKey),
      },
    }),
    [
      activeDocument,
      activeSession?.busy,
      activeSession?.documentViewMode,
      dirtyCount,
      onReload,
      saving,
      tabState.activeTabKey,
      tabState.openTabs.length,
      workspace.workspaceRoot,
    ],
  );

  useRegisterEditorMenuCommands(menuCommands);

  if (!startupReady) {
    return (
      <div className="narrative-streamlined-shell narrative-streamlined-loading">
        <div className="narrative-loading-card">
          <Badge tone="muted">加载中</Badge>
          <p>正在准备 Narrative Lab 工作区...</p>
        </div>
      </div>
    );
  }

  const openTabDocuments = tabState.openTabs
    .map((documentKey) => documents.find((document) => document.documentKey === documentKey) ?? null)
    .filter(Boolean) as EditableNarrativeDocument[];
  const previewBlocks = activeDocument ? splitNarrativeMarkdownBlocks(activeDocument.markdown) : [];
  const previewPatchSet = activeSession?.candidatePatchSet ?? null;

  return (
    <div className="narrative-streamlined-shell">
      <header className="narrative-streamlined-topbar">
        <div className="narrative-topbar-brand">
          <div>
            <h2>Narrative Lab</h2>
            <span className="narrative-topbar-subtitle">{workspaceLabel}</span>
          </div>
        </div>

        <div className="narrative-topbar-actions">
          <button type="button" className="toolbar-button toolbar-accent" onClick={() => createBlankDocument()}>
            新建空白文档
          </button>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => void saveAll()}
            disabled={saving || dirtyCount === 0}
          >
            保存全部
          </button>
          <button type="button" className="toolbar-button" onClick={() => void onReload()}>
            重新加载
          </button>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => void openOrFocusSettingsWindow("workspace")}
          >
            设置
          </button>
        </div>
      </header>

      <div className="narrative-streamlined-tabbar">
        {openTabDocuments.length ? (
          openTabDocuments.map((document) => (
            <button
              key={document.documentKey}
              type="button"
              className={`narrative-streamlined-tab ${
                document.documentKey === tabState.activeTabKey ? "narrative-streamlined-tab-active" : ""
              }`.trim()}
              onClick={() =>
                setTabState((current) => ({ ...current, activeTabKey: document.documentKey }))
              }
            >
              <span>{document.meta.title || document.meta.slug}</span>
              {document.dirty ? <span className="narrative-streamlined-tab-dirty" /> : null}
              <span
                className="narrative-streamlined-tab-close"
                onMouseDown={(event) => {
                  event.preventDefault();
                  event.stopPropagation();
                }}
                onClick={(event) => {
                  event.preventDefault();
                  event.stopPropagation();
                  closeTab(document.documentKey);
                }}
              >
                x
              </span>
            </button>
          ))
        ) : (
          <div className="narrative-streamlined-tab-empty">
            <span>还没有打开的文档标签</span>
          </div>
        )}
      </div>

      <div
        className={`narrative-streamlined-main ${
          leftSidebarCollapsed ? "narrative-streamlined-main-collapsed" : ""
        }`.trim()}
      >
        <div className="narrative-sidebar-rail">
          <button
            type="button"
            className="narrative-sidebar-toggle"
            onClick={() => setLeftSidebarCollapsed((current) => !current)}
            title={leftSidebarCollapsed ? "展开文档列表" : "收起文档列表"}
          >
            {leftSidebarCollapsed ? ">" : "<"}
          </button>
        </div>

        {!leftSidebarCollapsed ? (
          <aside className="narrative-doc-sidebar">
            <div className="narrative-pane-header">
              <h3>文档</h3>
            </div>

            <input
              className="field-input"
              type="text"
              value={searchQuery}
              onChange={(event) => setSearchQuery(event.target.value)}
              placeholder="搜索标题、slug 或路径"
            />

            <div className="narrative-doc-list">
              {filteredDocuments.length ? (
                filteredDocuments.map((document) => (
                  <button
                    key={document.documentKey}
                    type="button"
                    className={`narrative-doc-row ${
                      document.documentKey === tabState.activeTabKey ? "narrative-doc-row-active" : ""
                    }`.trim()}
                    onClick={() => openDocument(document.documentKey)}
                    onContextMenu={(event) => {
                      event.preventDefault();
                      setDocContextMenu({
                        documentKey: document.documentKey,
                        x: event.clientX,
                        y: event.clientY,
                      });
                    }}
                  >
                    <div className="narrative-doc-row-main">
                      <strong title={document.relativePath}>
                        {document.meta.title || document.meta.slug}
                      </strong>
                    </div>
                    <div className="narrative-doc-row-side">
                      {tabState.openTabs.includes(document.documentKey) ? (
                        <Badge tone="accent">已打开</Badge>
                      ) : null}
                      {document.dirty ? <Badge tone="warning">未保存</Badge> : null}
                    </div>
                  </button>
                ))
              ) : (
                <div className="narrative-empty-state">
                  <p>没有匹配的文档。</p>
                </div>
              )}
            </div>
          </aside>
        ) : null}

        <div
          ref={editorPanelsRef}
          className="narrative-editor-panels"
          style={editorPanelsStyle}
        >
        <section className="narrative-chat-panel">
          <div className="narrative-pane-header">
            <h3>AI</h3>
            {activeSession?.busy ? <Badge tone="warning">生成中</Badge> : null}
          </div>

          {pendingRestoreSessions ? (
            <div className="narrative-inline-banner">
              <span>{restoreStatus || "检测到上次保存的 Narrative Lab agent 会话。"}</span>
              <div className="toolbar-actions">
                <button
                  type="button"
                  className="toolbar-button toolbar-accent"
                  onClick={() => restorePersistedAgentSessions()}
                >
                  恢复会话
                </button>
                <button type="button" className="toolbar-button" onClick={() => skipPersistedAgentSessions()}>
                  只恢复文档
                </button>
              </div>
            </div>
          ) : restoreStatus ? (
            <p className="field-hint">{restoreStatus}</p>
          ) : null}

          {activeDocument && activeSession ? (
            <>
              <div className="narrative-chat-toolbar">
                <div className="narrative-chat-context-inline">
                  <strong title={activeDocument.relativePath}>
                    {activeDocument.meta.title || activeDocument.meta.slug}
                  </strong>
                </div>

                <div className="segmented-control narrative-mode-switch">
                  <button
                    type="button"
                    className={`segmented-control-item ${
                      activeSession.mode === "revise_document" ? "segmented-control-item-active" : ""
                    }`.trim()}
                    onClick={() =>
                      setDocumentAgents((current) =>
                        updateDocumentAgentSession(current, activeDocument.documentKey, (session) => ({
                          ...session,
                          mode: "revise_document",
                        })),
                      )
                    }
                  >
                    修改当前文档
                  </button>
                  <button
                    type="button"
                    className={`segmented-control-item ${
                      activeSession.mode === "create" ? "segmented-control-item-active" : ""
                    }`.trim()}
                    onClick={() =>
                      setDocumentAgents((current) =>
                        updateDocumentAgentSession(current, activeDocument.documentKey, (session) => ({
                          ...session,
                          mode: "create",
                        })),
                      )
                    }
                  >
                    生成新文档
                  </button>
                </div>
              </div>

              <div className="narrative-chat-context-strip">
                <span className="narrative-chat-context-strip-label">当前对话上下文</span>
                {selectedContextDocuments.length ? (
                  selectedContextDocuments.map((document) => (
                    <span
                      key={`context-chip-${document.documentKey}`}
                      className="narrative-context-chip"
                      title={document.relativePath}
                    >
                      <span>{document.meta.title || document.meta.slug}</span>
                      <button
                        type="button"
                        className="narrative-context-chip-remove"
                        aria-label={`移除 ${document.meta.title || document.meta.slug}`}
                        onMouseDown={(event) => {
                          event.preventDefault();
                          event.stopPropagation();
                        }}
                        onClick={(event) => {
                          event.preventDefault();
                          event.stopPropagation();
                          removeContextDocument(document.documentKey);
                        }}
                      >
                        x
                      </button>
                    </span>
                  ))
                ) : (
                  <span className="narrative-chat-context-empty">当前仅使用主文稿上下文</span>
                )}
              </div>

              <div className="narrative-chat-meta-row">
                <Badge tone="muted">{activeSession.mode === "create" ? "生成新文档" : "修改当前文档"}</Badge>
                {activeSession.status === "waiting_user" ? <Badge tone="warning">等待你的补充</Badge> : null}
                <button
                  type="button"
                  className={`toolbar-button ${
                    !showAdvancedPanel && hasAdvancedPanelContent ? "toolbar-accent" : ""
                  }`.trim()}
                  onClick={() => setShowAdvancedPanel((current) => !current)}
                >
                  {showAdvancedPanel ? "收起高级" : "高级"}
                </button>
              </div>

              {showAdvancedPanel ? (
                <section className="narrative-advanced-panel">
                  <article className="narrative-chat-message narrative-chat-message-context narrative-chat-message-compact">
                    <div className="narrative-chat-message-header">
                      <strong>操作边界</strong>
                    </div>
                    <p style={{ whiteSpace: "pre-wrap" }}>
                      `apply patch / apply all / clear pending actions` 只影响当前会话或当前编辑态；`save / rename / archive / split into documents`
                      会真正修改或新增工作区文稿。
                    </p>
                  </article>

              <article className="narrative-chat-message narrative-chat-message-context">
                <div className="narrative-chat-message-header">
                  <strong>{activeSession.sessionTitle || "当前会话"}</strong>
                  <Badge tone="muted">{activeSession.status}</Badge>
                </div>
                <div className="toolbar-summary">
                  <Badge tone="muted">{`更新于 ${activeSession.updatedAt}`}</Badge>
                  {activeSession.branchOfSessionId ? (
                    <Badge tone="accent">分支会话</Badge>
                  ) : null}
                  <Badge tone="muted">{activeSession.strategy.rewriteIntensity}</Badge>
                  <Badge tone="muted">{activeSession.strategy.priority}</Badge>
                  <Badge tone="muted">{activeSession.strategy.questionBehavior}</Badge>
                </div>
                <div className="toolbar-actions">
                  <button type="button" className="toolbar-button" onClick={() => renameCurrentSession()}>
                    重命名会话
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => forkCurrentSession()}>
                    复制为分支
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => archiveCurrentSession()}>
                    归档当前会话
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => clearCurrentConversation()}>
                    清空会话
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => void exportCurrentSession()}>
                    导出会话
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => void runRegressionSuite()}>
                    运行回归
                  </button>
                </div>
                {exportStatus ? <p style={{ whiteSpace: "pre-wrap" }}>{exportStatus}</p> : null}
                {activeSession.savedBranches.length ? (
                  <>
                    <div className="toolbar-summary">
                      {activeSession.savedBranches.map((branch) => (
                        <Badge key={branch.id} tone={branch.archived ? "muted" : "accent"}>
                          {branch.title}
                        </Badge>
                      ))}
                    </div>
                    <div className="toolbar-actions">
                      {activeSession.savedBranches.map((branch) => (
                        <button
                          key={`${branch.id}-restore`}
                          type="button"
                          className="toolbar-button"
                          onClick={() => restoreSavedBranch(branch.id)}
                        >
                          恢复 {branch.title}
                        </button>
                      ))}
                    </div>
                  </>
                ) : null}
              </article>

              <article className="narrative-chat-message narrative-chat-message-context">
                <div className="narrative-chat-message-header">
                  <strong>Agent 策略</strong>
                  <Badge tone="muted">P1</Badge>
                </div>
                <div className="toolbar-summary">
                  <Badge tone="muted">{buildStrategyInstruction(activeSession)}</Badge>
                </div>
                <div className="segmented-control narrative-mode-switch" style={{ marginBottom: 8 }}>
                  {(["light", "balanced", "aggressive"] as const).map((value) => (
                    <button
                      key={value}
                      type="button"
                      className={`segmented-control-item ${
                        activeSession.strategy.rewriteIntensity === value ? "segmented-control-item-active" : ""
                      }`.trim()}
                      onClick={() => updateActiveStrategy("rewriteIntensity", value)}
                    >
                      {value === "light" ? "保守改写" : value === "balanced" ? "平衡改写" : "激进重构"}
                    </button>
                  ))}
                </div>
                <div className="segmented-control narrative-mode-switch" style={{ marginBottom: 8 }}>
                  {(["consistency", "drama", "speed"] as const).map((value) => (
                    <button
                      key={value}
                      type="button"
                      className={`segmented-control-item ${
                        activeSession.strategy.priority === value ? "segmented-control-item-active" : ""
                      }`.trim()}
                      onClick={() => updateActiveStrategy("priority", value)}
                    >
                      {value === "consistency" ? "优先一致性" : value === "drama" ? "优先戏剧性" : "优先速度"}
                    </button>
                  ))}
                </div>
                <div className="segmented-control narrative-mode-switch">
                  {(["ask_first", "balanced", "direct"] as const).map((value) => (
                    <button
                      key={value}
                      type="button"
                      className={`segmented-control-item ${
                        activeSession.strategy.questionBehavior === value ? "segmented-control-item-active" : ""
                      }`.trim()}
                      onClick={() => updateActiveStrategy("questionBehavior", value)}
                    >
                      {value === "ask_first" ? "先提问后生成" : value === "balanced" ? "平衡" : "尽量直接产出"}
                    </button>
                  ))}
                </div>
              </article>

              <article className="narrative-chat-message narrative-chat-message-context">
                <div className="narrative-chat-message-header">
                  <strong>审阅队列</strong>
                  <Badge tone="muted">{activeReviewQueue.length}</Badge>
                </div>
                <p style={{ whiteSpace: "pre-wrap" }}>{summarizeReviewQueue(activeReviewQueue)}</p>
                {activeReviewQueue.length ? (
                  <ol>
                    {activeReviewQueue.map((item) => (
                      <li key={item.id}>
                        <strong>{item.title}</strong> <Badge tone="muted">{item.kind}</Badge> {item.description}
                      </li>
                    ))}
                  </ol>
                ) : null}
                <div className="toolbar-actions">
                  {previewPatchSet?.patches.length ? (
                    <button
                      type="button"
                      className="toolbar-button"
                      onClick={() => applyAllSuggestions()}
                      disabled={activeSession.busy}
                    >
                      连续应用所有建议
                    </button>
                  ) : null}
                  {previewPatchSet ? (
                    <button
                      type="button"
                      className="toolbar-button"
                      onClick={() => discardCurrentSuggestions()}
                      disabled={activeSession.busy}
                    >
                      清空 patch 建议
                    </button>
                  ) : null}
                  <button type="button" className="toolbar-button" onClick={() => void retryLastTurn()}>
                    重试本轮
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => void retryCurrentStep()}>
                    重试当前步骤
                  </button>
                  <button type="button" className="toolbar-button" onClick={() => clearPendingActionRequests()}>
                    清空待批准动作
                  </button>
                  <button
                    type="button"
                    className="toolbar-button"
                    onClick={() => void approveAllPendingActions()}
                    disabled={!pendingActions.length || activeSession.busy}
                  >
                    连续批准动作
                  </button>
                  <button
                    type="button"
                    className="toolbar-button"
                    onClick={() => rejectAllPendingActions()}
                    disabled={!pendingActions.length || activeSession.busy}
                  >
                    连续拒绝动作
                  </button>
                </div>
                {activeSession.pendingDerivedDocuments.length ? (
                  <>
                    <div className="narrative-chat-message-header" style={{ marginTop: 12 }}>
                      <strong>派生文稿待审</strong>
                      <Badge tone="warning">{activeSession.pendingDerivedDocuments.length}</Badge>
                    </div>
                    <ol>
                      {activeSession.pendingDerivedDocuments.map((document) => (
                        <li key={`derived-review-${document.slug}`}>
                          <strong>{document.title || document.slug}</strong>
                          <div className="toolbar-summary">
                            <Badge tone="muted">{document.slug}</Badge>
                            <Badge tone="muted">{`${document.headingCount} headings`}</Badge>
                          </div>
                          {document.excerpt ? (
                            <div style={{ whiteSpace: "pre-wrap" }}>{document.excerpt}</div>
                          ) : null}
                          <div className="toolbar-actions">
                            <button
                              type="button"
                              className="toolbar-button"
                              onClick={() => reviewDerivedDocument(document.slug)}
                            >
                              打开回看
                            </button>
                            <button
                              type="button"
                              className="toolbar-button toolbar-accent"
                              onClick={() => markDerivedDocumentQueueItem(document.slug, "approved")}
                            >
                              标记通过
                            </button>
                            <button
                              type="button"
                              className="toolbar-button"
                              onClick={() => markDerivedDocumentQueueItem(document.slug, "rejected")}
                            >
                              从列表移除
                            </button>
                          </div>
                        </li>
                      ))}
                    </ol>
                    <div className="toolbar-actions">
                      <button type="button" className="toolbar-button" onClick={() => reviewNextDerivedDocument()}>
                        逐项回看下一个
                      </button>
                      <button
                        type="button"
                        className="toolbar-button toolbar-accent"
                        onClick={() => approveAllDerivedDocuments()}
                      >
                        连续通过派生稿
                      </button>
                      <button type="button" className="toolbar-button" onClick={() => rejectAllDerivedDocuments()}>
                        连续移除派生稿
                      </button>
                    </div>
                  </>
                ) : null}
              </article>

              {regressionStatus || regressionResult ? (
                <article className="narrative-chat-message narrative-chat-message-context">
                  <div className="narrative-chat-message-header">
                    <strong>行为回归验证</strong>
                    <Badge tone={regressionResult?.ok ? "success" : regressionResult ? "warning" : "muted"}>
                      {regressionResult ? (regressionResult.ok ? "pass" : "check") : "idle"}
                    </Badge>
                  </div>
                  {regressionStatus ? <p style={{ whiteSpace: "pre-wrap" }}>{regressionStatus}</p> : null}
                  {regressionResult?.results.length ? (
                    <ol>
                      {regressionResult.results.map((item) => (
                        <li key={item.id}>
                          <Badge tone={item.ok ? "success" : "warning"}>
                            {item.actualTurnKind}
                          </Badge>{" "}
                          {item.label}，期望 {item.expectedTurnKinds.join(" / ")}
                        </li>
                      ))}
                    </ol>
                  ) : null}
                </article>
              ) : null}

              {activeSession.lastResponse ? (
                <article className="narrative-chat-message narrative-chat-message-context">
                  <div className="narrative-chat-message-header">
                    <strong>Provenance</strong>
                    <Badge tone="muted">P1</Badge>
                  </div>
                  <div className="toolbar-summary">
                    {(activeSession.lastResponse.sourceDocumentKeys.length
                      ? activeSession.lastResponse.sourceDocumentKeys
                      : [activeDocument.meta.slug]
                    ).map((key) => (
                      <Badge key={`source-${key}`} tone="accent">
                        {key}
                      </Badge>
                    ))}
                  </div>
                  <div className="toolbar-summary">
                    {activeSession.lastResponse.provenanceRefs.length ? (
                      activeSession.lastResponse.provenanceRefs.map((ref) => (
                        <Badge key={`prov-${ref}`} tone="muted">
                          {ref}
                        </Badge>
                      ))
                    ) : (
                      <Badge tone="muted">本轮没有额外 provenance ref</Badge>
                    )}
                  </div>
                </article>
              ) : null}
                </section>
              ) : null}

              <div className="narrative-chat-log">
                {activeSession.chatMessages.length ? (
                  activeSession.chatMessages.map((message) => (
                    <article
                      key={message.id}
                      className={`narrative-chat-message narrative-chat-message-${message.role}`.trim()}
                    >
                      <div className="narrative-chat-message-header">
                        <strong>{message.label}</strong>
                        {message.tone ? <Badge tone={message.tone}>{message.role}</Badge> : null}
                      </div>
                      <ChatMessageContent message={message} />
                      {message.meta?.length ? (
                        <div className="toolbar-summary">
                          {message.meta.map((entry) => (
                            <Badge key={`${message.id}-${entry}`} tone="muted">
                              {entry}
                            </Badge>
                          ))}
                        </div>
                      ) : null}
                    </article>
                  ))
                ) : (
                  <div className="narrative-empty-state">
                    <p>这个文档还没有 AI 会话。告诉 AI 你想怎么写、怎么改。</p>
                  </div>
                )}

                {pendingQuestions.length ? (
                  <article className="narrative-chat-message narrative-chat-message-context">
                    <div className="narrative-chat-message-header">
                      <strong>待补充信息</strong>
                      <Badge tone="warning">clarification</Badge>
                    </div>
                    <p style={{ whiteSpace: "pre-wrap" }}>AI 需要这些信息后再继续生成。</p>
                    <ol>
                      {pendingQuestions.map((question) => (
                        <li key={question.id}>
                          {question.label}
                          {question.required ? "（必填）" : ""}
                        </li>
                      ))}
                    </ol>
                  </article>
                ) : null}

                {pendingOptions.length ? (
                  <article className="narrative-chat-message narrative-chat-message-context">
                    <div className="narrative-chat-message-header">
                      <strong>可选方向</strong>
                      <Badge tone="accent">options</Badge>
                    </div>
                    <p style={{ whiteSpace: "pre-wrap" }}>选一个方向，我会在当前会话里继续推进。</p>
                    <div className="narrative-option-list">
                      {pendingOptions.map((option) => (
                        <button
                          key={option.id}
                          type="button"
                          className="narrative-option-card"
                          disabled={activeSession.busy}
                          onClick={() => void runGeneration(option.followupPrompt)}
                          title={option.followupPrompt || option.description}
                        >
                          <strong>{option.label}</strong>
                          <span>{option.description || "选择这个方向继续推进当前会话。"}</span>
                        </button>
                      ))}
                    </div>
                  </article>
                ) : null}

                {latestTurnKind === "plan" && latestPlan.length ? (
                  <article className="narrative-chat-message narrative-chat-message-context">
                    <div className="narrative-chat-message-header">
                      <strong>执行计划</strong>
                      <Badge tone="muted">plan</Badge>
                    </div>
                    <ol>
                      {latestPlan.map((step) => (
                        <li key={step.id}>
                          {step.label}
                          {" "}
                          <Badge tone={step.status === "completed" ? "success" : step.status === "active" ? "accent" : "muted"}>
                            {step.status}
                          </Badge>
                        </li>
                      ))}
                    </ol>
                  </article>
                ) : null}

                {showAdvancedPanel && activeSession.executionSteps.length ? (
                  <article className="narrative-chat-message narrative-chat-message-context">
                    <div className="narrative-chat-message-header">
                      <strong>执行轨迹</strong>
                      <Badge tone="muted">{activeSession.status}</Badge>
                    </div>
                    <ol>
                      {activeSession.executionSteps.map((step) => (
                        <li key={step.id}>
                          <strong>{step.label}</strong>
                          {" "}
                          <Badge
                            tone={
                              step.status === "completed"
                                ? "success"
                                : step.status === "failed"
                                  ? "danger"
                                  : step.id === activeSession.currentStepId
                                    ? "accent"
                                    : "muted"
                            }
                          >
                            {step.status}
                          </Badge>
                          <div style={{ whiteSpace: "pre-wrap" }}>
                            {step.previewText?.trim() || step.detail}
                          </div>
                        </li>
                      ))}
                    </ol>
                  </article>
                ) : null}

                {pendingActions.length ? (
                  <article className="narrative-chat-message narrative-chat-message-context">
                    <div className="narrative-chat-message-header">
                      <strong>待批准动作</strong>
                      <Badge tone="warning">approval</Badge>
                    </div>
                    <p style={{ whiteSpace: "pre-wrap" }}>
                      这些动作不会自动执行，只有你批准后才会继续。
                    </p>
                    {pendingActions.map((action) => (
                      <div key={action.id} className="narrative-empty-state" style={{ marginBottom: 12 }}>
                        <strong>{action.title}</strong>
                        <p style={{ whiteSpace: "pre-wrap" }}>{action.description}</p>
                        <div className="toolbar-summary">
                          <Badge tone="muted">{action.actionType}</Badge>
                          <Badge tone="muted">{action.approvalPolicy}</Badge>
                          <Badge
                            tone={
                              action.riskLevel === "high"
                                ? "danger"
                                : action.riskLevel === "medium"
                                  ? "warning"
                                  : "muted"
                            }
                          >
                            {action.riskLevel ?? "medium"}
                          </Badge>
                          {action.previewOnly ? <Badge tone="accent">preview only</Badge> : null}
                          {action.affectedDocumentKeys?.map((key) => (
                            <Badge key={`${action.id}-${key}`} tone="muted">
                              {key}
                            </Badge>
                          ))}
                        </div>
                        <div className="toolbar-actions">
                          <button
                            type="button"
                            className="toolbar-button toolbar-accent"
                            disabled={activeSession.busy}
                            onClick={() => void approveActionRequest(action.id)}
                          >
                            批准并执行
                          </button>
                          <button
                            type="button"
                            className="toolbar-button"
                            disabled={activeSession.busy}
                            onClick={() => rejectActionRequest(action.id)}
                          >
                            拒绝
                          </button>
                        </div>
                      </div>
                    ))}
                  </article>
                ) : null}

                {showAdvancedPanel && activeSession.actionHistory.length ? (
                  <article className="narrative-chat-message narrative-chat-message-context">
                    <div className="narrative-chat-message-header">
                      <strong>动作记录</strong>
                      <Badge tone="muted">{activeSession.actionHistory.length}</Badge>
                    </div>
                    <ol>
                      {activeSession.actionHistory.map((result) => (
                        <li key={`${result.requestId}-${result.status}`}>
                          <Badge
                            tone={
                              result.status === "completed"
                                ? "success"
                                : result.status === "failed"
                                  ? "danger"
                                  : result.status === "approved"
                                    ? "accent"
                                    : "muted"
                            }
                          >
                            {result.status}
                          </Badge>
                          {" "}
                          {result.summary}
                        </li>
                      ))}
                    </ol>
                  </article>
                ) : null}

                {showAdvancedPanel && activeSession.versionHistory.length ? (
                  <article className="narrative-chat-message narrative-chat-message-context">
                    <div className="narrative-chat-message-header">
                      <strong>版本演变</strong>
                      <Badge tone="muted">{activeSession.versionHistory.length}</Badge>
                    </div>
                    <ol>
                      {activeSession.versionHistory.map((snapshot) => (
                        <li key={snapshot.id}>
                          <strong>{snapshot.title}</strong>
                          <div className="toolbar-summary">
                            <Badge tone="muted">{snapshot.createdAt}</Badge>
                            {snapshot.requestId ? <Badge tone="muted">{snapshot.requestId}</Badge> : null}
                          </div>
                          <div style={{ whiteSpace: "pre-wrap" }}>
                            Before: {snapshot.beforeMarkdown.slice(0, 80) || "(empty)"}
                          </div>
                          <div style={{ whiteSpace: "pre-wrap" }}>
                            After: {snapshot.afterMarkdown.slice(0, 80) || "(empty)"}
                          </div>
                        </li>
                      ))}
                    </ol>
                  </article>
                ) : null}
              </div>

              <div className="narrative-chat-composer">
                <textarea
                  className="field-input field-textarea narrative-chat-textarea"
                  value={activeSession.composerText}
                  onChange={(event) =>
                    setDocumentAgents((current) =>
                      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => ({
                        ...session,
                        composerText: event.target.value,
                      })),
                    )
                  }
                  onKeyDown={(event) => {
                    if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) {
                      event.preventDefault();
                      if (!activeSession.busy) {
                        void runGeneration();
                      }
                    }
                  }}
                  placeholder={composerPlaceholder}
                />
                <div className="narrative-chat-composer-footer">
                  <div className="toolbar-summary">
                    <Badge tone="muted">{activeDocument.meta.slug}</Badge>
                    {activeSession.status === "waiting_user" ? (
                      <Badge tone="warning">等待你的补充</Badge>
                    ) : null}
                  </div>
                  <div className="toolbar-actions">
                    <button
                      type="button"
                      className="toolbar-button toolbar-accent"
                      onClick={() => void runGeneration()}
                      disabled={activeSession.busy}
                    >
                      发送给 AI
                    </button>
                  </div>
                </div>
              </div>
            </>
          ) : (
            <div className="narrative-empty-state narrative-flex-fill">
              <p>先从左侧打开一个文档，或者直接新建一个空白文档标签。</p>
            </div>
          )}
        </section>

        <button
          type="button"
          className="narrative-panel-splitter"
          onPointerDown={beginPanelResize}
          onDoubleClick={resetPanelWidth}
          aria-label="调整 AI 与文档面板宽度"
          title="拖动调整 AI 与文档面板宽度，双击恢复默认宽度"
        />

        <section className="narrative-document-panel">
          <div className="narrative-pane-header">
            <h3>{activeDocument ? activeDocument.meta.title || activeDocument.meta.slug : "未选择文档"}</h3>
            {activeDocument ? (
              <Badge tone={activeDocument.dirty ? "warning" : "success"}>
                {activeDocument.dirty ? "未保存" : "已保存"}
              </Badge>
            ) : null}
          </div>

          {activeDocument && activeSession ? (
            <>
              <div className="narrative-document-toolbar">
                <input
                  className="field-input narrative-document-title"
                  type="text"
                  value={activeDocument.meta.title}
                  onChange={(event) =>
                    updateDocumentState(activeDocument.documentKey, (document) => ({
                      ...document,
                      meta: {
                        ...document.meta,
                        title: event.target.value,
                      },
                    }))
                  }
                  placeholder="文档标题"
                />
                <div className="segmented-control">
                  {(["preview", "edit"] as NarrativeDocumentViewMode[]).map((mode) => (
                    <button
                      key={mode}
                      type="button"
                      className={`segmented-control-item ${
                        activeSession.documentViewMode === mode ? "segmented-control-item-active" : ""
                      }`.trim()}
                      onClick={() =>
                        setDocumentAgents((current) =>
                          updateDocumentAgentSession(current, activeDocument.documentKey, (session) => ({
                            ...session,
                            documentViewMode: mode,
                          })),
                        )
                      }
                    >
                      {mode === "preview" ? "预览" : "编辑"}
                    </button>
                  ))}
                </div>
              </div>

              {activeSession.documentViewMode === "edit" ? (
                <textarea
                  ref={editorRef}
                  className="field-input field-textarea narrative-document-editor"
                  value={activeDocument.markdown}
                  onChange={(event) => {
                    updateDocumentState(activeDocument.documentKey, (document) => ({
                      ...document,
                      markdown: event.target.value,
                    }));
                    invalidateSuggestions(activeDocument.documentKey);
                  }}
                />
              ) : (
                <div className="narrative-document-preview">
                  {previewBlocks.length ? (
                    <>
                      {previewPatchSet?.mode === "patches" &&
                        previewPatchSet.patches
                          .filter((patch) => patch.startBlock === 0 && patch.endBlock === 0)
                          .map((patch) => (
                            <div key={patch.id} className="narrative-patch-card">
                              <div className="narrative-patch-card-header">
                                <strong>{patch.title}</strong>
                                <button
                                  type="button"
                                  className="toolbar-button toolbar-accent"
                                  onClick={() => applyPatch(patch.id)}
                                >
                                  应用
                                </button>
                              </div>
                              <MarkdownBlock markdown={patch.replacementText || "_AI 建议插入内容为空_"} />
                            </div>
                          ))}

                      {previewBlocks.map((block, index) => {
                        const inlinePatches =
                          previewPatchSet?.mode === "patches"
                            ? previewPatchSet.patches.filter((patch) => patch.endBlock === index + 1)
                            : [];

                        return (
                          <div key={`block-${index}`} className="narrative-preview-block-wrap">
                            <MarkdownBlock markdown={block} />
                            {inlinePatches.map((patch) => (
                              <div key={patch.id} className="narrative-patch-card">
                                <div className="narrative-patch-card-header">
                                  <strong>{patch.title}</strong>
                                  <button
                                    type="button"
                                    className="toolbar-button toolbar-accent"
                                    onClick={() => applyPatch(patch.id)}
                                  >
                                    应用
                                  </button>
                                </div>
                                {patch.originalText ? (
                                  <div className="narrative-patch-columns">
                                    <div>
                                      <span className="section-label">当前段落</span>
                                      <MarkdownBlock markdown={patch.originalText} />
                                    </div>
                                    <div>
                                      <span className="section-label">AI 建议</span>
                                      <MarkdownBlock markdown={patch.replacementText || "_空_"} />
                                    </div>
                                  </div>
                                ) : (
                                  <MarkdownBlock markdown={patch.replacementText || "_空_"} />
                                )}
                              </div>
                            ))}
                          </div>
                        );
                      })}
                    </>
                  ) : (
                    <div className="narrative-empty-state">
                      <p>当前文档还没有正文内容。</p>
                    </div>
                  )}

                  {previewPatchSet?.mode === "full_document" &&
                  activeSession.lastResponse?.draftMarkdown.trim() &&
                  normalizeNarrativeMarkdown(activeDocument.markdown) !==
                    normalizeNarrativeMarkdown(activeSession.lastResponse.draftMarkdown) ? (
                    <div className="narrative-patch-card narrative-patch-card-full">
                      <div className="narrative-patch-card-header">
                        <strong>整篇建议</strong>
                        <button
                          type="button"
                          className="toolbar-button toolbar-accent"
                          onClick={() => applyAllSuggestions()}
                        >
                          全部应用
                        </button>
                      </div>
                      <MarkdownBlock markdown={activeSession.lastResponse.draftMarkdown} />
                    </div>
                  ) : null}
                </div>
              )}
            </>
          ) : (
            <div className="narrative-empty-state narrative-flex-fill">
              <p>打开一个文档后，这里会显示它的预览或编辑器。</p>
            </div>
          )}
        </section>
        </div>
      </div>

      {docContextMenu ? (
        <div
          className="narrative-context-menu"
          style={{ left: docContextMenu.x, top: docContextMenu.y }}
          onPointerDown={(event) => event.stopPropagation()}
        >
          <button
            type="button"
            className="narrative-context-menu-item"
            disabled={!canAddContextFromMenu}
            title={contextMenuAddLabel}
            onClick={() => addContextDocument(docContextMenu.documentKey)}
          >
            {contextMenuAddLabel}
          </button>
          <button
            type="button"
            className="narrative-context-menu-item"
            onClick={() => void deleteDocumentByKey(docContextMenu.documentKey)}
          >
            删除
          </button>
          <button
            type="button"
            className="narrative-context-menu-item"
            onClick={() => void openDocumentFolder(docContextMenu.documentKey)}
          >
            打开所在文件夹
          </button>
        </div>
      ) : null}

      <footer className="narrative-streamlined-statusbar">
        <div className="narrative-streamlined-status-main">
          <span className="status-dot" />
          <span>{status}</span>
        </div>
      </footer>
    </div>
  );
}
