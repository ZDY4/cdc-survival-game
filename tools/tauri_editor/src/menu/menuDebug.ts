import { invoke } from "@tauri-apps/api/core";
import { isTauriRuntime } from "../lib/tauri";

function safeSerialize(data: unknown): string | null {
  if (typeof data === "undefined") {
    return null;
  }

  try {
    return JSON.stringify(data);
  } catch (error) {
    return JSON.stringify({
      serializationError: error instanceof Error ? error.message : String(error),
    });
  }
}

export function logEditorMenuDebug(
  level: "info" | "warn" | "error",
  message: string,
  data?: unknown,
) {
  const payload = safeSerialize(data);
  const logger = level === "error" ? console.error : level === "warn" ? console.warn : console.info;

  if (typeof data === "undefined") {
    logger(message);
  } else {
    logger(message, data);
  }

  if (!isTauriRuntime()) {
    return;
  }

  void invoke("log_editor_frontend_debug", {
    level,
    message,
    payload,
  }).catch(() => {
    // Avoid recursive logging if the debug bridge itself fails.
  });
}
