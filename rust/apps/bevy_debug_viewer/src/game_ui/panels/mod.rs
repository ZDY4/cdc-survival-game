//! 面板子模块门面：按职责域组织子实现并对外暴露稳定的 render_* 入口。
use super::*;

mod inventory;
mod map_settings;
mod progression;
mod skills;
mod skills_graph;

pub(super) use inventory::{render_inventory_panel_contents, InventoryPanelMode};

pub(super) fn render_inventory_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
    drag_state: &UiInventoryDragState,
    mode: InventoryPanelMode,
    window_height: f32,
) {
    inventory::render_inventory_panel(
        parent,
        font,
        snapshot,
        menu_state,
        drag_state,
        mode,
        window_height,
    )
}

pub(super) fn render_character_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCharacterSnapshot,
) {
    progression::render_character_panel(parent, font, snapshot)
}

pub(super) fn render_journal_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiJournalSnapshot,
) {
    progression::render_journal_panel(parent, font, snapshot)
}

pub(super) fn render_crafting_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCraftingSnapshot,
) {
    progression::render_crafting_panel(parent, font, snapshot)
}

pub(super) fn render_skills_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiSkillsSnapshot,
    menu_state: &UiMenuState,
    hotbar_state: &UiHotbarState,
) {
    skills::render_skills_panel(parent, font, snapshot, menu_state, hotbar_state)
}

pub(super) fn render_map_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    current: &game_core::OverworldStateSnapshot,
    overworld: &game_data::OverworldLibrary,
    menu_state: &UiMenuState,
) {
    map_settings::render_map_panel(parent, font, current, overworld, menu_state)
}

pub(super) fn render_settings_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    settings: &ViewerUiSettings,
) {
    map_settings::render_settings_panel(parent, font, settings)
}
