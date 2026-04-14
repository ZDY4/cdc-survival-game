import type {
  NarrativeChatRegressionMode,
  NarrativeChatRegressionReport,
  NarrativeChatRegressionScenario,
  NarrativeChatRegressionScenarioResult,
} from "../../types";

export const NARRATIVE_CHAT_REGRESSION_ACTIVE_SLUG = "cdc-world-core";

export const NARRATIVE_CHAT_REGRESSION_SCENARIOS: NarrativeChatRegressionScenario[] = [
  {
    id: "clarification-missing-brief",
    label: "缺少核心信息时先提问",
    prompt: "我要写一个新篇章，但你先别动笔，先告诉我还缺哪些必要信息。",
    mode: "both",
    smokeTier: "structured",
    expectedTurnKinds: ["clarification"],
  },
  {
    id: "options-branching",
    label: "给出截然不同的推进方向",
    prompt: "基于当前文稿先给我三个截然不同的推进方向，不要直接改正文。",
    mode: "both",
    smokeTier: "structured",
    expectedTurnKinds: ["options"],
  },
  {
    id: "plan-complex-task",
    label: "复杂任务先给执行计划",
    prompt: "把当前文稿拆成一个分步骤执行计划，等我确认后再继续。",
    mode: "both",
    smokeTier: "structured",
    expectedTurnKinds: ["plan"],
  },
  {
    id: "direct-revise-section",
    label: "直接重写污染机制小节",
    prompt: "保留设定一致性，重写‘污染机制’小节，让它更短、更清楚、更适合游戏内引用。",
    mode: "both",
    smokeTier: "core",
    expectedTurnKinds: ["final_answer"],
    expectDocumentChange: true,
  },
  {
    id: "split-out-character-doc",
    label: "拆出商人老王人物设定",
    prompt: "把当前文稿里‘商人老王’相关内容移出去，单独创建一份人物设定，并从当前文稿删掉这部分。",
    mode: "both",
    smokeTier: "core",
    expectedTurnKinds: ["final_answer"],
    expectedActionType: "create_derived_document",
    expectDocumentChange: true,
    expectDerivedDocumentSlug: "trader-lao-wang-split",
    expectDerivedDocumentDocType: "character_card",
    expectDerivedDocumentTitleIncludes: "商人老王",
    allowDerivedSlugVariance: true,
    autoApproveAction: true,
  },
  {
    id: "derive-location-note",
    label: "派生废弃医院地点文档",
    prompt: "基于这份世界观，创建一份‘废弃医院’地点设定文档，保持与陈医生线索一致。",
    mode: "offline",
    expectedTurnKinds: ["final_answer"],
    expectedActionType: "create_derived_document",
    expectDerivedDocumentSlug: "abandoned-hospital-ai-note",
    expectDerivedDocumentDocType: "location_note",
    autoApproveAction: true,
    useSelectedContextSlugs: ["doctor-chen-card", "abandoned-hospital-note"],
  },
  {
    id: "preview-actions-only",
    label: "仅预览建议动作",
    prompt: "先列出你建议执行的编辑动作，不要直接保存或应用。",
    mode: "offline",
    expectedTurnKinds: ["final_answer"],
    expectedActionType: "save_active_document",
    expectedPreviewOnly: true,
    autoRejectAction: true,
  },
  {
    id: "markdown-rich-render",
    label: "富文本 Markdown 显示",
    prompt: "给我一段用于策划评审的补充说明，包含引用、清单和表格，直接追加到文稿末尾。",
    mode: "offline",
    expectedTurnKinds: ["final_answer"],
    expectDocumentChange: true,
  },
  {
    id: "context-aware-revision",
    label: "结合上下文文档修订",
    prompt: "结合陈医生角色卡和当前世界观，补一段他为什么掌握首批污染线索。",
    mode: "offline",
    expectedTurnKinds: ["final_answer"],
    expectDocumentChange: true,
    expectSelectedContextRefs: true,
    useSelectedContextSlugs: ["doctor-chen-card"],
  },
  {
    id: "provider-error-429",
    label: "AI 服务 429 错误",
    prompt: "这是 429 回归场景，请按测试要求处理。",
    mode: "offline",
    expectedTurnKinds: ["blocked"],
  },
  {
    id: "stream-fallback",
    label: "流式失败后回退非流式",
    prompt: "这是 stream fallback 回归场景，请给我一段最终可以保存的精简总结。",
    mode: "offline",
    expectedTurnKinds: ["final_answer"],
    expectDocumentChange: true,
  },
  {
    id: "cancel-inflight",
    label: "取消处理中请求",
    prompt: "这是 cancel inflight 回归场景，请模拟较慢的生成过程。",
    mode: "offline",
    expectedTurnKinds: ["blocked"],
  },
];

export function scenariosForMode(
  mode: NarrativeChatRegressionMode,
  scenarios = NARRATIVE_CHAT_REGRESSION_SCENARIOS,
) {
  return scenarios.filter((scenario) => {
    const modeMatches =
      mode === "offline"
        ? scenario.mode === "both" || scenario.mode === "offline"
        : scenario.mode === "both";
    if (!modeMatches) {
      return false;
    }

    if (mode === "online-core") {
      return scenario.smokeTier === "core";
    }
    if (mode === "online-structured") {
      return scenario.smokeTier === "structured";
    }
    return true;
  });
}

export function isOnlineRegressionMode(mode: NarrativeChatRegressionMode) {
  return mode === "online" || mode === "online-core" || mode === "online-structured";
}

export function regressionModeLabel(mode: NarrativeChatRegressionMode) {
  switch (mode) {
    case "online-core":
      return "online-core";
    case "online-structured":
      return "online-structured";
    default:
      return mode;
  }
}

export function summarizeFailureKinds(results: NarrativeChatRegressionScenarioResult[]) {
  const counts = new Map<string, number>();
  for (const result of results) {
    if (result.ok || result.failureKind === "none") {
      continue;
    }
    counts.set(result.failureKind, (counts.get(result.failureKind) ?? 0) + 1);
  }
  return Array.from(counts.entries())
    .map(([failureKind, count]) => `${failureKind}=${count}`)
    .join(", ");
}

export function summarizeNarrativeChatRegression(
  report: Omit<NarrativeChatRegressionReport, "ok" | "summary">,
): NarrativeChatRegressionReport {
  const failed = report.scenarioResults.filter((item) => !item.ok);
  const ok = failed.length === 0;
  const failureSummary = summarizeFailureKinds(failed);
  const summary = ok
    ? `Narrative chat regression passed (${report.scenarioResults.length}/${report.scenarioResults.length}).`
    : `Narrative chat regression failed (${report.scenarioResults.length - failed.length}/${report.scenarioResults.length}). Failed: ${failed
        .map((item) => item.id)
        .join(", ")}.${failureSummary ? ` Failure kinds: ${failureSummary}.` : ""}`;

  return {
    ...report,
    ok,
    summary,
  };
}

export function scenarioResultSummary(result: NarrativeChatRegressionScenarioResult) {
  const status = result.ok ? "PASS" : "FAIL";
  return `[${status}] ${result.id} => ${result.actualTurnKind} / ${result.summary}`;
}
