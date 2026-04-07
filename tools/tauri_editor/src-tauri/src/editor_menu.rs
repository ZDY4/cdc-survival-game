use std::{collections::HashSet, sync::Mutex};

use serde::Serialize;
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem, SubmenuBuilder},
    AppHandle, Emitter, Manager, Runtime, WebviewWindow,
};

pub const EDITOR_MENU_COMMAND_EVENT: &str = "editor-menu:command";
const MENULESS_WINDOW_LABELS: &[&str] = &["main", "settings"];

fn log_menu(message: impl AsRef<str>) {
    eprintln!("[editor-menu] {}", message.as_ref());
}

pub mod ids {
    pub const FILE_NEW_CURRENT: &str = "file.new-current";
    pub const FILE_SAVE_ALL: &str = "file.save-all";
    pub const FILE_RELOAD: &str = "file.reload";
    pub const FILE_DELETE_CURRENT: &str = "file.delete-current";
    pub const EDIT_VALIDATE_CURRENT: &str = "edit.validate-current";
    pub const EDIT_AUTO_LAYOUT: &str = "edit.auto-layout";
    pub const EDIT_DELETE_SELECTION: &str = "edit.delete-selection";
    pub const VIEW_TOGGLE_SIDEBAR: &str = "view.toggle-sidebar";
    pub const VIEW_TOGGLE_STATUS_BAR: &str = "view.toggle-status-bar";
    pub const VIEW_RESET_LAYOUT: &str = "view.reset-layout";
    pub const VIEW_RESTORE_DEFAULT_LAYOUT: &str = "view.restore-default-layout";
    pub const VIEW_COLLAPSE_ADVANCED_PANELS: &str = "view.collapse-advanced-panels";
    pub const VIEW_EXPAND_ALL_PANELS: &str = "view.expand-all-panels";
    pub const VIEW_TOGGLE_INSPECTOR: &str = "view.toggle-inspector";
    pub const AI_GENERATE: &str = "ai.generate";
    pub const AI_TEST_PROVIDER_CONNECTION: &str = "ai.test-provider-connection";
    pub const AI_OPEN_PROVIDER_SETTINGS: &str = "ai.open-provider-settings";
    pub const MODULE_ITEMS: &str = "module.items";
    pub const MODULE_CHARACTERS: &str = "module.characters";
    pub const MODULE_DIALOGUES: &str = "module.dialogues";
    pub const MODULE_QUESTS: &str = "module.quests";
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

pub fn build_main_editor_menu<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<Menu<R>> {
    let file_new_current =
        MenuItem::with_id(app, ids::FILE_NEW_CURRENT, "New", true, Some("CmdOrCtrl+N"))?;
    let file_save_all = MenuItem::with_id(
        app,
        ids::FILE_SAVE_ALL,
        "Save All",
        true,
        Some("CmdOrCtrl+S"),
    )?;
    let file_reload = MenuItem::with_id(app, ids::FILE_RELOAD, "Reload", true, Some("F5"))?;
    let file_delete_current = MenuItem::with_id(
        app,
        ids::FILE_DELETE_CURRENT,
        "Delete Current",
        true,
        Some("Delete"),
    )?;

    let validate_current = MenuItem::with_id(
        app,
        ids::EDIT_VALIDATE_CURRENT,
        "Validate Current",
        true,
        Some("CmdOrCtrl+Shift+V"),
    )?;
    let auto_layout = MenuItem::with_id(
        app,
        ids::EDIT_AUTO_LAYOUT,
        "Auto Layout",
        true,
        Some("CmdOrCtrl+Shift+L"),
    )?;
    let delete_selection = MenuItem::with_id(
        app,
        ids::EDIT_DELETE_SELECTION,
        "Delete Selection",
        true,
        None::<&str>,
    )?;

    let toggle_sidebar = MenuItem::with_id(
        app,
        ids::VIEW_TOGGLE_SIDEBAR,
        "Toggle Sidebar",
        true,
        None::<&str>,
    )?;
    let toggle_status_bar = MenuItem::with_id(
        app,
        ids::VIEW_TOGGLE_STATUS_BAR,
        "Toggle Status Bar",
        true,
        None::<&str>,
    )?;
    let reset_layout = MenuItem::with_id(
        app,
        ids::VIEW_RESET_LAYOUT,
        "Reset Layout",
        true,
        None::<&str>,
    )?;
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
    let expand_all_panels = MenuItem::with_id(
        app,
        ids::VIEW_EXPAND_ALL_PANELS,
        "Expand All Panels",
        true,
        None::<&str>,
    )?;
    let toggle_inspector = MenuItem::with_id(
        app,
        ids::VIEW_TOGGLE_INSPECTOR,
        "Show/Hide Inspector",
        true,
        None::<&str>,
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

    let module_items = MenuItem::with_id(app, ids::MODULE_ITEMS, "Items", true, Some("Alt+1"))?;
    let module_characters =
        MenuItem::with_id(app, ids::MODULE_CHARACTERS, "Characters", true, Some("Alt+2"))?;
    let module_dialogues =
        MenuItem::with_id(app, ids::MODULE_DIALOGUES, "Dialogues", true, Some("Alt+3"))?;
    let module_quests = MenuItem::with_id(app, ids::MODULE_QUESTS, "Quests", true, Some("Alt+4"))?;
    let file_menu = SubmenuBuilder::new(app, "File")
        .item(&file_new_current)
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
        .separator()
        .item(&validate_current)
        .item(&auto_layout)
        .item(&delete_selection)
        .build()?;

    let view_menu = SubmenuBuilder::new(app, "View")
        .item(&toggle_sidebar)
        .item(&toggle_status_bar)
        .separator()
        .item(&reset_layout)
        .item(&restore_default_layout)
        .item(&collapse_advanced_panels)
        .item(&expand_all_panels)
        .item(&toggle_inspector)
        .build()?;

    let ai_menu = SubmenuBuilder::new(app, "AI")
        .item(&ai_generate)
        .item(&ai_test_provider)
        .item(&ai_open_provider)
        .build()?;

    let module_menu = SubmenuBuilder::new(app, "Module")
        .item(&module_items)
        .item(&module_characters)
        .item(&module_dialogues)
        .item(&module_quests)
        .build()?;

    let help_menu = SubmenuBuilder::new(app, "Help").about(None).build()?;

    Menu::with_items(
        app,
        &[
            &file_menu,
            &edit_menu,
            &view_menu,
            &ai_menu,
            &module_menu,
            &help_menu,
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

    if MENULESS_WINDOW_LABELS.contains(&window_label) {
        let _ = window.remove_menu()?;
        log_menu(format!("removed native menu for window={window_label}"));
        return Ok(());
    }

    log_menu(format!(
        "building main editor menu for window={window_label}"
    ));
    let menu = build_main_editor_menu(app)?;

    window.set_menu(menu)?;
    log_menu(format!("applied menu to window={window_label}"));
    Ok(())
}

pub fn attach_window_menu_listener<R: Runtime>(window: WebviewWindow<R>) {
    let label = window.label().to_string();
    let app = window.app_handle().clone();

    if MENULESS_WINDOW_LABELS.contains(&label.as_str()) {
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
    matches!(
        label,
        "items" | "characters" | "dialogues" | "quests" | "settings"
    )
}
