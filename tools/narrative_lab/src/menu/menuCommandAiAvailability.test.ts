import { afterEach, describe, expect, it } from "vitest";

import {
  clearEditorMenuCommandRegistryForTests,
  inspectEditorMenuCommand,
  registerEditorMenuCommands,
} from "./editorCommandRegistry";
import { EDITOR_MENU_COMMANDS } from "./menuCommands";

type AiAvailabilityState = {
  hasActiveDocument: boolean;
  hasPendingActions: boolean;
};

function registerAiGenerateWithState(state: AiAvailabilityState, sourceId: string) {
  registerEditorMenuCommands(sourceId, {
    [EDITOR_MENU_COMMANDS.AI_GENERATE]: {
      execute: () => undefined,
      isEnabled: () => state.hasActiveDocument && !state.hasPendingActions,
    },
  });
}

describe("AI generate command availability smoke tests", () => {
  afterEach(() => {
    clearEditorMenuCommandRegistryForTests();
  });

  it("is disabled when there is no active document", () => {
    const sourceId = "narrative-ai-no-document";
    registerAiGenerateWithState({ hasActiveDocument: false, hasPendingActions: false }, sourceId);

    expect(inspectEditorMenuCommand(EDITOR_MENU_COMMANDS.AI_GENERATE)).toEqual({
      reason: "disabled",
      sourceId,
    });
  });

  it("is disabled when pending actions are awaiting approval", () => {
    const sourceId = "narrative-ai-pending-actions";
    registerAiGenerateWithState({ hasActiveDocument: true, hasPendingActions: true }, sourceId);

    expect(inspectEditorMenuCommand(EDITOR_MENU_COMMANDS.AI_GENERATE)).toEqual({
      reason: "disabled",
      sourceId,
    });
  });

  it("is enabled when a document is active and no actions are pending", () => {
    const sourceId = "narrative-ai-ready";
    registerAiGenerateWithState({ hasActiveDocument: true, hasPendingActions: false }, sourceId);

    expect(inspectEditorMenuCommand(EDITOR_MENU_COMMANDS.AI_GENERATE)).toEqual({
      reason: "enabled",
      sourceId,
    });
  });
});
