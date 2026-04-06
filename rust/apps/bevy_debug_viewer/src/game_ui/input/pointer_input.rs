//! UI 指针输入：负责背包点击、右键菜单、装备选择和拖拽分发。

use super::button_actions::{
    execute_inventory_drop, execute_trade_sell, plan_inventory_drop, plan_trade_sell,
    InventoryDropPlan, TradeQuantityPlan,
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
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn handle_inventory_panel_pointer_input(
    window: Single<&Window>,
    buttons: Res<ButtonInput<MouseButton>>,
    mut ui: InventoryPointerUiState,
    targets: InventoryPointerTargets,
) {
    let trade_active = ui.modal_state.trade.is_some();
    let item_modal_open = ui.modal_state.item_quantity.is_some();
    let inventory_panel_active = ui.menu_state.active_panel == Some(UiMenuPanel::Inventory);
    let skills_panel_active = !trade_active && ui.menu_state.active_panel == Some(UiMenuPanel::Skills);
    if ui.scene_kind.is_main_menu() {
        ui.context_menu.clear();
        ui.drag_state.clear();
        return;
    }
    if item_modal_open {
        ui.context_menu.clear();
        ui.drag_state.clear();
        return;
    }
    if !trade_active && !inventory_panel_active && !skills_panel_active {
        ui.context_menu.clear();
        ui.drag_state.clear();
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
    {
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        ui.context_menu.clear();
        ui.drag_state.clear();
        return;
    };

    ui.drag_state.cursor_position = cursor_position;

    let inventory_hit = find_inventory_click_target(cursor_position, &targets.inventory_targets);
    let trade_inventory_hit =
        find_trade_inventory_click_target(cursor_position, &targets.trade_inventory_targets);
    let effective_inventory_hit = inventory_hit.or(trade_inventory_hit);
    let equipment_hit =
        targets
            .equipment_targets
            .iter()
            .find_map(|(target, computed, transform, cursor, visibility)| {
                hover_target_contains_cursor(
                    cursor_position,
                    computed,
                    transform,
                    cursor,
                    visibility,
                )
                .then_some(target.clone())
            });
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

    if skills_panel_active {
        let skill_hit = find_skill_hover_target(cursor_position, &targets.skill_targets);
        if right_just_pressed {
            if let Some((tree_id, skill_id)) = skill_hit {
                ui.menu_state.selected_skill_tree_id = Some(tree_id.clone());
                ui.menu_state.selected_skill_id = Some(skill_id.clone());
                ui.context_menu.visible = true;
                ui.context_menu.cursor_position = cursor_position;
                ui.context_menu.target = Some(UiContextMenuTarget::SkillEntry { tree_id, skill_id });
            } else if !clicked_context_menu {
                ui.context_menu.clear();
            }
        }
        if buttons.just_pressed(MouseButton::Left) && !clicked_context_menu {
            ui.context_menu.clear();
        }
        ui.drag_state.clear();
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
    let cursor_in_inventory_list =
        targets
            .inventory_list_drop_zones
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

    if right_just_pressed {
        if ui.drag_state.is_active() {
            ui.context_menu.clear();
            return;
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
        if trade_active {
            if let Some(item_id) = effective_inventory_hit {
                begin_inventory_drag(
                    &mut ui.drag_state,
                    UiInventoryDragSource::InventoryItem { item_id },
                    item_preview_label(&ui.items.0, item_id),
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
            && ui.drag_state.press_cursor_position.distance(cursor_position)
                >= INVENTORY_DRAG_THRESHOLD
        {
            ui.drag_state.dragging = true;
            ui.context_menu.clear();
        }
        if ui.drag_state.dragging {
            ui.drag_state.hover_target = resolve_drag_hover_target(
                trade_active,
                effective_inventory_hit,
                equipment_hit.as_ref(),
                cursor_in_inventory_list,
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
            &mut ui.menu_state,
            &mut ui.context_menu,
            &mut ui.runtime_state,
            &ui.save_path,
            &ui.items,
            effective_inventory_hit,
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
            &mut ui.menu_state,
            &mut ui.context_menu,
            &mut ui.runtime_state,
            &ui.save_path,
            &ui.items,
            effective_inventory_hit,
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
            if trade_active {
                if let Some(trade_shop_id) = ui
                    .modal_state
                    .trade
                    .as_ref()
                    .map(|trade| trade.shop_id.clone())
                {
                    match hover_target {
                        Some(UiInventoryDragHoverTarget::InventoryItem { item_id: before })
                            if before != item_id => {
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
        UiInventoryDragSource::EquipmentSlot {
            ref slot_id,
            item_id,
        } => match hover_target {
            Some(UiInventoryDragHoverTarget::EquipmentSlot { slot_id: target_slot }) => {
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
            Some(UiInventoryDragHoverTarget::InventoryItem { item_id: before_item_id }) => {
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
            _ if !trade_active && !cursor_in_inventory_panel => {
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
            UiInventoryDragSource::EquipmentSlot { .. } => ui.menu_state.selected_inventory_item,
        };
        ui.menu_state.selected_equipment_slot = None;
    }

    let _ = cursor_in_trade_panel;
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
    cursor_position: Vec2,
) {
    drag_state.active_source = Some(source);
    drag_state.hover_target = None;
    drag_state.press_cursor_position = cursor_position;
    drag_state.cursor_position = cursor_position;
    drag_state.dragging = false;
    drag_state.preview_label = preview_label;
}

fn resolve_drag_hover_target(
    trade_active: bool,
    inventory_hit: Option<u32>,
    equipment_hit: Option<&EquipmentSlotClickTarget>,
    cursor_in_inventory_list: bool,
    cursor_in_trade_sell_zone: bool,
) -> Option<UiInventoryDragHoverTarget> {
    if trade_active {
        if cursor_in_trade_sell_zone {
            return Some(UiInventoryDragHoverTarget::TradeSellZone);
        }
        if let Some(target) = equipment_hit {
            return Some(UiInventoryDragHoverTarget::EquipmentSlot {
                slot_id: target.slot_id.clone(),
            });
        }
        if let Some(item_id) = inventory_hit {
            return Some(UiInventoryDragHoverTarget::InventoryItem { item_id });
        }
        if cursor_in_inventory_list {
            return Some(UiInventoryDragHoverTarget::InventoryListEnd);
        }
        return None;
    }

    if let Some(target) = equipment_hit {
        return Some(UiInventoryDragHoverTarget::EquipmentSlot {
            slot_id: target.slot_id.clone(),
        });
    }
    if let Some(item_id) = inventory_hit {
        return Some(UiInventoryDragHoverTarget::InventoryItem { item_id });
    }
    if cursor_in_inventory_list {
        return Some(UiInventoryDragHoverTarget::InventoryListEnd);
    }
    None
}

#[allow(clippy::too_many_arguments)]
fn handle_click_release(
    trade_active: bool,
    menu_state: &mut UiMenuState,
    context_menu: &mut UiContextMenuState,
    runtime_state: &mut ViewerRuntimeState,
    save_path: &ViewerRuntimeSavePath,
    items: &ItemDefinitions,
    inventory_hit: Option<u32>,
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
        if let Some(actor_id) = player_actor_id(&runtime_state.runtime) {
            if let Some(from_slot) = menu_state.selected_equipment_slot.clone() {
                menu_state.status_text = runtime_state
                    .runtime
                    .move_equipped_item(actor_id, &from_slot, &target.slot_id, &items.0)
                    .map(|_| {
                        save_runtime_snapshot(save_path, &runtime_state.runtime);
                        format!("{from_slot} -> {}", target.slot_id)
                    })
                    .unwrap_or_else(|error| error.to_string());
                menu_state.selected_equipment_slot = None;
            } else {
                menu_state.selected_equipment_slot = Some(target.slot_id.clone());
            }
        }
        return;
    }

    if !trade_active && !clicked_context_menu {
        context_menu.clear();
    } else if trade_active && !clicked_context_menu {
        context_menu.clear();
    }
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
        Ok(_) => match runtime_state
            .runtime
            .move_inventory_item_before(actor_id, item_id, before_item_id)
        {
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

fn item_preview_label(items: &game_data::ItemLibrary, item_id: u32) -> String {
    items
        .get(item_id)
        .map(|item| item.name.clone())
        .unwrap_or_else(|| format!("item:{item_id}"))
}
