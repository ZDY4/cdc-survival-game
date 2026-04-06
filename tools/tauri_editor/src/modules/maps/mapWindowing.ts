import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import type {
  MapEditorOpenDocumentPayload,
  MapEditorSaveCompletePayload,
  MapEditorSessionEndedPayload,
  MapEditorStateChangedPayload,
  SpatialDocumentType,
} from "../../types";
import { formatError, isTauriRuntime } from "../../lib/tauri";

export const MAP_EDITOR_WINDOW_LABEL = "map-editor";
export const MAP_LIBRARY_WINDOW_LABEL = "maps";
export const NEW_MAP_DOCUMENT_KEY = "__new_map__";

export const MAP_EDITOR_OPEN_DOCUMENT_EVENT = "map-editor:open-document";
export const MAP_EDITOR_STATE_CHANGED_EVENT = "map-editor:state-changed";
export const MAP_EDITOR_SAVE_COMPLETE_EVENT = "map-editor:save-complete";
export const MAP_EDITOR_SESSION_ENDED_EVENT = "map-editor:session-ended";

export function buildMapEditorWindowUrl(
  documentType: SpatialDocumentType,
  documentKey?: string | null,
): string {
  const params = new URLSearchParams({
    surface: "map-editor",
    documentType,
  });
  if (documentKey?.trim()) {
    params.set("documentKey", documentKey.trim());
  }
  return `/?${params.toString()}`;
}

export function buildMapLibraryWindowUrl(): string {
  return "/?surface=maps";
}

async function emitToWindow<T>(label: string, event: string, payload: T) {
  const current = WebviewWindow.getCurrent();
  await current.emitTo(label, event, payload);
}

export async function openOrFocusMapEditor(
  documentType: SpatialDocumentType,
  documentKey: string,
) {
  if (!isTauriRuntime()) {
    return;
  }

  const existing = await WebviewWindow.getByLabel(MAP_EDITOR_WINDOW_LABEL);
  if (existing) {
    await existing.setFocus();
    await emitToWindow<MapEditorOpenDocumentPayload>(MAP_EDITOR_WINDOW_LABEL, MAP_EDITOR_OPEN_DOCUMENT_EVENT, {
      documentType,
      documentKey,
    });
    return;
  }

  await new Promise<void>((resolve, reject) => {
    const next = new WebviewWindow(MAP_EDITOR_WINDOW_LABEL, {
      title: "CDC Map Editor",
      width: 1680,
      height: 980,
      minWidth: 1320,
      minHeight: 760,
      resizable: true,
      url: buildMapEditorWindowUrl(documentType, documentKey),
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

export async function emitMapEditorStateChanged(payload: MapEditorStateChangedPayload) {
  if (!isTauriRuntime()) {
    return;
  }
  await emitToWindow(MAP_LIBRARY_WINDOW_LABEL, MAP_EDITOR_STATE_CHANGED_EVENT, payload);
}

export async function emitMapEditorSaveComplete(payload: MapEditorSaveCompletePayload) {
  if (!isTauriRuntime()) {
    return;
  }
  await emitToWindow(MAP_LIBRARY_WINDOW_LABEL, MAP_EDITOR_SAVE_COMPLETE_EVENT, payload);
}

export async function emitMapEditorSessionEnded(payload: MapEditorSessionEndedPayload) {
  if (!isTauriRuntime()) {
    return;
  }
  await emitToWindow(MAP_LIBRARY_WINDOW_LABEL, MAP_EDITOR_SESSION_ENDED_EVENT, payload);
}
