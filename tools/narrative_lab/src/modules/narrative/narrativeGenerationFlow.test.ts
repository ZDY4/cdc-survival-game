import { describe, expect, it, vi } from "vitest";
import type { DocumentAgentSession } from "../../types";
import {
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
    ...createDocumentAgentSession("revise_document"),
    ...overrides,
  };
}

describe("narrativeGenerationFlow", () => {
  it("builds a generation user message from the current session mode", () => {
    const message = buildGenerationUserMessage({
      submittedPrompt: "请润色这一段",
      session: buildSession({ mode: "revise_document" }),
    });

    expect(message.role).toBe("user");
    expect(message.meta).toEqual(["修改当前文档"]);
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

    expect(session.status).toBe("thinking");
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
