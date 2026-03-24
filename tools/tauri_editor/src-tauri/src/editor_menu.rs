use serde::Serialize;
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem, Submenu, SubmenuBuilder},
    AppHandle, Emitter, Manager, Runtime,
};

pub const EDITOR_MENU_COMMAND_EVENT: &str = "editor-menu:command";

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
    pub const MODULE_DIALOGUES: &str = "module.dialogues";
    pub const MODULE_QUESTS: &str = "module.quests";
    pub const MODULE_MAPS: &str = "module.maps";
    pub const MODULE_NARRATIVE: &str = "module.narrative";
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

pub fn build_main_editor_menu<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<Menu<R>> {
    let file_new_current =
        MenuItem::with_id(app, ids::FILE_NEW_CURRENT, "New", true, Some("CmdOrCtrl+N"))?;
    let file_save_all =
        MenuItem::with_id(app, ids::FILE_SAVE_ALL, "Save All", true, Some("CmdOrCtrl+S"))?;
    let file_reload = MenuItem::with_id(app, ids::FILE_RELOAD, "Reload", true, Some("F5"))?;
    let file_delete_current =
        MenuItem::with_id(app, ids::FILE_DELETE_CURRENT, "Delete Current", true, Some("Delete"))?;

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

    let toggle_sidebar =
        MenuItem::with_id(app, ids::VIEW_TOGGLE_SIDEBAR, "Toggle Sidebar", true, None::<&str>)?;
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
    let toggle_inspector =
        MenuItem::with_id(app, ids::VIEW_TOGGLE_INSPECTOR, "Show/Hide Inspector", true, None::<&str>)?;

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
    let module_dialogues =
        MenuItem::with_id(app, ids::MODULE_DIALOGUES, "Dialogues", true, Some("Alt+2"))?;
    let module_quests =
        MenuItem::with_id(app, ids::MODULE_QUESTS, "Quests", true, Some("Alt+3"))?;
    let module_maps = MenuItem::with_id(app, ids::MODULE_MAPS, "Maps", true, Some("Alt+4"))?;
    let module_narrative =
        MenuItem::with_id(app, ids::MODULE_NARRATIVE, "Narrative Lab", true, Some("Alt+5"))?;

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
        .item(&module_dialogues)
        .item(&module_quests)
        .item(&module_maps)
        .item(&module_narrative)
        .build()?;

    let help_menu = SubmenuBuilder::new(app, "Help")
        .about(None)
        .build()?;

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

pub fn build_narrative_lab_menu<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<Menu<R>> {
    let file_new_current =
        MenuItem::with_id(app, ids::FILE_NEW_CURRENT, "New Draft", true, Some("CmdOrCtrl+N"))?;
    let file_save_all =
        MenuItem::with_id(app, ids::FILE_SAVE_ALL, "Save All", true, Some("CmdOrCtrl+S"))?;
    let file_reload = MenuItem::with_id(app, ids::FILE_RELOAD, "Reload", true, Some("F5"))?;
    let file_delete_current =
        MenuItem::with_id(app, ids::FILE_DELETE_CURRENT, "Delete Current", true, Some("Delete"))?;

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
        .item(&toggle_sidebar)
        .item(&toggle_status_bar)
        .separator()
        .item(&reset_layout)
        .item(&restore_default_layout)
        .item(&collapse_advanced_panels)
        .item(&expand_all_panels)
        .build()?;

    let ai_menu = SubmenuBuilder::new(app, "AI")
        .item(&ai_generate)
        .item(&ai_test_provider)
        .item(&ai_open_provider)
        .build()?;

    let help_menu = SubmenuBuilder::new(app, "Help").about(None).build()?;

    Menu::with_items(app, &[&file_menu, &edit_menu, &view_menu, &ai_menu, &help_menu])
}

pub fn apply_window_menu<R: Runtime>(app: &AppHandle<R>, window_label: &str) -> tauri::Result<()> {
    let Some(window) = app.get_webview_window(window_label) else {
        return Ok(());
    };

    let menu = if window_label == "narrative-lab" {
        build_narrative_lab_menu(app)?
    } else {
        build_main_editor_menu(app)?
    };

    window.set_menu(menu)?;
    Ok(())
}

pub fn handle_editor_menu_event<R: Runtime>(app: &AppHandle<R>, menu_id: &str) {
    if !is_editor_menu_command(menu_id) {
        return;
    }

    let target_label = app
        .webview_windows()
        .into_iter()
        .find(|(_, window)| window.is_focused().unwrap_or(false))
        .map(|(label, _)| label)
        .or_else(|| app.get_webview_window("main").map(|window| window.label().to_string()))
        .or_else(|| {
            app.get_webview_window("narrative-lab")
                .map(|window| window.label().to_string())
        })
        .or_else(|| app.get_webview_window("map-editor").map(|window| window.label().to_string()));

    if let Some(label) = target_label {
        let _ = app.emit_to(
            label,
            EDITOR_MENU_COMMAND_EVENT,
            EditorMenuCommandPayload {
                command_id: menu_id.to_string(),
            },
        );
    }
}

fn is_editor_menu_command(menu_id: &str) -> bool {
    matches!(
        menu_id,
        ids::FILE_NEW_CURRENT
            | ids::FILE_SAVE_ALL
            | ids::FILE_RELOAD
            | ids::FILE_DELETE_CURRENT
            | ids::EDIT_VALIDATE_CURRENT
            | ids::EDIT_AUTO_LAYOUT
            | ids::EDIT_DELETE_SELECTION
            | ids::VIEW_TOGGLE_SIDEBAR
            | ids::VIEW_TOGGLE_STATUS_BAR
            | ids::VIEW_RESET_LAYOUT
            | ids::VIEW_RESTORE_DEFAULT_LAYOUT
            | ids::VIEW_COLLAPSE_ADVANCED_PANELS
            | ids::VIEW_EXPAND_ALL_PANELS
            | ids::VIEW_TOGGLE_INSPECTOR
            | ids::AI_GENERATE
            | ids::AI_TEST_PROVIDER_CONNECTION
            | ids::AI_OPEN_PROVIDER_SETTINGS
            | ids::MODULE_ITEMS
            | ids::MODULE_DIALOGUES
            | ids::MODULE_QUESTS
            | ids::MODULE_MAPS
            | ids::MODULE_NARRATIVE
            | ids::NARRATIVE_NEW_PROJECT_BRIEF
            | ids::NARRATIVE_NEW_CHARACTER_CARD
            | ids::NARRATIVE_NEW_CHAPTER_OUTLINE
            | ids::NARRATIVE_NEW_BRANCH_SHEET
            | ids::NARRATIVE_NEW_SCENE_DRAFT
    )
}
