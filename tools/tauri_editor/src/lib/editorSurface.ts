import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import {
  EDITOR_BOOTSTRAP_WINDOW_LABEL,
  type EditorSurface,
  isOpenableEditorSurface,
} from "./editorSurfaces";
import { isEditorSettingsSection } from "../modules/settings/settingsWindowing";
import type { EditorSettingsSection, SpatialDocumentType } from "../types";
import { isTauriRuntime } from "./tauri";

type ResolveEditorSurfaceOptions = {
  search?: string;
  label?: string | null;
};

export function resolveEditorSurface({
  search = "",
  label = null,
}: ResolveEditorSurfaceOptions): EditorSurface {
  const params = new URLSearchParams(search);
  const surface = params.get("surface")?.trim();
  if (isOpenableEditorSurface(surface)) {
    return surface;
  }
  if (isOpenableEditorSurface(label)) {
    return label;
  }
  if (label === EDITOR_BOOTSTRAP_WINDOW_LABEL || surface === "main") {
    return "main";
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
