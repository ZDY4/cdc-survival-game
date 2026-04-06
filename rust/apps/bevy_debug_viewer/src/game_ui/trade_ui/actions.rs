//! 交易动作模块：负责交易目标会话解析与买卖按钮行为处理。

use super::*;

pub(super) fn resolve_trade_session_for_target(
    runtime_state: &ViewerRuntimeState,
    target: &InteractionTargetId,
    shops: &game_data::ShopLibrary,
) -> Option<game_bevy::UiTradeSessionState> {
    let target_actor_id = match target {
        InteractionTargetId::Actor(actor_id) => Some(*actor_id),
        _ => None,
    };
    let snapshot = runtime_state.runtime.snapshot();
    let mut resolved_shop_id = None;
    if let Some(target_actor_id) = target_actor_id {
        if let Some(actor) = snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == target_actor_id)
        {
            if let Some(definition_id) = actor.definition_id.as_ref() {
                let candidate = format!("{}_shop", definition_id.as_str());
                if shops.get(&candidate).is_some() {
                    resolved_shop_id = Some(candidate);
                }
            }
        }
    }
    resolved_shop_id
        .or_else(|| shops.iter().next().map(|(shop_id, _)| shop_id.clone()))
        .map(|shop_id| game_bevy::UiTradeSessionState {
            shop_id,
            target_actor_id,
        })
}

pub(super) fn handle_trade_button_action(
    action: &GameUiButtonAction,
    ui: &mut GameUiCommandState,
    save_path: &ViewerRuntimeSavePath,
    content: &GameContentRefs<'_, '_>,
) -> bool {
    match action {
        GameUiButtonAction::CloseTrade => {
            ui.modal_state.item_quantity = None;
            ui.modal_state.trade = None;
            ui.viewer_state.pending_open_trade_target = None;
            ui.drag_state.clear();
            true
        }
        GameUiButtonAction::BuyTradeItem { shop_id, item_id } => {
            if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                match plan_trade_buy(
                    &ui.runtime_state.runtime,
                    actor_id,
                    shop_id,
                    *item_id,
                    &content.items,
                ) {
                    TradeQuantityPlan::Immediate { count } => {
                        let status = execute_trade_buy(
                            &mut ui.runtime_state,
                            &mut ui.menu_state,
                            save_path,
                            &content.items,
                            actor_id,
                            shop_id,
                            *item_id,
                            count,
                        );
                        ui.viewer_state.status_line = status.clone();
                        ui.menu_state.status_text = status;
                    }
                    TradeQuantityPlan::OpenModal(modal) => {
                        ui.modal_state.item_quantity = Some(modal);
                        ui.menu_state.status_text = "选择要买入的数量".to_string();
                    }
                    TradeQuantityPlan::Blocked { status } => {
                        ui.viewer_state.status_line = status.clone();
                        ui.menu_state.status_text = status;
                    }
                }
            }
            ui.drag_state.clear();
            true
        }
        GameUiButtonAction::SellTradeItem { shop_id, item_id } => {
            if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                match plan_trade_sell(
                    &ui.runtime_state.runtime,
                    actor_id,
                    shop_id,
                    *item_id,
                    &content.items,
                ) {
                    TradeQuantityPlan::Immediate { count } => {
                        let status = execute_trade_sell(
                            &mut ui.runtime_state,
                            &mut ui.menu_state,
                            save_path,
                            &content.items,
                            actor_id,
                            shop_id,
                            *item_id,
                            count,
                        );
                        ui.viewer_state.status_line = status.clone();
                        ui.menu_state.status_text = status;
                    }
                    TradeQuantityPlan::OpenModal(modal) => {
                        ui.modal_state.item_quantity = Some(modal);
                        ui.menu_state.status_text = "选择要卖出的数量".to_string();
                    }
                    TradeQuantityPlan::Blocked { status } => {
                        ui.viewer_state.status_line = status.clone();
                        ui.menu_state.status_text = status;
                    }
                }
            }
            ui.drag_state.clear();
            true
        }
        GameUiButtonAction::SellEquippedTradeItem { shop_id, slot_id } => {
            if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                let status = ui
                    .runtime_state
                    .runtime
                    .sell_equipped_item_to_shop(actor_id, shop_id, slot_id, &content.items.0)
                    .map(|outcome| {
                        save_runtime_snapshot(save_path, &ui.runtime_state.runtime);
                        let item_name = content
                            .items
                            .0
                            .get(outcome.item_id)
                            .map(|item| item.name.as_str())
                            .unwrap_or("未知物品");
                        format!("已卖出装备 {item_name} x1")
                    })
                    .unwrap_or_else(|error| error.to_string());
                ui.menu_state.status_text = status.clone();
                ui.viewer_state.status_line = status;
                if ui.menu_state.selected_equipment_slot.as_deref() == Some(slot_id.as_str()) {
                    ui.menu_state.selected_equipment_slot = None;
                }
            }
            ui.drag_state.clear();
            true
        }
        _ => false,
    }
}
