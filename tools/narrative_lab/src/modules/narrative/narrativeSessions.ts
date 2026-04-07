import type {
  DocumentAgentSession,
  NarrativeActiveSubmission,
  NarrativeDocumentViewMode,
  NarrativeGenerateRequest,
  NarrativeGenerateResponse,
  NarrativeQueuedSubmission,
} from "../../types";
import {
  buildReviewQueue,
  createSessionId,
  defaultNarrativeAgentStrategy,
  nowIso,
} from "./narrativeAgentState";

export type NarrativeTabState = {
  openTabs: string[];
  activeTabKey: string | null;
};

export type DocumentAgentSessionMap = Record<string, DocumentAgentSession>;

export function createDocumentAgentSession(
  overrides: Partial<DocumentAgentSession> = {},
): DocumentAgentSession {
  return {
    sessionId: createSessionId(),
    sessionTitle: "当前会话",
    branchOfSessionId: null,
    updatedAt: nowIso(),
    mode: "revise_document",
    composerText: "",
    chatMessages: [],
    lastRequest: null,
    lastResponse: null,
    candidatePatchSet: null,
    status: "idle",
    pendingQuestions: [],
    pendingOptions: [],
    lastPlan: null,
    pendingTurnKind: null,
    executionSteps: [],
    currentStepId: null,
    pendingActionRequests: [],
    actionHistory: [],
    selectedContextDocKeys: [],
    strategy: defaultNarrativeAgentStrategy(),
    reviewQueue: [],
    versionHistory: [],
    pendingDerivedDocuments: [],
    savedBranches: [],
    activeSubmission: null,
    queuedSubmissions: [],
    busy: false,
    inflightRequestId: null,
    documentViewMode: "preview",
    ...overrides,
  };
}

function buildActiveSubmission(
  submission: NarrativeQueuedSubmission,
  stage: NarrativeActiveSubmission["stage"] = "resolving_intent",
): NarrativeActiveSubmission {
  return {
    ...submission,
    stage,
  };
}

export function createNarrativeQueuedSubmission(
  prompt: string,
  source: NarrativeQueuedSubmission["source"],
): NarrativeQueuedSubmission {
  const timestamp = Date.now();
  const random = Math.random().toString(36).slice(2, 8);
  const requestId = `generation-${timestamp}-${random}`;
  return {
    submissionId: `submission-${timestamp}-${random}`,
    requestId,
    prompt,
    source,
    createdAt: nowIso(),
  };
}

export function enqueueNarrativeSubmission(
  session: DocumentAgentSession,
  submission: NarrativeQueuedSubmission,
  options: { clearComposerText?: boolean } = {},
): {
  session: DocumentAgentSession;
  outcome: "started" | "queued" | "duplicate_active" | "duplicate_tail";
} {
  const clearComposerText = options.clearComposerText ?? false;
  if (session.activeSubmission?.prompt === submission.prompt) {
    return {
      session,
      outcome: "duplicate_active",
    };
  }

  const queueTail =
    session.queuedSubmissions.length > 0
      ? session.queuedSubmissions[session.queuedSubmissions.length - 1]
      : undefined;
  if (queueTail?.prompt === submission.prompt) {
    return {
      session,
      outcome: "duplicate_tail",
    };
  }

  const baseSession = clearComposerText
    ? {
        ...session,
        composerText: "",
      }
    : session;

  if (!baseSession.activeSubmission) {
    return {
      session: {
        ...baseSession,
        updatedAt: nowIso(),
        status: "resolving_intent",
        activeSubmission: buildActiveSubmission(submission),
        pendingQuestions: [],
        pendingOptions: [],
        pendingTurnKind: null,
        busy: true,
        inflightRequestId: submission.requestId,
      },
      outcome: "started",
    };
  }

  return {
    session: {
      ...baseSession,
      updatedAt: nowIso(),
      queuedSubmissions: [...baseSession.queuedSubmissions, submission],
      busy: true,
    },
    outcome: "queued",
  };
}

export function updateActiveSubmissionStage(
  session: DocumentAgentSession,
  stage: NarrativeActiveSubmission["stage"],
): DocumentAgentSession {
  if (!session.activeSubmission) {
    return session;
  }

  return {
    ...session,
    updatedAt: nowIso(),
    status: stage,
    activeSubmission: {
      ...session.activeSubmission,
      stage,
    },
    pendingQuestions: [],
    pendingOptions: [],
    pendingTurnKind: null,
    busy: true,
    inflightRequestId: session.activeSubmission.requestId,
  };
}

export function clearActiveNarrativeSubmission(
  session: DocumentAgentSession,
): DocumentAgentSession {
  if (!session.activeSubmission) {
    return {
      ...session,
      busy: false,
      inflightRequestId: null,
    };
  }

  return {
    ...session,
    updatedAt: nowIso(),
    activeSubmission: null,
    busy: false,
    inflightRequestId: null,
  };
}

export function promoteNextNarrativeSubmission(
  session: DocumentAgentSession,
): DocumentAgentSession {
  const [nextSubmission, ...remainingQueue] = session.queuedSubmissions;
  if (!nextSubmission) {
    return session;
  }

  return {
    ...session,
    updatedAt: nowIso(),
    status: "resolving_intent",
    activeSubmission: buildActiveSubmission(nextSubmission),
    queuedSubmissions: remainingQueue,
    pendingQuestions: [],
    pendingOptions: [],
    pendingTurnKind: null,
    busy: true,
    inflightRequestId: nextSubmission.requestId,
  };
}

export function ensureDocumentAgentSession(
  sessions: DocumentAgentSessionMap,
  documentKey: string,
  viewMode: NarrativeDocumentViewMode = "preview",
): DocumentAgentSessionMap {
  if (sessions[documentKey]) {
    return sessions;
  }

  return {
    ...sessions,
    [documentKey]: createDocumentAgentSession({ documentViewMode: viewMode }),
  };
}

export function openNarrativeTab(
  state: NarrativeTabState,
  documentKey: string,
): NarrativeTabState {
  return {
    openTabs: state.openTabs.includes(documentKey)
      ? state.openTabs
      : [...state.openTabs, documentKey],
    activeTabKey: documentKey,
  };
}

export function closeNarrativeTab(
  state: NarrativeTabState,
  documentKey: string,
): NarrativeTabState {
  const nextTabs = state.openTabs.filter((entry) => entry !== documentKey);
  if (state.activeTabKey !== documentKey) {
    return {
      openTabs: nextTabs,
      activeTabKey: state.activeTabKey,
    };
  }

  return {
    openTabs: nextTabs,
    activeTabKey: nextTabs[nextTabs.length - 1] ?? null,
  };
}

export function updateDocumentAgentSession(
  sessions: DocumentAgentSessionMap,
  documentKey: string,
  transform: (session: DocumentAgentSession) => DocumentAgentSession,
): DocumentAgentSessionMap {
  const session = sessions[documentKey] ?? createDocumentAgentSession();
  return {
    ...sessions,
    [documentKey]: transform(session),
  };
}

export function withComputedReviewQueue(
  session: DocumentAgentSession,
): DocumentAgentSession {
  return {
    ...session,
    reviewQueue: buildReviewQueue(session),
  };
}

export function updateDocumentAgentSessionWithReviewQueue(
  sessions: DocumentAgentSessionMap,
  documentKey: string,
  transform: (session: DocumentAgentSession) => DocumentAgentSession,
): DocumentAgentSessionMap {
  return updateDocumentAgentSession(sessions, documentKey, (session) => {
    const nextSession = transform(session);
    if (nextSession === session) {
      return session;
    }
    return withComputedReviewQueue(nextSession);
  });
}

export function restoreDocumentAgentSessions(
  sessions: DocumentAgentSessionMap | null | undefined,
  validDocumentKeys: Iterable<string>,
): {
  restoredSessions: DocumentAgentSessionMap;
  restoreTargetKey: string | null;
} {
  const validKeys = new Set(validDocumentKeys);
  const restoredEntries = Object.entries(sessions ?? {}).filter(([documentKey]) =>
    validKeys.has(documentKey),
  );
  const restoreTargetKey =
    restoredEntries
      .slice()
      .sort((left, right) => {
        const leftTime = Date.parse(left[1].updatedAt || "");
        const rightTime = Date.parse(right[1].updatedAt || "");
        return (Number.isNaN(rightTime) ? 0 : rightTime) - (Number.isNaN(leftTime) ? 0 : leftTime);
      })[0]?.[0] ?? null;

  return {
    restoredSessions: Object.fromEntries(
      restoredEntries.map(([documentKey, session]) => [
        documentKey,
        withComputedReviewQueue({
          ...session,
          activeSubmission: null,
          queuedSubmissions: [],
          busy: false,
          inflightRequestId: null,
        }),
      ]),
    ),
    restoreTargetKey,
  };
}

export function addSelectedContextDocument(
  session: DocumentAgentSession,
  documentKey: string,
): DocumentAgentSession {
  if (session.selectedContextDocKeys.includes(documentKey)) {
    return session;
  }
  return {
    ...session,
    updatedAt: nowIso(),
    selectedContextDocKeys: [...session.selectedContextDocKeys, documentKey],
  };
}

export function removeSelectedContextDocument(
  session: DocumentAgentSession,
  documentKey: string,
): DocumentAgentSession {
  if (!session.selectedContextDocKeys.includes(documentKey)) {
    return session;
  }
  return {
    ...session,
    updatedAt: nowIso(),
    selectedContextDocKeys: session.selectedContextDocKeys.filter((entry) => entry !== documentKey),
  };
}

export function stashDocumentResponse(
  sessions: DocumentAgentSessionMap,
  documentKey: string,
  request: NarrativeGenerateRequest,
  response: NarrativeGenerateResponse,
): DocumentAgentSessionMap {
  return updateDocumentAgentSessionWithReviewQueue(sessions, documentKey, (session) => ({
    ...session,
    updatedAt: nowIso(),
    lastRequest: request,
    lastResponse: response,
    status: response.requiresUserReply ? "waiting_user" : "completed",
    pendingQuestions: response.questions,
    pendingOptions: response.options,
    lastPlan: response.planSteps.length ? response.planSteps : session.lastPlan,
    pendingTurnKind: response.requiresUserReply ? response.turnKind : null,
    executionSteps: response.executionSteps,
    currentStepId: response.currentStepId ?? null,
    pendingActionRequests: response.requestedActions,
    busy: false,
  }));
}
