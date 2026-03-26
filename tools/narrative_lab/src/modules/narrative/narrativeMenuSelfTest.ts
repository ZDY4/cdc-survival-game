import { inspectEditorMenuCommand } from "../../menu/editorCommandRegistry";
import { handleEditorMenuCommand } from "../../menu/menuBridge";
import { logEditorMenuDebug } from "../../menu/menuDebug";
import { EDITOR_MENU_COMMANDS, type EditorMenuCommandId } from "../../menu/menuCommands";

type SelfTestExpectation = "enabled" | "disabled";

type SelfTestCheck = {
  commandId: EditorMenuCommandId;
  expected: SelfTestExpectation;
  execute?: boolean;
};

type SelfTestCheckResult = {
  commandId: EditorMenuCommandId;
  expected: SelfTestExpectation;
  actual: "enabled" | "disabled" | "missing";
  passed: boolean;
  executed: boolean;
  sourceId?: string;
  error?: string;
};

export type NarrativeMenuSelfTestResult = {
  passed: boolean;
  summary: string;
  checks: SelfTestCheckResult[];
};

type RunNarrativeMenuSelfTestOptions = {
  hasActiveWorkspace: boolean;
  onStatusChange: (status: string) => void;
  windowLabel: string;
};

function buildNarrativeMenuSelfTestChecks(): SelfTestCheck[] {
  return [
    {
      commandId: EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT,
      expected: "enabled",
    },
    {
      commandId: EDITOR_MENU_COMMANDS.NARRATIVE_NEW_PROJECT_BRIEF,
      expected: "enabled",
    },
    {
      commandId: EDITOR_MENU_COMMANDS.VIEW_RESET_LAYOUT,
      expected: "enabled",
      execute: true,
    },
    {
      commandId: EDITOR_MENU_COMMANDS.VIEW_RESTORE_DEFAULT_LAYOUT,
      expected: "enabled",
      execute: true,
    },
    {
      commandId: EDITOR_MENU_COMMANDS.VIEW_COLLAPSE_ADVANCED_PANELS,
      expected: "enabled",
      execute: true,
    },
    {
      commandId: EDITOR_MENU_COMMANDS.VIEW_EXPAND_ALL_PANELS,
      expected: "enabled",
      execute: true,
    },
    {
      commandId: EDITOR_MENU_COMMANDS.AI_OPEN_PROVIDER_SETTINGS,
      expected: "enabled",
      execute: true,
    },
  ];
}

export async function runNarrativeMenuSelfTest({
  hasActiveWorkspace,
  onStatusChange,
  windowLabel,
}: RunNarrativeMenuSelfTestOptions): Promise<NarrativeMenuSelfTestResult> {
  const checks = buildNarrativeMenuSelfTestChecks();
  const results: SelfTestCheckResult[] = [];

  logEditorMenuDebug("info", "[editor-self-test] starting narrative menu self-test", {
    windowLabel,
    hasActiveWorkspace,
    checkCount: checks.length,
  });

  for (const check of checks) {
    const inspection = inspectEditorMenuCommand(check.commandId);
    const actual = inspection.reason;
    let passed = actual === check.expected;
    let executed = false;
    let error: string | undefined;

    if (passed && check.execute && actual === "enabled") {
      const executionResult = await handleEditorMenuCommand(
        check.commandId,
        onStatusChange,
        windowLabel,
      );

      executed = executionResult.ok;
      if (!executionResult.ok) {
        passed = false;
        error =
          executionResult.reason === "error"
            ? executionResult.error
            : executionResult.reason;
      }
    }

    const result: SelfTestCheckResult = {
      commandId: check.commandId,
      expected: check.expected,
      actual,
      passed,
      executed,
      sourceId: "sourceId" in inspection ? inspection.sourceId : undefined,
      error,
    };

    results.push(result);
    logEditorMenuDebug(
      passed ? "info" : "warn",
      "[editor-self-test] narrative menu check completed",
      result,
    );
  }

  const passedCount = results.filter((result) => result.passed).length;
  const failedChecks = results.filter((result) => !result.passed).map((result) => result.commandId);
  const passed = passedCount === results.length;
  const summary = passed
    ? `Narrative menu self-test passed (${passedCount}/${results.length}).`
    : `Narrative menu self-test failed (${passedCount}/${results.length}). Failed: ${failedChecks.join(", ")}.`;

  logEditorMenuDebug(
    passed ? "info" : "warn",
    "[editor-self-test] narrative menu self-test finished",
    {
      windowLabel,
      passed,
      passedCount,
      totalCount: results.length,
      failedChecks,
    },
  );

  return {
    passed,
    summary,
    checks: results,
  };
}
