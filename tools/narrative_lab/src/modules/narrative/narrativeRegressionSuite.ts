import type {
  NarrativeRegressionCase,
  NarrativeRegressionCaseResult,
  NarrativeRegressionSuiteResult,
} from "../../types";

// Narrative Lab 行为回归的定义与执行入口：
// 把 case 清单、runner 协议和结果汇总从主组件里独立出来，便于扩展和复用。
export const NARRATIVE_REGRESSION_CASES: NarrativeRegressionCase[] = [
  {
    id: "clarification-missing-brief",
    label: "缺少核心信息时先提问",
    prompt: "我要写一个新篇章，但你先别动笔，先告诉我还缺哪些必要信息。",
    expectedTurnKinds: ["clarification", "options"],
  },
  {
    id: "options-branching",
    label: "有分叉时给方向",
    prompt: "基于当前文稿先给我三个截然不同的推进方向，不要直接改正文。",
    expectedTurnKinds: ["options", "plan"],
  },
  {
    id: "plan-complex-task",
    label: "复杂任务先给计划",
    prompt: "把当前文稿拆成一个分步骤执行计划，等我确认后再继续。",
    expectedTurnKinds: ["plan"],
  },
  {
    id: "final-answer-polish",
    label: "明确改写时直接产出",
    prompt: "在保持设定一致的前提下润色当前文稿，并直接给我可保存版本。",
    expectedTurnKinds: ["final_answer"],
  },
  {
    id: "split-out-derived-doc",
    label: "拆出独立文档时仍保留当前文档编辑",
    prompt:
      "把当前文稿里“商人老王”的角色设定从这篇文档中移出去，并单独创建一份商人老王角色设定文档。",
    expectedTurnKinds: ["final_answer"],
  },
];

export type NarrativeRegressionRunner = (
  caseItem: NarrativeRegressionCase,
) => Promise<NarrativeRegressionCaseResult>;

export type NarrativeRegressionSuiteOptions = {
  cases?: NarrativeRegressionCase[];
  runCase: NarrativeRegressionRunner;
};

export function summarizeNarrativeRegressionResults(
  results: NarrativeRegressionCaseResult[],
): NarrativeRegressionSuiteResult {
  const passed = results.every((item) => item.ok);
  const summary = passed
    ? `回归验证通过，共 ${results.length} 项。`
    : `回归验证发现 ${results.filter((item) => !item.ok).length} 项漂移。`;

  return {
    ok: passed,
    results,
    summary,
  };
}

export async function runNarrativeRegressionSuite({
  cases = NARRATIVE_REGRESSION_CASES,
  runCase,
}: NarrativeRegressionSuiteOptions): Promise<NarrativeRegressionSuiteResult> {
  const results: NarrativeRegressionCaseResult[] = [];

  for (const caseItem of cases) {
    const result = await runCase(caseItem);
    results.push(result);
  }

  return summarizeNarrativeRegressionResults(results);
}
