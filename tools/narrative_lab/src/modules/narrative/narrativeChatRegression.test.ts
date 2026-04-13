import { describe, expect, it } from "vitest";

import {
  NARRATIVE_CHAT_REGRESSION_SCENARIOS,
  scenariosForMode,
  summarizeNarrativeChatRegression,
} from "./narrativeChatRegression";

describe("narrativeChatRegression", () => {
  it("keeps the online subset focused on the high-value scenarios", () => {
    expect(scenariosForMode("online").map((scenario) => scenario.id)).toEqual([
      "clarification-missing-brief",
      "options-branching",
      "plan-complex-task",
      "direct-revise-section",
      "split-out-character-doc",
    ]);
  });

  it("supports online smoke tiers", () => {
    expect(scenariosForMode("online-core").map((scenario) => scenario.id)).toEqual([
      "direct-revise-section",
      "split-out-character-doc",
    ]);
    expect(scenariosForMode("online-structured").map((scenario) => scenario.id)).toEqual([
      "clarification-missing-brief",
      "options-branching",
      "plan-complex-task",
    ]);
  });

  it("includes offline-only scenarios in offline mode", () => {
    const offlineScenarioIds = scenariosForMode("offline").map((scenario) => scenario.id);
    expect(offlineScenarioIds).toContain("provider-error-429");
    expect(offlineScenarioIds).toContain("stream-fallback");
    expect(offlineScenarioIds).toContain("cancel-inflight");
  });

  it("summarizes a passing regression report", () => {
    const report = summarizeNarrativeChatRegression({
      mode: "offline",
      workspaceRoot: "workspace",
      connectedProjectRoot: null,
      startedAt: "2026-01-01T00:00:00Z",
      completedAt: "2026-01-01T00:10:00Z",
      skippedScenarios: [],
      scenarioResults: NARRATIVE_CHAT_REGRESSION_SCENARIOS.slice(0, 1).map((scenario) => ({
        id: scenario.id,
        label: scenario.label,
        ok: true,
        prompt: scenario.prompt,
        mode: "offline" as const,
        smokeTier: scenario.smokeTier,
        failureKind: "none" as const,
        actualTurnKind: scenario.expectedTurnKinds[0] ?? "blocked",
        expectedTurnKinds: scenario.expectedTurnKinds,
        requestedActionType: null,
        requestedPreviewOnly: null,
        assistantMessage: "ok",
        providerError: "",
        documentChanged: false,
        activeDocumentSlug: "doc",
        derivedDocumentSlug: null,
        derivedDocumentPath: null,
        contextRefCount: 0,
        questionCount: 0,
        optionCount: 0,
        planStepCount: 0,
        requestedActionCount: 0,
        turnKindSource: "explicit",
        turnKindCorrection: null,
        diagnosticFlags: [],
        statusMessage: "ok",
        summary: "ok",
        error: null,
      })),
    });

    expect(report.ok).toBe(true);
    expect(report.summary).toContain("passed");
  });
});
