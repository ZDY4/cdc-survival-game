import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { MAP_EDITOR_WINDOW_LABEL } from "../modules/maps/mapWindowing";
import { isTauriRuntime } from "./tauri";

export type EditorSurface = "main" | "map-editor";

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
  return "main";
}

export function getRequestedDocumentKey(search = ""): string | null {
  const params = new URLSearchParams(search);
  const documentKey = params.get("documentKey")?.trim();
  return documentKey ? documentKey : null;
}

export function detectCurrentSurface(): EditorSurface {
  const search = typeof window === "undefined" ? "" : window.location.search;
  const label = isTauriRuntime() ? WebviewWindow.getCurrent().label : null;
  return resolveEditorSurface({ search, label });
}
