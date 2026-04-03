import type {
  AgentActionResult,
  AiChatMessage,
  DocumentAgentSession,
  NarrativeDocumentSummary,
  SavedDocumentAgentBranch,
  NarrativeGenerateRequest,
  NarrativeGenerateResponse,
  NarrativeGenerationProgressEvent,
  NarrativePatchSet,
} from "../../types";
import {
  buildVersionSnapshot,
  fromPersistedSessionState,
  nowIso,
  snapshotBranch,
} from "./narrativeAgentState";
import { createDocumentAgentSession } from "./narrativeSessions";

// Agent 会话结果应用层：
// 负责生成结果落会话、派生文稿分支、审阅队列、动作批准/拒绝，以及错误回填。
export function assistantMessageIdForRequest(requestId: string) {
  return `assistant-${requestId}`;
}

export function replaceChatMessage(
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

export function upsertExecutionStep(
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

export function sessionStatusFromProgress(
  event: NarrativeGenerationProgressEvent,
): DocumentAgentSession["status"] {
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

export function actionHistoryMessage(result: AgentActionResult) {
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

export function appendContextMessage(
  session: DocumentAgentSession,
  messageId: string,
  content: string,
  tone: AiChatMessage["tone"],
): DocumentAgentSession {
  return {
    ...session,
    updatedAt: nowIso(),
    chatMessages: [
      ...session.chatMessages,
      {
        id: messageId,
        role: "context",
        label: "系统",
        content,
        tone,
      },
    ],
  };
}

export function mergePendingDerivedDocuments(
  session: DocumentAgentSession,
  derivedSummaries: NarrativeDocumentSummary[],
): DocumentAgentSession {
  if (!derivedSummaries.length) {
    return session;
  }

  const nextPending = [
    ...session.pendingDerivedDocuments,
    ...derivedSummaries.filter(
      (summary) => !session.pendingDerivedDocuments.some((entry) => entry.slug === summary.slug),
    ),
  ];

  if (nextPending.length === session.pendingDerivedDocuments.length) {
    return session;
  }

  return {
    ...session,
    updatedAt: nowIso(),
    pendingDerivedDocuments: nextPending,
  };
}

export function resolveActionRequestSession(
  session: DocumentAgentSession,
  requestId: string,
  result: AgentActionResult,
  messageId: string,
  tone: AiChatMessage["tone"],
  content = actionHistoryMessage(result),
): DocumentAgentSession {
  const nextSession = appendContextMessage(session, messageId, content, tone);
  return {
    ...nextSession,
    pendingActionRequests: nextSession.pendingActionRequests.filter((entry) => entry.id !== requestId),
    actionHistory: [...nextSession.actionHistory, result],
  };
}

export function generationStatusFromResponse(
  response: NarrativeGenerateResponse,
): DocumentAgentSession["status"] {
  return response.requiresUserReply ? "waiting_user" : "completed";
}

type ApplyGenerationResponseInput = {
  session: DocumentAgentSession;
  request: NarrativeGenerateRequest;
  response: NarrativeGenerateResponse;
  assistantMessageId: string;
  assistantMessage: AiChatMessage;
  candidatePatchSet?: NarrativePatchSet | null;
  documentViewMode?: DocumentAgentSession["documentViewMode"];
  versionBeforeMarkdown?: string | null;
};

export function applyGenerationResponseToSession({
  session,
  request,
  response,
  assistantMessageId,
  assistantMessage,
  candidatePatchSet = null,
  documentViewMode = session.documentViewMode,
  versionBeforeMarkdown = null,
}: ApplyGenerationResponseInput): DocumentAgentSession {
  const nextSession: DocumentAgentSession = {
    ...session,
    updatedAt: nowIso(),
    status: generationStatusFromResponse(response),
    busy: false,
    inflightRequestId: null,
    lastRequest: request,
    lastResponse: response,
    candidatePatchSet,
    pendingQuestions: response.questions,
    pendingOptions: response.options,
    lastPlan: response.planSteps.length ? response.planSteps : session.lastPlan,
    pendingTurnKind: response.requiresUserReply ? response.turnKind : null,
    executionSteps: response.executionSteps,
    currentStepId: response.currentStepId ?? null,
    pendingActionRequests: response.requestedActions,
    documentViewMode,
    chatMessages: replaceChatMessage(session.chatMessages, assistantMessageId, assistantMessage),
    versionHistory:
      response.turnKind === "final_answer" &&
      candidatePatchSet &&
      versionBeforeMarkdown &&
      !response.providerError.trim()
        ? [
            buildVersionSnapshot(
              versionBeforeMarkdown,
              response.draftMarkdown,
              response.summary || response.assistantMessage,
              request.requestId ?? null,
            ),
            ...session.versionHistory,
          ].slice(0, 12)
        : session.versionHistory,
  };

  return nextSession;
}

type BuildDerivedDraftSessionInput = {
  request: NarrativeGenerateRequest;
  response: NarrativeGenerateResponse;
  userMessage: AiChatMessage;
  assistantMessage: AiChatMessage;
  sourceDocumentKey: string;
  sourceDocumentTitle: string;
};

export function buildDerivedDraftSession({
  request,
  response,
  userMessage,
  assistantMessage,
  sourceDocumentKey,
  sourceDocumentTitle,
}: BuildDerivedDraftSessionInput): DocumentAgentSession {
  return {
    ...createDocumentAgentSession(),
    mode: "revise_document",
    updatedAt: nowIso(),
    sessionTitle: `来自 ${sourceDocumentTitle} 的派生会话`,
    chatMessages: [
      {
        id: `seed-${Date.now()}`,
        role: "context",
        label: "系统",
        content: `该文档由《${sourceDocumentTitle}》会话生成。`,
        tone: "muted",
      },
      userMessage,
      assistantMessage,
    ],
    lastRequest: request,
    lastResponse: response,
    candidatePatchSet: null,
    status: "idle",
    pendingQuestions: [],
    pendingOptions: [],
    lastPlan: response.planSteps,
    pendingTurnKind: null,
    executionSteps: response.executionSteps,
    currentStepId: response.currentStepId ?? null,
    pendingActionRequests: response.requestedActions,
    selectedContextDocKeys: [sourceDocumentKey],
    documentViewMode: "preview",
    composerText: "",
  };
}

export function applyGenerationErrorToSession(
  session: DocumentAgentSession,
  assistantMessageId: string,
  error: unknown,
): DocumentAgentSession {
  return {
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
  };
}

export function renameSessionTitle(
  session: DocumentAgentSession,
  nextTitle: string,
): DocumentAgentSession {
  return {
    ...session,
    sessionTitle: nextTitle,
    updatedAt: nowIso(),
  };
}

export function updateSessionStrategyValue(
  session: DocumentAgentSession,
  key: keyof DocumentAgentSession["strategy"],
  value: DocumentAgentSession["strategy"][typeof key],
): DocumentAgentSession {
  return {
    ...session,
    updatedAt: nowIso(),
    strategy: {
      ...session.strategy,
      [key]: value,
    },
  };
}

export function forkSessionBranch(
  session: DocumentAgentSession,
  nextTitle: string,
): DocumentAgentSession {
  const savedBranch = snapshotBranch(session, session.sessionTitle, false);
  return {
    ...session,
    sessionId: `${session.sessionId}-fork-${Date.now()}`,
    sessionTitle: nextTitle,
    branchOfSessionId: session.sessionId,
    updatedAt: nowIso(),
    savedBranches: [...session.savedBranches, savedBranch],
  };
}

export function archiveSessionBranch(
  session: DocumentAgentSession,
): DocumentAgentSession {
  const archivedBranch = snapshotBranch(session, session.sessionTitle, true);
  return createDocumentAgentSession({
    mode: session.mode,
    documentViewMode: session.documentViewMode,
    savedBranches: [...session.savedBranches, archivedBranch],
  });
}

export function restoreSessionBranch(
  session: DocumentAgentSession,
  branch: SavedDocumentAgentBranch,
): DocumentAgentSession {
  return {
    ...fromPersistedSessionState(branch.snapshot, session.savedBranches),
    sessionTitle: branch.title,
    updatedAt: nowIso(),
    savedBranches: session.savedBranches,
  };
}

export function clearPendingActionRequestQueue(
  session: DocumentAgentSession,
): DocumentAgentSession {
  return {
    ...session,
    pendingActionRequests: [],
    updatedAt: nowIso(),
  };
}

export function clearConversationSession(
  session: DocumentAgentSession,
): DocumentAgentSession {
  return createDocumentAgentSession({
    mode: session.mode,
    documentViewMode: session.documentViewMode,
    sessionTitle: session.sessionTitle,
    strategy: session.strategy,
    selectedContextDocKeys: session.selectedContextDocKeys,
    savedBranches: session.savedBranches,
  });
}

export function resolveDerivedDocumentReview(
  session: DocumentAgentSession,
  slug: string,
  outcome: "approved" | "rejected",
): DocumentAgentSession {
  const target = session.pendingDerivedDocuments.find((item) => item.slug === slug);
  if (!target) {
    return session;
  }

  return appendContextMessage(
    {
      ...session,
      pendingDerivedDocuments: session.pendingDerivedDocuments.filter((item) => item.slug !== slug),
    },
    `context-derived-${outcome}-${slug}-${Date.now()}`,
    outcome === "approved"
      ? `已将派生文稿《${target.title || target.slug}》标记为已审阅。`
      : `已将派生文稿《${target.title || target.slug}》从待审列表移除。`,
    outcome === "approved" ? "success" : "warning",
  );
}

export function clearAllDerivedDocumentsReview(
  session: DocumentAgentSession,
  outcome: "approved" | "rejected",
): DocumentAgentSession {
  if (!session.pendingDerivedDocuments.length) {
    return session;
  }
  const count = session.pendingDerivedDocuments.length;
  return appendContextMessage(
    {
      ...session,
      pendingDerivedDocuments: [],
    },
    `context-derived-${outcome}-all-${Date.now()}`,
    outcome === "approved"
      ? `已批量完成 ${count} 份派生文稿的审阅。`
      : `已将 ${count} 份派生文稿从待审列表移除，文稿本身仍保留在工作区。`,
    outcome === "approved" ? "success" : "warning",
  );
}
