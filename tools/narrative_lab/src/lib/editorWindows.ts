import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { formatError, isTauriRuntime } from "./tauri";
import {
  buildSettingsWindowUrl,
  SETTINGS_OPEN_SECTION_EVENT,
  SETTINGS_WINDOW_LABEL,
} from "../modules/settings/settingsWindowing";
import type { EditorSettingsSection } from "../types";

export const MAIN_EDITOR_WINDOW_LABEL = "main";

export async function openOrFocusSettingsWindow(section: EditorSettingsSection = "ai") {
  if (!isTauriRuntime()) {
    return;
  }

  const existing = await WebviewWindow.getByLabel(SETTINGS_WINDOW_LABEL);
  if (existing) {
    await existing.setFocus();
    await WebviewWindow.getCurrent().emitTo(SETTINGS_WINDOW_LABEL, SETTINGS_OPEN_SECTION_EVENT, { section });
    return;
  }

  await new Promise<void>((resolve, reject) => {
    const next = new WebviewWindow(SETTINGS_WINDOW_LABEL, {
      title: "设置",
      width: 1240,
      height: 860,
      minWidth: 980,
      minHeight: 680,
      resizable: true,
      decorations: false,
      shadow: true,
      url: buildSettingsWindowUrl(section),
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
