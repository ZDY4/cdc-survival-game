//! 容器 UI 门面：负责锚定到世界物件附近的容器浮窗渲染。

use super::*;

const CONTAINER_WINDOW_WIDTH: f32 = UI_PANEL_WIDTH;
const CONTAINER_WINDOW_HEIGHT: f32 = 436.0;
const CONTAINER_WINDOW_OFFSET_X: f32 = 26.0;
const CONTAINER_WINDOW_ANCHOR_Y: f32 = 1.0;
const CONTAINER_WINDOW_MARGIN: f32 = 12.0;

mod rendering;

pub(super) fn render_container_page(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    window: &Window,
    camera: &Camera,
    camera_transform: &GlobalTransform,
    runtime: &game_core::SimulationRuntime,
    container_state: &game_bevy::UiContainerSessionState,
    container_snapshot: &game_bevy::UiContainerSnapshot,
    drag_state: &UiInventoryDragState,
) {
    rendering::render_container_page(
        parent,
        font,
        window,
        camera,
        camera_transform,
        runtime,
        container_state,
        container_snapshot,
        drag_state,
    );
}
