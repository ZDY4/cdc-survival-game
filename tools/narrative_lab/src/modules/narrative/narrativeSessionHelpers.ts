import type {
  DocumentAgentSession,
  NarrativeDocumentPayload,
  NarrativeGenerateResponse,
} from "../../types";

export type EditableNarrativeDocument = NarrativeDocumentPayload & {
  savedSnapshot: string;
  dirty: boolean;
  isDraft: boolean;
};

export function mergeRelatedDocSlugs(
  activeDocument: EditableNarrativeDocument,
  selectedContextDocuments: EditableNarrativeDocument[],
) {
  const slugs = [...activeDocument.meta.relatedDocs];
  for (const document of selectedContextDocuments) {
    if (!slugs.includes(document.meta.slug)) {
      slugs.push(document.meta.slug);
    }
  }
  return slugs;
}

export function buildPendingTurnContext(session: DocumentAgentSession) {
  if (session.pendingQuestions.length) {
    return [
      "上一轮 AI 正在等待这些补充信息：",
      ...session.pendingQuestions.map((question, index) => `${index + 1}. ${question.label}`),
    ].join("\n");
  }

  if (session.pendingOptions.length) {
    return [
      "上一轮 AI 给出的候选方向：",
      ...session.pendingOptions.map((option, index) => `${index + 1}. ${option.label}：${option.description}`),
    ].join("\n");
  }

  if (session.pendingTurnKind === "plan" && session.lastPlan?.length) {
    return [
      "上一轮 AI 提出的执行计划：",
      ...session.lastPlan.map((step, index) => `${index + 1}. ${step.label}`),
      "如果本轮用户表示继续、确认或补充约束，应基于这个计划继续执行。",
    ].join("\n");
  }

  return "";
}

export function responseMetaLabels(response: NarrativeGenerateResponse) {
  const turnLabelLookup: Record<NarrativeGenerateResponse["turnKind"], string> = {
    final_answer: "已生成结果",
    clarification: "等待补充",
    options: "等待选择",
    plan: "等待确认计划",
    blocked: "暂时阻塞",
  };

  return [
    response.providerError ? "提供方返回错误" : turnLabelLookup[response.turnKind],
    response.engineMode === "single_agent" ? "单文档助手" : "多 agent",
  ];
}
