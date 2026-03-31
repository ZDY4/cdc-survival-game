import type {
  DocumentAgentSession,
  NarrativeAgentStrategy,
  NarrativeAppSettings,
  NarrativeReviewQueueItem,
  NarrativeVersionSnapshot,
  PersistedDocumentAgentSessionState,
  SavedDocumentAgentBranch,
} from "../../types";

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
    chatMessages: session.chatMessages,
    lastRequest: session.lastRequest,
    lastResponse: session.lastResponse,
    candidatePatchSet: session.candidatePatchSet,
    status: session.status,
    pendingQuestions: session.pendingQuestions,
    pendingOptions: session.pendingOptions,
    lastPlan: session.lastPlan,
    pendingTurnKind: session.pendingTurnKind,
    executionSteps: session.executionSteps,
    currentStepId: session.currentStepId,
    pendingActionRequests: session.pendingActionRequests,
    actionHistory: session.actionHistory,
    documentViewMode: session.documentViewMode,
    selectedContextDocKeys: session.selectedContextDocKeys,
    strategy: session.strategy,
    reviewQueue: session.reviewQueue,
    versionHistory: session.versionHistory,
    pendingDerivedDocuments: session.pendingDerivedDocuments,
  };
}

export function fromPersistedSessionState(
  persisted: PersistedDocumentAgentSessionState,
  branches: SavedDocumentAgentBranch[] = [],
): DocumentAgentSession {
  return {
    ...persisted,
    branchOfSessionId: persisted.branchOfSessionId ?? null,
    reviewQueue: persisted.reviewQueue ?? [],
    versionHistory: persisted.versionHistory ?? [],
    pendingDerivedDocuments: persisted.pendingDerivedDocuments ?? [],
    selectedContextDocKeys: persisted.selectedContextDocKeys ?? [],
    strategy: persisted.strategy ?? defaultNarrativeAgentStrategy(),
    savedBranches: branches,
    busy: false,
    inflightRequestId: null,
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
