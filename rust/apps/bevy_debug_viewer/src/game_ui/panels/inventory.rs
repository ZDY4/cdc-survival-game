//! 负责构建装备区与物品列表的 Inventory 面板渲染。
use super::*;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(in crate::game_ui) enum InventoryPanelMode {
    Normal,
    Trade,
    Container { container_id: String },
}

pub(super) fn render_inventory_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
    drag_state: &UiInventoryDragState,
) {
    let body = panel_body(parent, UiMenuPanel::Inventory);
    parent.commands().entity(body).with_children(|body| {
        render_inventory_panel_contents(
            body,
            font,
            snapshot,
            menu_state,
            drag_state,
            InventoryPanelMode::Normal,
        );
    });
}

pub(in crate::game_ui) fn render_inventory_panel_contents(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
    drag_state: &UiInventoryDragState,
    mode: InventoryPanelMode,
) {
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                flex_grow: 1.0,
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                ..default()
            },
            InventoryPanelBounds,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|layout| {
            render_inventory_equipment_section(
                layout, font, snapshot, menu_state, drag_state, &mode,
            );
            render_inventory_filter_row(layout, font, snapshot.filter);
            render_inventory_entry_section(layout, font, snapshot, menu_state, drag_state, &mode);
        });
    parent.spawn(text_bundle(
        font,
        &format!(
            "负重 {:.1}/{:.1}",
            snapshot.total_weight, snapshot.max_weight
        ),
        10.4,
        ui_text_secondary_color(),
    ));
}

fn render_inventory_equipment_section(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiInventoryPanelSnapshot,
    _menu_state: &UiMenuState,
    drag_state: &UiInventoryDragState,
    _mode: &InventoryPanelMode,
) {
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                padding: UiRect::all(px(8)),
                flex_direction: FlexDirection::Column,
                row_gap: px(6),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(ui_panel_background_alt()),
            BorderColor::all(ui_border_color()),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|equipment| {
            if snapshot.equipment.is_empty() {
                equipment.spawn(text_bundle(
                    font,
                    "当前没有装备槽数据",
                    10.0,
                    ui_text_muted_color(),
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
                        let is_compatible_target = drag_state.is_active()
                            && drag_state.supports_equipment_slot(&slot.slot_id)
                            && !drag_state.is_source_equipment_slot(&slot.slot_id);
                        let is_drag_hover = matches!(
                            drag_state.hover_target.as_ref(),
                            Some(UiInventoryDragHoverTarget::EquipmentSlot { slot_id })
                                if slot_id == &slot.slot_id
                        );
                        let mut slot_entity = slots.spawn((
                            Button,
                            Node {
                                width: px(140),
                                min_height: px(62),
                                padding: UiRect::all(px(8)),
                                flex_direction: FlexDirection::Column,
                                row_gap: px(4),
                                border: UiRect::all(px(if is_drag_hover { 2.0 } else { 1.0 })),
                                ..default()
                            },
                            BackgroundColor(if is_drag_hover {
                                Color::srgba(0.19, 0.18, 0.14, 0.98).into()
                            } else if is_compatible_target {
                                Color::srgba(0.12, 0.16, 0.12, 0.98).into()
                            } else {
                                ui_panel_background_alt().into()
                            }),
                            BorderColor::all(if is_drag_hover {
                                Color::srgba(0.92, 0.80, 0.48, 1.0)
                            } else if is_compatible_target {
                                Color::srgba(0.44, 0.76, 0.48, 0.98)
                            } else {
                                ui_border_color()
                            }),
                            EquipmentSlotClickTarget {
                                slot_id: slot.slot_id.clone(),
                                item_id: slot.item_id,
                            },
                            RelativeCursorPosition::default(),
                            viewer_ui_passthrough_bundle(),
                        ));
                        if let Some(item_id) = slot.item_id {
                            slot_entity.insert(InventoryItemHoverTarget { item_id });
                        }
                        slot_entity.with_children(|slot_button| {
                            slot_button.spawn(text_bundle(
                                font,
                                &slot.slot_label,
                                9.5,
                                ui_text_muted_color(),
                            ));
                            slot_button.spawn(text_bundle(
                                font,
                                slot.item_name.as_deref().unwrap_or("空"),
                                10.6,
                                Color::WHITE,
                            ));
                            if is_drag_hover || is_compatible_target {
                                slot_button.spawn(text_bundle(
                                    font,
                                    if is_drag_hover {
                                        "松开放入"
                                    } else {
                                        "可放入"
                                    },
                                    8.8,
                                    if is_drag_hover {
                                        Color::srgba(0.97, 0.90, 0.66, 1.0)
                                    } else {
                                        Color::srgba(0.72, 0.92, 0.74, 0.98)
                                    },
                                ));
                            }
                        });
                    }
                });
        });
}

fn render_inventory_filter_row(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    active_filter: UiInventoryFilter,
) {
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                flex_wrap: FlexWrap::Wrap,
                column_gap: px(6),
                row_gap: px(6),
                ..default()
            },
            viewer_ui_passthrough_bundle(),
        ))
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
                let active = active_filter == filter;
                filters
                    .spawn((
                        Button,
                        Node {
                            min_width: px(46),
                            height: px(22),
                            padding: UiRect::axes(px(8), px(2)),
                            border: UiRect::all(px(if active { 2.0 } else { 1.0 })),
                            justify_content: JustifyContent::Center,
                            align_items: AlignItems::Center,
                            ..default()
                        },
                        BackgroundColor(if active {
                            ui_panel_background_selected().into()
                        } else {
                            ui_panel_background_alt().into()
                        }),
                        BorderColor::all(if active {
                            ui_border_selected_color()
                        } else {
                            ui_border_color()
                        }),
                        GameUiButtonAction::InventoryFilter(filter),
                        viewer_ui_passthrough_bundle(),
                    ))
                    .with_children(|button| {
                        button.spawn((
                            Text::new(filter.label().to_string()),
                            TextFont::from_font_size(8.3).with_font(font.0.clone()),
                            TextColor(if active {
                                Color::WHITE
                            } else {
                                ui_text_secondary_color()
                            }),
                            TextLayout::new(
                                bevy::text::Justify::Center,
                                bevy::text::LineBreak::NoWrap,
                            ),
                            viewer_ui_passthrough_bundle(),
                        ));
                    });
            }
        });
}

fn render_inventory_entry_section(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiInventoryPanelSnapshot,
    menu_state: &UiMenuState,
    drag_state: &UiInventoryDragState,
    mode: &InventoryPanelMode,
) {
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                flex_grow: 1.0,
                padding: UiRect::all(px(8)),
                flex_direction: FlexDirection::Row,
                column_gap: px(8),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(ui_panel_background()),
            BorderColor::all(
                if matches!(
                    drag_state.hover_target,
                    Some(UiInventoryDragHoverTarget::InventoryListEnd)
                ) {
                    Color::srgba(0.92, 0.80, 0.48, 1.0)
                } else {
                    ui_border_color()
                },
            ),
            InventoryListDropZone,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|entries| {
            entries
                .spawn((
                    Node {
                        flex_grow: 1.0,
                        flex_basis: px(0),
                        min_width: px(0),
                        height: Val::Percent(100.0),
                        padding: UiRect::right(px(4)),
                        flex_direction: FlexDirection::Column,
                        overflow: Overflow::scroll_y(),
                        ..default()
                    },
                    ScrollPosition::default(),
                    InventoryEntryScrollArea,
                    RelativeCursorPosition::default(),
                    viewer_ui_passthrough_bundle(),
                ))
                .with_children(|list| {
                    list.spawn((
                        Node {
                            width: Val::Percent(100.0),
                            flex_direction: FlexDirection::Column,
                            ..default()
                        },
                        viewer_ui_passthrough_bundle(),
                    ))
                    .with_children(|list| {
                        if snapshot.entries.is_empty() {
                            list.spawn((
                                Node {
                                    width: Val::Percent(100.0),
                                    min_height: px(180),
                                    justify_content: JustifyContent::Center,
                                    align_items: AlignItems::Center,
                                    ..default()
                                },
                                viewer_ui_passthrough_bundle(),
                            ))
                            .with_children(|empty| {
                                empty.spawn(text_bundle(
                                    font,
                                    "当前筛选下没有物品",
                                    10.4,
                                    ui_text_muted_color(),
                                ));
                            });
                        }
                        for entry in &snapshot.entries {
                            let is_selected =
                                menu_state.selected_inventory_item == Some(entry.item_id);
                            let is_drag_hover = matches!(
                                drag_state.hover_target.as_ref(),
                                Some(UiInventoryDragHoverTarget::InventoryItem { item_id })
                                    if *item_id == entry.item_id
                            );
                            list.spawn((
                                Node {
                                    width: Val::Percent(100.0),
                                    margin: UiRect::bottom(px(4)),
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
                                        padding: UiRect::axes(px(10), px(7)),
                                        border: UiRect::all(px(if is_selected || is_drag_hover {
                                            2.0
                                        } else {
                                            1.0
                                        })),
                                        align_items: AlignItems::Center,
                                        ..default()
                                    },
                                    BackgroundColor(if is_selected {
                                        ui_panel_background_selected().into()
                                    } else if is_drag_hover {
                                        Color::srgba(0.19, 0.18, 0.14, 0.98).into()
                                    } else {
                                        context_menu_button_color(
                                            ContextMenuStyle::for_variant(
                                                ContextMenuVariant::UiContext,
                                            ),
                                            false,
                                            false,
                                            Interaction::None,
                                        )
                                        .into()
                                    }),
                                    BorderColor::all(if is_selected {
                                        ui_border_selected_color()
                                    } else if is_drag_hover {
                                        Color::srgba(0.92, 0.80, 0.48, 1.0)
                                    } else {
                                        ui_border_color()
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
                                    viewer_ui_passthrough_bundle(),
                                ));

                                if let InventoryPanelMode::Container { container_id } = mode {
                                    row.spawn(action_button(
                                        font,
                                        "存入",
                                        GameUiButtonAction::StoreContainerItem {
                                            container_id: container_id.clone(),
                                            item_id: entry.item_id,
                                        },
                                    ));
                                }
                            });
                        }
                    });
                });
            entries
                .spawn((
                    Node {
                        width: px(6),
                        height: Val::Percent(100.0),
                        position_type: PositionType::Relative,
                        ..default()
                    },
                    BackgroundColor(Color::srgba(0.13, 0.13, 0.12, 0.92)),
                    Visibility::Visible,
                    InventoryEntryScrollbarTrack,
                    viewer_ui_passthrough_bundle(),
                ))
                .with_children(|track| {
                    track.spawn((
                        Node {
                            position_type: PositionType::Absolute,
                            left: px(0),
                            right: px(0),
                            top: px(0),
                            height: px(24),
                            ..default()
                        },
                        BackgroundColor(Color::srgba(0.72, 0.71, 0.68, 0.9)),
                        Visibility::Visible,
                        InventoryEntryScrollbarThumb,
                        viewer_ui_passthrough_bundle(),
                    ));
                });
        });
}
