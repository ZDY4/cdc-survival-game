import type {
  DocumentAgentSession,
  NarrativeDocumentViewMode,
  NarrativeGenerateRequest,
  NarrativeGenerateResponse,
} from "../../types";

export type NarrativeTabState = {
  openTabs: string[];
  activeTabKey: string | null;
};

export function createDocumentAgentSession(
  overrides: Partial<DocumentAgentSession> = {},
): DocumentAgentSession {
  return {
    mode: "revise_document",
    composerText: "",
    chatMessages: [],
    lastRequest: null,
    lastResponse: null,
    candidatePatchSet: null,
    busy: false,
    documentViewMode: "preview",
    ...overrides,
  };
}

export function ensureDocumentAgentSession(
  sessions: Record<string, DocumentAgentSession>,
  documentKey: string,
  viewMode: NarrativeDocumentViewMode = "preview",
): Record<string, DocumentAgentSession> {
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
  sessions: Record<string, DocumentAgentSession>,
  documentKey: string,
  transform: (session: DocumentAgentSession) => DocumentAgentSession,
): Record<string, DocumentAgentSession> {
  const session = sessions[documentKey] ?? createDocumentAgentSession();
  return {
    ...sessions,
    [documentKey]: transform(session),
  };
}

export function stashDocumentResponse(
  sessions: Record<string, DocumentAgentSession>,
  documentKey: string,
  request: NarrativeGenerateRequest,
  response: NarrativeGenerateResponse,
): Record<string, DocumentAgentSession> {
  return updateDocumentAgentSession(sessions, documentKey, (session) => ({
    ...session,
    lastRequest: request,
    lastResponse: response,
    busy: false,
  }));
}
