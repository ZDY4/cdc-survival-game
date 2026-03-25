import { beforeEach, describe, expect, it, vi } from "vitest";
import { runNarrativeMenuSelfTest } from "./narrativeMenuSelfTest";
import { EDITOR_MENU_COMMANDS } from "../../menu/menuCommands";

const { inspectEditorMenuCommandMock, handleEditorMenuCommandMock } = vi.hoisted(() => ({
  inspectEditorMenuCommandMock: vi.fn(),
  handleEditorMenuCommandMock: vi.fn(),
}));

vi.mock("../../menu/editorCommandRegistry", async () => {
  const actual = await vi.importActual<typeof import("../../menu/editorCommandRegistry")>(
    "../../menu/editorCommandRegistry",
  );

  return {
    ...actual,
    inspectEditorMenuCommand: inspectEditorMenuCommandMock,
  };
});

vi.mock("../../menu/menuBridge", async () => {
  const actual = await vi.importActual<typeof import("../../menu/menuBridge")>(
    "../../menu/menuBridge",
  );

  return {
    ...actual,
    handleEditorMenuCommand: handleEditorMenuCommandMock,
  };
});

vi.mock("../../menu/menuDebug", () => ({
  logEditorMenuDebug: vi.fn(),
}));

describe("narrativeMenuSelfTest", () => {
  beforeEach(() => {
    inspectEditorMenuCommandMock.mockReset();
    handleEditorMenuCommandMock.mockReset();
  });

  it("passes when commands match expectations and executable checks succeed", async () => {
    const executableCommands = new Set([
      EDITOR_MENU_COMMANDS.VIEW_RESET_LAYOUT,
      EDITOR_MENU_COMMANDS.VIEW_RESTORE_DEFAULT_LAYOUT,
      EDITOR_MENU_COMMANDS.VIEW_COLLAPSE_ADVANCED_PANELS,
      EDITOR_MENU_COMMANDS.VIEW_EXPAND_ALL_PANELS,
      EDITOR_MENU_COMMANDS.AI_OPEN_PROVIDER_SETTINGS,
    ]);

    inspectEditorMenuCommandMock.mockImplementation((commandId: string) => ({
      reason: "enabled",
      sourceId: `source-${commandId}`,
    }));
    handleEditorMenuCommandMock.mockResolvedValue({ ok: true });

    const result = await runNarrativeMenuSelfTest({
      hasActiveWorkspace: true,
      onStatusChange: vi.fn(),
      windowLabel: "narrative-lab",
    });

    expect(result.passed).toBe(true);
    expect(result.summary).toContain("passed");
    expect(handleEditorMenuCommandMock).toHaveBeenCalledTimes(executableCommands.size);
    expect(result.checks.every((check) => check.passed)).toBe(true);
  });

  it("fails when a workspace-dependent command is unexpectedly disabled", async () => {
    inspectEditorMenuCommandMock.mockImplementation((commandId: string) => {
      if (commandId === EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT) {
        return { reason: "disabled", sourceId: "narrative-source" };
      }

      return { reason: "enabled", sourceId: `source-${commandId}` };
    });
    handleEditorMenuCommandMock.mockResolvedValue({ ok: true });

    const result = await runNarrativeMenuSelfTest({
      hasActiveWorkspace: true,
      onStatusChange: vi.fn(),
      windowLabel: "narrative-lab",
    });

    expect(result.passed).toBe(false);
    expect(result.summary).toContain(EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT);
  });

  it("accepts disabled draft creation when no workspace is active", async () => {
    inspectEditorMenuCommandMock.mockImplementation((commandId: string) => {
      if (
        commandId === EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT ||
        commandId === EDITOR_MENU_COMMANDS.NARRATIVE_NEW_PROJECT_BRIEF
      ) {
        return { reason: "disabled", sourceId: "narrative-source" };
      }

      return { reason: "enabled", sourceId: `source-${commandId}` };
    });
    handleEditorMenuCommandMock.mockResolvedValue({ ok: true });

    const result = await runNarrativeMenuSelfTest({
      hasActiveWorkspace: false,
      onStatusChange: vi.fn(),
      windowLabel: "narrative-lab",
    });

    expect(result.passed).toBe(true);
  });
});
