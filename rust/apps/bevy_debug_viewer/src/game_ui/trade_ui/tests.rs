//! 交易 UI 测试：覆盖会话解析与卖出按钮文案等关键辅助逻辑。

use super::*;
use std::collections::BTreeMap;

use crate::bootstrap::load_viewer_gameplay_bootstrap;
use game_core::create_demo_runtime;
use game_data::{
    CharacterId, InteractionTargetId, ItemDefinition, ShopDefinition, ShopInventoryEntry,
};

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
fn trade_cart_confirmation_sells_before_buying_and_executes_on_confirm() {
    let (mut runtime, handles) = create_demo_runtime();
    let items = game_bevy::ItemDefinitions(game_data::ItemLibrary::from(BTreeMap::from([
        (
            1001,
            ItemDefinition {
                id: 1001,
                name: "绷带".to_string(),
                value: 10,
                ..ItemDefinition::default()
            },
        ),
        (
            1002,
            ItemDefinition {
                id: 1002,
                name: "废料".to_string(),
                value: 25,
                ..ItemDefinition::default()
            },
        ),
    ])));
    runtime.set_shop_library(game_data::ShopLibrary::from(BTreeMap::from([(
        "test_shop".to_string(),
        ShopDefinition {
            id: "test_shop".to_string(),
            buy_price_modifier: 1.0,
            sell_price_modifier: 1.0,
            money: 100,
            inventory: vec![ShopInventoryEntry {
                item_id: 1001,
                count: 3,
                price: 10,
            }],
        },
    )])));
    runtime
        .economy_mut()
        .add_item(handles.player, 1002, 1, &items.0)
        .expect("sell item should be added");
    let starting_money = runtime.economy().actor_money(handles.player).unwrap_or(0);
    let mut cart = game_bevy::UiTradeCartState::default();
    cart.add_buy(1001, "绷带".to_string(), 2, 10);
    cart.add_inventory_sell(1002, "废料".to_string(), 1, 25);

    actions::validate_trade_cart(&runtime, handles.player, "test_shop", &cart)
        .expect("net settlement should validate");

    actions::execute_trade_cart(&mut runtime, handles.player, "test_shop", &cart, &items)
        .expect("cart should execute");

    assert_eq!(
        runtime.economy().inventory_count(handles.player, 1001),
        Some(2)
    );
    assert_eq!(
        runtime.economy().inventory_count(handles.player, 1002),
        Some(0)
    );
    assert_eq!(
        runtime.economy().actor_money(handles.player),
        Some(starting_money + 5)
    );
}
