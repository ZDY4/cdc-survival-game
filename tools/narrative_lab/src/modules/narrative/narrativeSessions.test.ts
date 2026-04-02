import { describe, expect, it } from "vitest";
import {
  addSelectedContextDocument,
  closeNarrativeTab,
  createDocumentAgentSession,
  ensureDocumentAgentSession,
  openNarrativeTab,
  removeSelectedContextDocument,
  restoreDocumentAgentSessions,
  updateDocumentAgentSession,
  updateDocumentAgentSessionWithReviewQueue,
} from "./narrativeSessions";
import { stashDocumentResponse } from "./narrativeSessions";
import type { NarrativeGenerateRequest, NarrativeGenerateResponse } from "../../types";

describe("narrativeSessions", () => {
  it("opens tabs without duplicating existing entries", () => {
    const initial = { openTabs: ["doc-a"], activeTabKey: "doc-a" as string | null };
    const next = openNarrativeTab(initial, "doc-b");
    const deduped = openNarrativeTab(next, "doc-a");

    expect(next.openTabs).toEqual(["doc-a", "doc-b"]);
    expect(deduped.openTabs).toEqual(["doc-a", "doc-b"]);
    expect(deduped.activeTabKey).toBe("doc-a");
  });

  it("closes the active tab and falls back to the previous open tab", () => {
    const next = closeNarrativeTab(
      { openTabs: ["doc-a", "doc-b", "doc-c"], activeTabKey: "doc-c" },
      "doc-c",
    );

    expect(next.openTabs).toEqual(["doc-a", "doc-b"]);
    expect(next.activeTabKey).toBe("doc-b");
  });

  it("keeps document sessions isolated per tab", () => {
    const sessions = ensureDocumentAgentSession({}, "doc-a");
    const withDocA = updateDocumentAgentSession(sessions, "doc-a", (session) => ({
      ...session,
      composerText: "hello from a",
    }));
    const withDocB = updateDocumentAgentSession(withDocA, "doc-b", () =>
      createDocumentAgentSession({ composerText: "hello from b" }),
    );

    expect(withDocB["doc-a"].composerText).toBe("hello from a");
    expect(withDocB["doc-b"].composerText).toBe("hello from b");
  });

  it("rebuilds review queue after session updates that need it", () => {
    const next = updateDocumentAgentSessionWithReviewQueue({}, "doc-a", (session) => ({
      ...session,
      pendingActionRequests: [
        {
          id: "action-1",
          actionType: "apply_all_patches",
          title: "应用整篇建议",
          description: "应用当前全部 patch",
          payload: {},
          approvalPolicy: "always_require_user",
        },
      ],
    }));

    expect(next["doc-a"].reviewQueue).toHaveLength(1);
    expect(next["doc-a"].reviewQueue[0]?.title).toBe("应用整篇建议");
  });

  it("restores only valid document sessions and focuses the latest one", () => {
    const { restoredSessions, restoreTargetKey } = restoreDocumentAgentSessions(
      {
        "doc-a": createDocumentAgentSession({
          updatedAt: "2026-04-01T00:00:00.000Z",
          busy: true,
          inflightRequestId: "req-a",
        }),
        "doc-b": createDocumentAgentSession({
          updatedAt: "2026-04-02T00:00:00.000Z",
          busy: true,
          inflightRequestId: "req-b",
        }),
      },
      ["doc-b"],
    );

    expect(Object.keys(restoredSessions)).toEqual(["doc-b"]);
    expect(restoredSessions["doc-b"]?.busy).toBe(false);
    expect(restoredSessions["doc-b"]?.inflightRequestId).toBeNull();
    expect(restoreTargetKey).toBe("doc-b");
  });

  it("adds and removes context documents without changing relative order", () => {
    const session = createDocumentAgentSession({
      selectedContextDocKeys: ["doc-b"],
      updatedAt: "2026-04-01T00:00:00.000Z",
    });

    const added = addSelectedContextDocument(session, "doc-c");
    const deduped = addSelectedContextDocument(added, "doc-b");
    const removed = removeSelectedContextDocument(deduped, "doc-b");

    expect(added.selectedContextDocKeys).toEqual(["doc-b", "doc-c"]);
    expect(deduped.selectedContextDocKeys).toEqual(["doc-b", "doc-c"]);
    expect(removed.selectedContextDocKeys).toEqual(["doc-c"]);
  });
  it("marks waiting_user status and stores pending questions from clarification", () => {
    const baseSession = createDocumentAgentSession();
    const request: NarrativeGenerateRequest = {
      requestId: "req-1",
      docType: "task_setup",
      targetSlug: "doc-1",
      action: "revise_document",
      userPrompt: "继续",
      editorInstruction: "",
      currentMarkdown: "text",
      selectedRange: null,
      selectedText: "",
      relatedDocSlugs: [],
      derivedTargetDocType: null,
    };
    const response: NarrativeGenerateResponse = {
      engineMode: "single_agent",
      turnKind: "clarification",
      assistantMessage: "",
      draftMarkdown: "",
      summary: "问问题",
      reviewNotes: [],
      riskLevel: "low",
      changeScope: "document",
      promptDebug: {},
      rawOutput: "",
      usedContextRefs: [],
      diffPreview: "",
      providerError: "",
      synthesisNotes: [],
      agentRuns: [],
      questions: [{ id: "q1", label: "缺什么", placeholder: "描述", required: true }],
      options: [],
      planSteps: [],
      requiresUserReply: true,
      executionSteps: [],
      currentStepId: null,
      requestedActions: [],
      sourceDocumentKeys: [],
      provenanceRefs: [],
      reviewQueueItems: [],
    };

    const next = stashDocumentResponse({ doc: baseSession }, "doc", request, response);
    const stored = next["doc"];

    expect(stored.status).toBe("waiting_user");
    expect(stored.pendingQuestions).toHaveLength(1);
    expect(stored.pendingTurnKind).toBe("clarification");
  });

  it("prefers plan queue when response provides plan steps", () => {
    const baseSession = createDocumentAgentSession();
    const request: NarrativeGenerateRequest = {
      requestId: "req-2",
      docType: "task_setup",
      targetSlug: "doc-2",
      action: "revise_document",
      userPrompt: "规划",
      editorInstruction: "",
      currentMarkdown: "plan",
      selectedRange: null,
      selectedText: "",
      relatedDocSlugs: [],
      derivedTargetDocType: null,
    };
    const response: NarrativeGenerateResponse = {
      engineMode: "single_agent",
      turnKind: "plan",
      assistantMessage: "",
      draftMarkdown: "",
      summary: "制定计划",
      reviewNotes: [],
      riskLevel: "low",
      changeScope: "document",
      promptDebug: {},
      rawOutput: "",
      usedContextRefs: [],
      diffPreview: "",
      providerError: "",
      synthesisNotes: [],
      agentRuns: [],
      questions: [],
      options: [],
      planSteps: [{ id: "step1", label: "步骤一", status: "pending" }],
      requiresUserReply: true,
      executionSteps: [],
      currentStepId: null,
      requestedActions: [],
      sourceDocumentKeys: [],
      provenanceRefs: [],
      reviewQueueItems: [],
    };

    const next = stashDocumentResponse({ doc: baseSession }, "doc", request, response);
    const stored = next["doc"];

    expect(stored.pendingTurnKind).toBe("plan");
    expect(stored.reviewQueue.some((item) => item.kind === "plan")).toBe(true);
  });
});
