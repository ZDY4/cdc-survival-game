import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { MAP_EDITOR_WINDOW_LABEL } from "../modules/maps/mapWindowing";
import { SETTINGS_WINDOW_LABEL, isEditorSettingsSection } from "../modules/settings/settingsWindowing";
import type { EditorSettingsSection, SpatialDocumentType } from "../types";
import { isTauriRuntime } from "./tauri";

export type EditorSurface = "main" | "map-editor" | "settings";

type ResolveEditorSurfaceOptions = {
  search?: string;
  label?: string | null;
};

export function resolveEditorSurface({
  search = "",
  label = null,
}: ResolveEditorSurfaceOptions): EditorSurface {
  const params = new URLSearchParams(search);
  const surface = params.get("surface");
  if (surface === "map-editor" || label === MAP_EDITOR_WINDOW_LABEL) {
    return "map-editor";
  }
  if (surface === "settings" || label === SETTINGS_WINDOW_LABEL) {
    return "settings";
  }
  return "main";
}

export function getRequestedDocumentKey(search = ""): string | null {
  const params = new URLSearchParams(search);
  const documentKey = params.get("documentKey")?.trim();
  return documentKey ? documentKey : null;
}

export function getRequestedDocumentType(search = ""): SpatialDocumentType {
  const params = new URLSearchParams(search);
  return params.get("documentType") === "overworld" ? "overworld" : "map";
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
