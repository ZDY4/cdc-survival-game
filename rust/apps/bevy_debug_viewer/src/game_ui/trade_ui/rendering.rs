//! 交易页面渲染模块：负责交易主布局、玩家背包栏与商店栏的具体构建。

use super::*;

pub(super) fn render_trade_page(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    trade: &game_bevy::UiTradeSessionState,
    trade_snapshot: &game_bevy::UiTradeSnapshot,
    inventory_snapshot: &game_bevy::UiInventoryPanelSnapshot,
    _menu_state: &UiMenuState,
    drag_state: &UiInventoryDragState,
) {
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: px(0),
                top: px(0),
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                ..default()
            },
            BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.34)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
            UiMouseBlocker,
            UiMouseBlockerName("交易界面".to_string()),
        ))
        .with_children(|overlay| {
            overlay
                .spawn((
                    Node {
                        position_type: PositionType::Absolute,
                        left: Val::Percent(50.0),
                        top: px(TRADE_PAGE_TOP),
                        margin: UiRect {
                            left: px(-(trade_page_width() / 2.0)),
                            ..default()
                        },
                        width: px(trade_page_width()),
                        padding: UiRect::axes(px(18), px(14)),
                        flex_direction: FlexDirection::Row,
                        justify_content: JustifyContent::SpaceBetween,
                        align_items: AlignItems::Center,
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(ui_panel_background()),
                    BorderColor::all(ui_border_strong_color()),
                    FocusPolicy::Block,
                    RelativeCursorPosition::default(),
                    viewer_ui_passthrough_bundle(),
                    UiMouseBlocker,
                    UiMouseBlockerName("交易标题栏".to_string()),
                ))
                .with_children(|header| {
                    header
                        .spawn(Node {
                            flex_direction: FlexDirection::Row,
                            align_items: AlignItems::Center,
                            column_gap: px(18),
                            flex_grow: 1.0,
                            min_width: px(0),
                            ..default()
                        })
                        .with_children(|header_body| {
                            header_body
                                .spawn(Node {
                                    flex_direction: FlexDirection::Column,
                                    row_gap: px(4),
                                    flex_grow: 1.0,
                                    min_width: px(0),
                                    ..default()
                                })
                                .with_children(|titles| {
                                    titles.spawn(text_bundle(
                                        font,
                                        &format!("交易 · {}", trade_snapshot.shop_id),
                                        15.2,
                                        Color::WHITE,
                                    ));
                                    titles.spawn(text_bundle(
                                        font,
                                        &format!(
                                            "友好度 {} · 玩家资金 {} · 商店资金 {} · {}",
                                            trade_snapshot.relation_score,
                                            trade_snapshot.player_money,
                                            trade_snapshot.shop_money,
                                            settlement_text(&trade.cart)
                                        ),
                                        10.4,
                                        ui_text_secondary_color(),
                                    ));
                                });
                            header_body.spawn(action_button(
                                font,
                                "确认交易",
                                GameUiButtonAction::ConfirmTradeCart,
                            ));
                            header_body.spawn(action_button(
                                font,
                                "清空",
                                GameUiButtonAction::ClearTradeCart,
                            ));
                        });
                    let close_action = GameUiButtonAction::CloseTrade;
                    header
                        .spawn(close_icon_button(close_action))
                        .with_children(|button| {
                            button.spawn(close_icon_label(font));
                        });
                });

            overlay
                .spawn((
                    Node {
                        position_type: PositionType::Absolute,
                        left: Val::Percent(50.0),
                        top: px(TRADE_PAGE_TOP + 74.0),
                        bottom: px(TRADE_PAGE_BOTTOM),
                        margin: UiRect {
                            left: px(-(trade_page_width() / 2.0)),
                            ..default()
                        },
                        width: px(trade_page_width()),
                        flex_direction: FlexDirection::Row,
                        column_gap: px(TRADE_PAGE_GAP),
                        ..default()
                    },
                    viewer_ui_passthrough_bundle(),
                ))
                .with_children(|columns| {
                    render_trade_shop_column(columns, font, trade, trade_snapshot, drag_state);
                    render_trade_inventory_column(
                        columns,
                        font,
                        trade,
                        trade_snapshot,
                        inventory_snapshot,
                        drag_state,
                    );
                });
        });
}

fn trade_page_width() -> f32 {
    TRADE_PAGE_LEFT_WIDTH + TRADE_PAGE_RIGHT_WIDTH + TRADE_PAGE_GAP
}

fn render_trade_inventory_column(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    trade: &game_bevy::UiTradeSessionState,
    trade_snapshot: &game_bevy::UiTradeSnapshot,
    inventory_snapshot: &game_bevy::UiInventoryPanelSnapshot,
    drag_state: &UiInventoryDragState,
) {
    parent
        .spawn((
            Node {
                width: px(TRADE_PAGE_RIGHT_WIDTH),
                height: Val::Percent(100.0),
                padding: UiRect::all(px(14)),
                flex_direction: FlexDirection::Column,
                row_gap: px(10),
                border: UiRect::all(px(1)),
                overflow: Overflow::clip_y(),
                ..default()
            },
            BackgroundColor(ui_panel_background()),
            BorderColor::all(ui_border_color()),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            TradeInventoryPanelBounds,
            viewer_ui_passthrough_bundle(),
            UiMouseBlocker,
            UiMouseBlockerName("交易背包栏".to_string()),
        ))
        .with_children(|body| {
            body.spawn(text_bundle(font, "玩家物品", 11.4, ui_text_heading_color()));
            body.spawn(text_bundle(
                font,
                "点击条目加入待卖出，已装备物品显示 E 标记。",
                9.6,
                ui_text_muted_color(),
            ));
            render_trade_player_list(
                body,
                font,
                trade,
                trade_snapshot,
                inventory_snapshot,
                drag_state,
            );
        });
}

fn render_trade_shop_column(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    trade: &game_bevy::UiTradeSessionState,
    snapshot: &game_bevy::UiTradeSnapshot,
    _drag_state: &UiInventoryDragState,
) {
    parent
        .spawn((
            Node {
                width: px(TRADE_PAGE_RIGHT_WIDTH),
                height: Val::Percent(100.0),
                padding: UiRect::all(px(14)),
                flex_direction: FlexDirection::Column,
                row_gap: px(10),
                border: UiRect::all(px(1)),
                overflow: Overflow::clip_y(),
                ..default()
            },
            BackgroundColor(ui_panel_background()),
            BorderColor::all(ui_border_color()),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            TradeSellZone,
            viewer_ui_passthrough_bundle(),
            UiMouseBlocker,
            UiMouseBlockerName("交易商品栏".to_string()),
        ))
        .with_children(|body| {
            body.spawn(text_bundle(font, "商品列表", 11.4, ui_text_heading_color()));
            body.spawn(text_bundle(
                font,
                &format!(
                    "{} · 库存 {} 种",
                    snapshot.shop_id,
                    snapshot.shop_items.len()
                ),
                9.8,
                ui_text_muted_color(),
            ));
            body.spawn(text_bundle(
                font,
                "点击条目加入待买入；可堆叠物品会先选择数量。",
                9.8,
                ui_text_muted_color(),
            ));

            body.spawn((
                Node {
                    width: Val::Percent(100.0),
                    flex_grow: 1.0,
                    padding: UiRect::all(px(10)),
                    flex_direction: FlexDirection::Column,
                    row_gap: px(8),
                    border: UiRect::all(px(1)),
                    overflow: Overflow::clip_y(),
                    ..default()
                },
                BackgroundColor(ui_panel_background()),
                BorderColor::all(ui_border_color()),
                viewer_ui_passthrough_bundle(),
            ))
            .with_children(|items| {
                if snapshot.shop_items.is_empty() {
                    items.spawn(text_bundle(
                        font,
                        "商店库存为空",
                        10.4,
                        ui_text_muted_color(),
                    ));
                }
                for item in &snapshot.shop_items {
                    let queued = trade.cart.queued_buy_count(item.item_id);
                    render_trade_item_row(
                        items,
                        font,
                        "物",
                        &trade_item_count_label(&item.name, item.count, "待买", queued),
                        item.unit_price,
                        queued,
                        true,
                        GameUiButtonAction::QueueTradeBuy {
                            shop_id: snapshot.shop_id.clone(),
                            item_id: item.item_id,
                        },
                        Some(GameUiButtonAction::AdjustTradeBuy {
                            item_id: item.item_id,
                            delta: -1,
                        }),
                        Some(GameUiButtonAction::RemoveTradeBuy {
                            item_id: item.item_id,
                        }),
                        Some(item.item_id),
                        false,
                    );
                }
            });
        });
}

fn render_trade_player_list(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    trade: &game_bevy::UiTradeSessionState,
    trade_snapshot: &game_bevy::UiTradeSnapshot,
    inventory_snapshot: &game_bevy::UiInventoryPanelSnapshot,
    drag_state: &UiInventoryDragState,
) {
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                flex_grow: 1.0,
                min_height: px(0),
                padding: UiRect::all(px(10)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                border: UiRect::all(px(1)),
                overflow: Overflow::clip_y(),
                ..default()
            },
            BackgroundColor(ui_panel_background()),
            BorderColor::all(ui_border_color()),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|items| {
            if inventory_snapshot.entries.is_empty() {
                items.spawn(text_bundle(
                    font,
                    "当前筛选下没有物品",
                    10.4,
                    ui_text_muted_color(),
                ));
            }
            for item in &inventory_snapshot.entries {
                let equipped_source = item.equipped_slot_id.as_ref().map(|slot_id| {
                    game_bevy::UiTradeCartSellSource::Equipped {
                        slot_id: slot_id.clone(),
                    }
                });
                let source = equipped_source
                    .clone()
                    .unwrap_or(game_bevy::UiTradeCartSellSource::Inventory);
                let queued = match &source {
                    game_bevy::UiTradeCartSellSource::Inventory => {
                        trade.cart.queued_inventory_sell_count(item.item_id)
                    }
                    game_bevy::UiTradeCartSellSource::Equipped { slot_id } => {
                        i32::from(trade.cart.has_equipped_sell_slot(slot_id))
                    }
                };
                let price = trade_unit_price_for_player_item(trade_snapshot, item.item_id);
                let icon = trade_item_icon_label(item.item_type, item.equipped_slot_id.is_some());
                let is_drag_hover = matches!(
                    drag_state.hover_target.as_ref(),
                    Some(UiInventoryDragHoverTarget::InventoryItem { item_id })
                        if *item_id == item.item_id
                );
                render_trade_item_row(
                    items,
                    font,
                    icon,
                    &trade_item_count_label(&item.name, item.count, "待卖", queued),
                    price,
                    queued,
                    false,
                    if let Some(slot_id) = item.equipped_slot_id.clone() {
                        GameUiButtonAction::QueueTradeEquippedSell {
                            shop_id: trade_snapshot.shop_id.clone(),
                            slot_id,
                        }
                    } else {
                        GameUiButtonAction::QueueTradeSell {
                            shop_id: trade_snapshot.shop_id.clone(),
                            item_id: item.item_id,
                        }
                    },
                    Some(GameUiButtonAction::AdjustTradeSell {
                        item_id: item.item_id,
                        source: source.clone(),
                        delta: -1,
                    }),
                    Some(GameUiButtonAction::RemoveTradeSell {
                        item_id: item.item_id,
                        source,
                    }),
                    Some(item.item_id),
                    is_drag_hover,
                );
            }
        });
}

#[allow(clippy::too_many_arguments)]
fn render_trade_item_row(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    label: &str,
    item_label: &str,
    unit_price: i32,
    queued: i32,
    buying: bool,
    row_action: GameUiButtonAction,
    decrease_action: Option<GameUiButtonAction>,
    remove_action: Option<GameUiButtonAction>,
    hover_item_id: Option<u32>,
    highlighted: bool,
) {
    let mut row = parent.spawn((
        Button,
        Node {
            width: Val::Percent(100.0),
            min_height: px(42),
            padding: UiRect::axes(px(10), px(7)),
            flex_direction: FlexDirection::Row,
            column_gap: px(9),
            align_items: AlignItems::Center,
            border: UiRect::all(px(if highlighted || queued > 0 { 2.0 } else { 1.0 })),
            ..default()
        },
        BackgroundColor(if queued > 0 {
            ui_panel_background_selected().into()
        } else if highlighted {
            Color::srgba(0.19, 0.18, 0.14, 0.98).into()
        } else {
            ui_panel_background_alt().into()
        }),
        BorderColor::all(if queued > 0 {
            ui_border_selected_color()
        } else if highlighted {
            Color::srgba(0.92, 0.80, 0.48, 1.0)
        } else {
            ui_border_color()
        }),
        row_action,
        RelativeCursorPosition::default(),
        viewer_ui_passthrough_bundle(),
    ));
    if let Some(item_id) = hover_item_id {
        row.insert(InventoryItemHoverTarget { item_id });
    }
    row.with_children(|row| {
        row.spawn((
            Node {
                width: px(26),
                height: px(26),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                border: UiRect::all(px(1)),
                flex_shrink: 0.0,
                ..default()
            },
            BackgroundColor(Color::srgba(0.16, 0.17, 0.16, 0.98).into()),
            BorderColor::all(ui_border_color()),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|icon| {
            icon.spawn((
                Text::new(label.to_string()),
                TextFont::from_font_size(10.0).with_font(font.0.clone()),
                TextColor(ui_text_secondary_color()),
                viewer_ui_passthrough_bundle(),
            ));
        });
        row.spawn((
            Text::new(item_label.to_string()),
            TextFont::from_font_size(11.0).with_font(font.0.clone()),
            TextColor(Color::WHITE),
            Node {
                flex_grow: 1.0,
                min_width: px(0),
                ..default()
            },
            viewer_ui_passthrough_bundle(),
        ));
        if queued > 0 {
            row.spawn((
                Text::new(if buying {
                    format!("待买 x{queued}")
                } else {
                    format!("待卖 x{queued}")
                }),
                TextFont::from_font_size(9.2).with_font(font.0.clone()),
                TextColor(Color::srgba(0.94, 0.84, 0.52, 1.0)),
                viewer_ui_passthrough_bundle(),
            ));
        }
        row.spawn((
            Text::new(format!("单价 {unit_price}")),
            TextFont::from_font_size(10.4).with_font(font.0.clone()),
            TextColor(ui_text_secondary_color()),
            Node {
                width: px(82),
                justify_content: JustifyContent::FlexEnd,
                ..default()
            },
            viewer_ui_passthrough_bundle(),
        ));
        if let Some(decrease_action) = decrease_action.filter(|_| queued > 0) {
            row.spawn(action_button(font, "-1", decrease_action));
        }
        if let Some(remove_action) = remove_action.filter(|_| queued > 0) {
            row.spawn(action_button(font, "移除", remove_action));
        }
    });
}

fn trade_item_count_label(name: &str, count: i32, pending_label: &str, queued: i32) -> String {
    if queued > 0 {
        format!("{name} x{count} · {pending_label} x{queued}")
    } else {
        format!("{name} x{count}")
    }
}

fn trade_item_icon_label(item_type: game_bevy::UiItemType, equipped: bool) -> &'static str {
    if equipped {
        return "E";
    }
    match item_type {
        game_bevy::UiItemType::Weapon => "武",
        game_bevy::UiItemType::Armor => "甲",
        game_bevy::UiItemType::Accessory => "饰",
        game_bevy::UiItemType::Consumable => "药",
        game_bevy::UiItemType::Material => "材",
        game_bevy::UiItemType::Ammo => "弹",
        game_bevy::UiItemType::Misc => "物",
    }
}

fn trade_unit_price_for_player_item(snapshot: &game_bevy::UiTradeSnapshot, item_id: u32) -> i32 {
    snapshot
        .player_items
        .iter()
        .find(|entry| entry.item_id == item_id)
        .map(|entry| entry.unit_price)
        .unwrap_or(0)
}

fn settlement_text(cart: &game_bevy::UiTradeCartState) -> String {
    let buy_total = cart.buy_total();
    let sell_total = cart.sell_total();
    let net = cart.net_payment();
    let settlement = if net > 0 {
        format!("玩家需支付 {net}")
    } else if net < 0 {
        format!("玩家将获得 {}", -net)
    } else {
        "无需支付".to_string()
    };
    format!("买入 {buy_total} · 卖出 {sell_total} · {settlement}")
}
