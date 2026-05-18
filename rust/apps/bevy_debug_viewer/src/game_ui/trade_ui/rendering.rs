//! 交易页面渲染模块：负责交易主布局、玩家背包栏与商店栏的具体构建。

use super::*;

pub(super) fn render_trade_page(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    trade: &game_bevy::UiTradeSessionState,
    trade_snapshot: &game_bevy::UiTradeSnapshot,
    inventory_snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
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
                            flex_direction: FlexDirection::Column,
                            row_gap: px(4),
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
                                    "友好度 {} · 玩家资金 {} · 商店资金 {}",
                                    trade_snapshot.relation_score,
                                    trade_snapshot.player_money,
                                    trade_snapshot.shop_money
                                ),
                                10.4,
                                ui_text_secondary_color(),
                            ));
                        });
                    header.spawn(close_icon_button(font, GameUiButtonAction::CloseTrade));
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
                    render_trade_shop_column(columns, font, trade_snapshot, drag_state);
                    render_trade_inventory_column(
                        columns,
                        font,
                        trade_snapshot,
                        inventory_snapshot,
                        menu_state,
                        drag_state,
                    );
                    render_trade_cart_column(columns, font, trade, trade_snapshot);
                });
        });
}

fn trade_page_width() -> f32 {
    TRADE_PAGE_LEFT_WIDTH + TRADE_PAGE_MIDDLE_WIDTH + TRADE_PAGE_RIGHT_WIDTH + TRADE_PAGE_GAP * 2.0
}

fn render_trade_inventory_column(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    _trade_snapshot: &game_bevy::UiTradeSnapshot,
    inventory_snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
    drag_state: &UiInventoryDragState,
) {
    parent
        .spawn((
            Node {
                width: px(TRADE_PAGE_MIDDLE_WIDTH),
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
            render_inventory_panel_contents(
                body,
                font,
                inventory_snapshot,
                menu_state,
                drag_state,
                InventoryPanelMode::Trade,
            );
        });
}

fn render_trade_shop_column(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
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
            body.spawn(text_bundle(font, "商品界面", 11.4, ui_text_heading_color()));
            body.spawn(text_bundle(
                font,
                &format!(
                    "{} · 库存 {} 种 · 商店资金 {}",
                    snapshot.shop_id,
                    snapshot.shop_items.len(),
                    snapshot.shop_money
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
                    items
                        .spawn((
                            Button,
                            Node {
                                width: Val::Percent(100.0),
                                padding: UiRect::all(px(10)),
                                flex_direction: FlexDirection::Column,
                                row_gap: px(6),
                                border: UiRect::all(px(1)),
                                ..default()
                            },
                            BackgroundColor(ui_panel_background_alt()),
                            BorderColor::all(ui_border_color()),
                            GameUiButtonAction::QueueTradeBuy {
                                shop_id: snapshot.shop_id.clone(),
                                item_id: item.item_id,
                            },
                            viewer_ui_passthrough_bundle(),
                        ))
                        .with_children(|entry| {
                            entry.spawn(text_bundle(font, &item.name, 10.8, Color::WHITE));
                            entry.spawn(text_bundle(
                                font,
                                &format!(
                                    "库存 x{} · 单价 {} · 总重 {:.1}kg · 点击加入",
                                    item.count, item.unit_price, item.total_weight
                                ),
                                9.4,
                                ui_text_muted_color(),
                            ));
                        });
                }
            });
        });
}

fn render_trade_cart_column(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    trade: &game_bevy::UiTradeSessionState,
    snapshot: &game_bevy::UiTradeSnapshot,
) {
    let cart = &trade.cart;
    parent
        .spawn((
            Node {
                width: px(TRADE_PAGE_LEFT_WIDTH),
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
            viewer_ui_passthrough_bundle(),
            UiMouseBlocker,
            UiMouseBlockerName("交易结算栏".to_string()),
        ))
        .with_children(|body| {
            body.spawn(text_bundle(font, "待交易", 11.4, ui_text_heading_color()));
            body.spawn(text_bundle(
                font,
                "确认前不会改变背包或商店库存。",
                9.6,
                ui_text_muted_color(),
            ));
            render_trade_cart_lines(body, font, "待买入", true, cart);
            render_trade_cart_lines(body, font, "待卖出", false, cart);
            render_trade_totals(body, font, cart, snapshot);
            body.spawn((
                Node {
                    width: Val::Percent(100.0),
                    flex_direction: FlexDirection::Row,
                    column_gap: px(8),
                    ..default()
                },
                viewer_ui_passthrough_bundle(),
            ))
            .with_children(|actions| {
                actions.spawn(action_button(
                    font,
                    "确认交易",
                    GameUiButtonAction::ConfirmTradeCart,
                ));
                actions.spawn(action_button(
                    font,
                    "清空",
                    GameUiButtonAction::ClearTradeCart,
                ));
            });
        });
}

fn render_trade_cart_lines(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    title: &str,
    buy_lines: bool,
    cart: &game_bevy::UiTradeCartState,
) {
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                min_height: px(92),
                padding: UiRect::all(px(8)),
                flex_direction: FlexDirection::Column,
                row_gap: px(6),
                border: UiRect::all(px(1)),
                overflow: Overflow::clip_y(),
                ..default()
            },
            BackgroundColor(ui_panel_background_alt()),
            BorderColor::all(ui_border_color()),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|section| {
            section.spawn(text_bundle(font, title, 10.4, ui_text_heading_color()));
            if buy_lines {
                if cart.buy_lines.is_empty() {
                    section.spawn(text_bundle(font, "暂无待买入", 9.4, ui_text_muted_color()));
                }
                for line in &cart.buy_lines {
                    render_buy_cart_line(section, font, line);
                }
            } else {
                if cart.sell_lines.is_empty() {
                    section.spawn(text_bundle(font, "暂无待卖出", 9.4, ui_text_muted_color()));
                }
                for line in &cart.sell_lines {
                    render_sell_cart_line(section, font, line);
                }
            }
        });
}

fn render_buy_cart_line(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    line: &game_bevy::UiTradeCartBuyLine,
) {
    render_cart_line(
        parent,
        font,
        &format!(
            "{} x{} · {}",
            line.name,
            line.count,
            line.count * line.unit_price
        ),
        GameUiButtonAction::AdjustTradeBuy {
            item_id: line.item_id,
            delta: -1,
        },
        GameUiButtonAction::RemoveTradeBuy {
            item_id: line.item_id,
        },
    );
}

fn render_sell_cart_line(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    line: &game_bevy::UiTradeCartSellLine,
) {
    let marker = match &line.source {
        game_bevy::UiTradeCartSellSource::Inventory => "",
        game_bevy::UiTradeCartSellSource::Equipped { .. } => " [E]",
    };
    render_cart_line(
        parent,
        font,
        &format!(
            "{}{} x{} · {}",
            line.name,
            marker,
            line.count,
            line.count * line.unit_price
        ),
        GameUiButtonAction::AdjustTradeSell {
            item_id: line.item_id,
            source: line.source.clone(),
            delta: -1,
        },
        GameUiButtonAction::RemoveTradeSell {
            item_id: line.item_id,
            source: line.source.clone(),
        },
    );
}

fn render_cart_line(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    label: &str,
    decrease_action: GameUiButtonAction,
    remove_action: GameUiButtonAction,
) {
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                flex_direction: FlexDirection::Row,
                column_gap: px(6),
                align_items: AlignItems::Center,
                ..default()
            },
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|row| {
            row.spawn((
                Text::new(label.to_string()),
                TextFont::from_font_size(9.6).with_font(font.0.clone()),
                TextColor(Color::WHITE),
                Node {
                    flex_grow: 1.0,
                    min_width: px(0),
                    ..default()
                },
                viewer_ui_passthrough_bundle(),
            ));
            row.spawn(action_button(font, "-1", decrease_action));
            row.spawn(action_button(font, "移除", remove_action));
        });
}

fn render_trade_totals(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    cart: &game_bevy::UiTradeCartState,
    snapshot: &game_bevy::UiTradeSnapshot,
) {
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
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                padding: UiRect::all(px(10)),
                flex_direction: FlexDirection::Column,
                row_gap: px(5),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(ui_panel_background_alt()),
            BorderColor::all(ui_border_strong_color()),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|totals| {
            totals.spawn(text_bundle(
                font,
                &format!("买入合计 {buy_total} · 卖出合计 {sell_total}"),
                9.8,
                ui_text_secondary_color(),
            ));
            totals.spawn(text_bundle(font, &settlement, 11.2, Color::WHITE));
            totals.spawn(text_bundle(
                font,
                &format!(
                    "玩家资金 {} · 商店资金 {}",
                    snapshot.player_money, snapshot.shop_money
                ),
                9.4,
                ui_text_muted_color(),
            ));
        });
}
