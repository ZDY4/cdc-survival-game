import { describe, expect, it } from "vitest";

import {
  NARRATIVE_REGRESSION_CASES,
  runNarrativeRegressionSuite,
  summarizeNarrativeRegressionResults,
} from "./narrativeRegressionSuite";
import type { NarrativeRegressionCase, NarrativeRegressionCaseResult } from "../../types";

describe("narrativeRegressionSuite helpers", () => {
  it("summarizes a passing regression suite", () => {
    const results: NarrativeRegressionCaseResult[] = [
      {
        id: "clarification-missing-brief",
        label: "缺少核心信息时先提问",
        expectedTurnKinds: ["clarification", "options"],
        actualTurnKind: "clarification",
        ok: true,
        summary: "帮助提问",
      },
    ];

    const summary = summarizeNarrativeRegressionResults(results);

    expect(summary.ok).toBe(true);
    expect(summary.summary).toBe("回归验证通过，共 1 项。");
  });

  it("summarizes failing regression suites", () => {
    const results: NarrativeRegressionCaseResult[] = [
      {
        id: "options-branching",
        label: "有分叉时给方向",
        expectedTurnKinds: ["options", "plan"],
        actualTurnKind: "clarification",
        ok: false,
        summary: "先 clarifies",
      },
      {
        id: "plan-complex-task",
        label: "复杂任务先给计划",
        expectedTurnKinds: ["plan"],
        actualTurnKind: "plan",
        ok: true,
        summary: "Plan ready",
      },
    ];

    const summary = summarizeNarrativeRegressionResults(results);

    expect(summary.ok).toBe(false);
    expect(summary.summary).toBe("回归验证发现 1 项漂移。");
  });

  it("runs each regression case through the provided runner", async () => {
    const executionOrder: string[] = [];
    const runner = async (caseItem: NarrativeRegressionCase) => {
      executionOrder.push(caseItem.id);
      return {
        id: caseItem.id,
        label: caseItem.label,
        expectedTurnKinds: caseItem.expectedTurnKinds,
        actualTurnKind: caseItem.expectedTurnKinds[0] ?? "final_answer",
        ok: caseItem.id !== "options-branching",
        summary: `Processed ${caseItem.id}`,
      };
    };

    const result = await runNarrativeRegressionSuite({ runCase: runner });

    expect(executionOrder).toEqual(NARRATIVE_REGRESSION_CASES.map((entry) => entry.id));
    expect(result.summary).toBe("回归验证发现 1 项漂移。");
  });
});
