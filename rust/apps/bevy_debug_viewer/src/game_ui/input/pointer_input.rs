//! UI 指针输入：负责背包点击、右键菜单、装备选择和拖拽分发。

use super::button_actions::{
    execute_inventory_drop, execute_trade_sell, plan_container_store, plan_container_take,
    plan_inventory_drop, plan_trade_sell, ContainerQuantityPlan, InventoryDropPlan,
    TradeQuantityPlan,
};
use super::*;

const INVENTORY_DRAG_THRESHOLD: f32 = 8.0;

#[derive(SystemParam)]
pub(crate) struct InventoryPointerUiState<'w, 's> {
    scene_kind: Res<'w, ViewerSceneKind>,
    menu_state: ResMut<'w, UiMenuState>,
    modal_state: ResMut<'w, UiModalState>,
    context_menu: ResMut<'w, UiContextMenuState>,
    drag_state: ResMut<'w, UiInventoryDragState>,
    scrollbar_drag_state: ResMut<'w, UiInventoryScrollbarDragState>,
    runtime_state: ResMut<'w, ViewerRuntimeState>,
    viewer_state: ResMut<'w, ViewerState>,
    save_path: Res<'w, ViewerRuntimeSavePath>,
    items: Res<'w, ItemDefinitions>,
    marker: PhantomData<&'s ()>,
}

#[derive(SystemParam)]
pub(crate) struct InventoryPointerTargets<'w, 's> {
    inventory_targets: Query<
        'w,
        's,
        (
            &'static InventoryItemClickTarget,
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<Button>,
    >,
    trade_inventory_targets: Query<
        'w,
        's,
        (
            &'static TradeInventoryItemClickTarget,
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<Button>,
    >,
    container_inventory_targets: Query<
        'w,
        's,
        (
            &'static ContainerInventoryItemClickTarget,
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<Button>,
    >,
    equipment_targets: Query<
        'w,
        's,
        (
            &'static EquipmentSlotClickTarget,
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<Button>,
    >,
    skill_targets: Query<
        'w,
        's,
        (
            &'static SkillHoverTarget,
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<Button>,
    >,
    context_menu_roots: Query<
        'w,
        's,
        (
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<UiContextMenuRoot>,
    >,
    inventory_panel_bounds: Query<
        'w,
        's,
        (
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<InventoryPanelBounds>,
    >,
    inventory_list_drop_zones: Query<
        'w,
        's,
        (
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<InventoryListDropZone>,
    >,
    trade_panel_bounds: Query<
        'w,
        's,
        (
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<TradeInventoryPanelBounds>,
    >,
    trade_list_drop_zones: Query<
        'w,
        's,
        (
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<TradeInventoryListDropZone>,
    >,
    container_panel_bounds: Query<
        'w,
        's,
        (
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<ContainerInventoryPanelBounds>,
    >,
    container_list_drop_zones: Query<
        'w,
        's,
        (
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<ContainerInventoryListDropZone>,
    >,
    trade_sell_zones: Query<
        'w,
        's,
        (
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        With<TradeSellZone>,
    >,
    inventory_scroll_areas: Query<
        'w,
        's,
        (
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
            &'static mut ScrollPosition,
        ),
        With<InventoryEntryScrollArea>,
    >,
    inventory_scrollbar_tracks: Query<
        'w,
        's,
        (
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        (
            With<InventoryEntryScrollbarTrack>,
            Without<InventoryEntryScrollbarThumb>,
        ),
    >,
    inventory_scrollbar_thumbs: Query<
        'w,
        's,
        (
            &'static ComputedNode,
            &'static UiGlobalTransform,
            Option<&'static RelativeCursorPosition>,
            Option<&'static Visibility>,
        ),
        (
            With<InventoryEntryScrollbarThumb>,
            Without<InventoryEntryScrollbarTrack>,
        ),
    >,
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn handle_inventory_panel_pointer_input(
    window: Single<&Window>,
    buttons: Res<ButtonInput<MouseButton>>,
    mut ui: InventoryPointerUiState,
    mut targets: InventoryPointerTargets,
) {
    let trade_active = ui.modal_state.trade.is_some();
    let container_active = ui.modal_state.container.is_some();
    let item_modal_open = ui.modal_state.item_quantity.is_some();
    let inventory_panel_active = ui.menu_state.is_panel_open(UiMenuPanel::Inventory);
    let skills_panel_active =
        !trade_active && !container_active && ui.menu_state.is_panel_open(UiMenuPanel::Skills);
    if ui.scene_kind.is_main_menu() {
        ui.context_menu.clear();
        ui.drag_state.clear();
        ui.scrollbar_drag_state.clear();
        return;
    }
    if item_modal_open {
        ui.context_menu.clear();
        ui.drag_state.clear();
        ui.scrollbar_drag_state.clear();
        return;
    }
    if !trade_active && !container_active && !inventory_panel_active && !skills_panel_active {
        ui.context_menu.clear();
        ui.drag_state.clear();
        ui.scrollbar_drag_state.clear();
        return;
    }

    let left_just_pressed = buttons.just_pressed(MouseButton::Left);
    let left_pressed = buttons.pressed(MouseButton::Left);
    let left_just_released = buttons.just_released(MouseButton::Left);
    let right_just_pressed = buttons.just_pressed(MouseButton::Right);
    if !left_just_pressed
        && !left_just_released
        && !right_just_pressed
        && !ui.drag_state.is_active()
        && !ui.scrollbar_drag_state.is_active()
    {
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        ui.context_menu.clear();
        ui.drag_state.clear();
        ui.scrollbar_drag_state.clear();
        return;
    };

    ui.drag_state.cursor_position = cursor_position;

    if handle_inventory_scrollbar_pointer_input(
        cursor_position,
        &buttons,
        inventory_panel_active && !trade_active && !container_active,
        &mut ui.scrollbar_drag_state,
        &mut targets,
    ) {
        if left_just_pressed {
            ui.context_menu.clear();
        }
        return;
    }

    let inventory_hit = find_inventory_click_target(cursor_position, &targets.inventory_targets);
    let trade_inventory_hit =
        find_trade_inventory_click_target(cursor_position, &targets.trade_inventory_targets);
    let container_item_hit = find_container_inventory_click_target(
        cursor_position,
        &targets.container_inventory_targets,
    );
    let effective_inventory_hit = inventory_hit.or(trade_inventory_hit);
    let equipment_hit = targets.equipment_targets.iter().find_map(
        |(target, computed, transform, cursor, visibility)| {
            hover_target_contains_cursor(cursor_position, computed, transform, cursor, visibility)
                .then_some(target.clone())
        },
    );
    let clicked_context_menu =
        targets
            .context_menu_roots
            .iter()
            .any(|(computed, transform, cursor, visibility)| {
                hover_target_contains_cursor(
                    cursor_position,
                    computed,
                    transform,
                    cursor,
                    visibility,
                )
            });

    let skill_hit = skills_panel_active
        .then(|| find_skill_hover_target(cursor_position, &targets.skill_targets))
        .flatten();
    if let Some((tree_id, skill_id)) = skill_hit {
        if right_just_pressed {
            ui.menu_state.selected_skill_tree_id = Some(tree_id.clone());
            ui.menu_state.selected_skill_id = Some(skill_id.clone());
            ui.context_menu.visible = true;
            ui.context_menu.cursor_position = cursor_position;
            ui.context_menu.target = Some(UiContextMenuTarget::SkillEntry { tree_id, skill_id });
        }
        if buttons.just_pressed(MouseButton::Left) && !clicked_context_menu {
            ui.context_menu.clear();
        }
        ui.drag_state.clear();
        ui.scrollbar_drag_state.clear();
        return;
    }
    let cursor_in_inventory_panel =
        targets
            .inventory_panel_bounds
            .iter()
            .any(|(computed, transform, cursor, visibility)| {
                hover_target_contains_cursor(
                    cursor_position,
                    computed,
                    transform,
                    cursor,
                    visibility,
                )
            });
    let cursor_in_inventory_list = targets.inventory_list_drop_zones.iter().any(
        |(computed, transform, cursor, visibility)| {
            hover_target_contains_cursor(cursor_position, computed, transform, cursor, visibility)
        },
    );
    let cursor_in_trade_panel =
        targets
            .trade_panel_bounds
            .iter()
            .any(|(computed, transform, cursor, visibility)| {
                hover_target_contains_cursor(
                    cursor_position,
                    computed,
                    transform,
                    cursor,
                    visibility,
                )
            });
    let _cursor_in_trade_list =
        targets
            .trade_list_drop_zones
            .iter()
            .any(|(computed, transform, cursor, visibility)| {
                hover_target_contains_cursor(
                    cursor_position,
                    computed,
                    transform,
                    cursor,
                    visibility,
                )
            });
    let cursor_in_trade_sell_zone =
        targets
            .trade_sell_zones
            .iter()
            .any(|(computed, transform, cursor, visibility)| {
                hover_target_contains_cursor(
                    cursor_position,
                    computed,
                    transform,
                    cursor,
                    visibility,
                )
            });
    let cursor_in_container_panel =
        targets
            .container_panel_bounds
            .iter()
            .any(|(computed, transform, cursor, visibility)| {
                hover_target_contains_cursor(
                    cursor_position,
                    computed,
                    transform,
                    cursor,
                    visibility,
                )
            });
    let cursor_in_container_list = targets.container_list_drop_zones.iter().any(
        |(computed, transform, cursor, visibility)| {
            hover_target_contains_cursor(cursor_position, computed, transform, cursor, visibility)
        },
    );

    if right_just_pressed {
        if ui.drag_state.is_active() {
            ui.context_menu.clear();
            return;
        }
        if container_active {
            if let Some(item_id) = container_item_hit {
                ui.context_menu.visible = true;
                ui.context_menu.cursor_position = cursor_position;
                ui.context_menu.target = Some(UiContextMenuTarget::ContainerItem { item_id });
                return;
            }
        }
        if let Some(item_id) = effective_inventory_hit {
            ui.menu_state.selected_inventory_item = Some(item_id);
            ui.menu_state.selected_equipment_slot = None;
            ui.context_menu.visible = true;
            ui.context_menu.cursor_position = cursor_position;
            ui.context_menu.target = Some(UiContextMenuTarget::InventoryItem { item_id });
            return;
        }
        if let Some(target) = equipment_hit.as_ref() {
            if let Some(item_id) = target.item_id {
                ui.context_menu.visible = true;
                ui.context_menu.cursor_position = cursor_position;
                ui.context_menu.target = Some(UiContextMenuTarget::EquipmentSlot {
                    slot_id: target.slot_id.clone(),
                    item_id,
                });
            } else {
                ui.context_menu.clear();
            }
            return;
        }
        if !clicked_context_menu {
            ui.context_menu.clear();
        }
        return;
    }

    if left_just_pressed && !ui.drag_state.is_active() {
        if container_active {
            if let Some(item_id) = effective_inventory_hit {
                begin_inventory_drag(
                    &mut ui.drag_state,
                    UiInventoryDragSource::InventoryItem { item_id },
                    item_preview_label(&ui.items.0, item_id),
                    item_allowed_equipment_slots(&ui.items.0, item_id),
                    cursor_position,
                );
                ui.context_menu.clear();
                return;
            }
            if let Some(item_id) = container_item_hit {
                let Some(container_id) = ui
                    .modal_state
                    .container
                    .as_ref()
                    .map(|container| container.container_id.clone())
                else {
                    return;
                };
                begin_inventory_drag(
                    &mut ui.drag_state,
                    UiInventoryDragSource::ContainerItem {
                        container_id,
                        item_id,
                    },
                    item_preview_label(&ui.items.0, item_id),
                    item_allowed_equipment_slots(&ui.items.0, item_id),
                    cursor_position,
                );
                ui.context_menu.clear();
                return;
            }
        } else if trade_active {
            if let Some(item_id) = effective_inventory_hit {
                begin_inventory_drag(
                    &mut ui.drag_state,
                    UiInventoryDragSource::InventoryItem { item_id },
                    item_preview_label(&ui.items.0, item_id),
                    item_allowed_equipment_slots(&ui.items.0, item_id),
                    cursor_position,
                );
                ui.context_menu.clear();
                return;
            }
            if let Some(target) = equipment_hit.as_ref() {
                if let Some(item_id) = target.item_id {
                    begin_inventory_drag(
                        &mut ui.drag_state,
                        UiInventoryDragSource::EquipmentSlot {
                            slot_id: target.slot_id.clone(),
                            item_id,
                        },
                        item_preview_label(&ui.items.0, item_id),
                        item_allowed_equipment_slots(&ui.items.0, item_id),
                        cursor_position,
                    );
                    ui.context_menu.clear();
                    return;
                }
            }
        } else {
            if let Some(item_id) = effective_inventory_hit {
                begin_inventory_drag(
                    &mut ui.drag_state,
                    UiInventoryDragSource::InventoryItem { item_id },
                    item_preview_label(&ui.items.0, item_id),
                    item_allowed_equipment_slots(&ui.items.0, item_id),
                    cursor_position,
                );
                ui.context_menu.clear();
                return;
            }
            if let Some(target) = equipment_hit.as_ref() {
                if let Some(item_id) = target.item_id {
                    begin_inventory_drag(
                        &mut ui.drag_state,
                        UiInventoryDragSource::EquipmentSlot {
                            slot_id: target.slot_id.clone(),
                            item_id,
                        },
                        item_preview_label(&ui.items.0, item_id),
                        item_allowed_equipment_slots(&ui.items.0, item_id),
                        cursor_position,
                    );
                    ui.context_menu.clear();
                    return;
                }
            }
        }
    }

    if ui.drag_state.is_active() && left_pressed {
        if !ui.drag_state.dragging
            && ui
                .drag_state
                .press_cursor_position
                .distance(cursor_position)
                >= INVENTORY_DRAG_THRESHOLD
        {
            ui.drag_state.dragging = true;
            ui.context_menu.clear();
        }
        if ui.drag_state.dragging {
            ui.drag_state.hover_target = resolve_drag_hover_target(
                &ui.drag_state,
                trade_active,
                container_active,
                effective_inventory_hit,
                container_item_hit,
                equipment_hit.as_ref(),
                cursor_in_inventory_list,
                cursor_in_container_list,
                cursor_in_trade_sell_zone,
            );
        }
    }

    if !left_just_released {
        return;
    }

    if !ui.drag_state.is_active() {
        handle_click_release(
            trade_active,
            container_active,
            &mut ui.menu_state,
            &mut ui.context_menu,
            &mut ui.runtime_state,
            &ui.save_path,
            &ui.items,
            effective_inventory_hit,
            container_item_hit,
            equipment_hit.as_ref(),
            clicked_context_menu,
        );
        return;
    }

    let source = ui.drag_state.active_source.clone();
    let hover_target = ui.drag_state.hover_target.clone();
    let was_dragging = ui.drag_state.dragging;
    ui.drag_state.clear();

    let Some(source) = source else {
        return;
    };

    if !was_dragging {
        handle_click_release(
            trade_active,
            container_active,
            &mut ui.menu_state,
            &mut ui.context_menu,
            &mut ui.runtime_state,
            &ui.save_path,
            &ui.items,
            effective_inventory_hit,
            container_item_hit,
            equipment_hit.as_ref(),
            clicked_context_menu,
        );
        return;
    }

    let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) else {
        return;
    };

    let mut applied_drop = false;

    match source {
        UiInventoryDragSource::InventoryItem { item_id } => {
            if container_active {
                if let Some(container_id) = ui
                    .modal_state
                    .container
                    .as_ref()
                    .map(|container| container.container_id.clone())
                {
                    match hover_target {
                        Some(UiInventoryDragHoverTarget::InventoryItem { item_id: before })
                            if before != item_id =>
                        {
                            applied_drop = apply_inventory_reorder(
                                &mut ui.runtime_state,
                                &mut ui.menu_state,
                                &ui.save_path,
                                actor_id,
                                item_id,
                                Some(before),
                            );
                        }
                        Some(UiInventoryDragHoverTarget::InventoryListEnd) => {
                            applied_drop = apply_inventory_reorder(
                                &mut ui.runtime_state,
                                &mut ui.menu_state,
                                &ui.save_path,
                                actor_id,
                                item_id,
                                None,
                            );
                        }
                        Some(UiInventoryDragHoverTarget::ContainerItem { item_id: before }) => {
                            applied_drop = apply_container_store(
                                &mut ui.runtime_state,
                                &mut ui.viewer_state,
                                &mut ui.menu_state,
                                &mut ui.modal_state,
                                &ui.save_path,
                                &ui.items,
                                actor_id,
                                &container_id,
                                item_id,
                                Some(before),
                            );
                        }
                        Some(UiInventoryDragHoverTarget::ContainerListEnd) => {
                            applied_drop = apply_container_store(
                                &mut ui.runtime_state,
                                &mut ui.viewer_state,
                                &mut ui.menu_state,
                                &mut ui.modal_state,
                                &ui.save_path,
                                &ui.items,
                                actor_id,
                                &container_id,
                                item_id,
                                None,
                            );
                        }
                        _ => {}
                    }
                }
            } else if trade_active {
                if let Some(trade_shop_id) = ui
                    .modal_state
                    .trade
                    .as_ref()
                    .map(|trade| trade.shop_id.clone())
                {
                    match hover_target {
                        Some(UiInventoryDragHoverTarget::InventoryItem { item_id: before })
                            if before != item_id =>
                        {
                            applied_drop = apply_inventory_reorder(
                                &mut ui.runtime_state,
                                &mut ui.menu_state,
                                &ui.save_path,
                                actor_id,
                                item_id,
                                Some(before),
                            );
                        }
                        Some(UiInventoryDragHoverTarget::InventoryListEnd) => {
                            applied_drop = apply_inventory_reorder(
                                &mut ui.runtime_state,
                                &mut ui.menu_state,
                                &ui.save_path,
                                actor_id,
                                item_id,
                                None,
                            );
                        }
                        Some(UiInventoryDragHoverTarget::TradeSellZone) => {
                            applied_drop = apply_trade_sell(
                                &mut ui.runtime_state,
                                &mut ui.viewer_state,
                                &mut ui.menu_state,
                                &mut ui.modal_state,
                                &ui.save_path,
                                &ui.items,
                                actor_id,
                                &trade_shop_id,
                                item_id,
                            );
                        }
                        Some(UiInventoryDragHoverTarget::EquipmentSlot { slot_id }) => {
                            applied_drop = apply_inventory_equip(
                                &mut ui.runtime_state,
                                &mut ui.menu_state,
                                &ui.save_path,
                                actor_id,
                                item_id,
                                &slot_id,
                                &ui.items,
                            );
                        }
                        _ => {}
                    }
                }
            } else {
                match hover_target {
                    Some(UiInventoryDragHoverTarget::InventoryItem { item_id: before })
                        if before != item_id =>
                    {
                        applied_drop = apply_inventory_reorder(
                            &mut ui.runtime_state,
                            &mut ui.menu_state,
                            &ui.save_path,
                            actor_id,
                            item_id,
                            Some(before),
                        );
                    }
                    Some(UiInventoryDragHoverTarget::InventoryListEnd) => {
                        applied_drop = apply_inventory_reorder(
                            &mut ui.runtime_state,
                            &mut ui.menu_state,
                            &ui.save_path,
                            actor_id,
                            item_id,
                            None,
                        );
                    }
                    Some(UiInventoryDragHoverTarget::EquipmentSlot { slot_id }) => {
                        applied_drop = apply_inventory_equip(
                            &mut ui.runtime_state,
                            &mut ui.menu_state,
                            &ui.save_path,
                            actor_id,
                            item_id,
                            &slot_id,
                            &ui.items,
                        );
                    }
                    _ if !cursor_in_inventory_panel => {
                        applied_drop = apply_inventory_drop(
                            &mut ui.runtime_state,
                            &mut ui.viewer_state,
                            &mut ui.menu_state,
                            &mut ui.modal_state,
                            &ui.save_path,
                            &ui.items,
                            actor_id,
                            item_id,
                        );
                    }
                    _ => {}
                }
            }
        }
        UiInventoryDragSource::ContainerItem {
            ref container_id,
            item_id,
        } => {
            if container_active {
                match hover_target {
                    Some(UiInventoryDragHoverTarget::InventoryItem {
                        item_id: before_item_id,
                    }) => {
                        applied_drop = apply_container_take(
                            &mut ui.runtime_state,
                            &mut ui.viewer_state,
                            &mut ui.menu_state,
                            &mut ui.modal_state,
                            &ui.save_path,
                            &ui.items,
                            actor_id,
                            container_id,
                            item_id,
                            Some(before_item_id),
                        );
                    }
                    Some(UiInventoryDragHoverTarget::InventoryListEnd) => {
                        applied_drop = apply_container_take(
                            &mut ui.runtime_state,
                            &mut ui.viewer_state,
                            &mut ui.menu_state,
                            &mut ui.modal_state,
                            &ui.save_path,
                            &ui.items,
                            actor_id,
                            container_id,
                            item_id,
                            None,
                        );
                    }
                    _ => {}
                }
            }
        }
        UiInventoryDragSource::EquipmentSlot {
            ref slot_id,
            item_id,
        } => match hover_target {
            Some(UiInventoryDragHoverTarget::EquipmentSlot {
                slot_id: target_slot,
            }) => {
                applied_drop = apply_equipment_move(
                    &mut ui.runtime_state,
                    &mut ui.menu_state,
                    &ui.save_path,
                    actor_id,
                    &slot_id,
                    &target_slot,
                    &ui.items,
                );
            }
            Some(UiInventoryDragHoverTarget::InventoryItem {
                item_id: before_item_id,
            }) => {
                applied_drop = apply_equipment_unequip_and_reorder(
                    &mut ui.runtime_state,
                    &mut ui.menu_state,
                    &ui.save_path,
                    actor_id,
                    &slot_id,
                    item_id,
                    Some(before_item_id),
                );
            }
            Some(UiInventoryDragHoverTarget::InventoryListEnd) => {
                applied_drop = apply_equipment_unequip_and_reorder(
                    &mut ui.runtime_state,
                    &mut ui.menu_state,
                    &ui.save_path,
                    actor_id,
                    &slot_id,
                    item_id,
                    None,
                );
            }
            Some(UiInventoryDragHoverTarget::TradeSellZone) if trade_active => {
                if let Some(trade) = ui.modal_state.trade.as_ref() {
                    applied_drop = apply_trade_equipped_sell(
                        &mut ui.runtime_state,
                        &mut ui.viewer_state,
                        &mut ui.menu_state,
                        &ui.save_path,
                        &ui.items,
                        actor_id,
                        &trade.shop_id,
                        &slot_id,
                        item_id,
                    );
                }
            }
            _ if !trade_active && !container_active && !cursor_in_inventory_panel => {
                applied_drop = apply_equipped_drop(
                    &mut ui.runtime_state,
                    &mut ui.viewer_state,
                    &mut ui.menu_state,
                    &ui.save_path,
                    &ui.items,
                    actor_id,
                    &slot_id,
                    item_id,
                );
            }
            _ => {}
        },
    }

    if applied_drop {
        ui.drag_state.suppress_button_press_once = true;
        ui.menu_state.selected_inventory_item = match &source {
            UiInventoryDragSource::InventoryItem { item_id } => Some(*item_id),
            UiInventoryDragSource::ContainerItem { .. } => ui.menu_state.selected_inventory_item,
            UiInventoryDragSource::EquipmentSlot { .. } => ui.menu_state.selected_inventory_item,
        };
        ui.menu_state.selected_equipment_slot = None;
    }

    let _ = cursor_in_trade_panel;
    let _ = cursor_in_container_panel;
}

pub(super) fn find_inventory_hover_target(
    cursor_position: Vec2,
    targets: &Query<
        (
            &InventoryItemHoverTarget,
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<Button>,
    >,
) -> Option<u32> {
    targets
        .iter()
        .find_map(|(target, computed, transform, cursor, visibility)| {
            hover_target_contains_cursor(cursor_position, computed, transform, cursor, visibility)
                .then_some(target.item_id)
        })
}

pub(super) fn find_inventory_click_target(
    cursor_position: Vec2,
    targets: &Query<
        (
            &InventoryItemClickTarget,
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<Button>,
    >,
) -> Option<u32> {
    targets
        .iter()
        .find_map(|(target, computed, transform, cursor, visibility)| {
            hover_target_contains_cursor(cursor_position, computed, transform, cursor, visibility)
                .then_some(target.item_id)
        })
}

pub(super) fn find_trade_inventory_click_target(
    cursor_position: Vec2,
    targets: &Query<
        (
            &TradeInventoryItemClickTarget,
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<Button>,
    >,
) -> Option<u32> {
    targets
        .iter()
        .find_map(|(target, computed, transform, cursor, visibility)| {
            hover_target_contains_cursor(cursor_position, computed, transform, cursor, visibility)
                .then_some(target.item_id)
        })
}

pub(super) fn find_container_inventory_click_target(
    cursor_position: Vec2,
    targets: &Query<
        (
            &ContainerInventoryItemClickTarget,
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<Button>,
    >,
) -> Option<u32> {
    targets
        .iter()
        .find_map(|(target, computed, transform, cursor, visibility)| {
            hover_target_contains_cursor(cursor_position, computed, transform, cursor, visibility)
                .then_some(target.item_id)
        })
}

pub(super) fn find_skill_hover_target(
    cursor_position: Vec2,
    targets: &Query<
        (
            &SkillHoverTarget,
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<Button>,
    >,
) -> Option<(String, String)> {
    targets
        .iter()
        .find_map(|(target, computed, transform, cursor, visibility)| {
            hover_target_contains_cursor(cursor_position, computed, transform, cursor, visibility)
                .then(|| (target.tree_id.clone(), target.skill_id.clone()))
        })
}

pub(super) fn hover_target_contains_cursor(
    cursor_position: Vec2,
    computed: &ComputedNode,
    transform: &UiGlobalTransform,
    cursor: Option<&RelativeCursorPosition>,
    visibility: Option<&Visibility>,
) -> bool {
    if visibility.is_some_and(|visibility| *visibility == Visibility::Hidden) {
        return false;
    }

    cursor.is_some_and(RelativeCursorPosition::cursor_over)
        || computed.contains_point(*transform, cursor_position)
}

fn begin_inventory_drag(
    drag_state: &mut UiInventoryDragState,
    source: UiInventoryDragSource,
    preview_label: String,
    allowed_equipment_slots: Vec<String>,
    cursor_position: Vec2,
) {
    drag_state.active_source = Some(source);
    drag_state.hover_target = None;
    drag_state.press_cursor_position = cursor_position;
    drag_state.cursor_position = cursor_position;
    drag_state.dragging = false;
    drag_state.preview_label = preview_label;
    drag_state.allowed_equipment_slots = allowed_equipment_slots;
}

fn resolve_drag_hover_target(
    drag_state: &UiInventoryDragState,
    trade_active: bool,
    container_active: bool,
    inventory_hit: Option<u32>,
    container_item_hit: Option<u32>,
    equipment_hit: Option<&EquipmentSlotClickTarget>,
    cursor_in_inventory_list: bool,
    cursor_in_container_list: bool,
    cursor_in_trade_sell_zone: bool,
) -> Option<UiInventoryDragHoverTarget> {
    if trade_active {
        if cursor_in_trade_sell_zone {
            return Some(UiInventoryDragHoverTarget::TradeSellZone);
        }
        if let Some(target) = equipment_hit {
            if drag_state.supports_equipment_slot(&target.slot_id)
                && !drag_state.is_source_equipment_slot(&target.slot_id)
            {
                return Some(UiInventoryDragHoverTarget::EquipmentSlot {
                    slot_id: target.slot_id.clone(),
                });
            }
        }
        if let Some(item_id) = inventory_hit {
            return Some(UiInventoryDragHoverTarget::InventoryItem { item_id });
        }
        if cursor_in_inventory_list {
            return Some(UiInventoryDragHoverTarget::InventoryListEnd);
        }
        return None;
    }

    if container_active {
        if let Some(item_id) = container_item_hit {
            return Some(UiInventoryDragHoverTarget::ContainerItem { item_id });
        }
        if let Some(item_id) = inventory_hit {
            return Some(UiInventoryDragHoverTarget::InventoryItem { item_id });
        }
        if cursor_in_container_list {
            return Some(UiInventoryDragHoverTarget::ContainerListEnd);
        }
        if cursor_in_inventory_list {
            return Some(UiInventoryDragHoverTarget::InventoryListEnd);
        }
        return None;
    }

    if let Some(target) = equipment_hit {
        if drag_state.supports_equipment_slot(&target.slot_id)
            && !drag_state.is_source_equipment_slot(&target.slot_id)
        {
            return Some(UiInventoryDragHoverTarget::EquipmentSlot {
                slot_id: target.slot_id.clone(),
            });
        }
    }
    if let Some(item_id) = inventory_hit {
        return Some(UiInventoryDragHoverTarget::InventoryItem { item_id });
    }
    if cursor_in_inventory_list {
        return Some(UiInventoryDragHoverTarget::InventoryListEnd);
    }
    None
}

fn item_allowed_equipment_slots(items: &game_data::ItemLibrary, item_id: u32) -> Vec<String> {
    items
        .get(item_id)
        .map(|definition| {
            definition
                .fragments
                .iter()
                .filter_map(|fragment| match fragment {
                    game_data::ItemFragment::Equip { slots, .. } => Some(slots.clone()),
                    _ => None,
                })
                .flatten()
                .collect()
        })
        .unwrap_or_default()
}

#[allow(clippy::too_many_arguments)]
fn handle_click_release(
    trade_active: bool,
    container_active: bool,
    menu_state: &mut UiMenuState,
    context_menu: &mut UiContextMenuState,
    _runtime_state: &mut ViewerRuntimeState,
    _save_path: &ViewerRuntimeSavePath,
    _items: &ItemDefinitions,
    inventory_hit: Option<u32>,
    container_item_hit: Option<u32>,
    equipment_hit: Option<&EquipmentSlotClickTarget>,
    clicked_context_menu: bool,
) {
    if let Some(item_id) = inventory_hit {
        menu_state.selected_inventory_item = Some(item_id);
        menu_state.selected_equipment_slot = None;
        context_menu.clear();
        return;
    }

    if let Some(target) = equipment_hit {
        context_menu.clear();
        let _ = target;
        menu_state.selected_equipment_slot = None;
        return;
    }

    if container_active && container_item_hit.is_some() {
        context_menu.clear();
        return;
    }

    if !trade_active && !clicked_context_menu {
        context_menu.clear();
    } else if trade_active && !clicked_context_menu {
        context_menu.clear();
    }
}

pub(crate) fn handle_inventory_list_mouse_wheel(
    window: Single<&Window>,
    menu_state: Res<UiMenuState>,
    modal_state: Res<UiModalState>,
    scene_kind: Res<ViewerSceneKind>,
    mut mouse_wheel_events: MessageReader<bevy::input::mouse::MouseWheel>,
    mut scroll_areas: Query<
        (
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
            &mut ScrollPosition,
        ),
        With<InventoryEntryScrollArea>,
    >,
) {
    if scene_kind.is_main_menu()
        || modal_state.item_quantity.is_some()
        || (modal_state.container.is_none() && !menu_state.is_panel_open(UiMenuPanel::Inventory))
    {
        for _ in mouse_wheel_events.read() {}
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        for _ in mouse_wheel_events.read() {}
        return;
    };

    let Some((computed, _transform, _cursor, _visibility, mut scroll_position)) = scroll_areas
        .iter_mut()
        .find(|(computed, transform, cursor, visibility, _)| {
            hover_target_contains_cursor(cursor_position, computed, transform, *cursor, *visibility)
        })
    else {
        for _ in mouse_wheel_events.read() {}
        return;
    };

    let max_scroll =
        (computed.content_size.y - computed.size.y + computed.scrollbar_size.y).max(0.0);
    if max_scroll <= f32::EPSILON {
        for _ in mouse_wheel_events.read() {}
        return;
    }

    let mut scroll_delta = 0.0f32;
    for event in mouse_wheel_events.read() {
        scroll_delta += match event.unit {
            bevy::input::mouse::MouseScrollUnit::Line => event.y * 36.0,
            bevy::input::mouse::MouseScrollUnit::Pixel => event.y,
        };
    }
    if scroll_delta.abs() <= f32::EPSILON {
        return;
    }

    scroll_position.y = (scroll_position.y - scroll_delta).clamp(0.0, max_scroll);
}

#[derive(Debug, Clone, Copy)]
struct InventoryScrollbarMetrics {
    max_scroll: f32,
    thumb_height: f32,
    travel: f32,
}

fn handle_inventory_scrollbar_pointer_input(
    cursor_position: Vec2,
    buttons: &ButtonInput<MouseButton>,
    inventory_panel_active: bool,
    scrollbar_drag_state: &mut UiInventoryScrollbarDragState,
    targets: &mut InventoryPointerTargets,
) -> bool {
    if !inventory_panel_active {
        let consumed = scrollbar_drag_state.is_active() && buttons.just_released(MouseButton::Left);
        scrollbar_drag_state.clear();
        return consumed;
    }

    let Ok((scroll_area, _, _, _, mut scroll_position)) =
        targets.inventory_scroll_areas.single_mut()
    else {
        scrollbar_drag_state.clear();
        return false;
    };
    let Ok((track, track_transform, track_cursor, track_visibility)) =
        targets.inventory_scrollbar_tracks.single()
    else {
        scrollbar_drag_state.clear();
        return false;
    };
    let Ok((thumb, thumb_transform, thumb_cursor, thumb_visibility)) =
        targets.inventory_scrollbar_thumbs.single()
    else {
        scrollbar_drag_state.clear();
        return false;
    };

    let Some(metrics) = inventory_scrollbar_metrics(scroll_area, track) else {
        scrollbar_drag_state.clear();
        return false;
    };

    let left_just_pressed = buttons.just_pressed(MouseButton::Left);
    let left_pressed = buttons.pressed(MouseButton::Left);
    let left_just_released = buttons.just_released(MouseButton::Left);
    let thumb_hit = hover_target_contains_cursor(
        cursor_position,
        thumb,
        thumb_transform,
        thumb_cursor,
        thumb_visibility,
    );
    let track_hit = hover_target_contains_cursor(
        cursor_position,
        track,
        track_transform,
        track_cursor,
        track_visibility,
    );

    if left_just_pressed {
        if thumb_hit {
            scrollbar_drag_state.active = true;
            scrollbar_drag_state.grab_offset_y =
                cursor_offset_within_node_y(thumb, thumb_transform, cursor_position)
                    .unwrap_or(metrics.thumb_height * 0.5)
                    .clamp(0.0, metrics.thumb_height);
            return true;
        }
        if track_hit {
            scrollbar_drag_state.active = true;
            scrollbar_drag_state.grab_offset_y = metrics.thumb_height * 0.5;
            set_inventory_scroll_position_from_track_cursor(
                &mut scroll_position,
                track,
                track_transform,
                cursor_position,
                scrollbar_drag_state.grab_offset_y,
                metrics,
            );
            return true;
        }
    }

    if left_just_released {
        let consumed = scrollbar_drag_state.is_active();
        scrollbar_drag_state.clear();
        return consumed;
    }

    if !scrollbar_drag_state.is_active() {
        return false;
    }

    if !left_pressed {
        scrollbar_drag_state.clear();
        return false;
    }

    set_inventory_scroll_position_from_track_cursor(
        &mut scroll_position,
        track,
        track_transform,
        cursor_position,
        scrollbar_drag_state.grab_offset_y,
        metrics,
    );
    true
}

fn inventory_scrollbar_metrics(
    scroll_area: &ComputedNode,
    track: &ComputedNode,
) -> Option<InventoryScrollbarMetrics> {
    let viewport_height = scroll_area.size.y.max(0.0);
    let content_height = scroll_area.content_size.y.max(0.0);
    let track_height = track.size.y.max(0.0);
    let max_scroll = (content_height - viewport_height + scroll_area.scrollbar_size.y).max(0.0);
    let can_scroll = max_scroll > 0.5 && track_height > 0.0 && content_height > f32::EPSILON;
    if !can_scroll {
        return None;
    }

    let visible_ratio = (viewport_height / content_height).clamp(0.0, 1.0);
    let thumb_height = (track_height * visible_ratio).clamp(24.0, track_height);
    let travel = (track_height - thumb_height).max(0.0);
    Some(InventoryScrollbarMetrics {
        max_scroll,
        thumb_height,
        travel,
    })
}

fn cursor_offset_within_node_y(
    computed: &ComputedNode,
    transform: &UiGlobalTransform,
    cursor_position: Vec2,
) -> Option<f32> {
    computed
        .normalize_point(*transform, cursor_position)
        .map(|normalized| (normalized.y + 0.5) * computed.size.y)
}

fn set_inventory_scroll_position_from_track_cursor(
    scroll_position: &mut ScrollPosition,
    track: &ComputedNode,
    track_transform: &UiGlobalTransform,
    cursor_position: Vec2,
    grab_offset_y: f32,
    metrics: InventoryScrollbarMetrics,
) {
    let Some(cursor_y_in_track) =
        cursor_offset_within_node_y(track, track_transform, cursor_position)
    else {
        return;
    };

    let thumb_top = (cursor_y_in_track - grab_offset_y).clamp(0.0, metrics.travel);
    scroll_position.y = if metrics.travel <= f32::EPSILON {
        0.0
    } else {
        metrics.max_scroll * (thumb_top / metrics.travel)
    };
}

pub(crate) fn sync_inventory_list_scrollbar(
    mut tracks: Query<
        (&ComputedNode, &mut Visibility),
        (
            With<InventoryEntryScrollbarTrack>,
            Without<InventoryEntryScrollbarThumb>,
        ),
    >,
    mut thumbs: Query<
        (&mut Node, &mut Visibility),
        (
            With<InventoryEntryScrollbarThumb>,
            Without<InventoryEntryScrollbarTrack>,
        ),
    >,
    scroll_areas: Query<&ComputedNode, With<InventoryEntryScrollArea>>,
) {
    let Ok(scroll_area) = scroll_areas.single() else {
        return;
    };
    let Ok((track, mut track_visibility)) = tracks.single_mut() else {
        return;
    };
    let Ok((mut thumb_node, mut thumb_visibility)) = thumbs.single_mut() else {
        return;
    };

    let Some(metrics) = inventory_scrollbar_metrics(scroll_area, track) else {
        *track_visibility = Visibility::Hidden;
        *thumb_visibility = Visibility::Hidden;
        return;
    };

    *track_visibility = Visibility::Visible;
    *thumb_visibility = Visibility::Visible;
    let thumb_top = if metrics.max_scroll <= f32::EPSILON {
        0.0
    } else {
        metrics.travel * (scroll_area.scroll_position.y / metrics.max_scroll).clamp(0.0, 1.0)
    };

    thumb_node.top = px(thumb_top);
    thumb_node.height = px(metrics.thumb_height);
}

fn apply_inventory_reorder(
    runtime_state: &mut ViewerRuntimeState,
    menu_state: &mut UiMenuState,
    save_path: &ViewerRuntimeSavePath,
    actor_id: ActorId,
    item_id: u32,
    before_item_id: Option<u32>,
) -> bool {
    match runtime_state
        .runtime
        .move_inventory_item_before(actor_id, item_id, before_item_id)
    {
        Ok(()) => {
            save_runtime_snapshot(save_path, &runtime_state.runtime);
            menu_state.status_text = "背包顺序已更新".to_string();
            true
        }
        Err(error) => {
            menu_state.status_text = error.to_string();
            false
        }
    }
}

fn apply_inventory_equip(
    runtime_state: &mut ViewerRuntimeState,
    menu_state: &mut UiMenuState,
    save_path: &ViewerRuntimeSavePath,
    actor_id: ActorId,
    item_id: u32,
    slot_id: &str,
    items: &ItemDefinitions,
) -> bool {
    match runtime_state
        .runtime
        .equip_item(actor_id, item_id, Some(slot_id), &items.0)
    {
        Ok(_) => {
            save_runtime_snapshot(save_path, &runtime_state.runtime);
            menu_state.status_text = format!("已装备到 {slot_id}");
            true
        }
        Err(error) => {
            menu_state.status_text = error.to_string();
            false
        }
    }
}

fn apply_equipment_move(
    runtime_state: &mut ViewerRuntimeState,
    menu_state: &mut UiMenuState,
    save_path: &ViewerRuntimeSavePath,
    actor_id: ActorId,
    from_slot: &str,
    to_slot: &str,
    items: &ItemDefinitions,
) -> bool {
    match runtime_state
        .runtime
        .move_equipped_item(actor_id, from_slot, to_slot, &items.0)
    {
        Ok(()) => {
            save_runtime_snapshot(save_path, &runtime_state.runtime);
            menu_state.status_text = format!("{from_slot} -> {to_slot}");
            true
        }
        Err(error) => {
            menu_state.status_text = error.to_string();
            false
        }
    }
}

fn apply_equipment_unequip_and_reorder(
    runtime_state: &mut ViewerRuntimeState,
    menu_state: &mut UiMenuState,
    save_path: &ViewerRuntimeSavePath,
    actor_id: ActorId,
    slot_id: &str,
    item_id: u32,
    before_item_id: Option<u32>,
) -> bool {
    match runtime_state.runtime.unequip_item(actor_id, slot_id) {
        Ok(_) => match runtime_state.runtime.move_inventory_item_before(
            actor_id,
            item_id,
            before_item_id,
        ) {
            Ok(()) => {
                save_runtime_snapshot(save_path, &runtime_state.runtime);
                menu_state.status_text = format!("已卸下 {slot_id}");
                true
            }
            Err(error) => {
                menu_state.status_text = error.to_string();
                false
            }
        },
        Err(error) => {
            menu_state.status_text = error.to_string();
            false
        }
    }
}

fn apply_equipped_drop(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    menu_state: &mut UiMenuState,
    save_path: &ViewerRuntimeSavePath,
    items: &ItemDefinitions,
    actor_id: ActorId,
    slot_id: &str,
    item_id: u32,
) -> bool {
    let item_name = item_preview_label(&items.0, item_id);
    let status = runtime_state
        .runtime
        .drop_equipped_item_to_ground(actor_id, slot_id, &items.0)
        .map(|outcome| {
            save_runtime_snapshot(save_path, &runtime_state.runtime);
            format!(
                "已丢弃装备 {} 到 ({}, {}, {})",
                item_name, outcome.grid.x, outcome.grid.y, outcome.grid.z
            )
        })
        .unwrap_or_else(|error| error);
    let success = status.starts_with("已丢弃装备");
    viewer_state.status_line = status.clone();
    menu_state.status_text = status;
    success
}

fn apply_trade_sell(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    menu_state: &mut UiMenuState,
    modal_state: &mut UiModalState,
    save_path: &ViewerRuntimeSavePath,
    items: &ItemDefinitions,
    actor_id: ActorId,
    shop_id: &str,
    item_id: u32,
) -> bool {
    match plan_trade_sell(&runtime_state.runtime, actor_id, shop_id, item_id, items) {
        TradeQuantityPlan::Immediate { count } => {
            let status = execute_trade_sell(
                runtime_state,
                menu_state,
                save_path,
                items,
                actor_id,
                shop_id,
                item_id,
                count,
            );
            viewer_state.status_line = status.clone();
            menu_state.status_text = status;
            true
        }
        TradeQuantityPlan::OpenModal(modal) => {
            modal_state.item_quantity = Some(modal);
            viewer_state.status_line = "选择要卖出的数量".to_string();
            menu_state.status_text = viewer_state.status_line.clone();
            true
        }
        TradeQuantityPlan::Blocked { status } => {
            viewer_state.status_line = status.clone();
            menu_state.status_text = status;
            false
        }
    }
}

fn apply_trade_equipped_sell(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    menu_state: &mut UiMenuState,
    save_path: &ViewerRuntimeSavePath,
    items: &ItemDefinitions,
    actor_id: ActorId,
    shop_id: &str,
    slot_id: &str,
    item_id: u32,
) -> bool {
    let item_name = item_preview_label(&items.0, item_id);
    match runtime_state
        .runtime
        .sell_equipped_item_to_shop(actor_id, shop_id, slot_id, &items.0)
    {
        Ok(_) => {
            save_runtime_snapshot(save_path, &runtime_state.runtime);
            let status = format!("已卖出装备 {} x1", item_name);
            viewer_state.status_line = status.clone();
            menu_state.status_text = status;
            true
        }
        Err(error) => {
            let status = error.to_string();
            viewer_state.status_line = status.clone();
            menu_state.status_text = status;
            false
        }
    }
}

fn apply_inventory_drop(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    menu_state: &mut UiMenuState,
    modal_state: &mut UiModalState,
    save_path: &ViewerRuntimeSavePath,
    items: &ItemDefinitions,
    actor_id: ActorId,
    item_id: u32,
) -> bool {
    match plan_inventory_drop(&runtime_state.runtime, actor_id, item_id) {
        Some(InventoryDropPlan::Immediate { count }) => {
            execute_inventory_drop(
                runtime_state,
                viewer_state,
                menu_state,
                modal_state,
                save_path,
                items,
                actor_id,
                item_id,
                count,
            );
            true
        }
        Some(InventoryDropPlan::OpenModal(modal)) => {
            modal_state.item_quantity = Some(modal);
            menu_state.status_text = "选择要丢弃的数量".to_string();
            true
        }
        None => false,
    }
}

#[allow(clippy::too_many_arguments)]
fn apply_container_store(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    menu_state: &mut UiMenuState,
    modal_state: &mut UiModalState,
    save_path: &ViewerRuntimeSavePath,
    items: &ItemDefinitions,
    actor_id: ActorId,
    container_id: &str,
    item_id: u32,
    before_item_id: Option<u32>,
) -> bool {
    match plan_container_store(&runtime_state.runtime, actor_id, container_id, item_id) {
        ContainerQuantityPlan::Immediate { count } => {
            let item_name = item_preview_label(&items.0, item_id);
            let status = runtime_state
                .runtime
                .transfer_actor_item_to_container(
                    actor_id,
                    container_id,
                    item_id,
                    count,
                    before_item_id,
                    &items.0,
                )
                .map(|_| {
                    save_runtime_snapshot(save_path, &runtime_state.runtime);
                    format!("已存入 {item_name} x{count}")
                })
                .unwrap_or_else(|error| error.to_string());
            let success = status.starts_with("已存入");
            viewer_state.status_line = status.clone();
            menu_state.status_text = status;
            success
        }
        ContainerQuantityPlan::OpenModal(modal) => {
            modal_state.item_quantity = Some(modal);
            viewer_state.status_line = "选择要存入的数量".to_string();
            menu_state.status_text = viewer_state.status_line.clone();
            true
        }
        ContainerQuantityPlan::Blocked { status } => {
            viewer_state.status_line = status.clone();
            menu_state.status_text = status;
            false
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn apply_container_take(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    menu_state: &mut UiMenuState,
    modal_state: &mut UiModalState,
    save_path: &ViewerRuntimeSavePath,
    items: &ItemDefinitions,
    actor_id: ActorId,
    container_id: &str,
    item_id: u32,
    before_item_id: Option<u32>,
) -> bool {
    match plan_container_take(
        &runtime_state.runtime,
        actor_id,
        container_id,
        item_id,
        items,
    ) {
        ContainerQuantityPlan::Immediate { count } => {
            let item_name = item_preview_label(&items.0, item_id);
            let status = runtime_state
                .runtime
                .transfer_container_item_to_actor(
                    container_id,
                    actor_id,
                    item_id,
                    count,
                    before_item_id,
                    &items.0,
                )
                .map(|_| {
                    save_runtime_snapshot(save_path, &runtime_state.runtime);
                    format!("已取出 {item_name} x{count}")
                })
                .unwrap_or_else(|error| error.to_string());
            let success = status.starts_with("已取出");
            viewer_state.status_line = status.clone();
            menu_state.status_text = status;
            success
        }
        ContainerQuantityPlan::OpenModal(modal) => {
            modal_state.item_quantity = Some(modal);
            viewer_state.status_line = "选择要取出的数量".to_string();
            menu_state.status_text = viewer_state.status_line.clone();
            true
        }
        ContainerQuantityPlan::Blocked { status } => {
            viewer_state.status_line = status.clone();
            menu_state.status_text = status;
            false
        }
    }
}

fn item_preview_label(items: &game_data::ItemLibrary, item_id: u32) -> String {
    items
        .get(item_id)
        .map(|item| item.name.clone())
        .unwrap_or_else(|| format!("item:{item_id}"))
}
