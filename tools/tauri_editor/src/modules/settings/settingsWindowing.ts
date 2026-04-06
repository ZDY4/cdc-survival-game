import type { EditorSettingsSection } from "../../types";
import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { ALL_EDITOR_WINDOW_LABELS } from "../../lib/editorSurfaces";
import { isTauriRuntime } from "../../lib/tauri";

export const SETTINGS_WINDOW_LABEL = "settings";
export const SETTINGS_OPEN_SECTION_EVENT = "settings:open-section";
export const SETTINGS_CHANGED_EVENT = "settings:changed";

export function isEditorSettingsSection(value: string | null | undefined): value is EditorSettingsSection {
  return value === "ai";
}

export function buildSettingsWindowUrl(section: EditorSettingsSection = "ai"): string {
  const params = new URLSearchParams({
    surface: "settings",
    section,
  });
  return `/?${params.toString()}`;
}

export async function emitSettingsChanged(section: EditorSettingsSection) {
  if (!isTauriRuntime()) {
    return;
  }

  const current = WebviewWindow.getCurrent();
  await Promise.allSettled(
    ALL_EDITOR_WINDOW_LABELS.map((label) =>
      current.emitTo(label, SETTINGS_CHANGED_EVENT, {
        section,
      }),
    ),
  );
}
