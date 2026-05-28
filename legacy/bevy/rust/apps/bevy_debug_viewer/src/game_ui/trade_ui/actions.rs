//! 交易动作模块：负责交易目标会话解析、交易篮维护与确认结算。

use super::*;
use std::collections::{BTreeMap, BTreeSet};

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
            cart: game_bevy::UiTradeCartState::default(),
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
        GameUiButtonAction::QueueTradeBuy { shop_id, item_id } => {
            queue_trade_buy_action(ui, content, shop_id, *item_id);
            ui.drag_state.clear();
            true
        }
        GameUiButtonAction::QueueTradeSell { shop_id, item_id } => {
            queue_trade_sell_action(ui, content, shop_id, *item_id);
            ui.drag_state.clear();
            true
        }
        GameUiButtonAction::QueueTradeEquippedSell { shop_id, slot_id } => {
            if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                let status = queue_trade_equipped_sell(
                    &ui.runtime_state.runtime,
                    &mut ui.modal_state,
                    &content.items,
                    actor_id,
                    shop_id,
                    slot_id,
                );
                set_trade_status(ui, status);
            }
            ui.drag_state.clear();
            true
        }
        GameUiButtonAction::AdjustTradeBuy { item_id, delta } => {
            if *delta > 0 {
                if let Some(shop_id) = ui
                    .modal_state
                    .trade
                    .as_ref()
                    .map(|trade| trade.shop_id.clone())
                {
                    queue_trade_buy_action(ui, content, &shop_id, *item_id);
                }
            } else if let Some(trade) = ui.modal_state.trade.as_mut() {
                trade.cart.adjust_buy(*item_id, *delta);
                set_trade_status(ui, "已调整买入数量".to_string());
            }
            true
        }
        GameUiButtonAction::RemoveTradeBuy { item_id } => {
            if let Some(trade) = ui.modal_state.trade.as_mut() {
                trade.cart.buy_lines.retain(|line| line.item_id != *item_id);
                set_trade_status(ui, "已移除买入物品".to_string());
            }
            true
        }
        GameUiButtonAction::AdjustTradeSell {
            item_id,
            source,
            delta,
        } => {
            if *delta > 0 {
                if let Some(shop_id) = ui
                    .modal_state
                    .trade
                    .as_ref()
                    .map(|trade| trade.shop_id.clone())
                {
                    match source {
                        game_bevy::UiTradeCartSellSource::Inventory => {
                            queue_trade_sell_action(ui, content, &shop_id, *item_id);
                        }
                        game_bevy::UiTradeCartSellSource::Equipped { slot_id } => {
                            if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                                let status = queue_trade_equipped_sell(
                                    &ui.runtime_state.runtime,
                                    &mut ui.modal_state,
                                    &content.items,
                                    actor_id,
                                    &shop_id,
                                    slot_id,
                                );
                                set_trade_status(ui, status);
                            }
                        }
                    }
                }
            } else if let Some(trade) = ui.modal_state.trade.as_mut() {
                trade.cart.adjust_sell(*item_id, source, *delta);
                set_trade_status(ui, "已调整卖出数量".to_string());
            }
            true
        }
        GameUiButtonAction::RemoveTradeSell { item_id, source } => {
            if let Some(trade) = ui.modal_state.trade.as_mut() {
                trade
                    .cart
                    .sell_lines
                    .retain(|line| !(line.item_id == *item_id && line.source == *source));
                set_trade_status(ui, "已移除卖出物品".to_string());
            }
            true
        }
        GameUiButtonAction::ClearTradeCart => {
            if let Some(trade) = ui.modal_state.trade.as_mut() {
                trade.cart = game_bevy::UiTradeCartState::default();
                set_trade_status(ui, "已清空交易列表".to_string());
            }
            true
        }
        GameUiButtonAction::ConfirmTradeCart => {
            confirm_trade_cart(ui, save_path, content);
            ui.drag_state.clear();
            true
        }
        _ => false,
    }
}

fn queue_trade_buy_action(
    ui: &mut GameUiCommandState,
    content: &GameContentRefs<'_, '_>,
    shop_id: &str,
    item_id: u32,
) {
    let Some(trade) = ui.modal_state.trade.clone() else {
        set_trade_status(ui, "交易会话已关闭".to_string());
        return;
    };
    if trade.shop_id != shop_id {
        set_trade_status(ui, "交易对象已变化，请重新选择物品".to_string());
        return;
    }
    match plan_trade_cart_buy(&ui.runtime_state.runtime, &trade, item_id, &content.items) {
        TradeQuantityPlan::Immediate { count } => {
            let Some(unit_price) =
                trade_buy_unit_price(&ui.runtime_state.runtime, shop_id, item_id, &content.items)
            else {
                set_trade_status(ui, format!("unknown_item:{item_id}"));
                return;
            };
            let status = queue_trade_buy(
                &mut ui.modal_state,
                &content.items,
                shop_id,
                item_id,
                unit_price,
                count,
            );
            set_trade_status(ui, status);
        }
        TradeQuantityPlan::OpenModal(modal) => {
            ui.modal_state.item_quantity = Some(modal);
            set_trade_status(ui, "选择买入数量".to_string());
        }
        TradeQuantityPlan::Blocked { status } => set_trade_status(ui, status),
    }
}

fn queue_trade_sell_action(
    ui: &mut GameUiCommandState,
    content: &GameContentRefs<'_, '_>,
    shop_id: &str,
    item_id: u32,
) {
    let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) else {
        set_trade_status(ui, "找不到玩家角色".to_string());
        return;
    };
    let Some(trade) = ui.modal_state.trade.clone() else {
        set_trade_status(ui, "交易会话已关闭".to_string());
        return;
    };
    if trade.shop_id != shop_id {
        set_trade_status(ui, "交易对象已变化，请重新选择物品".to_string());
        return;
    }
    match plan_trade_cart_sell(
        &ui.runtime_state.runtime,
        actor_id,
        &trade,
        item_id,
        &content.items,
    ) {
        TradeQuantityPlan::Immediate { count } => {
            let Some(unit_price) =
                trade_sell_unit_price(&ui.runtime_state.runtime, shop_id, item_id, &content.items)
            else {
                set_trade_status(ui, format!("unknown_item:{item_id}"));
                return;
            };
            let status = queue_trade_sell(
                &mut ui.modal_state,
                &content.items,
                shop_id,
                item_id,
                unit_price,
                count,
            );
            set_trade_status(ui, status);
        }
        TradeQuantityPlan::OpenModal(modal) => {
            ui.modal_state.item_quantity = Some(modal);
            set_trade_status(ui, "选择卖出数量".to_string());
        }
        TradeQuantityPlan::Blocked { status } => set_trade_status(ui, status),
    }
}

fn confirm_trade_cart(
    ui: &mut GameUiCommandState,
    save_path: &ViewerRuntimeSavePath,
    content: &GameContentRefs<'_, '_>,
) {
    let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) else {
        set_trade_status(ui, "找不到玩家角色".to_string());
        return;
    };
    let Some(trade) = ui.modal_state.trade.clone() else {
        set_trade_status(ui, "交易会话已关闭".to_string());
        return;
    };
    if trade.cart.is_empty() {
        set_trade_status(ui, "交易列表为空".to_string());
        return;
    }
    if let Err(error) = validate_trade_cart(
        &ui.runtime_state.runtime,
        actor_id,
        &trade.shop_id,
        &trade.cart,
    ) {
        set_trade_status(ui, error);
        return;
    }

    let backup = ui.runtime_state.runtime.save_snapshot();
    let mut executed = false;
    let result = execute_trade_cart(
        &mut ui.runtime_state.runtime,
        actor_id,
        &trade.shop_id,
        &trade.cart,
        &content.items,
    );
    match result {
        Ok(()) => {
            executed = true;
            save_runtime_snapshot(save_path, &ui.runtime_state.runtime);
            if let Some(current_trade) = ui.modal_state.trade.as_mut() {
                current_trade.cart = game_bevy::UiTradeCartState::default();
            }
            ui.menu_state.selected_inventory_item = None;
            ui.menu_state.selected_equipment_slot = None;
            let net = trade.cart.net_payment();
            let status = if net > 0 {
                format!("交易完成，玩家支付 {net}")
            } else if net < 0 {
                format!("交易完成，玩家获得 {}", -net)
            } else {
                "交易完成，无需支付".to_string()
            };
            set_trade_status(ui, status);
        }
        Err(error) => {
            if let Err(restore_error) = ui.runtime_state.runtime.load_snapshot(backup) {
                set_trade_status(ui, format!("交易失败且回滚失败: {restore_error}"));
            } else {
                set_trade_status(ui, format!("交易失败，已回滚: {error}"));
            }
        }
    }
    if executed {
        ui.modal_state.item_quantity = None;
    }
}

pub(super) fn validate_trade_cart(
    runtime: &game_core::SimulationRuntime,
    actor_id: ActorId,
    shop_id: &str,
    cart: &game_bevy::UiTradeCartState,
) -> Result<(), String> {
    let shop = runtime
        .economy()
        .shop(shop_id)
        .ok_or_else(|| format!("unknown_shop:{shop_id}"))?;
    let mut buy_counts = BTreeMap::<u32, i32>::new();
    for line in &cart.buy_lines {
        if line.count <= 0 {
            return Err("买入数量无效".to_string());
        }
        *buy_counts.entry(line.item_id).or_default() += line.count;
    }
    for (item_id, count) in buy_counts {
        let current = shop
            .inventory
            .get(&item_id)
            .map(|entry| entry.count)
            .unwrap_or(0);
        if current < count {
            return Err(format!("商店库存不足: {item_id}"));
        }
    }

    let mut inventory_sell_counts = BTreeMap::<u32, i32>::new();
    let mut equipped_slots = BTreeSet::<String>::new();
    for line in &cart.sell_lines {
        if line.count <= 0 {
            return Err("卖出数量无效".to_string());
        }
        match &line.source {
            game_bevy::UiTradeCartSellSource::Inventory => {
                *inventory_sell_counts.entry(line.item_id).or_default() += line.count;
            }
            game_bevy::UiTradeCartSellSource::Equipped { slot_id } => {
                if line.count != 1 {
                    return Err("装备卖出数量无效".to_string());
                }
                if !equipped_slots.insert(slot_id.clone()) {
                    return Err("同一装备槽重复卖出".to_string());
                }
                let current_item = runtime
                    .economy()
                    .actor(actor_id)
                    .and_then(|actor| actor.equipped_slots.get(slot_id))
                    .map(|equipped| equipped.item_id);
                if current_item != Some(line.item_id) {
                    return Err(format!("装备槽已变化: {slot_id}"));
                }
            }
        }
    }
    for (item_id, count) in inventory_sell_counts {
        let current = runtime
            .economy()
            .inventory_count(actor_id, item_id)
            .unwrap_or(0);
        if current < count {
            return Err(format!("玩家库存不足: {item_id}"));
        }
    }

    let player_money = runtime.economy().actor_money(actor_id).unwrap_or(0);
    let buy_total = cart.buy_total();
    let sell_total = cart.sell_total();
    if player_money + sell_total < buy_total {
        return Err(format!(
            "资金不足: 需支付 {}，当前可用 {}",
            buy_total - sell_total,
            player_money
        ));
    }
    if shop.money < sell_total {
        return Err(format!(
            "商店资金不足: 需要 {}，当前 {}",
            sell_total, shop.money
        ));
    }
    Ok(())
}

pub(super) fn execute_trade_cart(
    runtime: &mut game_core::SimulationRuntime,
    actor_id: ActorId,
    shop_id: &str,
    cart: &game_bevy::UiTradeCartState,
    items: &ItemDefinitions,
) -> Result<(), String> {
    for line in &cart.sell_lines {
        match &line.source {
            game_bevy::UiTradeCartSellSource::Inventory => {
                runtime
                    .economy_mut()
                    .sell_item_to_shop(actor_id, shop_id, line.item_id, line.count, &items.0)
                    .map_err(|error| error.to_string())?;
            }
            game_bevy::UiTradeCartSellSource::Equipped { slot_id } => {
                runtime
                    .economy_mut()
                    .sell_equipped_item_to_shop(actor_id, shop_id, slot_id, &items.0)
                    .map_err(|error| error.to_string())?;
            }
        }
    }
    for line in &cart.buy_lines {
        runtime
            .economy_mut()
            .buy_item_from_shop(actor_id, shop_id, line.item_id, line.count, &items.0)
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

fn set_trade_status(ui: &mut GameUiCommandState, status: String) {
    ui.viewer_state.status_line = status.clone();
    ui.menu_state.status_text = status;
}
