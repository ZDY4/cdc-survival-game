import { beforeEach, describe, expect, it, vi } from "vitest";

const { dispatchEditorMenuCommandMock } = vi.hoisted(() => ({
  dispatchEditorMenuCommandMock: vi.fn(),
}));

vi.mock("@tauri-apps/api/window", () => ({
  getCurrentWindow: () => ({
    label: "main",
    listen: vi.fn(),
  }),
}));

vi.mock("@cdc/editor-shared/menu/menuDebug", () => ({
  logEditorMenuDebug: vi.fn(),
}));

import { handleEditorMenuCommand } from "./menuBridge";
import { EDITOR_MENU_COMMANDS } from "./menuCommands";

vi.mock("@cdc/editor-shared/menu/editorCommandRegistry", async () => {
  const actual = await vi.importActual<
    typeof import("@cdc/editor-shared/menu/editorCommandRegistry")
  >(
    "@cdc/editor-shared/menu/editorCommandRegistry",
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
      "main",
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
      EDITOR_MENU_COMMANDS.NARRATIVE_NEW_TASK_SETUP,
      onStatusChange,
      "main",
    );

    expect(onStatusChange).toHaveBeenCalledWith(
      "新建任务设定 在当前上下文中不可用。",
    );
  });

  it("reports missing commands with a not supported status message", async () => {
    const onStatusChange = vi.fn();
    dispatchEditorMenuCommandMock.mockResolvedValue({ ok: false, reason: "missing" });

    await handleEditorMenuCommand(
      EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT,
      onStatusChange,
      "main",
    );

    expect(onStatusChange).toHaveBeenCalledWith("新建草稿 在此窗口中不受支持。");
  });

  it("reports execution errors to the status bar", async () => {
    const onStatusChange = vi.fn();
    dispatchEditorMenuCommandMock.mockRejectedValue(new Error("boom"));

    await handleEditorMenuCommand(
      EDITOR_MENU_COMMANDS.AI_GENERATE,
      onStatusChange,
      "main",
    );

    expect(onStatusChange).toHaveBeenCalledWith("AI 生成 执行失败：boom");
  });
});
