import { beforeEach, describe, expect, it, vi } from "vitest";

const { dispatchEditorMenuCommandMock } = vi.hoisted(() => ({
  dispatchEditorMenuCommandMock: vi.fn(),
}));

vi.mock("@tauri-apps/api/window", () => ({
  getCurrentWindow: () => ({
    label: "narrative-lab",
    listen: vi.fn(),
  }),
}));

vi.mock("./menuDebug", () => ({
  logEditorMenuDebug: vi.fn(),
}));

import { handleEditorMenuCommand } from "./menuBridge";
import { EDITOR_MENU_COMMANDS } from "./menuCommands";

vi.mock("./editorCommandRegistry", async () => {
  const actual = await vi.importActual<typeof import("./editorCommandRegistry")>(
    "./editorCommandRegistry",
  );

  return {
    ...actual,
    dispatchEditorMenuCommand: dispatchEditorMenuCommandMock,
  };
});

describe("menuBridge", () => {
  beforeEach(() => {
    dispatchEditorMenuCommandMock.mockReset();
  });

  it("does not report status when the command executes successfully", async () => {
    const onStatusChange = vi.fn();
    dispatchEditorMenuCommandMock.mockResolvedValue({ ok: true });

    await handleEditorMenuCommand(
      EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT,
      onStatusChange,
      "narrative-lab",
    );

    expect(dispatchEditorMenuCommandMock).toHaveBeenCalledWith(
      EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT,
    );
    expect(onStatusChange).not.toHaveBeenCalled();
  });

  it("reports disabled commands with a contextual status message", async () => {
    const onStatusChange = vi.fn();
    dispatchEditorMenuCommandMock.mockResolvedValue({ ok: false, reason: "disabled" });

    await handleEditorMenuCommand(
      EDITOR_MENU_COMMANDS.NARRATIVE_NEW_PROJECT_BRIEF,
      onStatusChange,
      "narrative-lab",
    );

    expect(onStatusChange).toHaveBeenCalledWith(
      "New Project Brief is unavailable in the current context.",
    );
  });

  it("reports missing commands with a not supported status message", async () => {
    const onStatusChange = vi.fn();
    dispatchEditorMenuCommandMock.mockResolvedValue({ ok: false, reason: "missing" });

    await handleEditorMenuCommand(
      EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT,
      onStatusChange,
      "narrative-lab",
    );

    expect(onStatusChange).toHaveBeenCalledWith("New is not supported in this window.");
  });

  it("reports execution errors to the status bar", async () => {
    const onStatusChange = vi.fn();
    dispatchEditorMenuCommandMock.mockRejectedValue(new Error("boom"));

    await handleEditorMenuCommand(
      EDITOR_MENU_COMMANDS.AI_GENERATE,
      onStatusChange,
      "narrative-lab",
    );

    expect(onStatusChange).toHaveBeenCalledWith("AI Generate failed: boom");
  });
});
