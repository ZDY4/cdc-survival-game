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
  NARRATIVE_NEW_TASK_SETUP: "narrative.new.task-setup",
  NARRATIVE_NEW_LOCATION_NOTE: "narrative.new.location-note",
  NARRATIVE_NEW_MONSTER_NOTE: "narrative.new.monster-note",
  NARRATIVE_NEW_ITEM_NOTE: "narrative.new.item-note",
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
  [EDITOR_MENU_COMMANDS.FILE_NEW_CURRENT]: "新建草稿",
  [EDITOR_MENU_COMMANDS.FILE_SAVE_ALL]: "全部保存",
  [EDITOR_MENU_COMMANDS.FILE_RELOAD]: "重新加载",
  [EDITOR_MENU_COMMANDS.FILE_DELETE_CURRENT]: "删除当前项",
  [EDITOR_MENU_COMMANDS.WORKBENCH_COMMAND_PALETTE]: "命令面板",
  [EDITOR_MENU_COMMANDS.WORKBENCH_QUICK_OPEN]: "快速打开",
  [EDITOR_MENU_COMMANDS.EDIT_VALIDATE_CURRENT]: "校验当前项",
  [EDITOR_MENU_COMMANDS.EDIT_AUTO_LAYOUT]: "自动布局",
  [EDITOR_MENU_COMMANDS.EDIT_DELETE_SELECTION]: "删除选区",
  [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_SIDEBAR]: "切换侧边栏",
  [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_LEFT_SIDEBAR]: "切换左侧边栏",
  [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_RIGHT_SIDEBAR]: "切换右侧边栏",
  [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_BOTTOM_PANEL]: "切换底部面板",
  [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_STATUS_BAR]: "切换状态栏",
  [EDITOR_MENU_COMMANDS.VIEW_RESET_LAYOUT]: "重置布局",
  [EDITOR_MENU_COMMANDS.VIEW_RESTORE_DEFAULT_LAYOUT]: "恢复默认布局",
  [EDITOR_MENU_COMMANDS.VIEW_COLLAPSE_ADVANCED_PANELS]: "收起高级面板",
  [EDITOR_MENU_COMMANDS.VIEW_EXPAND_ALL_PANELS]: "展开全部面板",
  [EDITOR_MENU_COMMANDS.VIEW_TOGGLE_INSPECTOR]: "切换检查器",
  [EDITOR_MENU_COMMANDS.VIEW_FOCUS_EXPLORER]: "聚焦资源栏",
  [EDITOR_MENU_COMMANDS.VIEW_FOCUS_EDITOR]: "聚焦编辑器",
  [EDITOR_MENU_COMMANDS.VIEW_FOCUS_PROBLEMS]: "聚焦问题面板",
  [EDITOR_MENU_COMMANDS.VIEW_ZEN_MODE]: "切换专注模式",
  [EDITOR_MENU_COMMANDS.AI_GENERATE]: "AI 生成",
  [EDITOR_MENU_COMMANDS.AI_TEST_PROVIDER_CONNECTION]: "测试提供方连接",
  [EDITOR_MENU_COMMANDS.AI_OPEN_PROVIDER_SETTINGS]: "打开提供方设置",
  [EDITOR_MENU_COMMANDS.NAVIGATION_NEXT_TAB]: "下一个标签页",
  [EDITOR_MENU_COMMANDS.NAVIGATION_PREV_TAB]: "上一个标签页",
  [EDITOR_MENU_COMMANDS.NAVIGATION_CLOSE_ACTIVE_TAB]: "关闭当前标签页",
  [EDITOR_MENU_COMMANDS.MODULE_ITEMS]: "物品",
  [EDITOR_MENU_COMMANDS.MODULE_DIALOGUES]: "对话",
  [EDITOR_MENU_COMMANDS.MODULE_QUESTS]: "任务",
  [EDITOR_MENU_COMMANDS.MODULE_MAPS]: "地图",
  [EDITOR_MENU_COMMANDS.MODULE_NARRATIVE]: "叙事实验室",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_PROJECT_BRIEF]: "新建项目总纲",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHARACTER_CARD]: "新建人物设定",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_CHAPTER_OUTLINE]: "新建章节大纲",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_BRANCH_SHEET]: "新建分支设计",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_SCENE_DRAFT]: "新建场景稿",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_TASK_SETUP]: "新建任务设定",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_LOCATION_NOTE]: "新建地点设定",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_MONSTER_NOTE]: "新建怪物设定",
  [EDITOR_MENU_COMMANDS.NARRATIVE_NEW_ITEM_NOTE]: "新建物品设定",
};

export function formatEditorMenuCommandLabel(commandId: EditorMenuCommandId): string {
  return COMMAND_LABELS[commandId] ?? commandId;
}
