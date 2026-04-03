//! 负责构建装备区与物品列表的 Inventory 面板渲染。
use super::*;

pub(super) fn render_inventory_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
) {
    let body = panel_body(parent, UiMenuPanel::Inventory);
    parent.commands().entity(body).with_children(|body| {
        body.spawn(text_bundle(
            font,
            &format!(
                "负重 {:.1}/{:.1} · 筛选 {}",
                snapshot.total_weight,
                snapshot.max_weight,
                snapshot.filter.label()
            ),
            10.8,
            Color::srgba(0.84, 0.88, 0.95, 1.0),
        ));
        body.spawn(Node {
            width: Val::Percent(100.0),
            flex_direction: FlexDirection::Column,
            row_gap: px(10),
            ..default()
        })
        .with_children(|layout| {
            layout
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
                        "左键选择/交换装备槽，右键打开装备操作。",
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
                                let is_selected = menu_state.selected_equipment_slot.as_deref()
                                    == Some(slot.slot_id.as_str());
                                slots
                                    .spawn((
                                        Button,
                                        Node {
                                            width: px(164),
                                            min_height: px(62),
                                            padding: UiRect::all(px(8)),
                                            flex_direction: FlexDirection::Column,
                                            justify_content: JustifyContent::SpaceBetween,
                                            border: UiRect::all(px(if is_selected {
                                                2.0
                                            } else {
                                                1.0
                                            })),
                                            ..default()
                                        },
                                        BackgroundColor(if is_selected {
                                            Color::srgba(0.16, 0.18, 0.27, 0.98).into()
                                        } else {
                                            Color::srgba(0.08, 0.09, 0.13, 0.95).into()
                                        }),
                                        BorderColor::all(if is_selected {
                                            Color::srgba(0.72, 0.76, 0.92, 1.0)
                                        } else {
                                            Color::srgba(0.22, 0.25, 0.33, 1.0)
                                        }),
                                        EquipmentSlotClickTarget {
                                            slot_id: slot.slot_id.clone(),
                                            item_id: slot.item_id,
                                        },
                                        RelativeCursorPosition::default(),
                                    ))
                                    .with_children(|slot_button| {
                                        slot_button.spawn(text_bundle(
                                            font,
                                            &slot.slot_label,
                                            9.5,
                                            Color::srgba(0.74, 0.78, 0.86, 1.0),
                                        ));
                                        slot_button.spawn(text_bundle(
                                            font,
                                            slot.item_name.as_deref().unwrap_or("空"),
                                            10.6,
                                            Color::WHITE,
                                        ));
                                    });
                            }
                        });
                });

            layout
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
                            snapshot.filter == filter,
                            GameUiButtonAction::InventoryFilter(filter),
                        ));
                    }
                });

            layout
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
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
                        "物品列表",
                        11.2,
                        Color::srgba(0.94, 0.96, 1.0, 1.0),
                    ));
                    entries.spawn(text_bundle(
                        font,
                        "左键选中物品，右键打开可执行操作。",
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
                            InventoryItemHoverTarget {
                                item_id: entry.item_id,
                            },
                            InventoryItemClickTarget {
                                item_id: entry.item_id,
                            },
                            RelativeCursorPosition::default(),
                        ));
                    }
                });
        });
    });
}
