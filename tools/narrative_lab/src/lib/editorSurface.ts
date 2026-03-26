import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { SETTINGS_WINDOW_LABEL, isEditorSettingsSection } from "../modules/settings/settingsWindowing";
import type { EditorSettingsSection } from "../types";
import { isTauriRuntime } from "./tauri";

export type EditorSurface = "main" | "settings";

type ResolveEditorSurfaceOptions = {
  search?: string;
  label?: string | null;
};

export function resolveEditorSurface({
  search = "",
  label = null,
}: ResolveEditorSurfaceOptions): EditorSurface {
  const params = new URLSearchParams(search);
  if (params.get("surface") === "settings" || label === SETTINGS_WINDOW_LABEL) {
    return "settings";
  }
  return "main";
}

export function getRequestedDocumentKey(search = ""): string | null {
  const params = new URLSearchParams(search);
  const documentKey = params.get("documentKey")?.trim();
  return documentKey ? documentKey : null;
}

export function getRequestedSettingsSection(search = ""): EditorSettingsSection {
  const params = new URLSearchParams(search);
  const section = params.get("section")?.trim();
  return isEditorSettingsSection(section) ? section : "ai";
}

export function detectCurrentSurface(): EditorSurface {
  const search = typeof window === "undefined" ? "" : window.location.search;
  const label = isTauriRuntime() ? WebviewWindow.getCurrent().label : null;
  return resolveEditorSurface({ search, label });
}
