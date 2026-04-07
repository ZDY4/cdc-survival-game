import type {
  AgentOption,
  AgentPlanStep,
  AgentQuestion,
  AiChatMessage,
  DocumentAgentSession,
  NarrativeGenerateRequest,
  ResolveNarrativeActionIntentInput,
  NarrativeGenerateResponse,
  NarrativeTurnKind,
} from "../../types";
import {
  buildPendingTurnContext,
  mergeRelatedDocSlugs,
  type EditableNarrativeDocument,
} from "./narrativeSessionHelpers";
import { nowIso } from "./narrativeAgentState";

// AI 发起前的组装层：
// 负责请求构建、会话预热、聊天摘要文案，以及从生成结果里提取标题/上下文说明。
export function buildNarrativeChatPrompt(
  input: string,
  history: AiChatMessage[],
  selectedDocument: EditableNarrativeDocument | null,
  pendingTurnContext?: string,
) {
  const sections: string[] = [];
  const turns = history
    .filter((message) => message.role === "user" || message.role === "assistant")
    .slice(-6);

  if (selectedDocument) {
    sections.push(`当前文档：${selectedDocument.meta.title || selectedDocument.meta.slug}`);
  }

  if (turns.length) {
    sections.push(
      [
        "最近对话：",
        ...turns.map((message) => `${message.role === "user" ? "用户" : "AI"}：${message.content}`),
      ].join("\n"),
    );
  }

  if (pendingTurnContext?.trim()) {
    sections.push(pendingTurnContext.trim());
  }

  sections.push(`本轮需求：${input.trim()}`);

  return sections.filter(Boolean).join("\n\n");
}

export function buildStrategyInstruction(session: DocumentAgentSession) {
  const intensityLabel =
    session.strategy.rewriteIntensity === "light"
      ? "保守改写"
      : session.strategy.rewriteIntensity === "aggressive"
        ? "激进重构"
        : "平衡改写";
  const priorityLabel =
    session.strategy.priority === "drama"
      ? "优先戏剧性"
      : session.strategy.priority === "speed"
        ? "优先速度"
        : "优先一致性";
  const questionLabel =
    session.strategy.questionBehavior === "ask_first"
      ? "信息不足时先提问"
      : session.strategy.questionBehavior === "direct"
        ? "尽量直接产出"
        : "先判断再决定是否提问";
  return [intensityLabel, priorityLabel, questionLabel].join("；");
}

type BuildGenerationUserMessageInput = {
  submittedPrompt: string;
  action: "create" | "revise_document" | null;
};

export function buildGenerationUserMessage({
  submittedPrompt,
  action,
}: BuildGenerationUserMessageInput): AiChatMessage {
  return {
    id: `user-${Date.now()}`,
    role: "user",
    label: "你",
    content: submittedPrompt,
    meta: [
      action === null
        ? "待确认动作"
        : action === "create"
          ? "将创建新文档"
          : "将修改当前文档",
    ],
    tone: "accent",
  };
}

type BuildActionIntentRequestInput = {
  requestId: string;
  submittedPrompt: string;
  activeDocument: EditableNarrativeDocument;
  session: DocumentAgentSession;
  selectedContextDocuments: EditableNarrativeDocument[];
};

export function buildActionIntentRequest({
  requestId,
  submittedPrompt,
  activeDocument,
  session,
  selectedContextDocuments,
}: BuildActionIntentRequestInput): ResolveNarrativeActionIntentInput {
  return {
    requestId,
    submittedPrompt,
    docType: activeDocument.meta.docType,
    targetSlug: activeDocument.meta.slug,
    userPrompt: buildNarrativeChatPrompt(
      submittedPrompt,
      session.chatMessages,
      activeDocument,
      buildPendingTurnContext(session),
    ),
    editorInstruction: [
      `Agent strategy: ${buildStrategyInstruction(session)}`,
      selectedContextDocuments.length
        ? `Selected context docs: ${selectedContextDocuments
            .map((document) => document.meta.slug)
            .join(", ")}`
        : "",
    ]
      .filter(Boolean)
      .join("\n"),
    currentMarkdown: activeDocument.markdown,
    relatedDocSlugs: mergeRelatedDocSlugs(activeDocument, selectedContextDocuments),
  };
}

type BuildGenerationRequestInput = {
  requestId: string;
  submittedPrompt: string;
  activeDocument: EditableNarrativeDocument;
  session: DocumentAgentSession;
  selectedContextDocuments: EditableNarrativeDocument[];
  action: "create" | "revise_document";
};

export function buildGenerationRequest({
  requestId,
  submittedPrompt,
  activeDocument,
  session,
  selectedContextDocuments,
  action,
}: BuildGenerationRequestInput): NarrativeGenerateRequest {
  return {
    requestId,
    docType: activeDocument.meta.docType,
    targetSlug:
      action === "create"
        ? `${activeDocument.meta.slug}-ai-${Date.now()}`
        : activeDocument.meta.slug,
    action,
    userPrompt: buildNarrativeChatPrompt(
      submittedPrompt,
      session.chatMessages,
      activeDocument,
      buildPendingTurnContext(session),
    ),
    editorInstruction: [
      `Agent strategy: ${buildStrategyInstruction(session)}`,
      selectedContextDocuments.length
        ? `Selected context docs: ${selectedContextDocuments
            .map((document) => document.meta.slug)
            .join(", ")}`
        : "",
    ]
      .filter(Boolean)
      .join("\n"),
    currentMarkdown: activeDocument.markdown,
    relatedDocSlugs: mergeRelatedDocSlugs(activeDocument, selectedContextDocuments),
    derivedTargetDocType: null,
  };
}

type BeginGenerationSessionInput = {
  requestId: string;
  userMessage: AiChatMessage;
  assistantMessageId: string;
};

export function beginGenerationSession(
  session: DocumentAgentSession,
  { requestId, userMessage, assistantMessageId }: BeginGenerationSessionInput,
): DocumentAgentSession {
  return {
    ...session,
    updatedAt: nowIso(),
    status: "generating",
    executionSteps: [],
    currentStepId: null,
    busy: true,
    inflightRequestId: requestId,
    pendingQuestions: [],
    pendingOptions: [],
    pendingTurnKind: null,
    chatMessages: [
      ...session.chatMessages,
      userMessage,
      {
        id: assistantMessageId,
        role: "assistant",
        label: "AI",
        content: "正在准备生成内容...",
        meta: ["正在准备请求"],
        tone: "muted",
      },
    ],
  };
}

export function summarizeGenerationResponseForChat(response: {
  turnKind: NarrativeTurnKind;
  assistantMessage: string;
  draftMarkdown: string;
  providerError: string;
  summary: string;
  synthesisNotes: string[];
  questions: AgentQuestion[];
  options: AgentOption[];
  planSteps: AgentPlanStep[];
}) {
  const headline =
    response.providerError.trim() ||
    response.assistantMessage.trim() ||
    response.summary.trim() ||
    "AI 已返回结果。";
  const sections = [headline];

  if (!response.providerError.trim()) {
    if (response.turnKind === "clarification" && response.questions.length) {
      sections.push(
        [
          "还需要你补充这些信息：",
          ...response.questions.map(
            (question, index) =>
              `${index + 1}. ${question.label}${question.required ? "（必填）" : ""}`,
          ),
        ].join("\n"),
      );
    }

    if (response.turnKind === "options" && response.options.length) {
      sections.push(
        [
          "我整理了这些可继续推进的方向：",
          ...response.options.map((option, index) =>
            [
              `${index + 1}. **${option.label}**`,
              option.description.trim() ? `   ${option.description.trim()}` : "",
            ]
              .filter(Boolean)
              .join("\n"),
          ),
        ].join("\n"),
      );
    }

    if (response.turnKind === "plan" && response.planSteps.length) {
      sections.push(
        [
          "建议按这个计划继续：",
          ...response.planSteps.map(
            (step, index) =>
              `${index + 1}. ${step.label}${step.status === "completed" ? "（已完成）" : ""}`,
          ),
        ].join("\n"),
      );
    }
  }

  const notes = response.synthesisNotes.map((note) => note.trim()).filter(Boolean).slice(0, 2);
  if (notes.length) {
    sections.push(["补充说明：", ...notes.map((note) => `- ${note}`)].join("\n"));
  }

  if (
    !response.providerError.trim() &&
    response.turnKind === "final_answer" &&
    response.draftMarkdown.trim()
  ) {
    sections.push(["生成内容：", response.draftMarkdown.trim()].join("\n\n"));
  }

  return sections.join("\n\n");
}

export function extractTitleFromMarkdown(markdown: string, fallback: string) {
  const heading = markdown
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find((line) => line.startsWith("# "));
  return heading ? heading.replace(/^#\s+/, "").trim() || fallback : fallback;
}

export function buildUsedContextSummary(usedContextRefs: string[]): string {
  if (!usedContextRefs.length) {
    return "本轮仅使用主文稿与内置模板上下文。";
  }

  return `本轮实际引用：${usedContextRefs.join("、")}`;
}

export function isFullDocumentRewriteRisky(
  currentMarkdown: string,
  draftMarkdown: string,
  patchCount: number,
): boolean {
  if (!draftMarkdown.trim()) {
    return false;
  }

  if (!currentMarkdown.trim()) {
    return false;
  }

  return patchCount === 0;
}
