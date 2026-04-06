import { describe, expect, it } from "vitest";
import type { DocumentAgentSession } from "../../types";
import {
  buildReviewQueue,
  defaultNarrativeAgentStrategy,
  fromPersistedSessionState,
  toPersistedSessionState,
} from "./narrativeAgentState";
import { createDocumentAgentSession } from "./narrativeSessions";

function buildSession(overrides: Partial<DocumentAgentSession> = {}): DocumentAgentSession {
  return {
    ...createDocumentAgentSession({ mode: "revise_document" }),
    strategy: defaultNarrativeAgentStrategy(),
    ...overrides,
  };
}

describe("narrativeAgentState", () => {
  it("trims large persisted session fields while keeping restore-critical data", () => {
    const session = buildSession({
      status: "thinking",
      chatMessages: Array.from({ length: 50 }, (_, index) => ({
        id: `message-${index}`,
        role: index % 2 === 0 ? "user" : "assistant",
        label: index % 2 === 0 ? "你" : "AI",
        content: "x".repeat(5_000),
        tone: "muted",
      })),
      lastRequest: {
        requestId: "request-1",
        docType: "task_setup",
        targetSlug: "doc-1",
        action: "revise_document",
        userPrompt: "u".repeat(5_000),
        editorInstruction: "i".repeat(5_000),
        currentMarkdown: "m".repeat(20_000),
        relatedDocSlugs: Array.from({ length: 32 }, (_, index) => `doc-${index}`),
        derivedTargetDocType: null,
      },
      lastResponse: {
        engineMode: "single_agent",
        turnKind: "final_answer",
        assistantMessage: "a".repeat(5_000),
        draftMarkdown: "d".repeat(20_000),
        summary: "s".repeat(2_000),
        reviewNotes: ["r".repeat(800)],
        riskLevel: "medium",
        changeScope: "document",
        promptDebug: { huge: "debug" },
        rawOutput: "o".repeat(5_000),
        usedContextRefs: Array.from({ length: 40 }, (_, index) => `ref-${index}`),
        diffPreview: "p".repeat(5_000),
        providerError: "",
        synthesisNotes: ["n".repeat(800)],
        agentRuns: [
          {
            agentId: "agent-1",
            label: "主助手",
            focus: "focus",
            status: "completed",
            summary: "summary".repeat(200),
            notes: ["note".repeat(100)],
            riskLevel: "medium",
            draftMarkdown: "draft".repeat(1_000),
            rawOutput: "raw".repeat(1_000),
            providerError: "",
          },
        ],
        questions: [],
        options: [],
        planSteps: [],
        requiresUserReply: false,
        executionSteps: [
          {
            id: "step-1",
            label: "step",
            detail: "detail".repeat(200),
            status: "completed",
            previewText: "preview".repeat(120),
          },
        ],
        currentStepId: null,
        requestedActions: [],
        sourceDocumentKeys: Array.from({ length: 24 }, (_, index) => `source-${index}`),
        provenanceRefs: Array.from({ length: 24 }, (_, index) => `prov-${index}`),
        reviewQueueItems: [],
      },
      actionHistory: Array.from({ length: 24 }, (_, index) => ({
        requestId: `action-${index}`,
        actionType: "save_active_document",
        status: "completed",
        summary: "done".repeat(200),
        document: null,
        documentSummaries: [],
        openedSlug: null,
      })),
      versionHistory: Array.from({ length: 12 }, (_, index) => ({
        id: `version-${index}`,
        title: `版本 ${index}`,
        createdAt: "2025-01-01T00:00:00.000Z",
        beforeMarkdown: "before".repeat(500),
        afterMarkdown: "after".repeat(500),
        summary: "summary".repeat(100),
        requestId: null,
      })),
    });

    const persisted = toPersistedSessionState(session);

    expect(persisted.chatMessages).toHaveLength(40);
    expect(persisted.chatMessages[0]?.content.length).toBeLessThanOrEqual(4_000);
    expect(persisted.lastRequest?.currentMarkdown.length).toBeLessThanOrEqual(16_000);
    expect(persisted.lastResponse?.promptDebug).toEqual({});
    expect(persisted.lastResponse?.draftMarkdown.length).toBeLessThanOrEqual(16_000);
    expect(persisted.lastResponse?.usedContextRefs.length).toBeLessThanOrEqual(16);
    expect(persisted.actionHistory).toHaveLength(20);
    expect(persisted.versionHistory).toHaveLength(8);
    expect(persisted.status).toBe("idle");
  });

  it("rebuilds review queue and clears inflight state on restore", () => {
    const session = buildSession({
      pendingActionRequests: [
        {
          id: "action-1",
          actionType: "save_active_document",
          title: "保存当前文稿",
          description: "保存",
          payload: {},
          approvalPolicy: "always_require_user",
        },
      ],
    });
    const persisted = toPersistedSessionState(session);
    const restored = fromPersistedSessionState({
      ...persisted,
      reviewQueue: [],
    });

    expect(restored.busy).toBe(false);
    expect(restored.inflightRequestId).toBeNull();
    expect(restored.reviewQueue).toEqual(buildReviewQueue(restored));
  });
});
