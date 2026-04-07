//! 游戏 UI 输入门面：按按钮动作、指针输入和 tooltip 逻辑拆分，保持对外更新链精简稳定。

use super::*;

mod button_actions;
mod pointer_input;
mod tooltip;

pub(crate) use button_actions::handle_game_ui_buttons;
pub(super) use button_actions::{
    execute_trade_buy, execute_trade_sell, plan_trade_buy, plan_trade_sell, TradeQuantityPlan,
};
pub(crate) use pointer_input::{
    handle_inventory_list_mouse_wheel, handle_inventory_panel_pointer_input,
    sync_inventory_list_scrollbar,
};
pub(crate) use tooltip::update_hover_tooltip_state;
