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
  AiChatMessage,
  AiSettings,
  DocumentAgentSession,
  EditorMenuSelfTestScenario,
  NarrativeAppSettings,
  NarrativeDocType,
  NarrativeDocumentPayload,
  NarrativeDocumentViewMode,
  NarrativeGenerateRequest,
  NarrativeGenerationProgressEvent,
  NarrativeGenerateResponse,
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
import { docTypeDirectory } from "./narrativeTemplates";

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

const DEFAULT_CHAT_PANEL_WIDTH = 440;
const MIN_CHAT_PANEL_WIDTH = 320;
const MAX_CHAT_PANEL_WIDTH = 720;
const MIN_DOCUMENT_PANEL_WIDTH = 360;
const PANEL_SPLITTER_WIDTH = 12;
const NARRATIVE_GENERATION_PROGRESS_EVENT = "narrative:generation-progress";

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

function defaultAiSettings(): AiSettings {
  return {
    baseUrl: "https://api.openai.com/v1",
    model: "gpt-4.1-mini",
    apiKey: "",
    timeoutSec: 45,
    maxContextRecords: 24,
  };
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

  sections.push(`本次请求：${input.trim()}`);
  return sections.join("\n\n");
}

function summarizeResponseForChat(response: {
  providerError: string;
  summary: string;
  synthesisNotes: string[];
}) {
  const headline = response.providerError.trim() || response.summary.trim() || "AI 已返回结果。";
  const notes = response.synthesisNotes.map((note) => note.trim()).filter(Boolean).slice(0, 2);
  return notes.length ? [headline, ...notes].join("\n\n") : headline;
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

export function NarrativeWorkspace({
  workspace,
  appSettings,
  canPersist,
  startupReady,
  selfTestScenario: _selfTestScenario,
  status,
  runtimeLabel,
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
  const [aiSettings, setAiSettings] = useState<AiSettings>(defaultAiSettings());
  const [saving, setSaving] = useState(false);
  const editorRef = useRef<HTMLTextAreaElement | null>(null);
  const editorPanelsRef = useRef<HTMLDivElement | null>(null);
  const isResizingPanelsRef = useRef(false);
  const documentsRef = useRef<EditableNarrativeDocument[]>(documents);
  const documentAgentsRef = useRef<Record<string, DocumentAgentSession>>(documentAgents);
  const tabStateRef = useRef<NarrativeTabState>(tabState);
  const workspaceRootRef = useRef("");
  const layoutSnapshotRef = useRef("");

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

    setDocuments(nextDocuments);
    setTabState(initial.tabState);
    setLeftSidebarCollapsed(initial.leftSidebarCollapsed);
    setChatPanelWidth(initial.chatPanelWidth);
    layoutSnapshotRef.current = initial.layoutSnapshot;
    setDocumentAgents((current) => {
      const baseSessions = workspaceRootRef.current === workspace.workspaceRoot ? current : {};
      const nextSessions = { ...baseSessions };
      for (const documentKey of initial.tabState.openTabs) {
        if (!nextSessions[documentKey]) {
          nextSessions[documentKey] = createDocumentAgentSession();
        }
      }
      return nextSessions;
    });
    workspaceRootRef.current = workspace.workspaceRoot;
  }, [appSettings, workspace]);

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
      workspace.docTypes.find((entry) => entry.value === "scene_draft")?.value ??
      workspace.docTypes[0]?.value ??
      "project_brief"
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
    setTabState((current) => openNarrativeTab(current, documentKey));
    setDocumentAgents((current) => ensureDocumentAgentSession(current, documentKey));
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
    const document = getDocument(documentKey);
    if (!document) {
      return;
    }
    if (document.dirty) {
      onStatusChange(`请先保存 ${document.meta.title || document.meta.slug}，再关闭标签页。`);
      return;
    }

    setTabState((current) => closeNarrativeTab(current, documentKey));
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

  function createBlankDocument() {
    const docType = defaultDocType();
    const title = `未命名文档 ${documentsRef.current.filter((document) => document.isDraft).length + 1}`;
    const draft = buildLocalDraft(docType, title, `# ${title}\n\n`);
    setDocuments((current) => [draft, ...current]);
    openDocument(draft.documentKey);
    setDocumentAgents((current) =>
      ensureDocumentAgentSession(current, draft.documentKey, "edit"),
    );
    onStatusChange(`已创建本地草稿 ${title}。`);
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

    if (activeDocument.isDraft) {
      setDocuments((current) =>
        current.filter((document) => document.documentKey !== activeDocument.documentKey),
      );
      setTabState((current) => closeNarrativeTab(current, activeDocument.documentKey));
      onStatusChange(`已移除本地草稿 ${activeDocument.meta.title || activeDocument.meta.slug}。`);
      return;
    }

    if (!canPersist) {
      onStatusChange("当前运行在回退模式，无法删除文档。");
      return;
    }

    try {
      await invokeCommand("delete_narrative_document", {
        workspaceRoot: workspace.workspaceRoot,
        slug: activeDocument.meta.slug,
      });
      setDocuments((current) =>
        current.filter((document) => document.documentKey !== activeDocument.documentKey),
      );
      setTabState((current) => closeNarrativeTab(current, activeDocument.documentKey));
      onStatusChange(`已删除文档 ${activeDocument.meta.title || activeDocument.meta.slug}。`);
    } catch (error) {
      onStatusChange(`删除文档失败：${String(error)}`);
    }
  }

  async function runGeneration() {
    if (!activeDocument || !tabState.activeTabKey || !activeSession) {
      onStatusChange("请先打开一个文档标签，再和 AI 协作。");
      return;
    }

    const submittedPrompt = activeSession.composerText.trim();
    if (!submittedPrompt) {
      onStatusChange("请输入本轮要告诉 AI 的内容。");
      return;
    }

    const activeDocumentKey = activeDocument.documentKey;
    const action = activeSession.mode;
    const requestId = `generation-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
    const assistantMessageId = assistantMessageIdForRequest(requestId);
    const userMessage: AiChatMessage = {
      id: `user-${Date.now()}`,
      role: "user",
      label: "你",
      content: submittedPrompt,
      meta: [action === "create" ? "生成新文档" : "修改当前文档"],
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
      userPrompt: buildNarrativeChatPrompt(submittedPrompt, activeSession.chatMessages, activeDocument),
      editorInstruction: "",
      currentMarkdown: activeDocument.markdown,
      relatedDocSlugs: activeDocument.meta.relatedDocs,
      derivedTargetDocType: null,
    };

    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocumentKey, (session) => ({
        ...session,
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
        meta: [
          narrativeResponse.providerError ? "提供方返回错误" : "已生成结果",
          narrativeResponse.engineMode === "single_agent" ? "单文档助手" : "多 agent",
        ],
        tone: narrativeResponse.providerError ? "danger" : "success",
      };

      if (
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
          const next = updateDocumentAgentSession(current, activeDocumentKey, (session) => ({
            ...session,
            busy: false,
            inflightRequestId: null,
            lastRequest: request,
            lastResponse: narrativeResponse,
            candidatePatchSet: null,
            chatMessages: [
              ...replaceChatMessage(session.chatMessages, assistantMessageId, assistantMessage),
              {
                id: `context-${Date.now()}`,
                role: "context",
                label: "系统",
                content: `已为当前会话生成新文档《${newTitle}》。`,
                tone: "success",
              },
            ],
          }));

          next[draftDocument.documentKey] = {
            ...createDocumentAgentSession(),
            mode: "revise_document",
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
            busy: false,
            inflightRequestId: null,
            documentViewMode: "preview",
            composerText: "",
          };
          return next;
        });
        onStatusChange(`AI 已生成新文档《${newTitle}》，已打开新标签页。`);
        return;
      }

      const hasChanges =
        !narrativeResponse.providerError.trim() &&
        normalizeNarrativeMarkdown(activeDocument.markdown) !==
          normalizeNarrativeMarkdown(narrativeResponse.draftMarkdown);
      const patchSet = hasChanges
        ? buildNarrativePatchSet(activeDocument.markdown, narrativeResponse.draftMarkdown)
        : null;

      setDocumentAgents((current) =>
        updateDocumentAgentSession(current, activeDocumentKey, (session) => ({
          ...session,
          busy: false,
          inflightRequestId: null,
          lastRequest: request,
          lastResponse: narrativeResponse,
          candidatePatchSet: patchSet,
          documentViewMode: "preview",
          chatMessages: replaceChatMessage(session.chatMessages, assistantMessageId, assistantMessage),
        })),
      );
      onStatusChange(
        narrativeResponse.providerError || narrativeResponse.summary || "AI 已生成文档修改建议。",
      );
    } catch (error) {
      setDocumentAgents((current) =>
        updateDocumentAgentSession(current, activeDocumentKey, (session) => ({
          ...session,
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
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => ({
        ...session,
        candidatePatchSet: isComplete ? null : nextPatchSet,
        chatMessages: [
          ...session.chatMessages,
          {
            id: `context-apply-${Date.now()}`,
            role: "context",
            label: "系统",
            content: `已应用 ${patch.title}。`,
            tone: "success",
          },
        ],
      })),
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
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => ({
        ...session,
        candidatePatchSet: null,
        chatMessages: [
          ...session.chatMessages,
          {
            id: `context-apply-all-${Date.now()}`,
            role: "context",
            label: "系统",
            content: "已应用整篇 AI 建议。",
            tone: "success",
          },
        ],
      })),
    );
    onStatusChange("已应用整篇 AI 建议。");
  }

  function clearCurrentConversation() {
    if (!activeDocument) {
      return;
    }

    setDocumentAgents((current) =>
      updateDocumentAgentSession(current, activeDocument.documentKey, (session) => ({
        ...createDocumentAgentSession(),
        mode: session.mode,
        documentViewMode: session.documentViewMode,
      })),
    );
    onStatusChange("已清空当前文档的 AI 会话。");
  }

  const menuCommands = useMemo(
    () => ({
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: {
        execute: () => {
          createBlankDocument();
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
            <span className="section-label">Narrative Lab</span>
            <h2>多文档 AI 写作台</h2>
          </div>
          <div className="narrative-topbar-meta">
            <Badge tone="accent">{runtimeLabel}</Badge>
            <Badge tone={workspace.workspaceRoot ? "success" : "warning"}>
              {workspace.workspaceRoot ? "工作区已连接" : "未选择工作区"}
            </Badge>
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
            工作区设置
          </button>
          <button
            type="button"
            className="toolbar-button"
            onClick={() => void openOrFocusSettingsWindow("ai")}
          >
            AI 设置
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
                onClick={(event) => {
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
              <div>
                <span className="section-label">文档</span>
                <h3>工作区文章列表</h3>
              </div>
              <Badge tone="muted">{documents.length}</Badge>
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
                  >
                    <div className="narrative-doc-row-main">
                      <strong>{document.meta.title || document.meta.slug}</strong>
                      <span>{document.relativePath}</span>
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
            <div>
              <span className="section-label">AI</span>
              <h3>文档专属 Agent 会话</h3>
            </div>
            <div className="toolbar-summary">
              <Badge tone="muted">{aiSettings.model || "未配置模型"}</Badge>
              {activeSession?.busy ? <Badge tone="warning">生成中</Badge> : null}
            </div>
          </div>

          {activeDocument && activeSession ? (
            <>
              <div className="narrative-chat-toolbar">
                <div className="narrative-chat-context-inline" title={activeDocument.relativePath}>
                  <strong>{activeDocument.meta.title || activeDocument.meta.slug}</strong>
                  <span>{activeDocument.relativePath}</span>
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
                      <p>{message.content}</p>
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
                  placeholder="像聊天一样告诉 AI 你的修改或新文档需求。Enter 发送，Shift+Enter 换行。"
                />
                <div className="narrative-chat-composer-footer">
                  <div className="toolbar-summary">
                    <Badge tone="muted">
                      {activeSession.mode === "create" ? "生成新文档" : "修改当前文档"}
                    </Badge>
                    <Badge tone="muted">{activeDocument.meta.slug}</Badge>
                  </div>
                  <div className="toolbar-actions">
                    <button type="button" className="toolbar-button" onClick={() => clearCurrentConversation()}>
                      清空会话
                    </button>
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
            <div>
              <span className="section-label">文档</span>
              <h3>{activeDocument ? activeDocument.meta.title || activeDocument.meta.slug : "未选择文档"}</h3>
            </div>
            <div className="toolbar-summary">
              {activeDocument ? (
                <>
                  <Badge tone={activeDocument.dirty ? "warning" : "success"}>
                    {activeDocument.dirty ? "未保存" : "已保存"}
                  </Badge>
                  <Badge tone="muted">{activeDocument.meta.slug}</Badge>
                </>
              ) : null}
            </div>
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
                                  Apply
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
                                    Apply
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
                          Apply All
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

      <footer className="narrative-streamlined-statusbar">
        <div className="narrative-streamlined-status-main">
          <span className="status-dot" />
          <span>{status}</span>
        </div>
        <div className="toolbar-summary">
          <Badge tone="muted">{`${documents.length} 篇文档`}</Badge>
          <Badge tone={dirtyCount > 0 ? "warning" : "success"}>
            {dirtyCount > 0 ? `${dirtyCount} 篇未保存` : "全部已保存"}
          </Badge>
          {activeDocument ? <Badge tone="accent">{activeDocument.meta.docType}</Badge> : null}
        </div>
      </footer>
    </div>
  );
}
