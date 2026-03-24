import { useEffect, useRef } from "react";
import type { EditorMenuCommandId, EditorMenuCommandMap } from "./menuCommands";

type DispatchResult =
  | { ok: true }
  | { ok: false; reason: "missing" | "disabled" };

const commandRegistry = new Map<string, EditorMenuCommandMap>();
let nextSourceId = 0;

export async function dispatchEditorMenuCommand(
  commandId: EditorMenuCommandId,
): Promise<DispatchResult> {
  const registrations = Array.from(commandRegistry.values()).reverse();
  for (const commands of registrations) {
    const handler = commands[commandId];
    if (!handler) {
      continue;
    }
    if (handler.isEnabled && !handler.isEnabled()) {
      return { ok: false, reason: "disabled" };
    }
    await handler.execute();
    return { ok: true };
  }
  return { ok: false, reason: "missing" };
}

export function registerEditorMenuCommands(
  sourceId: string,
  commands: EditorMenuCommandMap,
) {
  commandRegistry.set(sourceId, commands);
  return () => {
    commandRegistry.delete(sourceId);
  };
}

export function useRegisterEditorMenuCommands(commands: EditorMenuCommandMap) {
  const sourceIdRef = useRef(`editor-menu-source-${nextSourceId++}`);

  useEffect(() => registerEditorMenuCommands(sourceIdRef.current, commands), [commands]);
}
