import { describe, expect, it, vi } from "vitest";
import type { DocumentAgentSession } from "../../types";
import {
  buildActionIntentRequest,
  beginGenerationSession,
  buildGenerationRequest,
  buildGenerationUserMessage,
  buildStrategyInstruction,
  buildUsedContextSummary,
  extractTitleFromMarkdown,
  summarizeGenerationResponseForChat,
} from "./narrativeGenerationFlow";
import { buildEditableDraftDocument } from "./narrativeDocumentState";
import { createDocumentAgentSession } from "./narrativeSessions";

function buildSession(overrides: Partial<DocumentAgentSession> = {}): DocumentAgentSession {
  return {
    ...createDocumentAgentSession({ mode: "revise_document" }),
    ...overrides,
  };
}

describe("narrativeGenerationFlow", () => {
  it("builds a generation user message from the resolved action", () => {
    const message = buildGenerationUserMessage({
      submittedPrompt: "请润色这一段",
      action: "revise_document",
    });

    expect(message.role).toBe("user");
    expect(message.meta).toEqual(["将修改当前文档"]);
  });

  it("builds an action intent request from current document and context", () => {
    const activeDocument = buildEditableDraftDocument("task_setup", "主文稿", "# 主文稿");
    const contextDocument = buildEditableDraftDocument("character_card", "角色文稿", "# 角色文稿");
    const session = buildSession({
      chatMessages: [
        { id: "user-1", role: "user", label: "你", content: "先看一下", tone: "accent" },
      ],
    });

    const request = buildActionIntentRequest({
      requestId: "intent-1",
      submittedPrompt: "把这个拆成单独文档",
      activeDocument,
      session,
      selectedContextDocuments: [contextDocument],
    });

    expect(request.requestId).toBe("intent-1");
    expect(request.submittedPrompt).toBe("把这个拆成单独文档");
    expect(request.docType).toBe(activeDocument.meta.docType);
    expect(request.targetSlug).toBe(activeDocument.meta.slug);
    expect(request.userPrompt).toContain("本轮需求：把这个拆成单独文档");
    expect(request.relatedDocSlugs).toContain(contextDocument.meta.slug);
  });

  it("builds a generation request with selected context ordering", () => {
    vi.useFakeTimers();
    vi.setSystemTime(1_710_000_000_000);

    const activeDocument = buildEditableDraftDocument("task_setup", "主文稿", "# 主文稿");
    vi.setSystemTime(1_710_000_000_001);
    const contextA = buildEditableDraftDocument("character_card", "人物 A", "# 人物 A");
    vi.setSystemTime(1_710_000_000_002);
    const contextB = buildEditableDraftDocument("location_note", "地点 B", "# 地点 B");
    const session = buildSession({
      chatMessages: [
        { id: "user-1", role: "user", label: "你", content: "先看一下", tone: "accent" },
      ],
    });

    const request = buildGenerationRequest({
      requestId: "request-1",
      submittedPrompt: "继续扩写",
      activeDocument,
      session,
      selectedContextDocuments: [contextA, contextB],
      action: "revise_document",
    });

    expect(request.requestId).toBe("request-1");
    expect(request.relatedDocSlugs).toEqual([contextA.meta.slug, contextB.meta.slug]);
    expect(request.editorInstruction).toContain(
      `Selected context docs: ${contextA.meta.slug}, ${contextB.meta.slug}`,
    );
    expect(request.userPrompt).toContain("本轮需求：继续扩写");

    vi.useRealTimers();
  });

  it("marks generation session as thinking and appends placeholder assistant text", () => {
    const session = beginGenerationSession(buildSession(), {
      requestId: "request-1",
      userMessage: {
        id: "user-1",
        role: "user",
        label: "你",
        content: "hello",
        tone: "accent",
      },
      assistantMessageId: "assistant-request-1",
    });

    expect(session.status).toBe("generating");
    expect(session.busy).toBe(true);
    expect(session.inflightRequestId).toBe("request-1");
    expect(session.chatMessages.at(-1)?.id).toBe("assistant-request-1");
    expect(session.chatMessages.at(-1)?.content).toContain("正在准备生成内容");
  });

  it("summarizes clarification responses with question list", () => {
    const summary = summarizeGenerationResponseForChat({
      turnKind: "clarification",
      assistantMessage: "",
      draftMarkdown: "",
      providerError: "",
      summary: "",
      synthesisNotes: [],
      questions: [
        { id: "q1", label: "主角是谁？", required: true, placeholder: "" },
      ],
      options: [],
      planSteps: [],
    });

    expect(summary).toContain("还需要你补充这些信息");
    expect(summary).toContain("主角是谁");
  });

  it("extracts titles from markdown headings", () => {
    expect(extractTitleFromMarkdown("# 新标题\n\n内容", "回退标题")).toBe("新标题");
    expect(extractTitleFromMarkdown("无标题正文", "回退标题")).toBe("回退标题");
  });

  it("builds used-context summary text", () => {
    expect(buildUsedContextSummary([])).toContain("仅使用主文稿");
    expect(buildUsedContextSummary(["narrative:doc-a", "runtime:quests"])).toContain(
      "narrative:doc-a、runtime:quests",
    );
  });

  it("formats strategy instruction with localized labels", () => {
    const summary = buildStrategyInstruction(
      buildSession({
        strategy: {
          rewriteIntensity: "aggressive",
          priority: "drama",
          questionBehavior: "ask_first",
        },
      }),
    );

    expect(summary).toBe("激进重构；优先戏剧性；信息不足时先提问");
  });
});
