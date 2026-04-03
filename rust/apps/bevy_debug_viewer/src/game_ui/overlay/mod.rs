//! UI 浮层门面：统一对外暴露主更新链、面板壳层、提示浮层与模态提示的稳定入口。

use super::*;

mod modal_prompt;
mod root_update;
mod shell;
mod tooltip_context;

pub(crate) fn update_game_ui(
    commands: Commands,
    root: Single<(Entity, Option<&Children>), With<GameUiRoot>>,
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<ViewerCamera>>,
    palette: Res<ViewerPalette>,
    font: Res<ViewerUiFont>,
    ui: GameUiViewState,
    content: GameContentRefs,
) {
    root_update::update_game_ui(
        commands,
        root,
        window,
        camera_query,
        palette,
        font,
        ui,
        content,
    );
}

pub(super) fn render_discard_quantity_modal(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    modal: &game_bevy::UiDiscardQuantityModalState,
    items: &ItemDefinitions,
) {
    modal_prompt::render_discard_quantity_modal(parent, font, modal, items);
}

pub(super) fn render_overworld_location_prompt(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    window: &Window,
    camera: &Camera,
    camera_transform: &GlobalTransform,
    runtime: &game_core::SimulationRuntime,
    prompt: &game_bevy::UiOverworldLocationPromptSnapshot,
) {
    modal_prompt::render_overworld_location_prompt(
        parent,
        font,
        window,
        camera,
        camera_transform,
        runtime,
        prompt,
    );
}

pub(super) fn render_main_menu(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    status_text: &str,
) {
    shell::render_main_menu(parent, font, status_text);
}

pub(super) fn render_panel_shell(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    panel: UiMenuPanel,
) {
    shell::render_panel_shell(parent, font, panel);
}

pub(super) fn panel_body(parent: &mut ChildSpawnerCommands, panel: UiMenuPanel) -> Entity {
    shell::panel_body(parent, panel)
}

pub(super) fn render_hover_tooltip(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    window: &Window,
    player_actor: Option<ActorId>,
    ui: &GameUiViewState<'_, '_>,
    content: &GameContentRefs<'_, '_>,
) {
    tooltip_context::render_hover_tooltip(parent, font, window, player_actor, ui, content);
}

pub(super) fn render_inventory_context_menu(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    window: &Window,
    player_actor: Option<ActorId>,
    ui: &GameUiViewState<'_, '_>,
    content: &GameContentRefs<'_, '_>,
) {
    tooltip_context::render_inventory_context_menu(parent, font, window, player_actor, ui, content);
}
