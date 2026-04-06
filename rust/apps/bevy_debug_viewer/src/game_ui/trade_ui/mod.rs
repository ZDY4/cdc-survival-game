//! 交易 UI 门面：统一暴露交易会话解析、交易页面渲染与交易按钮处理入口。

use super::*;

const TRADE_PAGE_LEFT_WIDTH: f32 = 568.0;
const TRADE_PAGE_RIGHT_WIDTH: f32 = UI_PANEL_WIDTH;
const TRADE_PAGE_TOP: f32 = 72.0;
const TRADE_PAGE_BOTTOM: f32 = 158.0;
const TRADE_PAGE_GAP: f32 = 14.0;

mod actions;
mod rendering;
#[cfg(test)]
mod tests;

pub(super) fn resolve_trade_session_for_target(
    runtime_state: &ViewerRuntimeState,
    target: &InteractionTargetId,
    shops: &game_data::ShopLibrary,
) -> Option<game_bevy::UiTradeSessionState> {
    actions::resolve_trade_session_for_target(runtime_state, target, shops)
}

pub(super) fn render_trade_page(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    trade_snapshot: &game_bevy::UiTradeSnapshot,
    inventory_snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
    drag_state: &UiInventoryDragState,
) {
    rendering::render_trade_page(
        parent,
        font,
        trade_snapshot,
        inventory_snapshot,
        menu_state,
        drag_state,
    );
}

pub(super) fn handle_trade_button_action(
    action: &GameUiButtonAction,
    ui: &mut GameUiCommandState,
    save_path: &ViewerRuntimeSavePath,
    content: &GameContentRefs<'_, '_>,
) -> bool {
    actions::handle_trade_button_action(action, ui, save_path, content)
}
