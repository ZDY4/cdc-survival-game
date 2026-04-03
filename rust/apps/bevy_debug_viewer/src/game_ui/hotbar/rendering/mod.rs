//! 快捷栏渲染门面：统一暴露底栏槽位、当前 dock 布局和遗留样式入口。

use super::*;

mod dock;
mod legacy;
mod slots;

pub(crate) fn render_hotbar(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    viewer_state: &ViewerState,
    hotbar_state: &UiHotbarState,
    skills: &game_data::SkillLibrary,
    menu_state: &UiMenuState,
    show_clear_controls: bool,
    selected_skill_id: Option<&str>,
) {
    dock::render_hotbar(
        parent,
        font,
        viewer_state,
        hotbar_state,
        skills,
        menu_state,
        show_clear_controls,
        selected_skill_id,
    );
}

#[allow(dead_code)]
pub(crate) fn render_hotbar_legacy(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    viewer_state: &ViewerState,
    hotbar_state: &UiHotbarState,
    skills: &game_data::SkillLibrary,
    menu_state: &UiMenuState,
    player_stats: Option<&PlayerHudStats>,
    show_clear_controls: bool,
    selected_skill_id: Option<&str>,
) {
    legacy::render_hotbar_legacy(
        parent,
        font,
        viewer_state,
        hotbar_state,
        skills,
        menu_state,
        player_stats,
        show_clear_controls,
        selected_skill_id,
    );
}

fn render_hotbar_slots(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    hotbar_state: &UiHotbarState,
    skills: &game_data::SkillLibrary,
    show_clear_controls: bool,
    selected_skill_id: Option<&str>,
) {
    slots::render_hotbar_slots(
        parent,
        font,
        hotbar_state,
        skills,
        show_clear_controls,
        selected_skill_id,
    );
}
