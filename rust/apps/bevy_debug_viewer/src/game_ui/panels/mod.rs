//! 面板子模块门面：按职责域组织子实现并对外暴露稳定的 render_* 入口。
use super::*;

mod character;
mod crafting;
mod inventory;
mod journal;
mod map;
mod map_canvas;
mod map_settings;
mod skills;
mod skills_graph;

pub(super) use inventory::InventoryPanelMode;

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
    character::render_character_panel(parent, font, snapshot)
}

pub(super) fn render_journal_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiJournalSnapshot,
) {
    journal::render_journal_panel(parent, font, snapshot)
}

pub(super) fn render_crafting_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCraftingSnapshot,
) {
    crafting::render_crafting_panel(parent, font, snapshot)
}

pub(super) fn render_skills_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiSkillsSnapshot,
    menu_state: &UiMenuState,
    hotbar_state: &UiHotbarState,
    view_state: &UiSkillTreeViewState,
) {
    skills::render_skills_panel(parent, font, snapshot, menu_state, hotbar_state, view_state)
}

pub(super) fn render_map_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    view_state: &UiMapViewState,
) {
    map::render_map_panel(parent, font, snapshot, current_level, view_state)
}

pub(super) fn map_panel_render_key(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
    view_state: &UiMapViewState,
) -> String {
    map::map_panel_render_key(snapshot, current_level, view_state)
}

#[cfg(test)]
pub(super) fn map_panel_summary(
    snapshot: &game_core::SimulationSnapshot,
    current_level: i32,
) -> map::MapPanelSummary {
    map::map_panel_summary(snapshot, current_level)
}

pub(super) fn render_settings_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    settings: &ViewerUiSettings,
) {
    map_settings::render_settings_panel(parent, font, settings)
}
