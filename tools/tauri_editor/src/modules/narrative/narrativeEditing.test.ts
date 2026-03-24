import { describe, expect, it } from "vitest";
import { applySelectionRange, narrativeDiffSummary, toUtf8SelectionRange } from "./narrativeEditing";

describe("narrativeEditing", () => {
  it("converts textarea selection into utf8 byte offsets", () => {
    const source = "你好 world";
    const range = toUtf8SelectionRange(source, 0, 2);
    expect(range.start).toBe(0);
    expect(range.end).toBeGreaterThan(2);
  });

  it("replaces selected content using utf8 byte offsets", () => {
    const source = "第一段\n第二段";
    const range = toUtf8SelectionRange(source, 0, 3);
    const next = applySelectionRange(source, range, "新段落", "replace");
    expect(next.startsWith("新段落")).toBe(true);
    expect(next.includes("第二段")).toBe(true);
  });

  it("prefers host diff preview when available", () => {
    const summary = narrativeDiffSummary(
      "before",
      {
        engineMode: "multi_agent",
        draftMarkdown: "after",
        summary: "",
        reviewNotes: [],
        riskLevel: "low",
        changeScope: "document",
        promptDebug: {},
        rawOutput: "",
        usedContextRefs: [],
        diffPreview: "custom diff",
        providerError: "",
        synthesisNotes: [],
        agentRuns: [],
      },
      "",
    );
    expect(summary).toBe("custom diff");
  });
});
