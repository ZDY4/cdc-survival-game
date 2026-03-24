export type MapEditorPendingIntent =
  | { type: "switch-document"; documentKey: string }
  | { type: "close-window" };

export function shouldDeferPendingIntent(
  hasDirtySelection: boolean,
  currentDocumentKey: string | null,
  intent: MapEditorPendingIntent,
): boolean {
  if (!hasDirtySelection) {
    return false;
  }
  if (intent.type === "switch-document" && intent.documentKey === currentDocumentKey) {
    return false;
  }
  return true;
}
