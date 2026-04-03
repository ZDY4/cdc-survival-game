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
            ui.modal_state.trade = None;
            ui.viewer_state.pending_open_trade_target = None;
            true
        }
        GameUiButtonAction::BuyTradeItem { shop_id, item_id } => {
            if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                ui.menu_state.status_text = ui
                    .runtime_state
                    .runtime
                    .buy_item_from_shop(actor_id, shop_id, *item_id, 1, &content.items.0)
                    .map(|_| {
                        save_runtime_snapshot(save_path, &ui.runtime_state.runtime);
                        "买入成功".to_string()
                    })
                    .unwrap_or_else(|error| error.to_string());
            }
            true
        }
        GameUiButtonAction::SellTradeItem { shop_id, item_id } => {
            if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                ui.menu_state.status_text = ui
                    .runtime_state
                    .runtime
                    .sell_item_to_shop(actor_id, shop_id, *item_id, 1, &content.items.0)
                    .map(|_| {
                        save_runtime_snapshot(save_path, &ui.runtime_state.runtime);
                        "卖出成功".to_string()
                    })
                    .unwrap_or_else(|error| error.to_string());
            }
            true
        }
        _ => false,
    }
}
