//! 负责构建装备区与物品列表的 Inventory 面板渲染。
use super::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::game_ui) enum InventoryPanelMode {
    Normal,
    Trade,
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
    parent.spawn(text_bundle(
        font,
        &format!(
            "负重 {:.1}/{:.1} · 筛选 {}",
            snapshot.total_weight,
            snapshot.max_weight,
            snapshot.filter.label()
        ),
        10.8,
        ui_text_secondary_color(),
    ));
    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                flex_grow: 1.0,
                flex_direction: FlexDirection::Column,
                row_gap: px(10),
                ..default()
            },
            InventoryPanelBounds,
            RelativeCursorPosition::default(),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|layout| {
            render_inventory_equipment_section(
                layout, font, snapshot, menu_state, drag_state, mode,
            );
            render_inventory_filter_row(layout, font, snapshot.filter);
            render_inventory_entry_section(layout, font, snapshot, menu_state, drag_state, mode);
        });
}

fn render_inventory_equipment_section(
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
                padding: UiRect::all(px(10)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(ui_panel_background_alt()),
            BorderColor::all(ui_border_color()),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|equipment| {
            equipment.spawn(text_bundle(font, "装备区", 11.4, ui_text_heading_color()));
            equipment.spawn(text_bundle(
                font,
                match mode {
                    InventoryPanelMode::Normal => "左键选择/交换装备槽，右键打开装备操作。",
                    InventoryPanelMode::Trade => "左键可换位/拖拽，右键可卸下或卖出当前装备。",
                },
                9.8,
                ui_text_muted_color(),
            ));
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
                        let is_selected = menu_state.selected_equipment_slot.as_deref()
                            == Some(slot.slot_id.as_str());
                        let is_drag_hover = matches!(
                            drag_state.hover_target.as_ref(),
                            Some(UiInventoryDragHoverTarget::EquipmentSlot { slot_id })
                                if slot_id == &slot.slot_id
                        );
                        let mut slot_entity = slots.spawn((
                            Button,
                            Node {
                                width: px(164),
                                min_height: px(62),
                                padding: UiRect::all(px(8)),
                                flex_direction: FlexDirection::Column,
                                justify_content: JustifyContent::SpaceBetween,
                                border: UiRect::all(px(if is_selected { 2.0 } else { 1.0 })),
                                ..default()
                            },
                            BackgroundColor(if is_selected {
                                ui_panel_background_selected().into()
                            } else if is_drag_hover {
                                Color::srgba(0.19, 0.18, 0.14, 0.98).into()
                            } else {
                                ui_panel_background_alt().into()
                            }),
                            BorderColor::all(if is_selected {
                                ui_border_selected_color()
                            } else if is_drag_hover {
                                Color::srgba(0.92, 0.80, 0.48, 1.0)
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
                filters.spawn(dock_tab_button(
                    font,
                    filter.label(),
                    active_filter == filter,
                    GameUiButtonAction::InventoryFilter(filter),
                ));
            }
        });
}

fn render_inventory_entry_section(
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
                padding: UiRect::all(px(10)),
                flex_direction: FlexDirection::Column,
                row_gap: px(4),
                border: UiRect::all(px(1)),
                overflow: Overflow::clip_y(),
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
            entries.spawn(text_bundle(font, "物品列表", 11.2, ui_text_heading_color()));
            entries.spawn(text_bundle(
                font,
                match mode {
                    InventoryPanelMode::Normal => "左键选中物品，右键打开可执行操作。",
                    InventoryPanelMode::Trade => {
                        "左键可重排/拖拽，右键可装备或卖出，拖到左侧商品区可直接卖出。"
                    }
                },
                9.8,
                ui_text_muted_color(),
            ));
            entries
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        flex_grow: 1.0,
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
                                flex_grow: 1.0,
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
                        let is_selected = menu_state.selected_inventory_item == Some(entry.item_id);
                        let is_drag_hover = matches!(
                            drag_state.hover_target.as_ref(),
                            Some(UiInventoryDragHoverTarget::InventoryItem { item_id })
                                if *item_id == entry.item_id
                        );
                        list.spawn((
                            Button,
                            Node {
                                width: Val::Percent(100.0),
                                padding: UiRect::axes(px(10), px(7)),
                                margin: UiRect::bottom(px(4)),
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
                                    ContextMenuStyle::for_variant(ContextMenuVariant::UiContext),
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
                    }
                });
        });
}
