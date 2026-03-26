export const EDITOR_MENU_COMMANDS = {
  FILE_NEW_CURRENT: "file.new-current",
  FILE_SAVE_ALL: "file.save-all",
  FILE_RELOAD: "file.reload",
  FILE_DELETE_CURRENT: "file.delete-current",
  WORKBENCH_COMMAND_PALETTE: "workbench.command-palette",
  WORKBENCH_QUICK_OPEN: "workbench.quick-open",
  EDIT_VALIDATE_CURRENT: "edit.validate-current",
  EDIT_AUTO_LAYOUT: "edit.auto-layout",
  EDIT_DELETE_SELECTION: "edit.delete-selection",
  VIEW_TOGGLE_SIDEBAR: "view.toggle-sidebar",
  VIEW_TOGGLE_LEFT_SIDEBAR: "view.toggle-left-sidebar",
  VIEW_TOGGLE_RIGHT_SIDEBAR: "view.toggle-right-sidebar",
  VIEW_TOGGLE_BOTTOM_PANEL: "view.toggle-bottom-panel",
  VIEW_TOGGLE_STATUS_BAR: "view.toggle-status-bar",
  VIEW_RESET_LAYOUT: "view.reset-layout",
  VIEW_RESTORE_DEFAULT_LAYOUT: "view.restore-default-layout",
  VIEW_COLLAPSE_ADVANCED_PANELS: "view.collapse-advanced-panels",
  VIEW_EXPAND_ALL_PANELS: "view.expand-all-panels",
  VIEW_TOGGLE_INSPECTOR: "view.toggle-inspector",
  VIEW_FOCUS_EXPLORER: "view.focus-explorer",
  VIEW_FOCUS_EDITOR: "view.focus-editor",
  VIEW_FOCUS_PROBLEMS: "view.focus-problems",
  VIEW_ZEN_MODE: "view.zen-mode",
  AI_GENERATE: "ai.generate",
  AI_TEST_PROVIDER_CONNECTION: "ai.test-provider-connection",
  AI_OPEN_PROVIDER_SETTINGS: "ai.open-provider-settings",
  NAVIGATION_NEXT_TAB: "navigation.next-tab",
  NAVIGATION_PREV_TAB: "navigation.prev-tab",
  NAVIGATION_CLOSE_ACTIVE_TAB: "navigation.close-active-tab",
  MODULE_ITEMS: "module.items",
  MODULE_DIALOGUES: "module.dialogues",
  MODULE_QUESTS: "module.quests",
  MODULE_MAPS: "module.maps",
  MODULE_NARRATIVE: "module.narrative",
  NARRATIVE_NEW_PROJECT_BRIEF: "narrative.new.project-brief",
  NARRATIVE_NEW_CHARACTER_CARD: "narrative.new.character-card",
  NARRATIVE_NEW_CHAPTER_OUTLINE: "narrative.new.chapter-outline",
  NARRATIVE_NEW_BRANCH_SHEET: "narrative.new.branch-sheet",
  NARRATIVE_NEW_SCENE_DRAFT: "narrative.new.scene-draft",
} as const;

export type EditorMenuCommandId =
  (typeof EDITOR_MENU_COMMANDS)[keyof typeof EDITOR_MENU_COMMANDS];

export type EditorMenuCommandHandler = {
  execute: () => void | Promise<void>;
  isEnabled?: () => boolean;
};

export type EditorMenuCommandMap = Partial<
  Record<EditorMenuCommandId, EditorMenuCommandHandler>
>;

const COMMAND_LABELS: Record<EditorMenuCommandId, string> = {
  [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: "New",
  [EDITOR_MENU_COMMANDS.FILE_SAVE_ALL]: "Save All",
  [EDITOR_MENU_COMMANDS.FILE_RELOAD]: "Reload",
  [EDITOR_MENU_COMMANDS.FILE_DELETE_CURRENT]: "Delete Current",
  [EDITOR_MENU_COMMANDS.WORKBENCH_COMMAND_PALETTE]: "Command Palette",
  [EDITOR_MENU_COMMANDS.WORKBENCH_QUICK_OPEN]: "Quick Open",
  [EDITOR_MENU_COMMANDS.EDIT_VALIDATE_CURRENT]: "Validate Current",
  [EDITOR_MENU_COMMANDS.EDIT_AUTO_LAYOUT]: "Auto Layout",
  [EDITOR_MENU_COMMANDS.EDIT_DELETE_SELECTION]: "Delete Selection",
  [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_SIDEBAR]: "Toggle Sidebar",
  [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_LEFT_SIDEBAR]: "Toggle Left Sidebar",
  [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_RIGHT_SIDEBAR]: "Toggle Right Sidebar",
  [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_BOTTOM_PANEL]: "Toggle Bottom Panel",
  [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_STATUS_BAR]: "Toggle Status Bar",
  [EDITOR_MENU_COMMANDS.VIEW_RESET_LAYOUT]: "Reset Layout",
  [EDITOR_MENU_COMMANDS.VIEW_RESTORE_DEFAULT_LAYOUT]: "Restore Default Layout",
  [EDITOR_MENU_COMMANDS.VIEW_COLLAPSE_ADVANCED_PANELS]: "Collapse Advanced Panels",
  [EDITOR_MENU_COMMANDS.VIEW_EXPAND_ALL_PANELS]: "Expand All Panels",
  [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_INSPECTOR]: "Toggle Inspector",
  [EDITOR_MENU_COMMANDS.VIEW_FOCUS_EXPLORER]: "Focus Explorer",
  [EDITOR_MENU_COMMANDS.VIEW_FOCUS_EDITOR]: "Focus Editor",
  [EDITOR_MENU_COMMANDS.VIEW_FOCUS_PROBLEMS]: "Focus Problems",
  [EDITOR_MENU_COMMANDS.VIEW_ZEN_MODE]: "Toggle Zen Mode",
  [EDITOR_MENU_COMMANDS.AI_GENERATE]: "AI Generate",
  [EDITOR_MENU_COMMANDS.AI_TEST_PROVIDER_CONNECTION]: "Test Provider Connection",
  [EDITOR_MENU_COMMANDS.AI_OPEN_PROVIDER_SETTINGS]: "Open Provider Settings",
  [EDITOR_MENU_COMMANDS.NAVIGATION_NEXT_TAB]: "Next Tab",
  [EDITOR_MENU_COMMANDS.NAVIGATION_PREV_TAB]: "Previous Tab",
  [EDITOR_MENU_COMMANDS.NAVIGATION_CLOSE_ACTIVE_TAB]: "Close Active Tab",
  [EDITOR_MENU_COMMANDS.MODULE_ITEMS]: "Items",
  [EDITOR_MENU_COMMANDS.MODULE_DIALOGUES]: "Dialogues",
  [EDITOR_MENU_COMMANDS.MODULE_QUESTS]: "Quests",
  [EDITOR_MENU_COMMANDS.MODULE_MAPS]: "Maps",
  [EDITOR_MENU_COMMANDS.MODULE_NARRATIVE]: "Narrative Lab",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_PROJECT_BRIEF]: "New Project Brief",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHARACTER_CARD]: "New Character Card",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHAPTER_OUTLINE]: "New Chapter Outline",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_BRANCH_SHEET]: "New Branch Sheet",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_SCENE_DRAFT]: "New Scene Draft",
};

export function formatEditorMenuCommandLabel(commandId: EditorMenuCommandId): string {
  return COMMAND_LABELS[commandId] ?? commandId;
}
