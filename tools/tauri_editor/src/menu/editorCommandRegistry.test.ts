import { afterEach, describe, expect, it, vi } from "vitest";

vi.mock("./menuDebug", () => ({
  logEditorMenuDebug: vi.fn(),
}));

import {
  clearEditorMenuCommandRegistryForTests,
  dispatchEditorMenuCommand,
  inspectEditorMenuCommand,
  registerEditorMenuCommands,
} from "./editorCommandRegistry";
import { EDITOR_MENU_COMMANDS } from "./menuCommands";

describe("editorCommandRegistry", () => {
  afterEach(() => {
    clearEditorMenuCommandRegistryForTests();
    vi.clearAllMocks();
  });

  it("executes the registered handler for a command", async () => {
    const execute = vi.fn();
    registerEditorMenuCommands("narrative", {
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: { execute },
    });

    const result = await dispatchEditorMenuCommand(EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT);

    expect(result).toEqual({ ok: true });
    expect(execute).toHaveBeenCalledTimes(1);
  });

  it("prefers the most recently registered source", async () => {
    const olderExecute = vi.fn();
    const newerExecute = vi.fn();

    registerEditorMenuCommands("older", {
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: { execute: olderExecute },
    });
    registerEditorMenuCommands("newer", {
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: { execute: newerExecute },
    });

    const result = await dispatchEditorMenuCommand(EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT);

    expect(result).toEqual({ ok: true });
    expect(newerExecute).toHaveBeenCalledTimes(1);
    expect(olderExecute).not.toHaveBeenCalled();
  });

  it("returns disabled when the matching handler is not currently enabled", async () => {
    const execute = vi.fn();

    registerEditorMenuCommands("narrative", {
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: {
        execute,
        isEnabled: () => false,
      },
    });

    const result = await dispatchEditorMenuCommand(EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT);

    expect(result).toEqual({ ok: false, reason: "disabled" });
    expect(execute).not.toHaveBeenCalled();
  });

  it("inspects enabled, disabled, and missing command states without executing", () => {
    registerEditorMenuCommands("enabled-source", {
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: { execute: vi.fn() },
      [EDITOR_MENU_COMMANDS.FILE_SAVE_ALL]: {
        execute: vi.fn(),
        isEnabled: () => false,
      },
    });

    expect(inspectEditorMenuCommand(EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT)).toEqual({
      reason: "enabled",
      sourceId: "enabled-source",
    });
    expect(inspectEditorMenuCommand(EDITOR_MENU_COMMANDS.FILE_SAVE_ALL)).toEqual({
      reason: "disabled",
      sourceId: "enabled-source",
    });
    expect(inspectEditorMenuCommand(EDITOR_MENU_COMMANDS.FILE_DELETE_CURRENT)).toEqual({
      reason: "missing",
    });
  });

  it("returns missing after the source is unregistered", async () => {
    const dispose = registerEditorMenuCommands("narrative", {
      [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: { execute: vi.fn() },
    });
    dispose();

    const result = await dispatchEditorMenuCommand(EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT);

    expect(result).toEqual({ ok: false, reason: "missing" });
  });
});
