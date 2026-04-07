//! 容器 UI 门面：负责容器页面渲染。

use super::*;

const CONTAINER_PAGE_LEFT_WIDTH: f32 = 568.0;
const CONTAINER_PAGE_RIGHT_WIDTH: f32 = UI_PANEL_WIDTH;
const CONTAINER_PAGE_TOP: f32 = 72.0;
const CONTAINER_PAGE_BOTTOM: f32 = 158.0;
const CONTAINER_PAGE_GAP: f32 = 14.0;

mod rendering;

pub(super) fn render_container_page(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    container_snapshot: &game_bevy::UiContainerSnapshot,
    inventory_snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
    drag_state: &UiInventoryDragState,
) {
    rendering::render_container_page(
        parent,
        font,
        container_snapshot,
        inventory_snapshot,
        menu_state,
        drag_state,
    );
}
