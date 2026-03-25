import { getCurrentWindow } from "@tauri-apps/api/window";
import { useEffect } from "react";
import { formatError, isTauriRuntime } from "../lib/tauri";
import {
  dispatchEditorMenuCommand,
  type DispatchResult,
} from "./editorCommandRegistry";
import { logEditorMenuDebug } from "./menuDebug";
import {
  formatEditorMenuCommandLabel,
  type EditorMenuCommandId,
} from "./menuCommands";

export const EDITOR_MENU_COMMAND_EVENT = "editor-menu:command";

export type EditorMenuCommandPayload = {
  commandId: EditorMenuCommandId;
};

export type HandleEditorMenuCommandResult =
  | DispatchResult
  | {
      ok: false;
      reason: "error";
      error: string;
    };

export async function handleEditorMenuCommand(
  commandId: EditorMenuCommandId,
  onStatusChange: (status: string) => void,
  windowLabel: string,
): Promise<HandleEditorMenuCommandResult> {
  logEditorMenuDebug("info", "[editor-menu] received menu event", {
    windowLabel,
    commandId,
  });

  try {
    const result = await dispatchEditorMenuCommand(commandId);
    logEditorMenuDebug("info", "[editor-menu] dispatch result", {
      windowLabel,
      commandId,
      result,
    });
    if (!result.ok) {
      const label = formatEditorMenuCommandLabel(commandId);
      onStatusChange(
        result.reason === "disabled"
          ? `${label} is unavailable in the current context.`
          : `${label} is not supported in this window.`,
      );
    }

    return result;
  } catch (error) {
    const formattedError = formatError(error);
    onStatusChange(`${formatEditorMenuCommandLabel(commandId)} failed: ${formattedError}`);
    logEditorMenuDebug("error", "[editor-menu] command execution failed", {
      windowLabel,
      commandId,
      error: formattedError,
    });

    return {
      ok: false,
      reason: "error",
      error: formattedError,
    };
  }
}

export function useEditorMenuBridge(
  onStatusChange: (status: string) => void,
  enabled = true,
) {
  useEffect(() => {
    if (!enabled || !isTauriRuntime()) {
      logEditorMenuDebug("info", "[editor-menu] bridge skipped", {
        enabled,
        isTauriRuntime: isTauriRuntime(),
      });
      return;
    }

    let mounted = true;
    let unlisten: (() => void) | undefined;
    const currentWindow = getCurrentWindow();

    logEditorMenuDebug("info", "[editor-menu] bridge enabling", {
      windowLabel: currentWindow.label,
    });

    void currentWindow
      .listen<EditorMenuCommandPayload>(EDITOR_MENU_COMMAND_EVENT, async (event) => {
        if (!mounted) {
          logEditorMenuDebug("info", "[editor-menu] ignored menu event after unmount", {
            windowLabel: currentWindow.label,
            commandId: event.payload.commandId,
          });
          return;
        }

        const commandId = event.payload.commandId;
        await handleEditorMenuCommand(commandId, onStatusChange, currentWindow.label);
      })
      .then((dispose) => {
        unlisten = dispose;
        logEditorMenuDebug("info", "[editor-menu] bridge listener attached", {
          windowLabel: currentWindow.label,
        });
      })
      .catch((error) => {
        logEditorMenuDebug("error", "[editor-menu] failed to attach bridge listener", {
          windowLabel: currentWindow.label,
          error: formatError(error),
        });
      });

    return () => {
      mounted = false;
      logEditorMenuDebug("info", "[editor-menu] bridge cleanup", {
        windowLabel: currentWindow.label,
      });
      unlisten?.();
    };
  }, [enabled, onStatusChange]);
}
