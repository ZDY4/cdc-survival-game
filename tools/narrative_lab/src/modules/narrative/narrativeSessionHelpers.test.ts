import { describe, expect, it } from "vitest";
import {
  buildPendingTurnContext,
  EditableNarrativeDocument,
  mergeRelatedDocSlugs,
  responseMetaLabels,
} from "./narrativeSessionHelpers";
import type {
  AgentOption,
  AgentPlanStep,
  AgentQuestion,
  DocumentAgentSession,
  NarrativeGenerateResponse,
} from "../../types";

const baseDocument: EditableNarrativeDocument = {
  documentKey: "doc-1",
  originalSlug: "doc-1",
  fileName: "doc-1.md",
  relativePath: "doc-1.md",
  meta: {
    docType: "task_setup",
    slug: "doc-1",
    title: "Doc 1",
    status: "draft",
    tags: [],
    relatedDocs: ["related-a"],
    sourceRefs: [],
  },
  markdown: "",
  validation: [],
  savedSnapshot: "",
  dirty: false,
  isDraft: true,
};

describe("narrativeSessionHelpers", () => {
  it("merges related doc slugs without duplicates", () => {
    const additional: EditableNarrativeDocument[] = [
      { ...baseDocument, meta: { ...baseDocument.meta, slug: "related-b", relatedDocs: [] } },
      { ...baseDocument, meta: { ...baseDocument.meta, slug: "related-a", relatedDocs: [] } },
    ];
    const merged = mergeRelatedDocSlugs(baseDocument, additional);

    expect(merged).toEqual(["related-a", "related-b"]);
  });

  it("builds pending context from questions, options, and plan", () => {
    const session: DocumentAgentSession = {
      sessionId: "s",
      sessionTitle: "title",
      updatedAt: "",
      mode: "revise_document",
      composerText: "",
      chatMessages: [],
      lastRequest: null,
      lastResponse: null,
      candidatePatchSet: null,
      status: "idle",
      pendingQuestions: [
        { id: "q1", label: "Question?" as string, required: true },
      ] as AgentQuestion[],
      pendingOptions: [],
      lastPlan: null,
      pendingTurnKind: null,
      executionSteps: [],
      currentStepId: null,
      pendingActionRequests: [],
      actionHistory: [],
      selectedContextDocKeys: [],
      strategy: {
        priority: "drama",
        questionBehavior: "balanced",
        rewriteIntensity: "balanced",
      },
      reviewQueue: [],
      versionHistory: [],
      pendingDerivedDocuments: [],
      savedBranches: [],
      busy: false,
      documentViewMode: "preview",
    };

    const afterQuestion = buildPendingTurnContext(session);
    expect(afterQuestion).toContain("补充信息");

    const optionSession = { ...session, pendingQuestions: [], pendingOptions: [{ id: "opt", label: "Opt", description: "Desc", followupPrompt: "next" }] as AgentOption[] };
    expect(buildPendingTurnContext(optionSession)).toContain("候选方向");

    const planSession = {
      ...session,
      pendingQuestions: [],
      pendingOptions: [],
      pendingTurnKind: "plan",
      lastPlan: [{ id: "step", label: "Step", status: "pending" }] as AgentPlanStep[],
    };
    expect(buildPendingTurnContext(planSession)).toContain("执行计划");
  });

  it("labels provider errors and turn kinds", () => {
    const response: NarrativeGenerateResponse = {
      engineMode: "single_agent",
      turnKind: "final_answer",
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
      providerError: "boom",
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
    };

    expect(responseMetaLabels(response)).toEqual(["提供方返回错误", "单文档助手"]);
  });
});
