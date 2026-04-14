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
  AiSettings,
  AiChatMessage,
  NarrativeAiConfigSummary,
  AiConnectionTestResult,
  DocumentAgentSession,
  NarrativeCancelRequestResult,
  EditorMenuSelfTestScenario,
  NarrativeAppSettings,
  NarrativeChatRegressionExportInput,
  NarrativeChatRegressionExportResult,
  NarrativeChatRegressionFailureKind,
  NarrativeChatRegressionMode,
  NarrativeChatRegressionReport,
  NarrativeChatRegressionScenario,
  NarrativeChatRegressionScenarioResult,
  NarrativeDocType,
  NarrativeDocumentPayload,
  NarrativeRegressionSuiteResult,
  NarrativeDocumentViewMode,
  NarrativeGenerateRequest,
  NarrativeGenerationProgressEvent,
  NarrativeGenerateResponse,
  NarrativeQueuedSubmission,
  NarrativeSubmissionSource,
  ResolveNarrativeActionIntentResult,
  NarrativeDocumentSummary,
  NarrativeSessionExportInput,
  NarrativeSessionExportResult,
  NarrativeWorkspaceLayout,
  NarrativeWorkspacePayload,
  SaveNarrativeDocumentResult,
} from "../../types";
import {
  NARRATIVE_CHAT_REGRESSION_ACTIVE_SLUG,
  NARRATIVE_CHAT_REGRESSION_SCENARIOS,
  isOnlineRegressionMode,
  scenarioResultSummary,
  scenariosForMode,
  summarizeNarrativeChatRegression,
} from "./narrativeChatRegression";
import {
  applyNarrativePatch,
  buildNarrativePatchSet,
  normalizeNarrativeMarkdown,
  splitNarrativeMarkdownBlocks,
} from "./narrativePatches";
import {
  clearActiveNarrativeSubmission,
  addSelectedContextDocument,
  closeNarrativeTab,
  createNarrativeQueuedSubmission,
  createDocumentAgentSession,
  ensureDocumentAgentSession,
  openNarrativeTab,
  promoteNextNarrativeSubmission,
  enqueueNarrativeSubmission,
  removeSelectedContextDocument,
  updateActiveSubmissionStage,
  updateDocumentAgentSession,
  updateDocumentAgentSessionWithReviewQueue,
  type NarrativeTabState,
} from "./narrativeSessions";
import {
  buildReviewQueue,
  buildWorkspaceAgentState,
  defaultNarrativeAgentStrategy,
  fromPersistedSessionState,
  getWorkspacePersistedAgentState,
  nowIso,
} from "./narrativeAgentState";
import {
  EditableNarrativeDocument,
  mergeRelatedDocSlugs,
  responseMetaLabels,
} from "./narrativeSessionHelpers";
import {
  applySavedDocumentResult,
  buildEditableDraftDocument,
  hydrateEditableDocuments,
  markDocumentDirtyState,
  mergeSavedDocumentIntoCurrent,
  removeEditableDocument,
  replaceEditableDocument,
  revertDocumentToSnapshot,
  snapshotNarrativeDocument,
  updateEditableDocument,
} from "./narrativeDocumentState";
import {
  applyGenerationErrorToSession,
  applyGenerationResponseToSession,
  archiveSessionBranch,
  appendContextMessage,
  assistantMessageIdForRequest,
  buildDerivedDraftSession,
  clearAllDerivedDocumentsReview,
  clearConversationSession,
  clearPendingActionRequestQueue,
  forkSessionBranch,
  mergePendingDerivedDocuments,
  replaceChatMessage,
  renameSessionTitle,
  resolveDerivedDocumentReview,
  resolveActionRequestSession,
  restoreSessionBranch,
  sessionStatusFromProgress,
  updateSessionStrategyValue,
  upsertExecutionStep,
} from "./narrativeSessionFlow";
import {
  buildActionIntentRequest,
  beginGenerationSession,
  buildGenerationRequest,
  buildGenerationUserMessage,
  buildStrategyInstruction,
  buildUsedContextSummary,
  extractTitleFromMarkdown,
  shouldBypassActionIntentResolution,
  summarizeGenerationResponseForChat,
} from "./narrativeGenerationFlow";
import { runNarrativeRegressionSuite } from "./narrativeRegressionSuite";
import {
  defaultNarrativeMarkdown,
  defaultNarrativeTitle,
  docTypeLabel,
} from "./narrativeTemplates";

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
  chatRegressionMode: NarrativeChatRegressionMode | null;
  autoCloseAfterSelfTest: boolean;
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
const DEFAULT_LEFT_SIDEBAR_WIDTH = 152;
const MIN_LEFT_SIDEBAR_WIDTH = 148;
const MAX_LEFT_SIDEBAR_WIDTH = 520;
const MIN_EDITOR_PANELS_WIDTH = MIN_CHAT_PANEL_WIDTH + PANEL_SPLITTER_WIDTH + MIN_DOCUMENT_PANEL_WIDTH;
const SIDEBAR_RAIL_WIDTH = 40;
const SIDEBAR_SPLITTER_WIDTH = 12;
const NARRATIVE_GENERATION_PROGRESS_EVENT = "narrative:generation-progress";

function defaultWorkspaceLayout(
  activeDocumentKey: string | null,
  openDocumentKeys: string[],
  leftSidebarVisible: boolean,
  leftSidebarWidth = DEFAULT_LEFT_SIDEBAR_WIDTH,
  chatPanelWidth = DEFAULT_CHAT_PANEL_WIDTH,
): NarrativeWorkspaceLayout {
  return {
    version: 2,
    leftSidebarVisible,
    leftSidebarWidth,
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
  const savedSnapshot = snapshotNarrativeDocument(document);
  return {
    ...document,
    savedSnapshot,
    dirty: false,
    isDraft: false,
  };
}

function patchKindLabel(kind?: "replace" | "insert" | "delete") {
  switch (kind) {
    case "insert":
      return "插入";
    case "delete":
      return "删除";
    default:
      return "替换";
  }
}

function resolveInitialTabs(
  workspace: NarrativeWorkspacePayload,
  appSettings: NarrativeAppSettings,
  documents: EditableNarrativeDocument[],
): {
  tabState: NarrativeTabState;
  leftSidebarCollapsed: boolean;
  leftSidebarWidth: number;
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
    layout?.leftSidebarWidth ?? DEFAULT_LEFT_SIDEBAR_WIDTH,
    layout?.chatPanelWidth ?? DEFAULT_CHAT_PANEL_WIDTH,
  );

  return {
    tabState: {
      openTabs: openDocumentKeys,
      activeTabKey: activeDocumentKey,
    },
    leftSidebarCollapsed: persistedLayout.leftSidebarVisible === false,
    leftSidebarWidth: resolveInitialLeftSidebarWidth(persistedLayout.leftSidebarWidth),
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

function finalizeRestoredDocumentSessions(
  persistedSessions: Record<string, DocumentAgentSession>,
): {
  restoredSessions: Record<string, DocumentAgentSession>;
  restoredKeys: string[];
  restoreTargetKey: string | null;
} {
  const restoredEntries = Object.entries(persistedSessions);
  const restoreTargetKey =
    restoredEntries
      .slice()
      .sort((left, right) => {
        const leftTime = Date.parse(left[1].updatedAt || "");
        const rightTime = Date.parse(right[1].updatedAt || "");
        return (Number.isNaN(rightTime) ? 0 : rightTime) - (Number.isNaN(leftTime) ? 0 : leftTime);
      })[0]?.[0] ?? null;
  const restoredSessions = Object.fromEntries(
    restoredEntries.map(([documentKey, session]) => [
      documentKey,
      {
        ...session,
        reviewQueue: buildReviewQueue(session),
        activeSubmission: null,
        queuedSubmissions: [],
        busy: false,
        inflightRequestId: null,
      },
    ]),
  ) as Record<string, DocumentAgentSession>;

  return {
    restoredSessions,
    restoredKeys: Object.keys(restoredSessions),
    restoreTargetKey,
  };
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

function clampLeftSidebarWidth(width: number, containerWidth: number) {
  const maxWidth = Math.min(
    MAX_LEFT_SIDEBAR_WIDTH,
    Math.max(
      MIN_LEFT_SIDEBAR_WIDTH,
      containerWidth - SIDEBAR_RAIL_WIDTH - SIDEBAR_SPLITTER_WIDTH - MIN_EDITOR_PANELS_WIDTH,
    ),
  );
  return Math.min(Math.max(width, MIN_LEFT_SIDEBAR_WIDTH), maxWidth);
}

function estimateMainPanelsWidth() {
  if (typeof window === "undefined") {
    return SIDEBAR_RAIL_WIDTH + SIDEBAR_SPLITTER_WIDTH + MIN_EDITOR_PANELS_WIDTH + DEFAULT_LEFT_SIDEBAR_WIDTH;
  }

  return Math.max(
    SIDEBAR_RAIL_WIDTH + SIDEBAR_SPLITTER_WIDTH + MIN_EDITOR_PANELS_WIDTH + MIN_LEFT_SIDEBAR_WIDTH,
    window.innerWidth - 48,
  );
}

function resolveInitialLeftSidebarWidth(width: number | null | undefined) {
  const mainPanelsWidth = estimateMainPanelsWidth();
  const requestedWidth = width && width > 0 ? width : DEFAULT_LEFT_SIDEBAR_WIDTH;
  return clampLeftSidebarWidth(requestedWidth, mainPanelsWidth);
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
  selfTestScenario,
  chatRegressionMode,
  autoCloseAfterSelfTest,
  status,
  onStatusChange,
  onReload,
  onOpenWorkspace: _onOpenWorkspace,
  onConnectProject: _onConnectProject,
  onSaveAppSettings,
}: NarrativeWorkspaceProps) {
  const [documents, setDocuments] = useState<EditableNarrativeDocument[]>(
    hydrateEditableDocuments(workspace.documents),
  );
  const [tabState, setTabState] = useState<NarrativeTabState>({
    openTabs: workspace.documents[0] ? [workspace.documents[0].documentKey] : [],
    activeTabKey: workspace.documents[0]?.documentKey ?? null,
  });
  const [documentAgents, setDocumentAgents] = useState<Record<string, DocumentAgentSession>>({});
  const [leftSidebarCollapsed, setLeftSidebarCollapsed] = useState(false);
  const [leftSidebarWidth, setLeftSidebarWidth] = useState(DEFAULT_LEFT_SIDEBAR_WIDTH);
  const [chatPanelWidth, setChatPanelWidth] = useState(DEFAULT_CHAT_PANEL_WIDTH);
  const [searchQuery, setSearchQuery] = useState("");
  const [saving, setSaving] = useState(false);
  const [docContextMenu, setDocContextMenu] = useState<NarrativeDocContextMenuState | null>(null);
  const [regressionStatus, setRegressionStatus] = useState("");
  const [regressionResult, setRegressionResult] = useState<NarrativeRegressionSuiteResult | null>(
    null,
  );
  const [exportStatus, setExportStatus] = useState("");
  const editorRef = useRef<HTMLTextAreaElement | null>(null);
  const mainPanelsRef = useRef<HTMLDivElement | null>(null);
  const editorPanelsRef = useRef<HTMLDivElement | null>(null);
  const docContextMenuRef = useRef<HTMLDivElement | null>(null);
  const layoutSaveTimeoutRef = useRef<number | null>(null);
  const agentSaveTimeoutRef = useRef<number | null>(null);
  const flushingBeforeCloseRef = useRef(false);
  const isResizingSidebarRef = useRef(false);
  const isResizingPanelsRef = useRef(false);
  const appSettingsRef = useRef(appSettings);
  const documentsRef = useRef<EditableNarrativeDocument[]>(documents);
  const documentAgentsRef = useRef<Record<string, DocumentAgentSession>>(documentAgents);
  const tabStateRef = useRef<NarrativeTabState>(tabState);
  const submissionGateRef = useRef<Record<string, boolean>>({});
  const runningSubmissionRef = useRef<Record<string, string>>({});
  const workspaceRootRef = useRef("");
  const layoutSnapshotRef = useRef("");
  const agentSnapshotRef = useRef("");
  const selfTestStartedRef = useRef(false);

  useEffect(() => {
    appSettingsRef.current = appSettings;
  }, [appSettings]);

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
    const nextDocuments = hydrateEditableDocuments(workspace.documents);
    const initial = resolveInitialTabs(workspace, appSettings, nextDocuments);
    const validDocumentKeys = new Set(nextDocuments.map((document) => document.documentKey));
    const { restoredSessions, restoredKeys, restoreTargetKey } =
      finalizeRestoredDocumentSessions(
        restorePersistedDocumentSessions(appSettings, workspace, validDocumentKeys),
      );
    const restoredTabState =
      workspaceRootRef.current === workspace.workspaceRoot || !restoredKeys.length
        ? initial.tabState
        : {
            openTabs: restoredKeys.reduce((openTabs, documentKey) => {
              if (openTabs.includes(documentKey)) {
                return openTabs;
              }
              return [...openTabs, documentKey];
            }, initial.tabState.openTabs),
            activeTabKey: restoreTargetKey ?? initial.tabState.activeTabKey,
          };

    commitDocuments(() => nextDocuments);
    setTabState(restoredTabState);
    setLeftSidebarCollapsed(initial.leftSidebarCollapsed);
    setLeftSidebarWidth(initial.leftSidebarWidth);
    setChatPanelWidth(initial.chatPanelWidth);
    layoutSnapshotRef.current = initial.layoutSnapshot;
    agentSnapshotRef.current = JSON.stringify(buildWorkspaceAgentState(restoredSessions));
    setDocumentAgents((current) => {
      return workspaceRootRef.current === workspace.workspaceRoot
        ? current
        : restoredSessions;
    });
    workspaceRootRef.current = workspace.workspaceRoot;
  }, [workspace]);

  useEffect(() => {
    if (!startupReady || !workspace.workspaceRoot.trim()) {
      return;
    }

    if (workspaceRootRef.current !== workspace.workspaceRoot) {
      return;
    }

    if (Object.keys(documentAgentsRef.current).length > 0) {
      return;
    }

    const validDocumentKeys = new Set(documentsRef.current.map((document) => document.documentKey));
    if (!validDocumentKeys.size) {
      return;
    }

    const { restoredSessions, restoredKeys, restoreTargetKey } =
      finalizeRestoredDocumentSessions(
        restorePersistedDocumentSessions(appSettings, workspace, validDocumentKeys),
      );
    if (!restoredKeys.length) {
      return;
    }

    agentSnapshotRef.current = JSON.stringify(buildWorkspaceAgentState(restoredSessions));
    setDocumentAgents(restoredSessions);
    setTabState((current) => ({
      openTabs: restoredKeys.reduce((openTabs, documentKey) => {
        if (openTabs.includes(documentKey)) {
          return openTabs;
        }
        return [...openTabs, documentKey];
      }, current.openTabs),
      activeTabKey: current.activeTabKey ?? restoreTargetKey ?? restoredKeys[0] ?? null,
    }));
  }, [appSettings, startupReady, workspace]);

  useEffect(() => {
    const handlePointerMove = (event: PointerEvent) => {
      if (isResizingSidebarRef.current && mainPanelsRef.current) {
        const bounds = mainPanelsRef.current.getBoundingClientRect();
        setLeftSidebarWidth(clampLeftSidebarWidth(event.clientX - bounds.left - SIDEBAR_RAIL_WIDTH, bounds.width));
        return;
      }

      if (isResizingPanelsRef.current && editorPanelsRef.current) {
        const bounds = editorPanelsRef.current.getBoundingClientRect();
        setChatPanelWidth(clampChatPanelWidth(event.clientX - bounds.left, bounds.width));
      }
    };

    const stopResizing = () => {
      if (!isResizingPanelsRef.current && !isResizingSidebarRef.current) {
        return;
      }

      isResizingSidebarRef.current = false;
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
    if (!docContextMenu) {
      return;
    }

    const closeMenu = () => {
      setDocContextMenu(null);
    };
    const handlePointerDown = (event: PointerEvent) => {
      const target = event.target;
      if (target instanceof Node && docContextMenuRef.current?.contains(target)) {
        return;
      }
      closeMenu();
    };
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        closeMenu();
      }
    };

    window.addEventListener("pointerdown", handlePointerDown);
    window.addEventListener("blur", closeMenu);
    window.addEventListener("resize", closeMenu);
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      window.removeEventListener("pointerdown", handlePointerDown);
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
      leftSidebarWidth,
      chatPanelWidth,
    );
    const serialized = JSON.stringify(persistedLayout);
    if (serialized === layoutSnapshotRef.current) {
      return;
    }

    layoutSaveTimeoutRef.current = window.setTimeout(() => {
      void persistWorkspaceLayoutNow(persistedLayout)
        .then(() => {
          layoutSaveTimeoutRef.current = null;
        })
        .catch((error) => {
          layoutSaveTimeoutRef.current = null;
          onStatusChange(`保存 Narrative Lab 布局失败：${String(error)}`);
        });
    }, 220);

    return () => {
      if (layoutSaveTimeoutRef.current !== null) {
        window.clearTimeout(layoutSaveTimeoutRef.current);
        layoutSaveTimeoutRef.current = null;
      }
    };
  }, [
    appSettings,
    canPersist,
    chatPanelWidth,
    leftSidebarCollapsed,
    leftSidebarWidth,
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

    agentSaveTimeoutRef.current = window.setTimeout(() => {
      void persistAgentStateNow(persistedAgentState)
        .then(() => {
          agentSaveTimeoutRef.current = null;
        })
        .catch((error) => {
          agentSaveTimeoutRef.current = null;
          onStatusChange(`保存 Narrative Lab agent 会话失败：${String(error)}`);
        });
    }, 260);

    return () => {
      if (agentSaveTimeoutRef.current !== null) {
        window.clearTimeout(agentSaveTimeoutRef.current);
        agentSaveTimeoutRef.current = null;
      }
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
    if (!isTauriRuntime()) {
      return;
    }

    const currentWindow = getCurrentWindow();
    let unlisten: (() => void) | undefined;
    void currentWindow
      .onCloseRequested(async (event) => {
        if (flushingBeforeCloseRef.current) {
          return;
        }

        event.preventDefault();
        flushingBeforeCloseRef.current = true;
        try {
          await flushWorkspacePersistence();
          unlisten?.();
          await currentWindow.close();
        } catch (error) {
          onStatusChange(`关闭前保存 Narrative Lab 状态失败：${String(error)}`);
          flushingBeforeCloseRef.current = false;
        }
      })
      .then((dispose) => {
        unlisten = dispose;
      });

    return () => {
      unlisten?.();
    };
  }, [
    appSettings,
    canPersist,
    chatPanelWidth,
    leftSidebarCollapsed,
    leftSidebarWidth,
    onSaveAppSettings,
    onStatusChange,
    tabState.activeTabKey,
    tabState.openTabs,
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
  const activeSubmission = activeSession?.activeSubmission ?? null;
  const queuedSubmissions = activeSession?.queuedSubmissions ?? [];
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
  const composerPlaceholder =
    activeSession?.status === "waiting_user" &&
    activeSession.pendingTurnKind === "clarification" &&
    pendingQuestions.some((question) => question.id === "action-intent")
      ? "请先确认这轮是修改当前文档，还是创建一份新文档。"
      : activeSession?.status === "waiting_user" && pendingQuestions.length
      ? pendingQuestions[0]?.placeholder?.trim() || "先回答上面的问题，我会继续推进。"
      : activeSession?.status === "waiting_user" && pendingOptions.length
        ? "也可以直接点上面的方向按钮，或补充你想要的版本。"
        : activeSession?.status === "waiting_user" && activeSession.pendingTurnKind === "plan"
          ? "如果认可这个计划，可以直接回复“继续”或补充新的约束。"
        : "像聊天一样告诉 AI 你的修改或新文档需求。Enter 发送，Shift+Enter 换行。";
  const actionIntentQuestion = pendingQuestions.find((question) => question.id === "action-intent");
  const isActionIntentClarification =
    activeSession?.status === "waiting_user" &&
    activeSession.pendingTurnKind === "clarification" &&
    Boolean(actionIntentQuestion) &&
    pendingOptions.length > 0;
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
  const mainPanelsStyle = useMemo(
    () =>
      ({
        "--narrative-left-sidebar-width": `${leftSidebarWidth}px`,
      }) as CSSProperties,
    [leftSidebarWidth],
  );

  function getDocument(documentKey: string) {
    return documentsRef.current.find((document) => document.documentKey === documentKey) ?? null;
  }

  function getSession(documentKey: string) {
    return documentAgentsRef.current[documentKey] ?? null;
  }

  function getSelectedContextDocumentsForSession(
    documentKey: string,
    session: DocumentAgentSession,
  ) {
    const documentMap = new Map(
      documentsRef.current.map((document) => [document.documentKey, document] as const),
    );

    return session.selectedContextDocKeys
      .filter((contextDocumentKey) => contextDocumentKey !== documentKey)
      .map((contextDocumentKey) => documentMap.get(contextDocumentKey) ?? null)
      .filter(Boolean) as EditableNarrativeDocument[];
  }

  function submissionStageLabel(stage: NonNullable<DocumentAgentSession["activeSubmission"]>["stage"]) {
    switch (stage) {
      case "resolving_intent":
        return "解析意图";
      case "cancelling":
        return "正在停止";
      default:
        return "生成中";
    }
  }

  function commitDocuments(
    updater: (current: EditableNarrativeDocument[]) => EditableNarrativeDocument[],
  ) {
    setDocuments((current) => {
      const next = updater(current);
      documentsRef.current = next;
      return next;
    });
  }

  function commitDocumentAgents(
    updater: (
      current: Record<string, DocumentAgentSession>,
    ) => Record<string, DocumentAgentSession>,
  ) {
    setDocumentAgents((current) => {
      const next = updater(current);
      documentAgentsRef.current = next;
      return next;
    });
  }

  async function persistWorkspaceLayoutNow(
    persistedLayout = defaultWorkspaceLayout(
      tabState.activeTabKey,
      tabState.openTabs,
      !leftSidebarCollapsed,
      leftSidebarWidth,
      chatPanelWidth,
    ),
  ) {
    if (!canPersist || !workspace.workspaceRoot.trim()) {
      return;
    }

    const serialized = JSON.stringify(persistedLayout);
    if (serialized === layoutSnapshotRef.current) {
      return;
    }

    const savedSettings = await onSaveAppSettings({
      ...appSettingsRef.current,
      workspaceLayouts: {
        ...(appSettingsRef.current.workspaceLayouts ?? {}),
        [workspace.workspaceRoot]: persistedLayout,
      },
    });
    appSettingsRef.current = savedSettings;
    layoutSnapshotRef.current = serialized;
  }

  async function persistAgentStateNow(
    persistedAgentState = buildWorkspaceAgentState(documentAgentsRef.current),
  ) {
    if (!canPersist || !workspace.workspaceRoot.trim()) {
      return;
    }

    const serialized = JSON.stringify(persistedAgentState);
    if (serialized === agentSnapshotRef.current) {
      return;
    }

    const savedSettings = await onSaveAppSettings({
      ...appSettingsRef.current,
      workspaceAgentSessions: {
        ...(appSettingsRef.current.workspaceAgentSessions ?? {}),
        [workspace.workspaceRoot]: persistedAgentState,
      },
    });
    appSettingsRef.current = savedSettings;
    agentSnapshotRef.current = serialized;
  }

  async function flushWorkspacePersistence() {
    if (layoutSaveTimeoutRef.current !== null) {
      window.clearTimeout(layoutSaveTimeoutRef.current);
      layoutSaveTimeoutRef.current = null;
    }
    if (agentSaveTimeoutRef.current !== null) {
      window.clearTimeout(agentSaveTimeoutRef.current);
      agentSaveTimeoutRef.current = null;
    }

    await persistWorkspaceLayoutNow();
    await persistAgentStateNow();
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
    setTabState((current) => {
      const next = openNarrativeTab(current, documentKey);
      tabStateRef.current = next;
      return next;
    });
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
      updateDocumentAgentSessionWithReviewQueue(current, activeDocument.documentKey, (session) => {
        const nextSession = addSelectedContextDocument(session, documentKey);
        added = nextSession !== session;
        return nextSession;
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
      updateDocumentAgentSessionWithReviewQueue(current, activeDocument.documentKey, (session) => {
        const nextSession = removeSelectedContextDocument(session, documentKey);
        removed = nextSession !== session;
        return nextSession;
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
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) =>
        updateSessionStrategyValue(session, key, value),
      ),
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
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) =>
        renameSessionTitle(session, nextTitle),
      ),
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
      updateDocumentAgentSessionWithReviewQueue(current, activeDocument.documentKey, (session) =>
        forkSessionBranch(session, nextTitle),
      ),
    );
    onStatusChange(`已基于当前会话创建分支《${nextTitle}》。`);
  }

  function archiveCurrentSession() {
    if (!activeDocument || !activeSession) {
      return;
    }
    setDocumentAgents((current) =>
      updateDocumentAgentSessionWithReviewQueue(current, activeDocument.documentKey, (session) =>
        archiveSessionBranch(session),
      ),
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
      updateDocumentAgentSessionWithReviewQueue(current, activeDocument.documentKey, (session) =>
        restoreSessionBranch(session, branch),
      ),
    );
    onStatusChange(`已恢复会话分支《${branch.title}》。`);
  }

  function clearPendingActionRequests() {
    if (!activeDocument) {
      return;
    }
    setDocumentAgents((current) =>
      updateDocumentAgentSessionWithReviewQueue(current, activeDocument.documentKey, (session) =>
        clearPendingActionRequestQueue(session),
      ),
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
    await submitNarrativePrompt(lastUserMessage.content, "composer");
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

    try {
      const result = await runNarrativeRegressionSuite({
        runCase: async (caseItem) => {
          const request: NarrativeGenerateRequest = {
            requestId: `regression-${caseItem.id}-${Date.now()}`,
            docType: activeDocument.meta.docType,
            targetSlug: activeDocument.meta.slug,
            action: "revise_document",
            userPrompt: `回归验证上下文\n\n${caseItem.prompt}`,
            editorInstruction: [
              "Regression suite",
              buildStrategyInstruction(activeSession),
              "仅判断最合适的 turn_kind，避免受历史对话干扰。",
            ].join("\n"),
            currentMarkdown: activeDocument.markdown,
            relatedDocSlugs: mergeRelatedDocSlugs(activeDocument, selectedContextDocuments),
            derivedTargetDocType: null,
          };
          const response = await invokeCommand<NarrativeGenerateResponse>(
            "revise_narrative_draft",
            {
              workspaceRoot: workspace.workspaceRoot,
              projectRoot: workspace.connectedProjectRoot ?? null,
              request,
            },
          );

          return {
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
          };
        },
      });

      setRegressionResult(result);
      setRegressionStatus(result.summary);
      onStatusChange(result.summary);
    } catch (error) {
      const message = `运行 Narrative Lab 回归验证失败：${String(error)}`;
      setRegressionStatus(message);
      onStatusChange(message);
    }
  }

  function activeRegressionDocumentKey() {
    return (
      documentsRef.current.find((document) => document.meta.slug === NARRATIVE_CHAT_REGRESSION_ACTIVE_SLUG)
        ?.documentKey ??
      documentsRef.current[0]?.documentKey ??
      null
    );
  }

  async function waitForNarrativeCondition<T>(
    label: string,
    predicate: () => T | null | undefined | false,
    timeoutMs = 20000,
    intervalMs = 80,
  ): Promise<T> {
    const startedAt = Date.now();

    while (Date.now() - startedAt < timeoutMs) {
      const value = predicate();
      if (value) {
        return value;
      }
      await new Promise((resolve) => window.setTimeout(resolve, intervalMs));
    }

    throw new Error(`等待 ${label} 超时。`);
  }

  async function loadRegressionAiConfigSummary(): Promise<NarrativeAiConfigSummary | null> {
    try {
      const settings = await invokeCommand<AiSettings>("load_ai_settings");
      const isLocalStub =
        settings.baseUrl.includes("127.0.0.1") ||
        settings.baseUrl.includes("localhost") ||
        settings.model.toLowerCase().includes("stub") ||
        settings.model.toLowerCase().includes("mock");
      return {
        baseUrl: settings.baseUrl,
        model: settings.model,
        timeoutSec: isLocalStub ? settings.timeoutSec : Math.max(settings.timeoutSec, 90),
        apiKeyConfigured: Boolean(settings.apiKey.trim()),
      };
    } catch {
      return null;
    }
  }

  function classifyRegressionFailure(
    _scenario: NarrativeChatRegressionScenario,
    response: NarrativeGenerateResponse | null,
    diagnostics: {
      domValid: boolean;
      actionMatches: boolean;
      previewMatches?: boolean;
      changeMatches: boolean;
      derivedMatches: boolean;
      contextMatches: boolean;
      timedOut?: boolean;
      errorText?: string;
    },
  ): NarrativeChatRegressionFailureKind {
    if (!response) {
      if (diagnostics.timedOut || diagnostics.errorText?.includes("超时")) {
        return "timeout_unclassified";
      }
      return "product_defect";
    }

    if (response.providerError.trim()) {
      return "provider_error";
    }

    if (response.diagnosticFlags?.includes("structured_turn_kind_classification_timeout")) {
      return "timeout_turn_kind_classification";
    }

    if (response.diagnosticFlags?.includes("structured_turn_kind_generation_timeout")) {
      return "timeout_structured_content";
    }

    if (response.diagnosticFlags?.includes("requested_actions_backfill_timeout")) {
      return "timeout_requested_actions_backfill";
    }

    if (response.diagnosticFlags?.includes("requested_actions_backfill_provider_error")) {
      return "provider_error";
    }

    if (!diagnostics.domValid || !diagnostics.changeMatches) {
      return "product_defect";
    }

    if (!diagnostics.derivedMatches && response.requestedActions.length > 0) {
      return "product_defect";
    }

    if (
      !diagnostics.actionMatches &&
      response.diagnosticFlags?.includes("missing_requested_actions_for_split")
    ) {
      return "model_variance";
    }

    if (!diagnostics.actionMatches || diagnostics.previewMatches === false || !diagnostics.contextMatches) {
      return "model_variance";
    }

    return "model_variance";
  }

  async function resetChatRegressionWorkspace(documentKey: string) {
    const resetDocuments = hydrateEditableDocuments(workspace.documents);
    commitDocuments(() => resetDocuments);
    commitDocumentAgents(() => ({
      [documentKey]: createDocumentAgentSession({ mode: "revise_document" }),
    }));
    const nextTabState = {
      openTabs: [documentKey],
      activeTabKey: documentKey,
    };
    tabStateRef.current = nextTabState;
    setTabState(nextTabState);
    setRegressionResult(null);
    setRegressionStatus("");
    setExportStatus("");
    await waitForNarrativeCondition(
      "回归工作区重置",
      () => {
        const document = getDocument(documentKey);
        const session = getSession(documentKey);
        if (!document || !session) {
          return null;
        }
        if (tabStateRef.current.activeTabKey !== documentKey) {
          return null;
        }
        if (
          session.lastResponse ||
          session.lastRequest ||
          session.activeSubmission ||
          session.pendingQuestions.length ||
          session.pendingOptions.length ||
          session.pendingActionRequests.length ||
          session.chatMessages.length
        ) {
          return null;
        }
        return true;
      },
      12000,
    );
  }

  function setScenarioContextDocuments(
    documentKey: string,
    scenario: NarrativeChatRegressionScenario,
  ) {
    const requestedDocumentKeys = (scenario.useSelectedContextSlugs ?? [])
      .map((slug) =>
        documentsRef.current.find((document) => document.meta.slug === slug)?.documentKey ?? null,
      )
      .filter(Boolean) as string[];

    commitDocumentAgents((current) =>
      updateDocumentAgentSessionWithReviewQueue(
        ensureDocumentAgentSession(current, documentKey, "edit"),
        documentKey,
        (session) => ({
          ...session,
          selectedContextDocKeys: requestedDocumentKeys,
        }),
      ),
    );
  }

  function validateRegressionDom(
    scenario: NarrativeChatRegressionScenario,
    response: NarrativeGenerateResponse | null,
  ) {
    const clarificationPanel = document.querySelector('[data-testid="narrative-clarification-panel"]');
    const optionsPanel = document.querySelector('[data-testid="narrative-options-panel"]');
    const planPanel = document.querySelector('[data-testid="narrative-plan-panel"]');
    const actionsPanel = document.querySelector('[data-testid="narrative-pending-actions-panel"]');

    if (scenario.id === "clarification-missing-brief") {
      return Boolean(clarificationPanel?.querySelector("li"));
    }
    if (scenario.id === "options-branching") {
      return (optionsPanel?.querySelectorAll('[data-testid="narrative-option-card"]').length ?? 0) >= 2;
    }
    if (scenario.id === "plan-complex-task") {
      return (planPanel?.querySelectorAll("li").length ?? 0) >= 1;
    }
    if (scenario.id === "preview-actions-only") {
      return Boolean(actionsPanel?.querySelector('[data-preview-only="true"]'));
    }
    if (scenario.id === "markdown-rich-render") {
      const chatPanel = document.querySelector('[data-testid="narrative-chat-panel"]');
      return Boolean(chatPanel?.querySelector("blockquote")) && Boolean(chatPanel?.querySelector("table"));
    }
    if (response?.turnKind === "blocked") {
      const assistantMessages = Array.from(
        document.querySelectorAll('[data-message-role="assistant"]'),
      );
      return assistantMessages.some((node) => node.textContent?.includes(response.assistantMessage ?? ""));
    }
    return true;
  }

  function inferTimedOutRegressionFailureKind(
    session: DocumentAgentSession | null | undefined,
    requestId: string,
  ): NarrativeChatRegressionFailureKind {
    if (!session) {
      return "timeout_unclassified";
    }

    const assistantMessage = session.chatMessages.find(
      (message) => message.id === assistantMessageIdForRequest(requestId),
    );
    const step = session.executionSteps.find((entry) => entry.id === session.currentStepId);
    const signals = [
      assistantMessage?.meta?.join("\n") ?? "",
      assistantMessage?.content ?? "",
      step?.detail ?? "",
      step?.previewText ?? "",
    ]
      .join("\n")
      .toLowerCase();

    if (signals.includes("补提取待批准动作") || signals.includes("backfill")) {
      return "timeout_requested_actions_backfill";
    }

    if (
      signals.includes("已判定为 clarification") ||
      signals.includes("已判定为 options") ||
      signals.includes("已判定为 plan") ||
      signals.includes("正在生成对应内容") ||
      signals.includes("结构化内容")
    ) {
      return "timeout_structured_content";
    }

    if (signals.includes("正在执行短分类") || signals.includes("回合分类")) {
      return "timeout_turn_kind_classification";
    }

    return "timeout_unclassified";
  }

  function timedOutRegressionSummary(
    session: DocumentAgentSession | null | undefined,
    requestId: string,
  ) {
    if (!session) {
      return "";
    }

    const assistantMessage = session.chatMessages.find(
      (message) => message.id === assistantMessageIdForRequest(requestId),
    );
    const step = session.executionSteps.find((entry) => entry.id === session.currentStepId);
    return (
      assistantMessage?.meta?.[0] ??
      step?.detail ??
      step?.previewText ??
      assistantMessage?.content ??
      ""
    ).trim();
  }

  async function runSingleChatRegressionScenario(
    scenario: NarrativeChatRegressionScenario,
    mode: NarrativeChatRegressionMode,
    aiConfig: NarrativeAiConfigSummary | null,
  ): Promise<NarrativeChatRegressionScenarioResult> {
    const sessionTimeoutMs = isOnlineRegressionMode(mode)
      ? Math.max(70000, (aiConfig?.timeoutSec ?? 45) * 4000 + 30000)
      : 20000;
    const documentKey = activeRegressionDocumentKey();
    if (!documentKey) {
      throw new Error("未找到 Narrative chat regression 主文稿。");
    }

    await resetChatRegressionWorkspace(documentKey);
    setScenarioContextDocuments(documentKey, scenario);
    openDocument(documentKey);

    const beforeDocument = getDocument(documentKey);
    if (!beforeDocument) {
      throw new Error("回归主文稿不存在。");
    }
    const beforeMarkdown = beforeDocument.markdown;
    const beforeDocuments = documentsRef.current.map((document) => ({
      documentKey: document.documentKey,
      slug: document.meta.slug,
      docType: document.meta.docType,
      title: document.meta.title,
      markdown: document.markdown,
    }));
    const findDerivedDocument = () => {
      const exactMatch = scenario.expectDerivedDocumentSlug
        ? documentsRef.current.find((document) => document.meta.slug === scenario.expectDerivedDocumentSlug) ?? null
        : null;
      if (exactMatch) {
        return exactMatch;
      }
      if (!scenario.allowDerivedSlugVariance) {
        return null;
      }
      return (
        documentsRef.current.find((document) => {
          if (document.documentKey === documentKey) {
            return false;
          }
          if (
            scenario.expectDerivedDocumentDocType &&
            document.meta.docType !== scenario.expectDerivedDocumentDocType
          ) {
            return false;
          }
          if (
            scenario.expectDerivedDocumentTitleIncludes &&
            !document.meta.title.includes(scenario.expectDerivedDocumentTitleIncludes)
          ) {
            return false;
          }
          const previous = beforeDocuments.find((entry) => entry.documentKey === document.documentKey);
          if (!previous) {
            return true;
          }
          return (
            previous.slug !== document.meta.slug ||
            previous.title !== document.meta.title ||
            previous.docType !== document.meta.docType ||
            normalizeNarrativeMarkdown(previous.markdown) !==
              normalizeNarrativeMarkdown(document.markdown)
          );
        }) ?? null
      );
    };

    const requestId = await submitNarrativePrompt(scenario.prompt, "composer");
    if (!requestId) {
      throw new Error(`场景 ${scenario.id} 未能成功提交请求。`);
    }

    if (scenario.id === "cancel-inflight") {
      await waitForNarrativeCondition(
        "取消场景进入可取消阶段",
        () => {
          const session = getSession(documentKey);
          if (
            (session?.activeSubmission?.requestId === requestId &&
              session.activeSubmission.stage === "generating") ||
            session?.status === "generating"
          ) {
            return true;
          }
          return null;
        },
        8000,
      );
      await cancelActiveSubmission();
      await waitForNarrativeCondition(
        "取消场景收敛",
        () => {
          const session = getSession(documentKey);
          const hasCancelMessage = Boolean(
            session?.chatMessages.some(
              (message) =>
                message.content.includes("已取消当前发送") ||
                message.content.includes("当前请求已取消"),
            ),
          );
          if (
            session &&
            !session.activeSubmission &&
            !session.busy &&
            (
              hasCancelMessage ||
              !session.lastResponse ||
              session.status === "idle" ||
              session.status === "error"
            )
          ) {
            return session;
          }
          return null;
        },
        16000,
      );

      const cancelledDocument = getDocument(documentKey);
      const documentChanged =
        normalizeNarrativeMarkdown(cancelledDocument?.markdown ?? "") !==
        normalizeNarrativeMarkdown(beforeMarkdown);

      return {
        id: scenario.id,
        label: scenario.label,
        ok: !documentChanged,
        prompt: scenario.prompt,
        mode,
        smokeTier: scenario.smokeTier,
        failureKind: documentChanged ? "product_defect" : "none",
        actualTurnKind: "blocked",
        expectedTurnKinds: scenario.expectedTurnKinds,
        requestedActionType: null,
        requestedPreviewOnly: null,
        assistantMessage: "已取消当前发送。",
        providerError: "",
        documentChanged,
        activeDocumentSlug: cancelledDocument?.meta.slug ?? beforeDocument.meta.slug,
        derivedDocumentSlug: null,
        derivedDocumentPath: null,
        contextRefCount: 0,
        questionCount: 0,
        optionCount: 0,
        planStepCount: 0,
        requestedActionCount: 0,
        turnKindSource: null,
        turnKindCorrection: null,
        diagnosticFlags: [],
        statusMessage: "已取消当前发送。",
        summary: documentChanged ? "取消后文稿仍发生变化。" : "取消后未残留半截输出。",
        error: documentChanged ? "取消请求后文稿发生了意外变化。" : null,
      };
    }

    let settledSession: DocumentAgentSession;
    try {
      settledSession = await waitForNarrativeCondition(
        `${scenario.id} 会话完成`,
        () => {
          const session = getSession(documentKey);
          if (
            session &&
            !session.activeSubmission &&
            !session.busy &&
            session.lastResponse &&
            session.lastRequest?.requestId === requestId
          ) {
            return session;
          }
          return null;
        },
        sessionTimeoutMs,
      );
    } catch (error) {
      const timedOutSession = getSession(documentKey);
      const failureKind = String(error).includes("超时")
        ? inferTimedOutRegressionFailureKind(timedOutSession, requestId)
        : "product_defect";
      const timeoutDetail = timedOutRegressionSummary(timedOutSession, requestId);
      return {
        id: scenario.id,
        label: scenario.label,
        ok: false,
        prompt: scenario.prompt,
        mode,
        smokeTier: scenario.smokeTier,
        failureKind,
        actualTurnKind: "blocked",
        expectedTurnKinds: scenario.expectedTurnKinds,
        requestedActionType: null,
        requestedPreviewOnly: null,
        assistantMessage: timeoutDetail,
        providerError: "",
        documentChanged: false,
        activeDocumentSlug: NARRATIVE_CHAT_REGRESSION_ACTIVE_SLUG,
        derivedDocumentSlug: null,
        derivedDocumentPath: null,
        contextRefCount: 0,
        questionCount: 0,
        optionCount: 0,
        planStepCount: 0,
        requestedActionCount: 0,
        turnKindSource: null,
        turnKindCorrection: null,
        diagnosticFlags: [],
        statusMessage: String(error),
        summary: timeoutDetail
          ? `场景执行失败：${String(error)} 当前阶段：${timeoutDetail}`
          : `场景执行失败：${String(error)}`,
        error: String(error),
      };
    }
    const response = settledSession.lastResponse!;
    const requestedAction = settledSession.pendingActionRequests[0] ?? null;
    const domValid = validateRegressionDom(scenario, response);

    if (scenario.expectDocumentChange && response.turnKind === "final_answer" && !response.providerError.trim()) {
      openDocument(documentKey);
      applyAllSuggestions();
      await waitForNarrativeCondition(
        `${scenario.id} 应用整篇建议`,
        () => {
          const document = getDocument(documentKey);
          if (
            document &&
            normalizeNarrativeMarkdown(document.markdown) ===
              normalizeNarrativeMarkdown(response.draftMarkdown)
          ) {
            return document;
          }
          return null;
        },
        6000,
      );
      await saveDocument(documentKey);
    }

    if (scenario.autoApproveAction && requestedAction) {
      openDocument(documentKey);
      await approveActionRequest(requestedAction.id);
      await waitForNarrativeCondition(
        `${scenario.id} agent 动作完成`,
        () => {
          const session = getSession(documentKey);
          if (session && !session.pendingActionRequests.length) {
            return true;
          }
          return null;
        },
        8000,
      );
      if (
        scenario.expectDerivedDocumentSlug ||
        (scenario.allowDerivedSlugVariance &&
          (scenario.expectDerivedDocumentDocType || scenario.expectDerivedDocumentTitleIncludes))
      ) {
        await waitForNarrativeCondition(
          `${scenario.id} 派生文稿落地`,
          () => findDerivedDocument(),
          8000,
        );
      }
    }

    if (scenario.autoRejectAction && requestedAction) {
      openDocument(documentKey);
      rejectActionRequest(requestedAction.id);
      await waitForNarrativeCondition(
        `${scenario.id} agent 动作拒绝完成`,
        () => {
          const session = getSession(documentKey);
          if (session && !session.pendingActionRequests.length) {
            return true;
          }
          return null;
        },
        4000,
      );
    }

    const afterDocument = getDocument(documentKey) ?? beforeDocument;
    const derivedDocument = findDerivedDocument();
    const documentChanged =
      normalizeNarrativeMarkdown(afterDocument.markdown) !==
      normalizeNarrativeMarkdown(beforeMarkdown);
    const actionMatches = scenario.expectedActionType
      ? requestedAction?.actionType === scenario.expectedActionType
      : true;
    const previewMatches =
      scenario.expectedPreviewOnly === undefined || scenario.expectedPreviewOnly === null
        ? true
        : requestedAction?.previewOnly === scenario.expectedPreviewOnly;
    const turnKindMatches = scenario.expectedTurnKinds.includes(response.turnKind);
    const changeMatches =
      scenario.expectDocumentChange === undefined
        ? true
        : documentChanged === scenario.expectDocumentChange;
    const derivedMatches =
      scenario.expectDerivedDocumentSlug ||
      scenario.expectDerivedDocumentDocType ||
      scenario.expectDerivedDocumentTitleIncludes
        ? Boolean(derivedDocument) &&
          (!scenario.expectDerivedDocumentSlug ||
            scenario.allowDerivedSlugVariance ||
            derivedDocument?.meta.slug === scenario.expectDerivedDocumentSlug) &&
          (!scenario.expectDerivedDocumentDocType ||
            derivedDocument?.meta.docType === scenario.expectDerivedDocumentDocType) &&
          (!scenario.expectDerivedDocumentTitleIncludes ||
            derivedDocument?.meta.title.includes(scenario.expectDerivedDocumentTitleIncludes))
        : true;
    const contextMatches = scenario.expectSelectedContextRefs ? response.usedContextRefs.length > 0 : true;

    const ok =
      turnKindMatches &&
      actionMatches &&
      previewMatches &&
      changeMatches &&
      derivedMatches &&
      contextMatches &&
      domValid;
    const failureKind = ok
      ? "none"
      : classifyRegressionFailure(scenario, response, {
          domValid,
          actionMatches,
          previewMatches,
          changeMatches,
          derivedMatches,
          contextMatches,
        });

    return {
      id: scenario.id,
      label: scenario.label,
      ok,
      prompt: scenario.prompt,
      mode,
      smokeTier: scenario.smokeTier,
      failureKind,
      actualTurnKind: response.turnKind,
      expectedTurnKinds: scenario.expectedTurnKinds,
      requestedActionType: requestedAction?.actionType ?? null,
      requestedPreviewOnly: requestedAction?.previewOnly ?? null,
      assistantMessage: response.assistantMessage,
      providerError: response.providerError,
      documentChanged,
      activeDocumentSlug: afterDocument.meta.slug,
      derivedDocumentSlug: derivedDocument?.meta.slug ?? null,
      derivedDocumentPath: derivedDocument?.relativePath ?? null,
      contextRefCount: response.usedContextRefs.length,
      questionCount: response.responseStructure?.questionCount ?? response.questions.length,
      optionCount: response.responseStructure?.optionCount ?? response.options.length,
      planStepCount: response.responseStructure?.planStepCount ?? response.planSteps.length,
      requestedActionCount:
        response.responseStructure?.requestedActionCount ?? response.requestedActions.length,
      turnKindSource: response.turnKindSource ?? null,
      turnKindCorrection: response.turnKindCorrection ?? null,
      diagnosticFlags: response.diagnosticFlags ?? [],
      statusMessage:
        response.providerError ||
        response.assistantMessage ||
        response.summary ||
        "无状态摘要",
      summary: ok
        ? response.summary || response.assistantMessage || "场景通过"
        : [
            !turnKindMatches ? `turn_kind=${response.turnKind}` : "",
            !actionMatches ? `action=${requestedAction?.actionType ?? "none"}` : "",
            !previewMatches ? `previewOnly=${String(requestedAction?.previewOnly ?? null)}` : "",
            !changeMatches ? `documentChanged=${String(documentChanged)}` : "",
            !derivedMatches ? `derived=${derivedDocument?.meta.slug ?? "missing"}` : "",
            !contextMatches ? `contextRefCount=${response.usedContextRefs.length}` : "",
            !domValid ? "dom=invalid" : "",
          ]
            .filter(Boolean)
            .join("; "),
      error: ok ? null : response.providerError || null,
    };
  }

  async function exportChatRegressionReport(report: NarrativeChatRegressionReport) {
    const input: NarrativeChatRegressionExportInput = {
      mode: report.mode,
      workspaceRoot: report.workspaceRoot,
      connectedProjectRoot: report.connectedProjectRoot ?? null,
      aiConfig: report.aiConfig ?? null,
      startedAt: report.startedAt,
      completedAt: report.completedAt,
      ok: report.ok,
      summary: report.summary,
      scenarioResults: report.scenarioResults,
      skippedScenarios: report.skippedScenarios,
    };

    return invokeCommand<NarrativeChatRegressionExportResult>(
      "export_narrative_chat_regression_report",
      {
        workspaceRoot: workspace.workspaceRoot,
        input,
      },
    );
  }

  async function runNarrativeChatRegression() {
    const mode = chatRegressionMode ?? "offline";
    const startedAt = nowIso();
    const selectedScenarios = scenariosForMode(mode, NARRATIVE_CHAT_REGRESSION_SCENARIOS);
    const aiConfig = await loadRegressionAiConfigSummary();

    if (!selectedScenarios.length) {
      onStatusChange("当前模式下没有可运行的 Narrative chat regression 场景。");
      return;
    }

    if (isOnlineRegressionMode(mode)) {
      const connection = await invokeCommand<AiConnectionTestResult>("test_ai_provider");
      if (!connection.ok) {
        const shouldSkip =
          connection.error.includes("API Key 未配置") ||
          connection.error.includes("Base URL 不能为空");
        if (shouldSkip) {
          const skippedReport = summarizeNarrativeChatRegression({
            mode,
            workspaceRoot: workspace.workspaceRoot,
            connectedProjectRoot: workspace.connectedProjectRoot ?? null,
            aiConfig,
            startedAt,
            completedAt: nowIso(),
            scenarioResults: [],
            skippedScenarios: selectedScenarios.map((scenario) => scenario.id),
          });
          const exported = await exportChatRegressionReport(skippedReport);
          onStatusChange(`在线冒烟已跳过：${connection.error} ${exported.markdownPath}`);
          if (autoCloseAfterSelfTest && isTauriRuntime()) {
            window.setTimeout(() => {
              void getCurrentWindow().close();
            }, 600);
          }
          return;
        }
      }
    }

    const scenarioResults: NarrativeChatRegressionScenarioResult[] = [];
    const skippedScenarios: string[] = [];

    for (const scenario of selectedScenarios) {
      onStatusChange(`正在运行 Narrative chat regression：${scenario.label}`);
      try {
        const result = await runSingleChatRegressionScenario(scenario, mode, aiConfig);
        scenarioResults.push(result);
        onStatusChange(scenarioResultSummary(result));
      } catch (error) {
        scenarioResults.push({
          id: scenario.id,
          label: scenario.label,
          ok: false,
          prompt: scenario.prompt,
          mode,
          smokeTier: scenario.smokeTier,
          failureKind: String(error).includes("超时") ? "timeout_unclassified" : "product_defect",
          actualTurnKind: "blocked",
          expectedTurnKinds: scenario.expectedTurnKinds,
          requestedActionType: null,
          requestedPreviewOnly: null,
          assistantMessage: "",
          providerError: "",
          documentChanged: false,
          activeDocumentSlug: NARRATIVE_CHAT_REGRESSION_ACTIVE_SLUG,
          derivedDocumentSlug: null,
          derivedDocumentPath: null,
          contextRefCount: 0,
          questionCount: 0,
          optionCount: 0,
          planStepCount: 0,
          requestedActionCount: 0,
          turnKindSource: null,
          turnKindCorrection: null,
          diagnosticFlags: [],
          statusMessage: String(error),
          summary: `场景执行失败：${String(error)}`,
          error: String(error),
        });
      }
    }

    const report = summarizeNarrativeChatRegression({
      mode,
      workspaceRoot: workspace.workspaceRoot,
      connectedProjectRoot: workspace.connectedProjectRoot ?? null,
      aiConfig,
      startedAt,
      completedAt: nowIso(),
      scenarioResults,
      skippedScenarios,
    });
    const exported = await exportChatRegressionReport(report);
    onStatusChange(`${report.summary} ${exported.markdownPath}`);

    if (autoCloseAfterSelfTest && isTauriRuntime()) {
      window.setTimeout(() => {
        void getCurrentWindow().close();
      }, 600);
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
      updateDocumentAgentSessionWithReviewQueue(current, activeDocument.documentKey, (session) =>
        resolveDerivedDocumentReview(session, slug, outcome),
      ),
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
      updateDocumentAgentSessionWithReviewQueue(current, activeDocument.documentKey, (session) =>
        clearAllDerivedDocumentsReview(session, "approved"),
      ),
    );
    onStatusChange(`已批量完成 ${count} 份派生文稿的审阅。`);
  }

  function rejectAllDerivedDocuments() {
    if (!activeDocument || !activeSession?.pendingDerivedDocuments.length) {
      return;
    }
    const count = activeSession.pendingDerivedDocuments.length;
    setDocumentAgents((current) =>
      updateDocumentAgentSessionWithReviewQueue(current, activeDocument.documentKey, (session) =>
        clearAllDerivedDocumentsReview(session, "rejected"),
      ),
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
        commitDocuments((current) => removeEditableDocument(current, document.documentKey));
        setDocumentAgents((current) => {
          const next = { ...current };
          delete next[document.documentKey];
          return next;
        });
        setTabState((current) => closeNarrativeTab(current, document.documentKey));
        onStatusChange(`已放弃本地草稿《${document.meta.title || document.meta.slug}》并关闭标签页。`);
        return;
      }

      commitDocuments((current) =>
        replaceEditableDocument(
          current,
          document.documentKey,
          revertDocumentToSnapshot(document, document.savedSnapshot),
        ),
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
      commitDocuments((current) => removeEditableDocument(current, document.documentKey));
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
      commitDocuments((current) => removeEditableDocument(current, document.documentKey));
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

  function beginSidebarResize(event: React.PointerEvent<HTMLButtonElement>) {
    if (!mainPanelsRef.current || leftSidebarCollapsed || window.innerWidth <= 1100) {
      return;
    }

    event.preventDefault();
    isResizingSidebarRef.current = true;
    document.body.style.cursor = "col-resize";
    document.body.style.userSelect = "none";

    const bounds = mainPanelsRef.current.getBoundingClientRect();
    setLeftSidebarWidth(
      clampLeftSidebarWidth(event.clientX - bounds.left - SIDEBAR_RAIL_WIDTH, bounds.width),
    );
  }

  function resetPanelWidth() {
    if (!editorPanelsRef.current) {
      setChatPanelWidth(DEFAULT_CHAT_PANEL_WIDTH);
      return;
    }

    const bounds = editorPanelsRef.current.getBoundingClientRect();
    setChatPanelWidth(clampChatPanelWidth(DEFAULT_CHAT_PANEL_WIDTH, bounds.width));
  }

  function resetSidebarWidth() {
    if (!mainPanelsRef.current) {
      setLeftSidebarWidth(DEFAULT_LEFT_SIDEBAR_WIDTH);
      return;
    }

    const bounds = mainPanelsRef.current.getBoundingClientRect();
    setLeftSidebarWidth(clampLeftSidebarWidth(DEFAULT_LEFT_SIDEBAR_WIDTH, bounds.width));
  }

  function updateDocumentState(
    documentKey: string,
    transform: (document: EditableNarrativeDocument) => EditableNarrativeDocument,
  ) {
    commitDocuments((current) => updateEditableDocument(current, documentKey, transform));
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
      const draft = markDocumentDirtyState({
        ...created,
        savedSnapshot: snapshotNarrativeDocument(created),
        dirty: false,
        isDraft: true,
      }, snapshotNarrativeDocument(created));

      commitDocuments((current) => [draft, ...current]);
      openDocument(draft.documentKey);
      setDocumentAgents((current) =>
        ensureDocumentAgentSession(current, draft.documentKey, "edit"),
      );
      onStatusChange(`已新建${docTypeLabel(docType)}。`);
      return;
    }

    const draft = buildEditableDraftDocument(
      docType,
      title,
      defaultNarrativeMarkdown(docType, title),
    );
    commitDocuments((current) => [draft, ...current]);
    openDocument(draft.documentKey);
    setDocumentAgents((current) =>
      ensureDocumentAgentSession(current, draft.documentKey, "edit"),
    );
    onStatusChange(`已创建本地${docTypeLabel(docType)}草稿。`);
  }

  function createBlankDocument() {
    void createTypedDraft(defaultDocType()).catch((error) => {
      const message = error instanceof Error ? error.message : String(error);
      onStatusChange(`新建草稿失败：${message}`);
    });
  }

  async function saveDocument(documentKey: string) {
    const documentToSave = getDocument(documentKey);
    if (!documentToSave || !documentToSave.dirty) {
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

    const savedRequestSnapshot = snapshotNarrativeDocument(documentToSave);
    const result = await invokeCommand<SaveNarrativeDocumentResult>("save_narrative_document", {
      workspaceRoot: workspace.workspaceRoot,
      input: {
        originalSlug: documentToSave.isDraft ? null : documentToSave.originalSlug,
        document: documentToSave,
      },
    });

    const nextDocument = applySavedDocumentResult(documentToSave, result);

    commitDocuments((current) =>
      current.map((document) =>
        document.documentKey === documentKey
          ? mergeSavedDocumentIntoCurrent(document, nextDocument, savedRequestSnapshot)
          : document,
      ),
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

  function isNarrativeCancellationError(error: unknown) {
    const normalized = String(error).toLowerCase();
    return normalized.includes("narrative request cancelled") || normalized.includes("request cancelled");
  }

  async function submitNarrativePrompt(
    promptOverride?: string,
    source: NarrativeSubmissionSource = promptOverride ? "option" : "composer",
  ): Promise<string | null> {
    const activeDocumentKey = tabStateRef.current.activeTabKey;
    const currentDocument = activeDocumentKey ? getDocument(activeDocumentKey) : null;
    const currentSession = currentDocument
      ? getSession(currentDocument.documentKey) ?? createDocumentAgentSession()
      : null;

    if (!currentDocument || !activeDocumentKey || !currentSession) {
      onStatusChange("请先打开一个文档标签，再和 AI 协作。");
      return null;
    }

    const submittedPrompt = (promptOverride ?? currentSession.composerText).trim();
    if (!submittedPrompt) {
      onStatusChange("请输入本轮要告诉 AI 的内容。");
      return null;
    }

    if (submissionGateRef.current[currentDocument.documentKey]) {
      return null;
    }

    submissionGateRef.current[currentDocument.documentKey] = true;
    let enqueueOutcome: "started" | "queued" | "duplicate_active" | "duplicate_tail" | null =
      null;
    let queuedCount = 0;
    let submittedRequestId: string | null = null;

    try {
      const submission = createNarrativeQueuedSubmission(submittedPrompt, source);
      submittedRequestId = submission.requestId;
      const userMessage = buildGenerationUserMessage({
        submittedPrompt: submission.prompt,
        action: null,
        messageId: `user-${submission.requestId}`,
      });
      const assistantMessageId = assistantMessageIdForRequest(submission.requestId);
      setDocumentAgents((current) =>
        updateDocumentAgentSession(current, activeDocumentKey, (session) => {
          const result = enqueueNarrativeSubmission(session, submission, {
            clearComposerText: promptOverride === undefined,
          });
          enqueueOutcome = result.outcome;
          queuedCount = result.session.queuedSubmissions.length;
          if (result.outcome !== "started") {
            return result.session;
          }

          return {
            ...result.session,
            chatMessages: replaceChatMessage(
              [...result.session.chatMessages, userMessage],
              assistantMessageId,
              {
                id: assistantMessageId,
                role: "assistant",
                label: "AI",
                content: "正在解析意图...",
                meta: ["解析意图"],
                tone: "muted",
              },
            ),
          };
        }),
      );
    } finally {
      submissionGateRef.current[currentDocument.documentKey] = false;
    }

    if (enqueueOutcome === "duplicate_active") {
      onStatusChange("相同内容已在处理中。");
      return null;
    }
    if (enqueueOutcome === "duplicate_tail") {
      onStatusChange("相同内容已在待发送队列末尾。");
      return null;
    }
    if (enqueueOutcome === "queued") {
      onStatusChange(`已加入待发送队列，当前待发送 ${queuedCount} 条。`);
      return submittedRequestId;
    }

    onStatusChange("已提交给 AI，正在处理。");
    return submittedRequestId;
  }

  async function cancelActiveSubmission() {
    const documentKey = tabStateRef.current.activeTabKey;
    const currentDocument = documentKey ? getDocument(documentKey) : null;
    const currentSession = currentDocument ? getSession(currentDocument.documentKey) : null;
    if (!currentDocument || !currentSession?.activeSubmission) {
      return;
    }

    const submission = currentSession.activeSubmission;
    if (submission.stage === "cancelling") {
      return;
    }

    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, currentDocument.documentKey, (session) =>
        session.activeSubmission?.submissionId === submission.submissionId
          ? updateActiveSubmissionStage(session, "cancelling")
          : session,
      ),
    );
    onStatusChange("正在停止当前发送...");

    try {
      const result = await invokeCommand<NarrativeCancelRequestResult>(
        "cancel_narrative_request",
        {
          requestId: submission.requestId,
        },
      );
      if (result.status === "already_finished") {
        onStatusChange("当前发送已结束，正在等待界面同步结果。");
      }
    } catch (error) {
      setDocumentAgents((current) =>
        updateDocumentAgentSession(current, currentDocument.documentKey, (session) => {
          if (session.activeSubmission?.submissionId !== submission.submissionId) {
            return session;
          }
          return updateActiveSubmissionStage(session, submission.stage);
        }),
      );
      onStatusChange(`停止当前发送失败：${String(error)}`);
    }
  }

  async function executeActiveSubmission(
    documentKey: string,
    submission: NarrativeQueuedSubmission,
  ) {
    const activeDocumentSnapshot = getDocument(documentKey);
    const sessionSnapshot = getSession(documentKey);

    if (
      !activeDocumentSnapshot ||
      !sessionSnapshot ||
      sessionSnapshot.activeSubmission?.submissionId !== submission.submissionId
    ) {
      return;
    }

    const selectedContextDocumentSnapshot = getSelectedContextDocumentsForSession(
      documentKey,
      sessionSnapshot,
    );

    const userMessage = buildGenerationUserMessage({
      submittedPrompt: submission.prompt,
      action: null,
      messageId: `user-${submission.requestId}`,
    });
    const placeholderAssistantId = assistantMessageIdForRequest(submission.requestId);

    try {
      const actionIntent = shouldBypassActionIntentResolution(submission.prompt)
        ? ({
            action: "revise_document",
            assistantMessage: "",
            questions: [],
            options: [],
          } satisfies ResolveNarrativeActionIntentResult)
        : await invokeCommand<ResolveNarrativeActionIntentResult>(
            "resolve_narrative_action_intent",
            {
              workspaceRoot: workspace.workspaceRoot,
              projectRoot: workspace.connectedProjectRoot ?? null,
              input: buildActionIntentRequest({
                requestId: submission.requestId,
                submittedPrompt: submission.prompt,
                activeDocument: activeDocumentSnapshot,
                session: sessionSnapshot,
                selectedContextDocuments: selectedContextDocumentSnapshot,
              }),
            },
          );

      if (!actionIntent.action) {
        setDocumentAgents((current) =>
          updateDocumentAgentSessionWithReviewQueue(current, documentKey, (session) =>
            promoteNextNarrativeSubmission(
              clearActiveNarrativeSubmission({
                ...session,
                updatedAt: nowIso(),
                status: "waiting_user",
                pendingQuestions: actionIntent.questions,
                pendingOptions: actionIntent.options,
                pendingTurnKind: "clarification",
                chatMessages: session.chatMessages.map((message) =>
                  message.id === placeholderAssistantId
                    ? {
                        id: placeholderAssistantId,
                        role: "assistant",
                        label: "AI",
                        content:
                          actionIntent.assistantMessage ||
                          "我还不能稳定判断这轮应该修改当前文档，还是基于它创建一份新文档。请先确认一次。",
                        meta: ["等待补充"],
                        tone: "warning",
                      }
                    : message,
                ),
              }),
            ),
          ),
        );
        onStatusChange("需要先确认本轮是修改当前文档，还是创建新文档。");
        return;
      }

      const latestDocument = getDocument(documentKey);
      const latestSession = getSession(documentKey);
      if (
        !latestDocument ||
        !latestSession ||
        latestSession.activeSubmission?.submissionId !== submission.submissionId
      ) {
        return;
      }

      const action = actionIntent.action;
      const assistantMessageId = placeholderAssistantId;

      const selectedContextDocumentsForGeneration = getSelectedContextDocumentsForSession(
        documentKey,
        latestSession,
      );
      const request = buildGenerationRequest({
        requestId: submission.requestId,
        submittedPrompt: submission.prompt,
        activeDocument: latestDocument,
        session: latestSession,
        selectedContextDocuments: selectedContextDocumentsForGeneration,
        action,
      });

      setDocumentAgents((current) =>
        updateDocumentAgentSession(current, documentKey, (session) =>
          beginGenerationSession(
            updateActiveSubmissionStage(
              {
                ...session,
                mode: action,
              },
              "generating",
            ),
            {
              requestId: submission.requestId,
              userMessage: {
                ...userMessage,
                meta: [action === "create" ? "将创建新文档" : "将修改当前文档"],
              },
              assistantMessageId,
            },
          ),
        ),
      );

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
        content: summarizeGenerationResponseForChat(narrativeResponse),
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
          `${latestDocument.meta.title} AI 草稿`,
        );
        const draftDocument = buildEditableDraftDocument(
          latestDocument.meta.docType,
          newTitle,
          narrativeResponse.draftMarkdown,
        );

        commitDocuments((current) => [draftDocument, ...current]);
        setTabState((current) => openNarrativeTab(current, draftDocument.documentKey));
        setDocumentAgents((current) => {
          const derivedSession = buildDerivedDraftSession({
            request,
            response: narrativeResponse,
            userMessage,
            assistantMessage,
            sourceDocumentKey: latestDocument.documentKey,
            sourceDocumentTitle: latestDocument.meta.title || latestDocument.meta.slug,
          });
          const next = updateDocumentAgentSessionWithReviewQueue(
            current,
            documentKey,
            (session) =>
              promoteNextNarrativeSubmission(
                clearActiveNarrativeSubmission(
                  appendContextMessage(
                    applyGenerationResponseToSession({
                      session,
                      request,
                      response: narrativeResponse,
                      assistantMessageId,
                      assistantMessage,
                    }),
                    `context-${Date.now()}`,
                    `已为当前会话生成新文档《${newTitle}》。`,
                    "success",
                  ),
                ),
              ),
          );
          next[draftDocument.documentKey] = {
            ...derivedSession,
            reviewQueue: buildReviewQueue(derivedSession),
          };
          return next;
        });
        onStatusChange(`AI 已生成新文档《${newTitle}》，已打开新标签页。`);
        return;
      }

      const hasChanges =
        narrativeResponse.turnKind === "final_answer" &&
        !narrativeResponse.providerError.trim() &&
        normalizeNarrativeMarkdown(latestDocument.markdown) !==
          normalizeNarrativeMarkdown(narrativeResponse.draftMarkdown);
      const patchSet = hasChanges
        ? buildNarrativePatchSet(latestDocument.markdown, narrativeResponse.draftMarkdown)
        : null;

      setDocumentAgents((current) =>
        updateDocumentAgentSessionWithReviewQueue(current, documentKey, (session) =>
          promoteNextNarrativeSubmission(
            clearActiveNarrativeSubmission(
              applyGenerationResponseToSession({
                session,
                request,
                response: narrativeResponse,
                assistantMessageId,
                assistantMessage,
                candidatePatchSet: patchSet,
                documentViewMode: "preview",
                versionBeforeMarkdown: latestDocument.markdown,
              }),
            ),
          ),
        ),
      );
      const missingRequestedActionAlert = narrativeResponse.diagnosticFlags?.includes(
        "missing_requested_actions_for_split",
      );
      onStatusChange(
        missingRequestedActionAlert
          ? "AI 已生成正文，但未返回预期的待批准动作；请检查 provider 输出。"
          : narrativeResponse.providerError ||
            narrativeResponse.assistantMessage ||
            narrativeResponse.summary ||
            "AI 已生成文档修改建议。",
      );
    } catch (error) {
      if (isNarrativeCancellationError(error)) {
        setDocumentAgents((current) =>
          updateDocumentAgentSessionWithReviewQueue(current, documentKey, (session) =>
            promoteNextNarrativeSubmission(
              clearActiveNarrativeSubmission(
                appendContextMessage(
                  {
                    ...session,
                    updatedAt: nowIso(),
                    status: "idle",
                  },
                  `context-cancel-${submission.requestId}`,
                  "已取消当前发送。",
                  "warning",
                ),
              ),
            ),
          ),
        );
        onStatusChange("已停止当前发送。");
        return;
      }

      const assistantMessageId = assistantMessageIdForRequest(submission.requestId);
      setDocumentAgents((current) =>
        updateDocumentAgentSessionWithReviewQueue(current, documentKey, (session) =>
          promoteNextNarrativeSubmission(
            clearActiveNarrativeSubmission(
              applyGenerationErrorToSession(session, assistantMessageId, error),
            ),
          ),
        ),
      );
      onStatusChange(`AI 执行失败：${String(error)}`);
    }
  }

  useEffect(() => {
    for (const [documentKey, session] of Object.entries(documentAgents)) {
      const activeSubmission = session.activeSubmission;
      if (!activeSubmission) {
        continue;
      }

      if (runningSubmissionRef.current[documentKey] === activeSubmission.submissionId) {
        continue;
      }

      runningSubmissionRef.current[documentKey] = activeSubmission.submissionId;
      void executeActiveSubmission(documentKey, activeSubmission).finally(() => {
        if (runningSubmissionRef.current[documentKey] === activeSubmission.submissionId) {
          delete runningSubmissionRef.current[documentKey];
        }
      });
    }
  }, [documentAgents]);

  useEffect(() => {
    if (
      selfTestStartedRef.current ||
      selfTestScenario !== "narrative-chat-regression" ||
      !startupReady ||
      !workspace.workspaceRoot.trim() ||
      !documents.length
    ) {
      return;
    }

    selfTestStartedRef.current = true;
    void runNarrativeChatRegression().catch((error) => {
      onStatusChange(`Narrative chat regression 执行失败：${String(error)}`);
    });
  }, [
    documents.length,
    onStatusChange,
    selfTestScenario,
    startupReady,
    workspace.workspaceRoot,
  ]);

  function applyPatch(patchId: string) {
    const documentKey = tabStateRef.current.activeTabKey;
    const currentDocument = documentKey ? getDocument(documentKey) : null;
    const currentSession = currentDocument ? getSession(currentDocument.documentKey) : null;
    if (!currentDocument || !currentSession?.candidatePatchSet || !currentSession.lastResponse) {
      return;
    }

    const patch = currentSession.candidatePatchSet.patches.find((entry) => entry.id === patchId);
    if (!patch) {
      return;
    }

    const nextMarkdown = applyNarrativePatch(currentDocument.markdown, patch);
    updateDocumentState(currentDocument.documentKey, (document) => ({
      ...document,
      markdown: nextMarkdown,
    }));

    const nextPatchSet = buildNarrativePatchSet(
      nextMarkdown,
      currentSession.lastResponse.draftMarkdown,
    );
    const isComplete =
      normalizeNarrativeMarkdown(nextMarkdown) ===
      normalizeNarrativeMarkdown(currentSession.lastResponse.draftMarkdown);

    setDocumentAgents((current) =>
      updateDocumentAgentSessionWithReviewQueue(current, currentDocument.documentKey, (session) =>
        appendContextMessage(
          {
            ...session,
            candidatePatchSet: isComplete ? null : nextPatchSet,
          },
          `context-apply-${Date.now()}`,
          `已应用 ${patch.title}。`,
          "success",
        ),
      ),
    );
    onStatusChange(`已应用 ${patch.title}。`);
  }

  function applyAllSuggestions() {
    const documentKey = tabStateRef.current.activeTabKey;
    const currentDocument = documentKey ? getDocument(documentKey) : null;
    const currentSession = currentDocument ? getSession(currentDocument.documentKey) : null;
    if (!currentDocument || !currentSession?.lastResponse?.draftMarkdown.trim()) {
      return;
    }

    updateDocumentState(currentDocument.documentKey, (document) => ({
      ...document,
      markdown: currentSession.lastResponse?.draftMarkdown ?? document.markdown,
    }));
    setDocumentAgents((current) =>
      updateDocumentAgentSessionWithReviewQueue(current, currentDocument.documentKey, (session) =>
        appendContextMessage(
          {
            ...session,
            candidatePatchSet: null,
          },
          `context-apply-all-${Date.now()}`,
          "已应用整篇 AI 建议。",
          "success",
        ),
      ),
    );
    onStatusChange("已应用整篇 AI 建议。");
  }

  function discardCurrentSuggestions() {
    const documentKey = tabStateRef.current.activeTabKey;
    const currentDocument = documentKey ? getDocument(documentKey) : null;
    if (!currentDocument) {
      return;
    }

    setDocumentAgents((current) =>
      updateDocumentAgentSessionWithReviewQueue(current, currentDocument.documentKey, (session) =>
        appendContextMessage(
          {
            ...session,
            candidatePatchSet: null,
          },
          `context-discard-suggestions-${Date.now()}`,
          "已清空当前 patch 建议。",
          "warning",
        ),
      ),
    );
    onStatusChange("已清空当前 patch 建议。");
  }

  function applyAgentDocumentResult(
    result: AgentActionResult,
    requestId: string,
    sourceDocumentKey?: string | null,
  ) {
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

    if (derivedSummaries.length && sourceDocumentKey) {
      setDocumentAgents((current) =>
        updateDocumentAgentSessionWithReviewQueue(current, sourceDocumentKey, (session) =>
          mergePendingDerivedDocuments(session, derivedSummaries),
        ),
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

    commitDocuments((current) => {
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
      setDocumentAgents((current) =>
        updateDocumentAgentSessionWithReviewQueue(
          ensureDocumentAgentSession(current, nextDocument.documentKey, "preview"),
          nextDocument.documentKey,
          (session) =>
            appendContextMessage(
              session,
              `context-agent-created-${requestId}`,
              `该文稿由 agent 动作创建：${result.summary}`,
              "success",
            ),
        ),
      );
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
    const documentKey = tabStateRef.current.activeTabKey;
    const currentDocument = documentKey ? getDocument(documentKey) : null;
    const currentSession = currentDocument ? getSession(currentDocument.documentKey) : null;
    if (!currentDocument || !currentSession) {
      return;
    }

    const request = currentSession.pendingActionRequests.find((entry) => entry.id === requestId);
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
            currentDocument: currentDocument,
          },
        });

        if (result.openedSlug) {
          const existing = documentsRef.current.find((document) => document.meta.slug === result.openedSlug);
          if (existing) {
            openDocument(existing.documentKey);
          }
        }

        applyAgentDocumentResult(result, requestId, currentDocument.documentKey);
      }

      setDocumentAgents((current) =>
        updateDocumentAgentSessionWithReviewQueue(current, currentDocument.documentKey, (session) =>
          resolveActionRequestSession(
            session,
            requestId,
            result,
            `context-agent-action-${requestId}`,
            result.status === "failed" ? "danger" : "success",
          ),
        ),
      );
      onStatusChange(result.summary);
    } catch (error) {
      const failedResult: AgentActionResult = {
        ...baseResult,
        status: "failed",
        summary: `agent 动作执行失败：${String(error)}`,
      };
      setDocumentAgents((current) =>
        updateDocumentAgentSessionWithReviewQueue(current, currentDocument.documentKey, (session) =>
          resolveActionRequestSession(
            session,
            requestId,
            failedResult,
            `context-agent-action-error-${requestId}`,
            "danger",
            failedResult.summary,
          ),
        ),
      );
      onStatusChange(failedResult.summary);
    }
  }

  function rejectActionRequest(requestId: string) {
    const documentKey = tabStateRef.current.activeTabKey;
    const currentDocument = documentKey ? getDocument(documentKey) : null;
    const currentSession = currentDocument ? getSession(currentDocument.documentKey) : null;
    if (!currentDocument || !currentSession) {
      return;
    }
    const request = currentSession.pendingActionRequests.find((entry) => entry.id === requestId);
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
      updateDocumentAgentSessionWithReviewQueue(current, currentDocument.documentKey, (session) =>
        resolveActionRequestSession(
          session,
          requestId,
          result,
          `context-agent-action-reject-${requestId}`,
          "warning",
          result.summary,
        ),
      ),
    );
    onStatusChange(result.summary);
  }

  function clearCurrentConversation() {
    if (!activeDocument) {
      return;
    }

    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) =>
        clearConversationSession(session),
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
          await submitNarrativePrompt();
        },
        isEnabled: () =>
          Boolean(activeDocument) &&
          !(activeSession?.pendingActionRequests.length ?? 0),
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
      activeSession?.documentViewMode,
      activeSession?.pendingActionRequests.length,
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
        ref={mainPanelsRef}
        className={`narrative-streamlined-main ${
          leftSidebarCollapsed ? "narrative-streamlined-main-collapsed" : ""
        }`.trim()}
        style={mainPanelsStyle}
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
          <>
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

            <button
              type="button"
              className="narrative-sidebar-splitter"
              onPointerDown={beginSidebarResize}
              onDoubleClick={resetSidebarWidth}
              aria-label="调整文档列表宽度"
              title="拖动调整文档列表宽度，双击恢复默认宽度"
            />
          </>
        ) : null}

        <div
          ref={editorPanelsRef}
          className="narrative-editor-panels"
          style={editorPanelsStyle}
        >
        <section className="narrative-chat-panel">
          {activeDocument && activeSession ? (
            <>
              <div className="narrative-chat-sticky-topbar">
                <div className="narrative-chat-topbar-row">
                  <div
                    className="narrative-chat-context-strip narrative-chat-context-strip-compact"
                    title={buildUsedContextSummary(activeSession.lastResponse?.usedContextRefs ?? [])}
                  >
                    <span className="narrative-chat-context-strip-label">上下文</span>
                    <div className="narrative-chat-context-strip-scroller">
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
                        <span className="narrative-chat-context-empty">仅主文稿</span>
                      )}
                    </div>
                  </div>

                  <div className="narrative-chat-topbar-actions">
                    {activeSubmission ? (
                      <Badge tone={activeSubmission.stage === "cancelling" ? "warning" : "accent"}>
                        {submissionStageLabel(activeSubmission.stage)}
                      </Badge>
                    ) : null}
                    {queuedSubmissions.length ? (
                      <Badge tone="muted">排队 {queuedSubmissions.length}</Badge>
                    ) : null}
                    {activeSession.status === "waiting_user" ? <Badge tone="warning">等待补充</Badge> : null}
                    <button
                      type="button"
                      className="toolbar-button"
                      onClick={() => void openOrFocusSettingsWindow("ai")}
                    >
                      设置
                    </button>
                  </div>
                </div>
              </div>

              <div className="narrative-chat-log" data-testid="narrative-chat-panel">
                {activeSession.chatMessages.length ? (
                  activeSession.chatMessages.map((message) => (
                    <article
                      key={message.id}
                      className={`narrative-chat-message narrative-chat-message-${message.role}`.trim()}
                      data-message-role={message.role}
                    >
                      {message.role === "context" ? (
                        <div className="narrative-chat-message-header">
                          <strong>{message.label}</strong>
                          {message.tone ? <Badge tone={message.tone}>{message.role}</Badge> : null}
                        </div>
                      ) : null}
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
                    <p>这个文档还没有 AI 会话。告诉 AI 你想扩写、修改，或基于当前文稿派生新文档。</p>
                  </div>
                )}

                {isActionIntentClarification && actionIntentQuestion ? (
                  <article
                    className="narrative-chat-message narrative-chat-message-context"
                    data-testid="narrative-clarification-panel"
                  >
                    <div className="narrative-chat-message-header">
                      <strong>确认动作</strong>
                      <Badge tone="warning">clarification</Badge>
                    </div>
                    <p style={{ whiteSpace: "pre-wrap" }}>{actionIntentQuestion.label}</p>
                    <div className="narrative-option-list">
                      {pendingOptions.map((option) => (
                        <button
                          key={option.id}
                          type="button"
                          className="narrative-option-card"
                          data-testid="narrative-option-card"
                          onClick={() => void submitNarrativePrompt(option.followupPrompt, "option")}
                          title={option.followupPrompt || option.description}
                        >
                          <strong>{option.label}</strong>
                          <span>{option.description || "确认这个动作后继续推进当前会话。"}</span>
                        </button>
                      ))}
                    </div>
                  </article>
                ) : null}

                {!isActionIntentClarification && pendingQuestions.length ? (
                  <article
                    className="narrative-chat-message narrative-chat-message-context"
                    data-testid="narrative-clarification-panel"
                  >
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

                {!isActionIntentClarification && pendingOptions.length ? (
                  <article
                    className="narrative-chat-message narrative-chat-message-context"
                    data-testid="narrative-options-panel"
                  >
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
                          data-testid="narrative-option-card"
                          onClick={() => void submitNarrativePrompt(option.followupPrompt, "option")}
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
                  <article
                    className="narrative-chat-message narrative-chat-message-context"
                    data-testid="narrative-plan-panel"
                  >
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

                {pendingActions.length ? (
                  <article
                    className="narrative-chat-message narrative-chat-message-context"
                    data-testid="narrative-pending-actions-panel"
                  >
                    <div className="narrative-chat-message-header">
                      <strong>待批准动作</strong>
                      <Badge tone="warning">approval</Badge>
                    </div>
                    <p style={{ whiteSpace: "pre-wrap" }}>
                      这些动作不会自动执行，只有你批准后才会继续。
                    </p>
                    {pendingActions.map((action) => (
                      <div
                        key={action.id}
                        className="narrative-empty-state"
                        style={{ marginBottom: 12 }}
                        data-action-type={action.actionType}
                        data-preview-only={action.previewOnly ? "true" : "false"}
                      >
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

              </div>

              <div className="narrative-chat-composer">
                {queuedSubmissions.length ? (
                  <div className="narrative-submission-status">
                    <div className="narrative-submission-status-main">
                      <strong>待发送</strong>
                      <span
                        className="narrative-submission-status-text"
                        title={queuedSubmissions[0]?.prompt ?? ""}
                      >
                        {queuedSubmissions[0]?.prompt ?? ""}
                      </span>
                      <span className="narrative-submission-status-meta">
                        后续 {queuedSubmissions.length} 条
                      </span>
                    </div>
                  </div>
                ) : null}
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
                      void submitNarrativePrompt();
                    }
                  }}
                  onPaste={(event) => {
                    const items = event.clipboardData?.items;
                    if (!items) {
                      return;
                    }
                    for (const item of items) {
                      if (item.type.startsWith("image/")) {
                        event.preventDefault();
                        onStatusChange("当前 AI 模型不支持图片输入，请仅粘贴文本内容。");
                        return;
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
                      className="toolbar-button toolbar-accent narrative-chat-send-button"
                      onClick={() => void submitNarrativePrompt()}
                    >
                      {activeSubmission ? "加入队列" : "发送给 AI"}
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
            {activeDocument && activeSession ? (
              <div className="segmented-control narrative-document-view-switch">
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
            ) : null}
            {activeDocument ? (
              <Badge tone={activeDocument.dirty ? "warning" : "success"}>
                {activeDocument.dirty ? "未保存" : "已保存"}
              </Badge>
            ) : null}
          </div>

          {activeDocument && activeSession ? (
            <>
              {activeSession.documentViewMode === "edit" ? (
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
                </div>
              ) : null}

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
                                <div>
                                  <strong>{patch.title}</strong>
                                  <div className="toolbar-summary">
                                    {patch.sectionTitle ? <Badge tone="muted">{patch.sectionTitle}</Badge> : null}
                                    <Badge tone="muted">{patchKindLabel(patch.patchKind)}</Badge>
                                  </div>
                                </div>
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
                                  <div>
                                    <strong>{patch.title}</strong>
                                    <div className="toolbar-summary">
                                      {patch.sectionTitle ? <Badge tone="muted">{patch.sectionTitle}</Badge> : null}
                                      <Badge tone="muted">{patchKindLabel(patch.patchKind)}</Badge>
                                    </div>
                                  </div>
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
                      <p className="field-hint">
                        当前无法稳定拆成局部 patch，整篇应用会直接覆盖当前文稿，建议先通读后再执行。
                      </p>
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
          ref={docContextMenuRef}
          className="narrative-context-menu"
          style={{ left: docContextMenu.x, top: docContextMenu.y }}
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
