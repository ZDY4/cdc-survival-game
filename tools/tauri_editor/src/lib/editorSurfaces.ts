export const EDITOR_BOOTSTRAP_WINDOW_LABEL = "main";

export const MODULE_EDITOR_SURFACES = ["dialogues", "quests"] as const;
export const AUXILIARY_EDITOR_SURFACES = ["settings"] as const;
export const OPENABLE_EDITOR_SURFACES = [
  ...MODULE_EDITOR_SURFACES,
  ...AUXILIARY_EDITOR_SURFACES,
] as const;
export const ALL_EDITOR_WINDOW_LABELS = [...OPENABLE_EDITOR_SURFACES] as const;

export type ModuleEditorSurface = (typeof MODULE_EDITOR_SURFACES)[number];
export type AuxiliaryEditorSurface = (typeof AUXILIARY_EDITOR_SURFACES)[number];
export type OpenableEditorSurface = (typeof OPENABLE_EDITOR_SURFACES)[number];
export type EditorSurface = OpenableEditorSurface | "main";

export const DEFAULT_EDITOR_START_SURFACE: ModuleEditorSurface = "dialogues";

export function isModuleEditorSurface(value: string | null | undefined): value is ModuleEditorSurface {
  return MODULE_EDITOR_SURFACES.includes(value as ModuleEditorSurface);
}

export function isOpenableEditorSurface(value: string | null | undefined): value is OpenableEditorSurface {
  return OPENABLE_EDITOR_SURFACES.includes(value as OpenableEditorSurface);
}
