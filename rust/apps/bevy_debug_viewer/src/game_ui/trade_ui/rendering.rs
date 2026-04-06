//! 交易页面渲染模块：负责交易主布局、玩家背包栏与商店栏的具体构建。

use super::*;

pub(super) fn render_trade_page(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
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
            UiMouseBlocker,
        ))
        .with_children(|overlay| {
            overlay
                .spawn((
                    Node {
                        position_type: PositionType::Absolute,
                        left: Val::Percent(50.0),
                        top: px(TRADE_PAGE_TOP),
                        margin: UiRect {
                            left: px(-((TRADE_PAGE_LEFT_WIDTH
                                + TRADE_PAGE_RIGHT_WIDTH
                                + TRADE_PAGE_GAP)
                                / 2.0)),
                            ..default()
                        },
                        width: px(TRADE_PAGE_LEFT_WIDTH + TRADE_PAGE_RIGHT_WIDTH + TRADE_PAGE_GAP),
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
                    UiMouseBlocker,
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
                    header.spawn(action_button(
                        font,
                        "关闭交易",
                        GameUiButtonAction::CloseTrade,
                    ));
                });

            overlay
                .spawn(Node {
                    position_type: PositionType::Absolute,
                    left: Val::Percent(50.0),
                    top: px(TRADE_PAGE_TOP + 74.0),
                    bottom: px(TRADE_PAGE_BOTTOM),
                    margin: UiRect {
                        left: px(-((TRADE_PAGE_LEFT_WIDTH
                            + TRADE_PAGE_RIGHT_WIDTH
                            + TRADE_PAGE_GAP)
                            / 2.0)),
                        ..default()
                    },
                    width: px(TRADE_PAGE_LEFT_WIDTH + TRADE_PAGE_RIGHT_WIDTH + TRADE_PAGE_GAP),
                    flex_direction: FlexDirection::Row,
                    column_gap: px(TRADE_PAGE_GAP),
                    ..default()
                })
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
                });
        });
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
            TradeInventoryPanelBounds,
            UiMouseBlocker,
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
            UiMouseBlocker,
        ))
        .with_children(|body| {
            body.spawn(text_bundle(
                font,
                "商品界面",
                11.4,
                ui_text_heading_color(),
            ));
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
                "点击条目买入；可堆叠物品会先选择数量。",
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
                        ))
                        .with_children(|entry| {
                            entry.spawn(text_bundle(font, &item.name, 10.8, Color::WHITE));
                            entry.spawn(text_bundle(
                                font,
                                &format!(
                                    "库存 x{} · 单价 {} · 总重 {:.1}kg",
                                    item.count, item.unit_price, item.total_weight
                                ),
                                9.4,
                                ui_text_muted_color(),
                            ));
                            entry.spawn(action_button(
                                font,
                                &format!("买入 {}", item.name),
                                GameUiButtonAction::BuyTradeItem {
                                    shop_id: snapshot.shop_id.clone(),
                                    item_id: item.item_id,
                                },
                            ));
                        });
                }
            });
        });
}

