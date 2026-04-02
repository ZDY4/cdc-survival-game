import { describe, expect, it } from "vitest";
import type { AgentActionResult, DocumentAgentSession } from "../../types";
import { createDocumentAgentSession } from "./narrativeSessions";
import {
  actionHistoryMessage,
  archiveSessionBranch,
  applyGenerationErrorToSession,
  applyGenerationResponseToSession,
  appendContextMessage,
  assistantMessageIdForRequest,
  buildDerivedDraftSession,
  clearAllDerivedDocumentsReview,
  clearConversationSession,
  clearPendingActionRequestQueue,
  forkSessionBranch,
  generationStatusFromResponse,
  renameSessionTitle,
  replaceChatMessage,
  resolveDerivedDocumentReview,
  resolveActionRequestSession,
  restoreSessionBranch,
  sessionStatusFromProgress,
  updateSessionStrategyValue,
  upsertExecutionStep,
  mergePendingDerivedDocuments,
} from "./narrativeSessionFlow";

describe("narrativeSessionFlow", () => {
  it("builds assistant placeholder ids from request ids", () => {
    expect(assistantMessageIdForRequest("req-1")).toBe("assistant-req-1");
  });

  it("replaces an existing chat message or appends when missing", () => {
    const original = {
      id: "assistant-1",
      role: "assistant" as const,
      label: "AI",
      content: "old",
    };
    const replacement = { ...original, content: "new" };

    expect(replaceChatMessage([original], original.id, replacement)[0]?.content).toBe("new");
    expect(replaceChatMessage([], original.id, replacement)).toEqual([replacement]);
  });

  it("upserts execution progress steps by step id", () => {
    const created = upsertExecutionStep([], {
      requestId: "req-1",
      stage: "status",
      status: "准备上下文",
      previewText: "预览",
      stepId: "build-context",
      stepLabel: "整理上下文",
      stepStatus: "running",
    });
    const updated = upsertExecutionStep(created, {
      requestId: "req-1",
      stage: "completed",
      status: "完成",
      previewText: "ok",
      stepId: "build-context",
      stepLabel: "整理上下文",
      stepStatus: "completed",
    });

    expect(created).toHaveLength(1);
    expect(updated[0]?.status).toBe("completed");
    expect(updated[0]?.detail).toBe("完成");
  });

  it("maps progress events to session status", () => {
    expect(
      sessionStatusFromProgress({
        requestId: "req",
        stage: "error",
        status: "失败",
        previewText: "",
      }),
    ).toBe("error");
    expect(
      sessionStatusFromProgress({
        requestId: "req",
        stage: "status",
        status: "处理中",
        previewText: "",
        stepId: "review-result",
        stepLabel: "整理结果",
        stepStatus: "running",
      }),
    ).toBe("reviewing_result");
  });

  it("formats action history summaries with related documents", () => {
    const result: AgentActionResult = {
      requestId: "action-1",
      actionType: "create_derived_document",
      status: "completed",
      summary: "已创建文稿。",
      documentSummaries: [{ slug: "b", title: "文稿 B", headingCount: 0, headings: [], excerpt: "" }],
      document: {
        documentKey: "doc-b",
        originalSlug: "doc-b",
        fileName: "doc-b.md",
        relativePath: "docs/doc-b.md",
        meta: {
          docType: "task_setup",
          slug: "doc-b",
          title: "文稿 B",
          status: "draft",
          tags: [],
          relatedDocs: [],
          sourceRefs: [],
        },
        markdown: "",
        validation: [],
      },
    };

    const message = actionHistoryMessage(result);
    expect(message).toContain("已创建文稿。");
    expect(message).toContain("涉及文稿：文稿 B");
    expect(message).toContain("目标文稿：文稿 B");
  });

  it("appends context messages and resolves action requests", () => {
    const session = createDocumentAgentSession({
      pendingActionRequests: [
        {
          id: "action-1",
          actionType: "apply_all_patches",
          title: "应用建议",
          description: "",
          payload: {},
          approvalPolicy: "always_require_user",
        },
      ],
    });
    const result: AgentActionResult = {
      requestId: "action-1",
      actionType: "apply_all_patches",
      status: "completed",
      summary: "已应用整篇 AI 建议。",
    };

    const appended = appendContextMessage(session, "msg-1", "上下文消息", "success");
    const resolved = resolveActionRequestSession(
      appended,
      "action-1",
      result,
      "msg-2",
      "success",
    );

    expect(appended.chatMessages).toHaveLength(1);
    expect(resolved.pendingActionRequests).toHaveLength(0);
    expect(resolved.actionHistory).toHaveLength(1);
    expect(resolved.chatMessages.at(-1)?.content).toContain("已应用整篇 AI 建议。");
  });

  it("merges pending derived documents without duplicates", () => {
    const session: DocumentAgentSession = createDocumentAgentSession({
      pendingDerivedDocuments: [
        { slug: "doc-a", title: "A", headingCount: 0, headings: [], excerpt: "" },
      ],
    });

    const next = mergePendingDerivedDocuments(session, [
      { slug: "doc-a", title: "A", headingCount: 0, headings: [], excerpt: "" },
      { slug: "doc-b", title: "B", headingCount: 0, headings: [], excerpt: "" },
    ]);

    expect(next.pendingDerivedDocuments.map((entry) => entry.slug)).toEqual(["doc-a", "doc-b"]);
  });

  it("maps generation response to waiting or completed session status", () => {
    expect(
      generationStatusFromResponse({
        engineMode: "single_agent",
        turnKind: "clarification",
        assistantMessage: "",
        draftMarkdown: "",
        summary: "",
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
        planSteps: [],
        requiresUserReply: true,
        executionSteps: [],
        requestedActions: [],
        sourceDocumentKeys: [],
        provenanceRefs: [],
        reviewQueueItems: [],
      }),
    ).toBe("waiting_user");
    expect(
      generationStatusFromResponse({
        engineMode: "single_agent",
        turnKind: "final_answer",
        assistantMessage: "done",
        draftMarkdown: "#",
        summary: "ok",
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
        planSteps: [],
        requiresUserReply: false,
        executionSteps: [],
        requestedActions: [],
        sourceDocumentKeys: [],
        provenanceRefs: [],
        reviewQueueItems: [],
      }),
    ).toBe("completed");
  });

  it("applies generation response onto an existing session", () => {
    const session = createDocumentAgentSession({
      chatMessages: [
        {
          id: "assistant-req-1",
          role: "assistant",
          label: "AI",
          content: "thinking",
        },
      ],
    });
    const next = applyGenerationResponseToSession({
      session,
      request: {
        requestId: "req-1",
        docType: "task_setup",
        targetSlug: "doc-a",
        action: "revise_document",
        userPrompt: "调整内容",
        editorInstruction: "",
        currentMarkdown: "# A\n\nold",
        relatedDocSlugs: [],
      },
      response: {
        engineMode: "single_agent",
        turnKind: "final_answer",
        assistantMessage: "done",
        draftMarkdown: "# A\n\nnew",
        summary: "已更新",
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
        planSteps: [],
        requiresUserReply: false,
        executionSteps: [],
        requestedActions: [],
        sourceDocumentKeys: [],
        provenanceRefs: [],
        reviewQueueItems: [],
      },
      assistantMessageId: "assistant-req-1",
      assistantMessage: {
        id: "assistant-req-1",
        role: "assistant",
        label: "AI",
        content: "已更新",
        tone: "success",
      },
      candidatePatchSet: {
        mode: "patches",
        currentMarkdown: "# A\n\nold",
        draftMarkdown: "# A\n\nnew",
        patches: [
          {
            id: "patch-1",
            title: "建议 1",
            startBlock: 1,
            endBlock: 2,
            originalText: "old",
            replacementText: "new",
          },
        ],
      },
      documentViewMode: "preview",
      versionBeforeMarkdown: "# A\n\nold",
    });

    expect(next.status).toBe("completed");
    expect(next.lastResponse?.summary).toBe("已更新");
    expect(next.chatMessages[0]?.content).toBe("已更新");
    expect(next.versionHistory).toHaveLength(1);
  });

  it("limits version history to 12 entries when new snapshot added", () => {
    const session = createDocumentAgentSession({
      versionHistory: Array.from({ length: 15 }, (_, index) => ({
        id: `version-${index}`,
        title: `old-${index}`,
        createdAt: new Date().toISOString(),
        beforeMarkdown: "a",
        afterMarkdown: "b",
        summary: `sum-${index}`,
        requestId: null,
      })),
    });
    const next = applyGenerationResponseToSession({
      session,
      request: {
        requestId: "req-4",
        docType: "task_setup",
        targetSlug: "doc-4",
        action: "revise_document",
        userPrompt: "更新内容",
        editorInstruction: "",
        currentMarkdown: "# A",
        relatedDocSlugs: [],
      },
      response: {
        engineMode: "single_agent",
        turnKind: "final_answer",
        assistantMessage: "done",
        draftMarkdown: "# A",
        summary: "ok",
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
        planSteps: [],
        requiresUserReply: false,
        executionSteps: [],
        requestedActions: [],
        sourceDocumentKeys: [],
        provenanceRefs: [],
        reviewQueueItems: [],
      },
      assistantMessageId: "assistant-req-4",
      assistantMessage: {
        id: "assistant-req-4",
        role: "assistant",
        label: "AI",
        content: "done",
        tone: "success",
      },
      candidatePatchSet: {
        mode: "patches",
        currentMarkdown: "# A",
        draftMarkdown: "# A",
        patches: [],
      },
      documentViewMode: "preview",
      versionBeforeMarkdown: "# A",
    });

    expect(next.versionHistory).toHaveLength(12);
  });

  it("builds a derived draft session seeded from the source conversation", () => {
    const session = buildDerivedDraftSession({
      request: {
        requestId: "req-2",
        docType: "task_setup",
        targetSlug: "doc-b",
        action: "create",
        userPrompt: "生成新文稿",
        editorInstruction: "",
        currentMarkdown: "# A",
        relatedDocSlugs: [],
      },
      response: {
        engineMode: "single_agent",
        turnKind: "final_answer",
        assistantMessage: "done",
        draftMarkdown: "# 新文稿",
        summary: "已生成",
        reviewNotes: [],
        riskLevel: "low",
        changeScope: "new_doc",
        promptDebug: {},
        rawOutput: "",
        usedContextRefs: [],
        diffPreview: "",
        providerError: "",
        synthesisNotes: [],
        agentRuns: [],
        questions: [],
        options: [],
        planSteps: [],
        requiresUserReply: false,
        executionSteps: [],
        requestedActions: [],
        sourceDocumentKeys: [],
        provenanceRefs: [],
        reviewQueueItems: [],
      },
      userMessage: {
        id: "user-1",
        role: "user",
        label: "你",
        content: "生成新文稿",
      },
      assistantMessage: {
        id: "assistant-req-2",
        role: "assistant",
        label: "AI",
        content: "done",
      },
      sourceDocumentKey: "doc-a",
      sourceDocumentTitle: "源文稿",
    });

    expect(session.selectedContextDocKeys).toEqual(["doc-a"]);
    expect(session.chatMessages[0]?.content).toContain("源文稿");
    expect(session.chatMessages).toHaveLength(3);
  });

  it("turns generation failures into an error session state", () => {
    const session = createDocumentAgentSession({
      chatMessages: [
        {
          id: "assistant-req-3",
          role: "assistant",
          label: "AI",
          content: "thinking",
        },
      ],
      busy: true,
      inflightRequestId: "req-3",
    });
    const next = applyGenerationErrorToSession(session, "assistant-req-3", new Error("boom"));

    expect(next.status).toBe("error");
    expect(next.busy).toBe(false);
    expect(next.inflightRequestId).toBeNull();
    expect(next.chatMessages[0]?.content).toContain("boom");
  });

  it("updates session title and strategy without dropping existing state", () => {
    const session = createDocumentAgentSession({
      sessionTitle: "旧标题",
      strategy: {
        rewriteIntensity: "balanced",
        priority: "consistency",
        questionBehavior: "balanced",
      },
    });

    const renamed = renameSessionTitle(session, "新标题");
    const updated = updateSessionStrategyValue(renamed, "priority", "drama");

    expect(updated.sessionTitle).toBe("新标题");
    expect(updated.strategy.priority).toBe("drama");
  });

  it("forks, archives, restores and clears session branches predictably", () => {
    const session = createDocumentAgentSession({
      sessionTitle: "主会话",
      pendingActionRequests: [
        {
          id: "action-1",
          actionType: "apply_all_patches",
          title: "动作",
          description: "",
          payload: {},
          approvalPolicy: "always_require_user",
        },
      ],
      savedBranches: [],
      selectedContextDocKeys: ["doc-a"],
    });

    const forked = forkSessionBranch(session, "主会话 分支");
    const archived = archiveSessionBranch(session);
    const branch = forked.savedBranches[0];
    const restored = branch ? restoreSessionBranch(forked, branch) : forked;
    const clearedActions = clearPendingActionRequestQueue(session);
    const clearedConversation = clearConversationSession(session);

    expect(forked.sessionTitle).toBe("主会话 分支");
    expect(forked.savedBranches).toHaveLength(1);
    expect(archived.savedBranches).toHaveLength(1);
    expect(archived.chatMessages).toHaveLength(0);
    expect(restored.sessionTitle).toBe(branch?.title);
    expect(clearedActions.pendingActionRequests).toHaveLength(0);
    expect(clearedConversation.selectedContextDocKeys).toEqual(["doc-a"]);
    expect(clearedConversation.chatMessages).toHaveLength(0);
  });

  it("resolves derived document review queues individually or in batch", () => {
    const session = createDocumentAgentSession({
      pendingDerivedDocuments: [
        { slug: "doc-a", title: "A", headingCount: 0, headings: [], excerpt: "" },
        { slug: "doc-b", title: "B", headingCount: 0, headings: [], excerpt: "" },
      ],
    });

    const approvedOne = resolveDerivedDocumentReview(session, "doc-a", "approved");
    const rejectedAll = clearAllDerivedDocumentsReview(session, "rejected");

    expect(approvedOne.pendingDerivedDocuments.map((entry) => entry.slug)).toEqual(["doc-b"]);
    expect(approvedOne.chatMessages.at(-1)?.content).toContain("已审阅");
    expect(rejectedAll.pendingDerivedDocuments).toHaveLength(0);
    expect(rejectedAll.chatMessages.at(-1)?.content).toContain("仍保留在工作区");
  });
});
