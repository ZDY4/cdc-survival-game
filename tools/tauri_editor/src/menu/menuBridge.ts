import { getCurrentWindow } from "@tauri-apps/api/window";
import { useEffect } from "react";
import { formatError, isTauriRuntime } from "../lib/tauri";
import { dispatchEditorMenuCommand } from "./editorCommandRegistry";
import {
  formatEditorMenuCommandLabel,
  type EditorMenuCommandId,
} from "./menuCommands";

export const EDITOR_MENU_COMMAND_EVENT = "editor-menu:command";

export type EditorMenuCommandPayload = {
  commandId: EditorMenuCommandId;
};

export function useEditorMenuBridge(
  onStatusChange: (status: string) => void,
  enabled = true,
) {
  useEffect(() => {
    if (!enabled || !isTauriRuntime()) {
      return;
    }

    let mounted = true;
    let unlisten: (() => void) | undefined;

    void getCurrentWindow()
      .listen<EditorMenuCommandPayload>(EDITOR_MENU_COMMAND_EVENT, async (event) => {
        if (!mounted) {
          return;
        }

        const commandId = event.payload.commandId;
        try {
          const result = await dispatchEditorMenuCommand(commandId);
          if (!result.ok) {
            const label = formatEditorMenuCommandLabel(commandId);
            onStatusChange(
              result.reason === "disabled"
                ? `${label} is unavailable in the current context.`
                : `${label} is not supported in this window.`,
            );
          }
        } catch (error) {
          onStatusChange(
            `${formatEditorMenuCommandLabel(commandId)} failed: ${formatError(error)}`,
          );
        }
      })
      .then((dispose) => {
        unlisten = dispose;
      });

    return () => {
      mounted = false;
      unlisten?.();
    };
  }, [enabled, onStatusChange]);
}
