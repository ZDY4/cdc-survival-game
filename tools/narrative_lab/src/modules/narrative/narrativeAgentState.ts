import type {
  AgentActionResult,
  AiChatMessage,
  NarrativeCandidatePatch,
  DocumentAgentSession,
  NarrativeAgentStrategy,
  NarrativeAppSettings,
  NarrativeGenerateRequest,
  NarrativeGenerateResponse,
  NarrativeReviewQueueItem,
  NarrativeVersionSnapshot,
  PersistedDocumentAgentSessionState,
  SavedDocumentAgentBranch,
} from "../../types";

// Agent 会话持久化层：
// 负责快照裁剪、恢复时的安全归一化，以及 review queue 的重建，避免 settings 无限膨胀。
const MAX_PERSISTED_CHAT_MESSAGES = 40;
const MAX_PERSISTED_ACTION_HISTORY = 20;
const MAX_PERSISTED_VERSION_HISTORY = 8;
const MAX_PERSISTED_DERIVED_DOCUMENTS = 16;
const MAX_PERSISTED_PATCHES = 24;
const MAX_PERSISTED_TEXT = 4_000;
const MAX_PERSISTED_MARKDOWN = 16_000;

export function nowIso() {
  return new Date().toISOString();
}

export function createSessionId() {
  return `session-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

export function defaultNarrativeAgentStrategy(): NarrativeAgentStrategy {
  return {
    rewriteIntensity: "balanced",
    priority: "consistency",
    questionBehavior: "balanced",
  };
}

function truncateText(value: string | undefined | null, maxLength: number) {
  const text = value?.trim() ?? "";
  if (text.length <= maxLength) {
    return text;
  }
  return `${text.slice(0, Math.max(0, maxLength - 1)).trimEnd()}…`;
}

function trimChatMessages(messages: AiChatMessage[]): AiChatMessage[] {
  return messages.slice(-MAX_PERSISTED_CHAT_MESSAGES).map((message) => ({
    ...message,
    content: truncateText(message.content, MAX_PERSISTED_TEXT),
    meta: message.meta?.slice(0, 6),
  }));
}

function trimGenerateRequest(
  request: NarrativeGenerateRequest | null,
): NarrativeGenerateRequest | null {
  if (!request) {
    return null;
  }

  return {
    ...request,
    userPrompt: truncateText(request.userPrompt, MAX_PERSISTED_TEXT),
    editorInstruction: truncateText(request.editorInstruction, 1_500),
    currentMarkdown: truncateText(request.currentMarkdown, MAX_PERSISTED_MARKDOWN),
    selectedText: truncateText(request.selectedText ?? "", 1_200),
    relatedDocSlugs: request.relatedDocSlugs.slice(0, MAX_PERSISTED_DERIVED_DOCUMENTS),
  };
}

function trimPatch(patch: NarrativeCandidatePatch): NarrativeCandidatePatch {
  return {
    ...patch,
    title: truncateText(patch.title, 120),
    originalText: truncateText(patch.originalText, MAX_PERSISTED_TEXT),
    replacementText: truncateText(patch.replacementText, MAX_PERSISTED_TEXT),
  };
}

function trimGenerateResponse(
  response: NarrativeGenerateResponse | null,
): NarrativeGenerateResponse | null {
  if (!response) {
    return null;
  }

  return {
    ...response,
    assistantMessage: truncateText(response.assistantMessage, MAX_PERSISTED_TEXT),
    draftMarkdown: truncateText(response.draftMarkdown, MAX_PERSISTED_MARKDOWN),
    summary: truncateText(response.summary, 1_200),
    reviewNotes: response.reviewNotes.slice(0, 12).map((note) => truncateText(note, 320)),
    promptDebug: {},
    rawOutput: truncateText(response.rawOutput, MAX_PERSISTED_TEXT),
    usedContextRefs: response.usedContextRefs.slice(0, MAX_PERSISTED_DERIVED_DOCUMENTS),
    diffPreview: truncateText(response.diffPreview, 2_000),
    providerError: truncateText(response.providerError, 1_200),
    synthesisNotes: response.synthesisNotes
      .slice(0, 8)
      .map((note) => truncateText(note, 320)),
    agentRuns: response.agentRuns.slice(0, 6).map((run) => ({
      ...run,
      summary: truncateText(run.summary, 320),
      notes: run.notes.slice(0, 6).map((note) => truncateText(note, 200)),
      draftMarkdown: truncateText(run.draftMarkdown, 4_000),
      rawOutput: truncateText(run.rawOutput, 1_200),
      providerError: truncateText(run.providerError, 500),
    })),
    questions: response.questions.slice(0, 4),
    options: response.options.slice(0, 4),
    planSteps: response.planSteps.slice(0, 8),
    executionSteps: response.executionSteps.slice(-8).map((step) => ({
      ...step,
      detail: truncateText(step.detail, 240),
      previewText: truncateText(step.previewText ?? "", 320),
    })),
    requestedActions: response.requestedActions.slice(0, 10).map((action) => ({
      ...action,
      title: truncateText(action.title, 120),
      description: truncateText(action.description, 240),
    })),
    sourceDocumentKeys: response.sourceDocumentKeys.slice(0, MAX_PERSISTED_DERIVED_DOCUMENTS),
    provenanceRefs: response.provenanceRefs.slice(0, MAX_PERSISTED_DERIVED_DOCUMENTS),
    reviewQueueItems: response.reviewQueueItems.slice(0, 12),
  };
}

function trimActionHistory(actionHistory: AgentActionResult[]): AgentActionResult[] {
  return actionHistory.slice(-MAX_PERSISTED_ACTION_HISTORY).map((entry) => ({
    ...entry,
    summary: truncateText(entry.summary, 320),
    document: entry.document
      ? {
          ...entry.document,
          markdown: "",
          validation: [],
        }
      : entry.document,
    documentSummaries: entry.documentSummaries?.slice(0, 8),
  }));
}

function trimVersionHistory(versionHistory: NarrativeVersionSnapshot[]): NarrativeVersionSnapshot[] {
  return versionHistory.slice(-MAX_PERSISTED_VERSION_HISTORY).map((entry) => ({
    ...entry,
    title: truncateText(entry.title, 120),
    beforeMarkdown: truncateText(entry.beforeMarkdown, 2_000),
    afterMarkdown: truncateText(entry.afterMarkdown, 2_000),
    summary: truncateText(entry.summary, 320),
  }));
}

function normalizeSessionStatus(session: DocumentAgentSession): PersistedDocumentAgentSessionState["status"] {
  if (
    session.status === "thinking" ||
    session.status === "resolving_intent" ||
    session.status === "generating" ||
    session.status === "cancelling" ||
    session.status === "executing_step"
  ) {
    return session.pendingQuestions.length ||
      session.pendingOptions.length ||
      (session.pendingTurnKind === "plan" && session.lastPlan?.length)
      ? "waiting_user"
      : "idle";
  }

  if (session.status === "reviewing_result") {
    return session.lastResponse || session.candidatePatchSet ? "completed" : "idle";
  }

  return session.status;
}

export function buildReviewQueue(session: DocumentAgentSession): NarrativeReviewQueueItem[] {
  const queue: NarrativeReviewQueueItem[] = [];

  if (session.candidatePatchSet?.patches.length) {
    queue.push({
      id: "queue-patch-review",
      kind: "patch",
      title: "Patch 审阅",
      description: `当前有 ${session.candidatePatchSet.patches.length} 个待审 patch。`,
      status: "pending",
    });
  }

  if (session.pendingTurnKind === "plan" && session.lastPlan?.length) {
    queue.push({
      id: "queue-plan-review",
      kind: "plan",
      title: "计划确认",
      description: `当前有 ${session.lastPlan.length} 个计划步骤等待确认。`,
      status: "pending",
    });
  }

  if (session.pendingDerivedDocuments.length) {
    queue.push({
      id: "queue-derived-review",
      kind: "derived_doc",
      title: "派生文稿审阅",
      description: `当前有 ${session.pendingDerivedDocuments.length} 份派生文稿等待回看。`,
      status: "pending",
    });
  }

  for (const action of session.pendingActionRequests) {
    queue.push({
      id: `queue-action-${action.id}`,
      kind: "action",
      title: action.title,
      description: action.description,
      status: "pending",
    });
  }

  for (const branch of session.savedBranches.filter((item) => !item.archived)) {
    queue.push({
      id: `queue-derived-${branch.id}`,
      kind: "derived_doc",
      title: branch.title,
      description: "可从已保存分支恢复或继续派生。",
      status: "completed",
    });
  }

  return queue;
}

export function toPersistedSessionState(
  session: DocumentAgentSession,
): PersistedDocumentAgentSessionState {
  return {
    sessionId: session.sessionId,
    sessionTitle: session.sessionTitle,
    branchOfSessionId: session.branchOfSessionId ?? null,
    updatedAt: session.updatedAt,
    mode: session.mode,
    composerText: session.composerText,
    chatMessages: trimChatMessages(session.chatMessages),
    lastRequest: trimGenerateRequest(session.lastRequest),
    lastResponse: trimGenerateResponse(session.lastResponse),
    candidatePatchSet: session.candidatePatchSet
      ? {
          ...session.candidatePatchSet,
          currentMarkdown: truncateText(session.candidatePatchSet.currentMarkdown, MAX_PERSISTED_MARKDOWN),
          draftMarkdown: truncateText(session.candidatePatchSet.draftMarkdown, MAX_PERSISTED_MARKDOWN),
          patches: session.candidatePatchSet.patches
            .slice(0, MAX_PERSISTED_PATCHES)
            .map(trimPatch),
        }
      : null,
    status: normalizeSessionStatus(session),
    pendingQuestions: session.pendingQuestions,
    pendingOptions: session.pendingOptions,
    lastPlan: session.lastPlan,
    pendingTurnKind:
      session.pendingQuestions.length ||
      session.pendingOptions.length ||
      (session.pendingTurnKind === "plan" && session.lastPlan?.length)
        ? session.pendingTurnKind
        : null,
    executionSteps: session.executionSteps.slice(-8).map((step) => ({
      ...step,
      detail: truncateText(step.detail, 240),
      previewText: truncateText(step.previewText ?? "", 320),
    })),
    currentStepId: session.currentStepId,
    pendingActionRequests: session.pendingActionRequests,
    actionHistory: trimActionHistory(session.actionHistory),
    documentViewMode: session.documentViewMode,
    selectedContextDocKeys: session.selectedContextDocKeys,
    strategy: session.strategy,
    reviewQueue: session.reviewQueue,
    versionHistory: trimVersionHistory(session.versionHistory),
    pendingDerivedDocuments: session.pendingDerivedDocuments.slice(-MAX_PERSISTED_DERIVED_DOCUMENTS),
  };
}

export function fromPersistedSessionState(
  persisted: PersistedDocumentAgentSessionState,
  branches: SavedDocumentAgentBranch[] = [],
): DocumentAgentSession {
  const restored: DocumentAgentSession = {
    ...persisted,
    branchOfSessionId: persisted.branchOfSessionId ?? null,
    versionHistory: persisted.versionHistory ?? [],
    pendingDerivedDocuments: persisted.pendingDerivedDocuments ?? [],
    selectedContextDocKeys: persisted.selectedContextDocKeys ?? [],
    strategy: persisted.strategy ?? defaultNarrativeAgentStrategy(),
    savedBranches: branches,
    activeSubmission: null,
    queuedSubmissions: [],
    busy: false,
    inflightRequestId: null,
  };

  return {
    ...restored,
    reviewQueue: buildReviewQueue(restored),
  };
}

export function buildWorkspaceAgentState(sessions: Record<string, DocumentAgentSession>) {
  const persistedSessions = Object.fromEntries(
    Object.entries(sessions).map(([documentKey, session]) => [
      documentKey,
      toPersistedSessionState({
        ...session,
        reviewQueue: buildReviewQueue(session),
      }),
    ]),
  );

  return {
    savedAt: nowIso(),
    sessions: persistedSessions,
  };
}

export function getWorkspacePersistedAgentState(
  settings: NarrativeAppSettings,
  workspaceRoot: string,
) {
  return settings.workspaceAgentSessions?.[workspaceRoot] ?? null;
}

export function buildVersionSnapshot(
  beforeMarkdown: string,
  afterMarkdown: string,
  summary: string,
  requestId?: string | null,
): NarrativeVersionSnapshot {
  const createdAt = nowIso();
  return {
    id: `version-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    title: summary || "本轮生成结果",
    createdAt,
    beforeMarkdown,
    afterMarkdown,
    summary,
    requestId: requestId ?? null,
  };
}

export function snapshotBranch(
  session: DocumentAgentSession,
  title: string,
  archived: boolean,
): SavedDocumentAgentBranch {
  return {
    id: `branch-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    title,
    archived,
    branchOfSessionId: session.sessionId,
    createdAt: nowIso(),
    updatedAt: nowIso(),
    snapshot: toPersistedSessionState(session),
  };
}
