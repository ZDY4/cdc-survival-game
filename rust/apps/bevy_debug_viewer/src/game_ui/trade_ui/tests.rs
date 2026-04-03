//! 交易 UI 测试：覆盖会话解析与卖出按钮文案等关键辅助逻辑。

use super::*;
use std::collections::BTreeMap;

use crate::bootstrap::load_viewer_gameplay_bootstrap;
use game_data::{CharacterId, InteractionTargetId, ShopDefinition, ShopInventoryEntry};

fn sample_shops() -> game_data::ShopLibrary {
    game_data::ShopLibrary::from(BTreeMap::from([
        (
            "fallback_shop".to_string(),
            ShopDefinition {
                id: "fallback_shop".to_string(),
                inventory: vec![ShopInventoryEntry {
                    item_id: 1001,
                    count: 1,
                    price: 12,
                }],
                ..ShopDefinition::default()
            },
        ),
        (
            "trader_lao_wang_shop".to_string(),
            ShopDefinition {
                id: "trader_lao_wang_shop".to_string(),
                inventory: vec![ShopInventoryEntry {
                    item_id: 1002,
                    count: 2,
                    price: 18,
                }],
                ..ShopDefinition::default()
            },
        ),
    ]))
}

#[test]
fn resolve_trade_session_prefers_actor_matched_shop() {
    let bootstrap = load_viewer_gameplay_bootstrap().expect("viewer bootstrap should load");
    let trader_actor_id = bootstrap
        .runtime
        .snapshot()
        .actors
        .iter()
        .find(|actor| {
            actor.definition_id.as_ref().map(CharacterId::as_str) == Some("trader_lao_wang")
        })
        .map(|actor| actor.actor_id)
        .expect("trader actor should exist");
    let runtime_state = ViewerRuntimeState {
        runtime: bootstrap.runtime,
        recent_events: Vec::new(),
        ai_snapshot: Default::default(),
    };
    let shops = sample_shops();

    let session = resolve_trade_session_for_target(
        &runtime_state,
        &InteractionTargetId::Actor(trader_actor_id),
        &shops,
    )
    .expect("trade session should resolve");

    assert_eq!(session.shop_id, "trader_lao_wang_shop");
    assert_eq!(session.target_actor_id, Some(trader_actor_id));
}

#[test]
fn resolve_trade_session_falls_back_to_first_shop_for_non_actor_target() {
    let bootstrap = load_viewer_gameplay_bootstrap().expect("viewer bootstrap should load");
    let runtime_state = ViewerRuntimeState {
        runtime: bootstrap.runtime,
        recent_events: Vec::new(),
        ai_snapshot: Default::default(),
    };
    let shops = sample_shops();

    let session = resolve_trade_session_for_target(
        &runtime_state,
        &InteractionTargetId::MapObject("shelf".into()),
        &shops,
    )
    .expect("fallback trade session should resolve");

    assert_eq!(session.shop_id, "fallback_shop");
    assert_eq!(session.target_actor_id, None);
}

#[test]
fn trade_sell_button_label_reflects_selected_item() {
    let snapshot = game_bevy::UiTradeSnapshot {
        shop_id: "test_shop".into(),
        relation_score: 0,
        player_money: 20,
        shop_money: 80,
        player_items: vec![game_bevy::UiTradeEntryView {
            item_id: 1008,
            name: "Scrap".into(),
            count: 3,
            unit_price: 7,
            total_weight: 1.5,
        }],
        shop_items: Vec::new(),
    };

    assert_eq!(
        rendering::trade_sell_button_label(&snapshot, None),
        "选择一个物品后，可在这里卖出 x1"
    );
    assert_eq!(
        rendering::trade_sell_button_label(&snapshot, Some(1008)),
        "已选中 Scrap · 库存 x3 · 预计卖出 7 货币"
    );
    assert_eq!(
        rendering::trade_sell_button_label(&snapshot, Some(9999)),
        "该物品当前不可交易，请重新选择一个可售物品"
    );
}
