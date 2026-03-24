import type { MapObjectKind } from "../../types";

export type MapEditorShortcutAction =
  | { type: "save" }
  | { type: "set-tool"; tool: "select" | "erase" | MapObjectKind }
  | { type: "rotate" }
  | { type: "level-step"; delta: -1 | 1 }
  | { type: "delete-selection" }
  | { type: "clear-selection" };

type ShortcutEvent = {
  key: string;
  ctrlKey: boolean;
  metaKey: boolean;
  altKey: boolean;
  target: EventTarget | null;
};

function targetBlocksShortcuts(target: EventTarget | null): boolean {
  if (!target || typeof target !== "object") {
    return false;
  }
  const candidate = target as { isContentEditable?: boolean; tagName?: string };
  if (candidate.isContentEditable) {
    return true;
  }
  return ["INPUT", "TEXTAREA", "SELECT"].includes(candidate.tagName ?? "");
}

export function resolveMapEditorShortcut(event: ShortcutEvent): MapEditorShortcutAction | null {
  const key = event.key.toLowerCase();
  const isSave = (event.ctrlKey || event.metaKey) && !event.altKey && key === "s";
  if (isSave) {
    return { type: "save" };
  }

  if (targetBlocksShortcuts(event.target)) {
    return null;
  }

  if (event.altKey || event.ctrlKey || event.metaKey) {
    return null;
  }

  if (key === "v") {
    return { type: "set-tool", tool: "select" };
  }
  if (key === "e") {
    return { type: "set-tool", tool: "erase" };
  }
  if (key === "1") {
    return { type: "set-tool", tool: "building" };
  }
  if (key === "2") {
    return { type: "set-tool", tool: "pickup" };
  }
  if (key === "3") {
    return { type: "set-tool", tool: "interactive" };
  }
  if (key === "4") {
    return { type: "set-tool", tool: "ai_spawn" };
  }
  if (key === "r") {
    return { type: "rotate" };
  }
  if (key === "[") {
    return { type: "level-step", delta: -1 };
  }
  if (key === "]") {
    return { type: "level-step", delta: 1 };
  }
  if (key === "delete" || key === "backspace") {
    return { type: "delete-selection" };
  }
  if (key === "escape") {
    return { type: "clear-selection" };
  }
  return null;
}
