import { useEffect, useRef } from "react";
import type { EditorMenuCommandId, EditorMenuCommandMap } from "./menuCommands";
import { logEditorMenuDebug } from "./menuDebug";

export type DispatchResult =
  | { ok: true }
  | { ok: false; reason: "missing" | "disabled" };

export type EditorMenuCommandInspection =
  | { reason: "enabled"; sourceId: string }
  | { reason: "disabled"; sourceId: string }
  | { reason: "missing" };

const commandRegistry = new Map<string, EditorMenuCommandMap>();
let nextSourceId = 0;

function getRegisteredCommandIds(commands: EditorMenuCommandMap): EditorMenuCommandId[] {
  return Object.keys(commands) as EditorMenuCommandId[];
}

export function inspectEditorMenuCommand(
  commandId: EditorMenuCommandId,
): EditorMenuCommandInspection {
  const registrations = Array.from(commandRegistry.entries()).reverse();

  for (const [sourceId, commands] of registrations) {
    const handler = commands[commandId];
    if (!handler) {
      continue;
    }

    if (handler.isEnabled && !handler.isEnabled()) {
      return { reason: "disabled", sourceId };
    }

    return { reason: "enabled", sourceId };
  }

  return { reason: "missing" };
}

export async function dispatchEditorMenuCommand(
  commandId: EditorMenuCommandId,
): Promise<DispatchResult> {
  const registrations = Array.from(commandRegistry.entries()).reverse();
  logEditorMenuDebug("info", "[editor-menu] dispatch requested", {
    commandId,
    registrationCount: registrations.length,
    sources: registrations.map(([sourceId, commands]) => ({
      sourceId,
      commandIds: getRegisteredCommandIds(commands),
    })),
  });

  for (const [sourceId, commands] of registrations) {
    const handler = commands[commandId];
    if (!handler) {
      logEditorMenuDebug("info", "[editor-menu] command not handled by source", {
        sourceId,
        commandId,
      });
      continue;
    }
    if (handler.isEnabled && !handler.isEnabled()) {
      logEditorMenuDebug("warn", "[editor-menu] command disabled in source", {
        sourceId,
        commandId,
      });
      return { ok: false, reason: "disabled" };
    }
    logEditorMenuDebug("info", "[editor-menu] executing command", {
      sourceId,
      commandId,
    });
    await handler.execute();
    logEditorMenuDebug("info", "[editor-menu] command executed", {
      sourceId,
      commandId,
    });
    return { ok: true };
  }
  logEditorMenuDebug("warn", "[editor-menu] missing command handler", {
    commandId,
  });
  return { ok: false, reason: "missing" };
}

export function registerEditorMenuCommands(
  sourceId: string,
  commands: EditorMenuCommandMap,
) {
  logEditorMenuDebug("info", "[editor-menu] register command source", {
    sourceId,
    commandIds: getRegisteredCommandIds(commands),
    totalBefore: commandRegistry.size,
  });
  commandRegistry.set(sourceId, commands);
  return () => {
    logEditorMenuDebug("info", "[editor-menu] unregister command source", {
      sourceId,
      totalBefore: commandRegistry.size,
    });
    commandRegistry.delete(sourceId);
  };
}

export function useRegisterEditorMenuCommands(commands: EditorMenuCommandMap) {
  const sourceIdRef = useRef(`editor-menu-source-${nextSourceId++}`);
  const registeredRef = useRef(false);

  useEffect(() => {
    const sourceId = sourceIdRef.current;
    if (!registeredRef.current) {
      logEditorMenuDebug("info", "[editor-menu] register command source", {
        sourceId,
        commandIds: getRegisteredCommandIds(commands),
        totalBefore: commandRegistry.size,
      });
      registeredRef.current = true;
    }
    commandRegistry.set(sourceId, commands);
  }, [commands]);

  useEffect(
    () => () => {
      const sourceId = sourceIdRef.current;
      if (registeredRef.current) {
        logEditorMenuDebug("info", "[editor-menu] unregister command source", {
          sourceId,
          totalBefore: commandRegistry.size,
        });
      }
      commandRegistry.delete(sourceId);
    },
    [],
  );
}

export function clearEditorMenuCommandRegistryForTests() {
  commandRegistry.clear();
}
