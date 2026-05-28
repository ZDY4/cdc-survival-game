//! 快捷栏渲染门面：统一暴露底栏槽位和当前 dock / 观察模式布局。

use super::*;

mod dock;
mod observe;
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
    if viewer_state.is_free_observe() {
        observe::render_observe_hotbar(parent, font, viewer_state);
    } else {
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
