import { WebviewWindow } from "@tauri-apps/api/webviewWindow";
import { EDITOR_MENU_COMMANDS } from "../menu/menuCommands";
import type { EditorSettingsSection } from "../types";
import { formatError, isTauriRuntime } from "./tauri";
import {
  DEFAULT_EDITOR_START_SURFACE,
  EDITOR_BOOTSTRAP_WINDOW_LABEL,
  type ModuleEditorSurface,
  type OpenableEditorSurface,
  isModuleEditorSurface,
} from "./editorSurfaces";

type WindowDescriptor = {
  label: OpenableEditorSurface;
  title: string;
  width: number;
  height: number;
  minWidth: number;
  minHeight: number;
  resizable: boolean;
  decorations?: boolean;
  shadow?: boolean;
  buildUrl: () => string;
};

const WINDOW_DESCRIPTORS: Record<Exclude<OpenableEditorSurface, "settings">, WindowDescriptor> = {
  items: {
    label: "items",
    title: "CDC Item Editor",
    width: 1440,
    height: 920,
    minWidth: 1100,
    minHeight: 700,
    resizable: true,
    buildUrl: () => "/?surface=items",
  },
  dialogues: {
    label: "dialogues",
    title: "CDC Dialogue Editor",
    width: 1480,
    height: 940,
    minWidth: 1180,
    minHeight: 760,
    resizable: true,
    buildUrl: () => "/?surface=dialogues",
  },
  quests: {
    label: "quests",
    title: "CDC Quest Editor",
    width: 1480,
    height: 940,
    minWidth: 1180,
    minHeight: 760,
    resizable: true,
    buildUrl: () => "/?surface=quests",
  },
};

function getWindowDescriptor(surface: Exclude<OpenableEditorSurface, "settings">): WindowDescriptor {
  return WINDOW_DESCRIPTORS[surface];
}

async function createOrFocusWindow(
  descriptor: WindowDescriptor,
  afterFocus?: (label: string) => Promise<void>,
) {
  const existing = await WebviewWindow.getByLabel(descriptor.label);
  if (existing) {
    await existing.setFocus();
    if (afterFocus) {
      await afterFocus(descriptor.label);
    }
    return;
  }

  await new Promise<void>((resolve, reject) => {
    const next = new WebviewWindow(descriptor.label, {
      title: descriptor.title,
      width: descriptor.width,
      height: descriptor.height,
      minWidth: descriptor.minWidth,
      minHeight: descriptor.minHeight,
      resizable: descriptor.resizable,
      decorations: descriptor.decorations,
      shadow: descriptor.shadow,
      url: descriptor.buildUrl(),
    });

    void next.once("tauri://created", async () => {
      try {
        await next.setFocus();
        if (afterFocus) {
          await afterFocus(descriptor.label);
        }
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

export function buildEditorWindowUrl(surface: Exclude<OpenableEditorSurface, "settings">): string {
  return getWindowDescriptor(surface).buildUrl();
}

export function getSurfaceForModuleCommand(
  commandId: string,
): ModuleEditorSurface | null {
  switch (commandId) {
    case EDITOR_MENU_COMMANDS.MODULE_ITEMS:
      return "items";
    case EDITOR_MENU_COMMANDS.MODULE_DIALOGUES:
      return "dialogues";
    case EDITOR_MENU_COMMANDS.MODULE_QUESTS:
      return "quests";
    default:
      return null;
  }
}

export async function openOrFocusEditorWindow(surface: ModuleEditorSurface) {
  if (!isTauriRuntime()) {
    return;
  }

  await createOrFocusWindow(getWindowDescriptor(surface));
}

export async function openOrFocusModuleEditor(
  commandId: string,
) {
  const surface = getSurfaceForModuleCommand(commandId);
  if (!surface) {
    return;
  }
  await openOrFocusEditorWindow(surface);
}

export async function openOrFocusSettingsWindow(section: EditorSettingsSection = "ai") {
  if (!isTauriRuntime()) {
    return;
  }

  await createOrFocusWindow(
    {
      label: "settings",
      title: "Editor Settings",
      width: 1240,
      height: 860,
      minWidth: 980,
      minHeight: 680,
      resizable: true,
      decorations: false,
      shadow: true,
      buildUrl: () => {
        const params = new URLSearchParams({
          surface: "settings",
          section,
        });
        return `/?${params.toString()}`;
      },
    },
    async (label) => {
      await WebviewWindow.getCurrent().emitTo(label, "settings:open-section", { section });
    },
  );
}

export function getConfiguredStartupSurface(envValue: string | undefined): ModuleEditorSurface {
  const value = envValue?.trim().toLowerCase();
  return isModuleEditorSurface(value) ? value : DEFAULT_EDITOR_START_SURFACE;
}

export {
  DEFAULT_EDITOR_START_SURFACE,
  EDITOR_BOOTSTRAP_WINDOW_LABEL,
};
