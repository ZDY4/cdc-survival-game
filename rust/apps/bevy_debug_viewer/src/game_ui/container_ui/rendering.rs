//! 容器页面渲染：双栏展示玩家背包与容器库存。

use super::*;

pub(super) fn render_container_page(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    container_snapshot: &game_bevy::UiContainerSnapshot,
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
        ))
        .with_children(|overlay| {
            overlay
                .spawn((
                    Node {
                        position_type: PositionType::Absolute,
                        left: Val::Percent(50.0),
                        top: px(CONTAINER_PAGE_TOP),
                        margin: UiRect {
                            left: px(-((CONTAINER_PAGE_LEFT_WIDTH
                                + CONTAINER_PAGE_RIGHT_WIDTH
                                + CONTAINER_PAGE_GAP)
                                / 2.0)),
                            ..default()
                        },
                        width: px(
                            CONTAINER_PAGE_LEFT_WIDTH
                                + CONTAINER_PAGE_RIGHT_WIDTH
                                + CONTAINER_PAGE_GAP,
                        ),
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
                                &format!("容器 · {}", container_snapshot.display_name),
                                15.2,
                                Color::WHITE,
                            ));
                            titles.spawn(text_bundle(
                                font,
                                &format!(
                                    "容器 ID {} · {} 种物品",
                                    container_snapshot.container_id,
                                    container_snapshot.item_kind_count
                                ),
                                10.4,
                                ui_text_secondary_color(),
                            ));
                        });
                    header.spawn(action_button(
                        font,
                        "关闭容器",
                        GameUiButtonAction::CloseContainer,
                    ));
                });

            overlay
                .spawn((
                    Node {
                        position_type: PositionType::Absolute,
                        left: Val::Percent(50.0),
                        top: px(CONTAINER_PAGE_TOP + 74.0),
                        bottom: px(CONTAINER_PAGE_BOTTOM),
                        margin: UiRect {
                            left: px(-((CONTAINER_PAGE_LEFT_WIDTH
                                + CONTAINER_PAGE_RIGHT_WIDTH
                                + CONTAINER_PAGE_GAP)
                                / 2.0)),
                            ..default()
                        },
                        width: px(
                            CONTAINER_PAGE_LEFT_WIDTH
                                + CONTAINER_PAGE_RIGHT_WIDTH
                                + CONTAINER_PAGE_GAP,
                        ),
                        flex_direction: FlexDirection::Row,
                        column_gap: px(CONTAINER_PAGE_GAP),
                        ..default()
                    },
                    viewer_ui_passthrough_bundle(),
                ))
                .with_children(|columns| {
                    render_container_inventory_column(
                        columns,
                        font,
                        inventory_snapshot,
                        menu_state,
                        drag_state,
                        &container_snapshot.container_id,
                    );
                    render_container_stock_column(columns, font, container_snapshot, drag_state);
                });
        });
}

fn render_container_inventory_column(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    inventory_snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
    drag_state: &UiInventoryDragState,
    container_id: &str,
) {
    parent
        .spawn((
            Node {
                width: px(CONTAINER_PAGE_LEFT_WIDTH),
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
            InventoryPanelBounds,
            viewer_ui_passthrough_bundle(),
            UiMouseBlocker,
        ))
        .with_children(|body| {
            render_inventory_panel_contents(
                body,
                font,
                inventory_snapshot,
                menu_state,
                drag_state,
                InventoryPanelMode::Container {
                    container_id: container_id.to_string(),
                },
            );
        });
}

fn render_container_stock_column(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiContainerSnapshot,
    drag_state: &UiInventoryDragState,
) {
    let list_hover = matches!(
        drag_state.hover_target,
        Some(UiInventoryDragHoverTarget::ContainerListEnd)
    );
    parent
        .spawn((
            Node {
                width: px(CONTAINER_PAGE_RIGHT_WIDTH),
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
            ContainerInventoryPanelBounds,
            viewer_ui_passthrough_bundle(),
            UiMouseBlocker,
        ))
        .with_children(|body| {
            body.spawn(text_bundle(font, "容器库存", 11.4, ui_text_heading_color()));
            body.spawn(text_bundle(
                font,
                &format!(
                    "{} · 物品 {} 种",
                    snapshot.display_name, snapshot.item_kind_count
                ),
                9.8,
                ui_text_muted_color(),
            ));
            body.spawn(text_bundle(
                font,
                "点击取出；堆叠物品会先选择数量，也可直接拖回背包。",
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
                    border: UiRect::all(px(if list_hover { 2.0 } else { 1.0 })),
                    overflow: Overflow::clip_y(),
                    ..default()
                },
                BackgroundColor(ui_panel_background()),
                BorderColor::all(if list_hover {
                    Color::srgba(0.92, 0.80, 0.48, 1.0)
                } else {
                    ui_border_color()
                }),
                ContainerInventoryListDropZone,
                RelativeCursorPosition::default(),
                viewer_ui_passthrough_bundle(),
            ))
            .with_children(|items| {
                if snapshot.entries.is_empty() {
                    items.spawn(text_bundle(font, "容器为空", 10.4, ui_text_muted_color()));
                }
                for entry in &snapshot.entries {
                    let is_drag_hover = matches!(
                        drag_state.hover_target.as_ref(),
                        Some(UiInventoryDragHoverTarget::ContainerItem { item_id })
                            if *item_id == entry.item_id
                    );
                    items
                        .spawn((
                            Node {
                                width: Val::Percent(100.0),
                                flex_direction: FlexDirection::Row,
                                column_gap: px(6),
                                align_items: AlignItems::Stretch,
                                ..default()
                            },
                            viewer_ui_passthrough_bundle(),
                        ))
                        .with_children(|row| {
                            row.spawn((
                                Button,
                                Node {
                                    flex_grow: 1.0,
                                    min_width: px(0),
                                    padding: UiRect::all(px(10)),
                                    flex_direction: FlexDirection::Column,
                                    row_gap: px(6),
                                    border: UiRect::all(px(if is_drag_hover { 2.0 } else { 1.0 })),
                                    ..default()
                                },
                                BackgroundColor(if is_drag_hover {
                                    Color::srgba(0.19, 0.18, 0.14, 0.98).into()
                                } else {
                                    ui_panel_background_alt().into()
                                }),
                                BorderColor::all(if is_drag_hover {
                                    Color::srgba(0.92, 0.80, 0.48, 1.0)
                                } else {
                                    ui_border_color()
                                }),
                                InventoryItemHoverTarget {
                                    item_id: entry.item_id,
                                },
                                ContainerInventoryItemClickTarget {
                                    item_id: entry.item_id,
                                },
                                RelativeCursorPosition::default(),
                                viewer_ui_passthrough_bundle(),
                            ))
                            .with_children(|entry_button| {
                                entry_button.spawn(text_bundle(
                                    font,
                                    &entry.name,
                                    10.8,
                                    Color::WHITE,
                                ));
                                entry_button.spawn(text_bundle(
                                    font,
                                    &format!(
                                        "库存 x{} · 总重 {:.1}kg",
                                        entry.count, entry.total_weight
                                    ),
                                    9.4,
                                    ui_text_muted_color(),
                                ));
                            });
                            row.spawn(action_button(
                                font,
                                "取出",
                                GameUiButtonAction::TakeContainerItem {
                                    container_id: snapshot.container_id.clone(),
                                    item_id: entry.item_id,
                                },
                            ));
                        });
                }
            });
        });
}
