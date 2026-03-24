import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { formatError, isTauriRuntime } from "./tauri";
import { buildNarrativeLabWindowUrl, NARRATIVE_LAB_WINDOW_LABEL } from "../modules/narrative/narrativeWindowing";
import { EDITOR_MENU_COMMAND_EVENT, type EditorMenuCommandPayload } from "../menu/menuBridge";
import { EDITOR_MENU_COMMANDS } from "../menu/menuCommands";

export const MAIN_EDITOR_WINDOW_LABEL = "main";

async function emitMenuCommandToWindow(label: string, payload: EditorMenuCommandPayload) {
  const current = WebviewWindow.getCurrent();
  await current.emitTo(label, EDITOR_MENU_COMMAND_EVENT, payload);
}

export async function openOrFocusNarrativeLab() {
  if (!isTauriRuntime()) {
    return;
  }

  const existing = await WebviewWindow.getByLabel(NARRATIVE_LAB_WINDOW_LABEL);
  if (existing) {
    await existing.setFocus();
    return;
  }

  await new Promise<void>((resolve, reject) => {
    const next = new WebviewWindow(NARRATIVE_LAB_WINDOW_LABEL, {
      title: "Narrative Lab",
      width: 1480,
      height: 960,
      minWidth: 1180,
      minHeight: 760,
      resizable: true,
      url: buildNarrativeLabWindowUrl(),
    });

    void next.once("tauri://created", async () => {
      try {
        await next.setFocus();
        resolve();
      } catch (error) {
        reject(new Error(formatError(error)));
      }
    });

    void next.once("tauri://error", (event) => {
      reject(new Error(formatError(event.payload)));
    });
  });
}

export async function openOrFocusMainEditor(moduleCommandId?: EditorMenuCommandPayload["commandId"]) {
  if (!isTauriRuntime()) {
    return;
  }

  const existing = await WebviewWindow.getByLabel(MAIN_EDITOR_WINDOW_LABEL);
  if (existing) {
    await existing.setFocus();
    if (moduleCommandId) {
      await emitMenuCommandToWindow(MAIN_EDITOR_WINDOW_LABEL, { commandId: moduleCommandId });
    }
    return;
  }

  await new Promise<void>((resolve, reject) => {
    const next = new WebviewWindow(MAIN_EDITOR_WINDOW_LABEL, {
      title: "CDC Content Editor",
      width: 1440,
      height: 920,
      minWidth: 1100,
      minHeight: 700,
      resizable: true,
      url: "/",
    });

    void next.once("tauri://created", async () => {
      try {
        await next.setFocus();
        if (moduleCommandId && moduleCommandId !== EDITOR_MENU_COMMANDS.MODULE_ITEMS) {
          await emitMenuCommandToWindow(MAIN_EDITOR_WINDOW_LABEL, { commandId: moduleCommandId });
        }
        resolve();
      } catch (error) {
        reject(new Error(formatError(error)));
      }
    });

    void next.once("tauri://error", (event) => {
      reject(new Error(formatError(event.payload)));
    });
  });
}
