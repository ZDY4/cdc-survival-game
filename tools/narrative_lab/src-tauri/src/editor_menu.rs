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
    pub const VIEW_TOGGLE_LEFT_SIDEBAR: &str = "view.toggle-left-sidebar";
    pub const VIEW_FOCUS_EDITOR: &str = "view.focus-editor";
    pub const AI_GENERATE: &str = "ai.generate";
    pub const AI_OPEN_PROVIDER_SETTINGS: &str = "ai.open-provider-settings";
    pub const NAVIGATION_NEXT_TAB: &str = "navigation.next-tab";
    pub const NAVIGATION_PREV_TAB: &str = "navigation.prev-tab";
    pub const NAVIGATION_CLOSE_ACTIVE_TAB: &str = "navigation.close-active-tab";
    pub const NARRATIVE_NEW_CHARACTER_CARD: &str = "narrative.new.character-card";
    pub const NARRATIVE_NEW_TASK_SETUP: &str = "narrative.new.task-setup";
    pub const NARRATIVE_NEW_LOCATION_NOTE: &str = "narrative.new.location-note";
    pub const NARRATIVE_NEW_MONSTER_NOTE: &str = "narrative.new.monster-note";
    pub const NARRATIVE_NEW_ITEM_NOTE: &str = "narrative.new.item-note";
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
    let file_new_current = MenuItem::with_id(
        app,
        ids::FILE_NEW_CURRENT,
        "新建草稿",
        true,
        Some("CmdOrCtrl+N"),
    )?;
    let file_save_all = MenuItem::with_id(
        app,
        ids::FILE_SAVE_ALL,
        "全部保存",
        true,
        Some("CmdOrCtrl+S"),
    )?;
    let file_reload = MenuItem::with_id(app, ids::FILE_RELOAD, "重新加载", true, Some("F5"))?;
    let file_delete_current = MenuItem::with_id(
        app,
        ids::FILE_DELETE_CURRENT,
        "删除当前项",
        true,
        Some("Delete"),
    )?;

    let narrative_new_task_setup = MenuItem::with_id(
        app,
        ids::NARRATIVE_NEW_TASK_SETUP,
        "任务设定",
        true,
        None::<&str>,
    )?;
    let narrative_new_location_note = MenuItem::with_id(
        app,
        ids::NARRATIVE_NEW_LOCATION_NOTE,
        "地点设定",
        true,
        None::<&str>,
    )?;
    let narrative_new_character_card = MenuItem::with_id(
        app,
        ids::NARRATIVE_NEW_CHARACTER_CARD,
        "人物设定",
        true,
        None::<&str>,
    )?;
    let narrative_new_monster_note = MenuItem::with_id(
        app,
        ids::NARRATIVE_NEW_MONSTER_NOTE,
        "怪物设定",
        true,
        None::<&str>,
    )?;
    let narrative_new_item_note = MenuItem::with_id(
        app,
        ids::NARRATIVE_NEW_ITEM_NOTE,
        "物品设定",
        true,
        None::<&str>,
    )?;

    let toggle_left_sidebar = MenuItem::with_id(
        app,
        ids::VIEW_TOGGLE_LEFT_SIDEBAR,
        "切换左侧边栏",
        true,
        Some("CmdOrCtrl+B"),
    )?;
    let focus_editor = MenuItem::with_id(
        app,
        ids::VIEW_FOCUS_EDITOR,
        "聚焦编辑器",
        true,
        None::<&str>,
    )?;
    let next_tab = MenuItem::with_id(
        app,
        ids::NAVIGATION_NEXT_TAB,
        "下一个标签页",
        true,
        Some("CmdOrCtrl+Tab"),
    )?;
    let prev_tab = MenuItem::with_id(
        app,
        ids::NAVIGATION_PREV_TAB,
        "上一个标签页",
        true,
        Some("CmdOrCtrl+Shift+Tab"),
    )?;
    let close_active_tab = MenuItem::with_id(
        app,
        ids::NAVIGATION_CLOSE_ACTIVE_TAB,
        "关闭当前标签页",
        true,
        Some("CmdOrCtrl+W"),
    )?;

    let ai_generate = MenuItem::with_id(
        app,
        ids::AI_GENERATE,
        "AI 生成",
        true,
        Some("CmdOrCtrl+Shift+G"),
    )?;
    let ai_open_provider = MenuItem::with_id(
        app,
        ids::AI_OPEN_PROVIDER_SETTINGS,
        "打开提供方设置",
        true,
        None::<&str>,
    )?;

    let new_narrative_submenu = Submenu::with_items(
        app,
        "新建叙事文稿",
        true,
        &[
            &narrative_new_task_setup,
            &narrative_new_location_note,
            &narrative_new_character_card,
            &narrative_new_monster_note,
            &narrative_new_item_note,
        ],
    )?;

    let file_menu = SubmenuBuilder::new(app, "文件")
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

    let edit_menu = SubmenuBuilder::new(app, "编辑")
        .undo()
        .redo()
        .separator()
        .cut()
        .copy()
        .paste()
        .select_all()
        .build()?;

    let view_menu = SubmenuBuilder::new(app, "视图")
        .item(&toggle_left_sidebar)
        .separator()
        .item(&focus_editor)
        .build()?;

    let go_menu = SubmenuBuilder::new(app, "导航")
        .item(&next_tab)
        .item(&prev_tab)
        .item(&close_active_tab)
        .build()?;

    let ai_menu = SubmenuBuilder::new(app, "AI")
        .item(&ai_generate)
        .item(&ai_open_provider)
        .build()?;

    let help_menu = SubmenuBuilder::new(app, "帮助").about(None).build()?;

    Menu::with_items(
        app,
        &[
            &file_menu, &edit_menu, &view_menu, &go_menu, &ai_menu, &help_menu,
        ],
    )
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

    log_menu(format!(
        "building narrative lab menu for window={window_label}"
    ));
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
        if let Ok(mut attached_menu_windows) =
            app.state::<EditorMenuState>().attached_menu_windows.lock()
        {
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
