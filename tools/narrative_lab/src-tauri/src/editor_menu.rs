use std::{collections::HashSet, sync::Mutex};

use serde::Serialize;
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem, Submenu, SubmenuBuilder},
    AppHandle, Emitter, Manager, Runtime, WebviewWindow,
};

pub const EDITOR_MENU_COMMAND_EVENT: &str = "editor-menu:command";

fn log_menu(message: impl AsRef<str>) {
    eprintln!("[editor-menu] {}", message.as_ref());
}

pub mod ids {
    pub const FILE_NEW_CURRENT: &str = "file.new-current";
    pub const FILE_SAVE_ALL: &str = "file.save-all";
    pub const FILE_RELOAD: &str = "file.reload";
    pub const FILE_DELETE_CURRENT: &str = "file.delete-current";
    pub const WORKBENCH_COMMAND_PALETTE: &str = "workbench.command-palette";
    pub const WORKBENCH_QUICK_OPEN: &str = "workbench.quick-open";
    pub const VIEW_TOGGLE_SIDEBAR: &str = "view.toggle-sidebar";
    pub const VIEW_TOGGLE_LEFT_SIDEBAR: &str = "view.toggle-left-sidebar";
    pub const VIEW_TOGGLE_RIGHT_SIDEBAR: &str = "view.toggle-right-sidebar";
    pub const VIEW_TOGGLE_BOTTOM_PANEL: &str = "view.toggle-bottom-panel";
    pub const VIEW_TOGGLE_STATUS_BAR: &str = "view.toggle-status-bar";
    pub const VIEW_RESET_LAYOUT: &str = "view.reset-layout";
    pub const VIEW_RESTORE_DEFAULT_LAYOUT: &str = "view.restore-default-layout";
    pub const VIEW_COLLAPSE_ADVANCED_PANELS: &str = "view.collapse-advanced-panels";
    pub const VIEW_EXPAND_ALL_PANELS: &str = "view.expand-all-panels";
    pub const VIEW_TOGGLE_INSPECTOR: &str = "view.toggle-inspector";
    pub const VIEW_FOCUS_EXPLORER: &str = "view.focus-explorer";
    pub const VIEW_FOCUS_EDITOR: &str = "view.focus-editor";
    pub const VIEW_FOCUS_PROBLEMS: &str = "view.focus-problems";
    pub const VIEW_ZEN_MODE: &str = "view.zen-mode";
    pub const AI_GENERATE: &str = "ai.generate";
    pub const AI_TEST_PROVIDER_CONNECTION: &str = "ai.test-provider-connection";
    pub const AI_OPEN_PROVIDER_SETTINGS: &str = "ai.open-provider-settings";
    pub const NAVIGATION_NEXT_TAB: &str = "navigation.next-tab";
    pub const NAVIGATION_PREV_TAB: &str = "navigation.prev-tab";
    pub const NAVIGATION_CLOSE_ACTIVE_TAB: &str = "navigation.close-active-tab";
    pub const NARRATIVE_NEW_PROJECT_BRIEF: &str = "narrative.new.project-brief";
    pub const NARRATIVE_NEW_CHARACTER_CARD: &str = "narrative.new.character-card";
    pub const NARRATIVE_NEW_CHAPTER_OUTLINE: &str = "narrative.new.chapter-outline";
    pub const NARRATIVE_NEW_BRANCH_SHEET: &str = "narrative.new.branch-sheet";
    pub const NARRATIVE_NEW_SCENE_DRAFT: &str = "narrative.new.scene-draft";
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct EditorMenuCommandPayload {
    pub command_id: String,
}

#[derive(Default)]
pub struct EditorMenuState {
    last_focused_window: Mutex<Option<String>>,
    attached_menu_windows: Mutex<HashSet<String>>,
}

pub fn build_narrative_lab_menu<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<Menu<R>> {
    let file_new_current =
        MenuItem::with_id(app, ids::FILE_NEW_CURRENT, "New Draft", true, Some("CmdOrCtrl+N"))?;
    let file_save_all =
        MenuItem::with_id(app, ids::FILE_SAVE_ALL, "Save All", true, Some("CmdOrCtrl+S"))?;
    let file_reload = MenuItem::with_id(app, ids::FILE_RELOAD, "Reload", true, Some("F5"))?;
    let file_delete_current =
        MenuItem::with_id(app, ids::FILE_DELETE_CURRENT, "Delete Current", true, Some("Delete"))?;
    let workbench_command_palette = MenuItem::with_id(
        app,
        ids::WORKBENCH_COMMAND_PALETTE,
        "Command Palette",
        true,
        Some("CmdOrCtrl+Shift+P"),
    )?;
    let workbench_quick_open = MenuItem::with_id(
        app,
        ids::WORKBENCH_QUICK_OPEN,
        "Quick Open",
        true,
        Some("CmdOrCtrl+P"),
    )?;

    let narrative_new_project_brief = MenuItem::with_id(
        app,
        ids::NARRATIVE_NEW_PROJECT_BRIEF,
        "Project Brief",
        true,
        None::<&str>,
    )?;
    let narrative_new_character_card = MenuItem::with_id(
        app,
        ids::NARRATIVE_NEW_CHARACTER_CARD,
        "Character Card",
        true,
        None::<&str>,
    )?;
    let narrative_new_chapter_outline = MenuItem::with_id(
        app,
        ids::NARRATIVE_NEW_CHAPTER_OUTLINE,
        "Chapter Outline",
        true,
        None::<&str>,
    )?;
    let narrative_new_branch_sheet = MenuItem::with_id(
        app,
        ids::NARRATIVE_NEW_BRANCH_SHEET,
        "Branch Sheet",
        true,
        None::<&str>,
    )?;
    let narrative_new_scene_draft = MenuItem::with_id(
        app,
        ids::NARRATIVE_NEW_SCENE_DRAFT,
        "Scene Draft",
        true,
        None::<&str>,
    )?;

    let toggle_sidebar =
        MenuItem::with_id(app, ids::VIEW_TOGGLE_SIDEBAR, "Toggle Sidebar", true, None::<&str>)?;
    let toggle_left_sidebar = MenuItem::with_id(
        app,
        ids::VIEW_TOGGLE_LEFT_SIDEBAR,
        "Toggle Left Sidebar",
        true,
        Some("CmdOrCtrl+B"),
    )?;
    let toggle_right_sidebar = MenuItem::with_id(
        app,
        ids::VIEW_TOGGLE_RIGHT_SIDEBAR,
        "Toggle Right Sidebar",
        true,
        None::<&str>,
    )?;
    let toggle_bottom_panel = MenuItem::with_id(
        app,
        ids::VIEW_TOGGLE_BOTTOM_PANEL,
        "Toggle Bottom Panel",
        true,
        Some("CmdOrCtrl+J"),
    )?;
    let toggle_status_bar = MenuItem::with_id(
        app,
        ids::VIEW_TOGGLE_STATUS_BAR,
        "Toggle Status Bar",
        true,
        None::<&str>,
    )?;
    let reset_layout =
        MenuItem::with_id(app, ids::VIEW_RESET_LAYOUT, "Reset Layout", true, None::<&str>)?;
    let restore_default_layout = MenuItem::with_id(
        app,
        ids::VIEW_RESTORE_DEFAULT_LAYOUT,
        "Restore Default Layout",
        true,
        None::<&str>,
    )?;
    let collapse_advanced_panels = MenuItem::with_id(
        app,
        ids::VIEW_COLLAPSE_ADVANCED_PANELS,
        "Collapse Advanced Panels",
        true,
        None::<&str>,
    )?;
    let expand_all_panels =
        MenuItem::with_id(app, ids::VIEW_EXPAND_ALL_PANELS, "Expand All Panels", true, None::<&str>)?;
    let toggle_inspector = MenuItem::with_id(
        app,
        ids::VIEW_TOGGLE_INSPECTOR,
        "Toggle Inspector",
        true,
        None::<&str>,
    )?;
    let focus_explorer = MenuItem::with_id(
        app,
        ids::VIEW_FOCUS_EXPLORER,
        "Focus Explorer",
        true,
        None::<&str>,
    )?;
    let focus_editor = MenuItem::with_id(
        app,
        ids::VIEW_FOCUS_EDITOR,
        "Focus Editor",
        true,
        None::<&str>,
    )?;
    let focus_problems = MenuItem::with_id(
        app,
        ids::VIEW_FOCUS_PROBLEMS,
        "Focus Problems",
        true,
        None::<&str>,
    )?;
    let zen_mode =
        MenuItem::with_id(app, ids::VIEW_ZEN_MODE, "Zen Mode", true, None::<&str>)?;
    let next_tab = MenuItem::with_id(
        app,
        ids::NAVIGATION_NEXT_TAB,
        "Next Tab",
        true,
        Some("CmdOrCtrl+Tab"),
    )?;
    let prev_tab = MenuItem::with_id(
        app,
        ids::NAVIGATION_PREV_TAB,
        "Previous Tab",
        true,
        Some("CmdOrCtrl+Shift+Tab"),
    )?;
    let close_active_tab = MenuItem::with_id(
        app,
        ids::NAVIGATION_CLOSE_ACTIVE_TAB,
        "Close Active Tab",
        true,
        Some("CmdOrCtrl+W"),
    )?;

    let ai_generate = MenuItem::with_id(
        app,
        ids::AI_GENERATE,
        "AI Generate",
        true,
        Some("CmdOrCtrl+Shift+G"),
    )?;
    let ai_test_provider = MenuItem::with_id(
        app,
        ids::AI_TEST_PROVIDER_CONNECTION,
        "Test Provider Connection",
        true,
        None::<&str>,
    )?;
    let ai_open_provider = MenuItem::with_id(
        app,
        ids::AI_OPEN_PROVIDER_SETTINGS,
        "Open Provider Settings",
        true,
        None::<&str>,
    )?;

    let new_narrative_submenu = Submenu::with_items(
        app,
        "New Narrative",
        true,
        &[
            &narrative_new_project_brief,
            &narrative_new_character_card,
            &narrative_new_chapter_outline,
            &narrative_new_branch_sheet,
            &narrative_new_scene_draft,
        ],
    )?;

    let file_menu = SubmenuBuilder::new(app, "File")
        .item(&file_new_current)
        .item(&new_narrative_submenu)
        .separator()
        .item(&file_save_all)
        .item(&file_reload)
        .item(&file_delete_current)
        .separator()
        .item(&PredefinedMenuItem::close_window(app, None)?)
        .item(&PredefinedMenuItem::quit(app, None)?)
        .build()?;

    let edit_menu = SubmenuBuilder::new(app, "Edit")
        .undo()
        .redo()
        .separator()
        .cut()
        .copy()
        .paste()
        .select_all()
        .build()?;

    let view_menu = SubmenuBuilder::new(app, "View")
        .item(&workbench_command_palette)
        .separator()
        .item(&toggle_sidebar)
        .item(&toggle_left_sidebar)
        .item(&toggle_right_sidebar)
        .item(&toggle_bottom_panel)
        .item(&toggle_inspector)
        .item(&toggle_status_bar)
        .separator()
        .item(&focus_explorer)
        .item(&focus_editor)
        .item(&focus_problems)
        .item(&zen_mode)
        .separator()
        .item(&reset_layout)
        .item(&restore_default_layout)
        .item(&collapse_advanced_panels)
        .item(&expand_all_panels)
        .build()?;

    let go_menu = SubmenuBuilder::new(app, "Go")
        .item(&workbench_quick_open)
        .separator()
        .item(&next_tab)
        .item(&prev_tab)
        .item(&close_active_tab)
        .build()?;

    let ai_menu = SubmenuBuilder::new(app, "AI")
        .item(&ai_generate)
        .item(&ai_test_provider)
        .item(&ai_open_provider)
        .build()?;

    let help_menu = SubmenuBuilder::new(app, "Help").about(None).build()?;

    Menu::with_items(app, &[&file_menu, &edit_menu, &view_menu, &go_menu, &ai_menu, &help_menu])
}

pub fn apply_window_menu<R: Runtime>(app: &AppHandle<R>, window_label: &str) -> tauri::Result<()> {
    let Some(window) = app.get_webview_window(window_label) else {
        log_menu(format!(
            "skip applying menu because window is missing: {}",
            window_label
        ));
        return Ok(());
    };

    if window_label == "settings" {
        let _ = window.remove_menu()?;
        log_menu(format!("removed native menu for window={window_label}"));
        return Ok(());
    }

    log_menu(format!("building narrative lab menu for window={window_label}"));
    let menu = build_narrative_lab_menu(app)?;

    window.set_menu(menu)?;
    log_menu(format!("applied menu to window={window_label}"));
    Ok(())
}

pub fn attach_window_menu_listener<R: Runtime>(window: WebviewWindow<R>) {
    let label = window.label().to_string();
    let app = window.app_handle().clone();

    if label == "settings" {
        log_menu(format!("skip attaching menu listener for window={label}"));
        return;
    }

    let should_attach = {
        if let Ok(mut attached_menu_windows) = app.state::<EditorMenuState>().attached_menu_windows.lock() {
            attached_menu_windows.insert(label.clone())
        } else {
            log_menu(format!(
                "failed to acquire attached window registry lock for window={label}"
            ));
            false
        }
    };

    if !should_attach {
        log_menu(format!(
            "menu listener already attached or unavailable for window={label}"
        ));
        return;
    }

    log_menu(format!("attaching menu listener to window={label}"));
    window.on_menu_event(move |window, event| {
        let command_id = event.id().as_ref().to_string();
        log_menu(format!(
            "menu click received from window={} command_id={command_id}",
            window.label()
        ));

        match app.emit_to(
            window.label(),
            EDITOR_MENU_COMMAND_EVENT,
            EditorMenuCommandPayload {
                command_id: command_id.clone(),
            },
        ) {
            Ok(()) => {
                log_menu(format!(
                    "forwarded command to frontend window={} command_id={command_id}",
                    window.label()
                ));
            }
            Err(error) => {
                log_menu(format!(
                    "failed to forward command to frontend window={} command_id={} error={}",
                    window.label(),
                    command_id,
                    error
                ));
            }
        }
    });
}

pub fn remember_focused_editor_window<R: Runtime>(
    app: &AppHandle<R>,
    window_label: &str,
    focused: bool,
) {
    if !focused || !is_editor_window_label(window_label) {
        return;
    }

    if let Ok(mut last_focused_window) = app.state::<EditorMenuState>().last_focused_window.lock() {
        *last_focused_window = Some(window_label.to_string());
        log_menu(format!("focused editor window changed to {window_label}"));
    } else {
        log_menu(format!(
            "failed to record focused editor window={window_label}"
        ));
    }
}

fn is_editor_window_label(label: &str) -> bool {
    matches!(label, "main" | "settings")
}
