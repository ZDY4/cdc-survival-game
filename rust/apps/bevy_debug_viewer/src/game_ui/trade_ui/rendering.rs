//! 交易页面渲染模块：负责交易主布局、玩家背包栏与商店栏的具体构建。

use super::*;

pub(super) fn render_trade_page(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    trade_snapshot: &game_bevy::UiTradeSnapshot,
    inventory_snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
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
                    BackgroundColor(Color::srgba(0.04, 0.045, 0.06, 0.985)),
                    BorderColor::all(Color::srgba(0.26, 0.30, 0.38, 1.0)),
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
                                Color::srgba(0.80, 0.85, 0.92, 1.0),
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
                    render_trade_inventory_column(
                        columns,
                        font,
                        trade_snapshot,
                        inventory_snapshot,
                        menu_state,
                    );
                    render_trade_shop_column(columns, font, trade_snapshot);
                });
        });
}

fn render_trade_inventory_column(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    trade_snapshot: &game_bevy::UiTradeSnapshot,
    inventory_snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
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
            BackgroundColor(Color::srgba(0.04, 0.045, 0.06, 0.98)),
            BorderColor::all(Color::srgba(0.22, 0.25, 0.33, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .with_children(|body| {
            body.spawn(text_bundle(
                font,
                &format!(
                    "玩家背包 · 负重 {:.1}/{:.1} · 当前筛选 {}",
                    inventory_snapshot.total_weight,
                    inventory_snapshot.max_weight,
                    inventory_snapshot.filter.label()
                ),
                11.0,
                Color::srgba(0.84, 0.88, 0.95, 1.0),
            ));
            body.spawn(text_bundle(
                font,
                "交易中左键仅用于选择要卖出的物品，不提供使用、装备或右键菜单。",
                9.8,
                Color::srgba(0.72, 0.76, 0.82, 1.0),
            ));

            render_trade_equipment_overview(body, font, inventory_snapshot);
            render_trade_inventory_filters(body, font, inventory_snapshot.filter);
            render_trade_inventory_entries(body, font, inventory_snapshot, menu_state);
            render_trade_sell_action(
                body,
                font,
                trade_snapshot,
                menu_state.selected_inventory_item,
            );
        });
}

fn render_trade_equipment_overview(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiInventoryPanelSnapshot,
) {
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                padding: UiRect::all(px(10)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.06, 0.07, 0.10, 0.96)),
            BorderColor::all(Color::srgba(0.19, 0.23, 0.30, 1.0)),
        ))
        .with_children(|equipment| {
            equipment.spawn(text_bundle(
                font,
                "装备区",
                11.4,
                Color::srgba(0.94, 0.96, 1.0, 1.0),
            ));
            equipment.spawn(text_bundle(
                font,
                "交易页仅展示当前装备状态。",
                9.8,
                Color::srgba(0.72, 0.76, 0.82, 1.0),
            ));
            if snapshot.equipment.is_empty() {
                equipment.spawn(text_bundle(
                    font,
                    "当前没有装备槽数据",
                    10.0,
                    Color::srgba(0.72, 0.76, 0.82, 1.0),
                ));
            }
            equipment
                .spawn(Node {
                    width: Val::Percent(100.0),
                    flex_wrap: FlexWrap::Wrap,
                    column_gap: px(8),
                    row_gap: px(8),
                    ..default()
                })
                .with_children(|slots| {
                    for slot in &snapshot.equipment {
                        slots
                            .spawn((
                                Node {
                                    width: px(176),
                                    min_height: px(62),
                                    padding: UiRect::all(px(8)),
                                    flex_direction: FlexDirection::Column,
                                    justify_content: JustifyContent::SpaceBetween,
                                    border: UiRect::all(px(1)),
                                    ..default()
                                },
                                BackgroundColor(Color::srgba(0.08, 0.09, 0.13, 0.95)),
                                BorderColor::all(Color::srgba(0.22, 0.25, 0.33, 1.0)),
                            ))
                            .with_children(|slot_card| {
                                slot_card.spawn(text_bundle(
                                    font,
                                    &slot.slot_label,
                                    9.5,
                                    Color::srgba(0.74, 0.78, 0.86, 1.0),
                                ));
                                slot_card.spawn(text_bundle(
                                    font,
                                    slot.item_name.as_deref().unwrap_or("空"),
                                    10.6,
                                    Color::WHITE,
                                ));
                            });
                    }
                });
        });
}

fn render_trade_inventory_filters(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    active_filter: UiInventoryFilter,
) {
    parent
        .spawn(Node {
            width: Val::Percent(100.0),
            flex_wrap: FlexWrap::Wrap,
            column_gap: px(6),
            row_gap: px(6),
            ..default()
        })
        .with_children(|filters| {
            for filter in [
                UiInventoryFilter::All,
                UiInventoryFilter::Weapon,
                UiInventoryFilter::Armor,
                UiInventoryFilter::Accessory,
                UiInventoryFilter::Consumable,
                UiInventoryFilter::Material,
                UiInventoryFilter::Ammo,
                UiInventoryFilter::Misc,
            ] {
                filters.spawn(dock_tab_button(
                    font,
                    filter.label(),
                    active_filter == filter,
                    GameUiButtonAction::InventoryFilter(filter),
                ));
            }
        });
}

fn render_trade_inventory_entries(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
) {
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                flex_grow: 1.0,
                padding: UiRect::all(px(10)),
                flex_direction: FlexDirection::Column,
                row_gap: px(4),
                border: UiRect::all(px(1)),
                overflow: Overflow::clip_y(),
                ..default()
            },
            BackgroundColor(Color::srgba(0.05, 0.06, 0.09, 0.97)),
            BorderColor::all(Color::srgba(0.19, 0.22, 0.30, 1.0)),
        ))
        .with_children(|entries| {
            entries.spawn(text_bundle(
                font,
                "可售物品",
                11.2,
                Color::srgba(0.94, 0.96, 1.0, 1.0),
            ));
            entries.spawn(text_bundle(
                font,
                "左键选中一件物品后，使用底部按钮卖出 x1。",
                9.8,
                Color::srgba(0.72, 0.76, 0.82, 1.0),
            ));
            if snapshot.entries.is_empty() {
                entries.spawn(text_bundle(
                    font,
                    "当前筛选下没有物品",
                    10.4,
                    Color::srgba(0.72, 0.76, 0.82, 1.0),
                ));
            }
            for entry in &snapshot.entries {
                let is_selected = menu_state.selected_inventory_item == Some(entry.item_id);
                entries.spawn((
                    Button,
                    Node {
                        width: Val::Percent(100.0),
                        padding: UiRect::axes(px(10), px(7)),
                        margin: UiRect::bottom(px(4)),
                        border: UiRect::all(px(if is_selected { 2.0 } else { 1.0 })),
                        align_items: AlignItems::Center,
                        ..default()
                    },
                    BackgroundColor(if is_selected {
                        Color::srgba(0.16, 0.22, 0.31, 0.98).into()
                    } else {
                        interaction_menu_button_color(false, Interaction::None).into()
                    }),
                    BorderColor::all(if is_selected {
                        Color::srgba(0.64, 0.76, 0.94, 1.0)
                    } else {
                        Color::srgba(0.19, 0.24, 0.32, 1.0)
                    }),
                    Text::new(format!(
                        "{} x{} · {} · {:.1}kg",
                        entry.name,
                        entry.count,
                        entry.item_type.as_str(),
                        entry.total_weight
                    )),
                    TextFont::from_font_size(11.0).with_font(font.0.clone()),
                    TextColor(Color::WHITE),
                    InventoryItemClickTarget {
                        item_id: entry.item_id,
                    },
                    RelativeCursorPosition::default(),
                ));
            }
        });
}

fn render_trade_sell_action(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiTradeSnapshot,
    selected_inventory_item: Option<u32>,
) {
    let selected_entry = selected_player_trade_entry(snapshot, selected_inventory_item);
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                padding: UiRect::all(px(10)),
                flex_direction: FlexDirection::Column,
                row_gap: px(6),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.05, 0.058, 0.076, 0.985)),
            BorderColor::all(Color::srgba(0.26, 0.31, 0.40, 1.0)),
        ))
        .with_children(|footer| {
            footer.spawn(text_bundle(
                font,
                &trade_sell_button_label(snapshot, selected_inventory_item),
                10.4,
                Color::srgba(0.82, 0.87, 0.95, 1.0),
            ));
            if let Some(entry) = selected_entry {
                footer.spawn(action_button(
                    font,
                    &format!("卖出 {} x1 · {} 货币", entry.name, entry.unit_price),
                    GameUiButtonAction::SellTradeItem {
                        shop_id: snapshot.shop_id.clone(),
                        item_id: entry.item_id,
                    },
                ));
            } else {
                footer
                    .spawn((
                        Node {
                            width: Val::Percent(100.0),
                            padding: UiRect::axes(px(10), px(7)),
                            border: UiRect::all(px(1)),
                            ..default()
                        },
                        BackgroundColor(Color::srgba(0.07, 0.08, 0.11, 0.90)),
                        BorderColor::all(Color::srgba(0.18, 0.21, 0.28, 1.0)),
                    ))
                    .with_children(|empty_state| {
                        empty_state.spawn(text_bundle(
                            font,
                            "卖出已选 x1",
                            11.0,
                            Color::srgba(0.52, 0.56, 0.63, 1.0),
                        ));
                    });
            }
        });
}

fn render_trade_shop_column(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiTradeSnapshot,
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
            BackgroundColor(Color::srgba(0.04, 0.045, 0.06, 0.98)),
            BorderColor::all(Color::srgba(0.22, 0.25, 0.33, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .with_children(|body| {
            body.spawn(text_bundle(
                font,
                "商品界面",
                11.4,
                Color::srgba(0.94, 0.96, 1.0, 1.0),
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
                Color::srgba(0.72, 0.76, 0.82, 1.0),
            ));
            body.spawn(text_bundle(
                font,
                "点击条目立即买入 x1。",
                9.8,
                Color::srgba(0.72, 0.76, 0.82, 1.0),
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
                BackgroundColor(Color::srgba(0.05, 0.06, 0.09, 0.97)),
                BorderColor::all(Color::srgba(0.19, 0.22, 0.30, 1.0)),
            ))
            .with_children(|items| {
                if snapshot.shop_items.is_empty() {
                    items.spawn(text_bundle(
                        font,
                        "商店库存为空",
                        10.4,
                        Color::srgba(0.72, 0.76, 0.82, 1.0),
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
                            BackgroundColor(Color::srgba(0.08, 0.09, 0.13, 0.95)),
                            BorderColor::all(Color::srgba(0.19, 0.24, 0.32, 1.0)),
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
                                Color::srgba(0.74, 0.79, 0.88, 1.0),
                            ));
                            entry.spawn(action_button(
                                font,
                                &format!("买入 {} x1", item.name),
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

pub(super) fn selected_player_trade_entry(
    snapshot: &game_bevy::UiTradeSnapshot,
    selected_inventory_item: Option<u32>,
) -> Option<&game_bevy::UiTradeEntryView> {
    let item_id = selected_inventory_item?;
    snapshot
        .player_items
        .iter()
        .find(|entry| entry.item_id == item_id && entry.count > 0)
}

pub(super) fn trade_sell_button_label(
    snapshot: &game_bevy::UiTradeSnapshot,
    selected_inventory_item: Option<u32>,
) -> String {
    match selected_player_trade_entry(snapshot, selected_inventory_item) {
        Some(entry) => format!(
            "已选中 {} · 库存 x{} · 预计卖出 {} 货币",
            entry.name, entry.count, entry.unit_price
        ),
        None if selected_inventory_item.is_some() => {
            "该物品当前不可交易，请重新选择一个可售物品".to_string()
        }
        None => "选择一个物品后，可在这里卖出 x1".to_string(),
    }
}
