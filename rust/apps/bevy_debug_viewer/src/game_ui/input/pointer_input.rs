//! UI 指针输入：负责背包点击、右键菜单、装备选择和鼠标悬停命中处理。

use super::*;

#[allow(clippy::too_many_arguments)]
pub(crate) fn handle_inventory_panel_pointer_input(
    window: Single<&Window>,
    buttons: Res<ButtonInput<MouseButton>>,
    scene_kind: Res<ViewerSceneKind>,
    mut menu_state: ResMut<UiMenuState>,
    modal_state: Res<UiModalState>,
    mut context_menu: ResMut<UiInventoryContextMenuState>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    save_path: Res<ViewerRuntimeSavePath>,
    items: Res<ItemDefinitions>,
    inventory_targets: Query<
        (
            &InventoryItemClickTarget,
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<Button>,
    >,
    equipment_targets: Query<
        (
            &EquipmentSlotClickTarget,
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<Button>,
    >,
    context_menu_roots: Query<
        (
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<InventoryContextMenuRoot>,
    >,
) {
    let trade_active = modal_state.trade.is_some();
    let discard_modal_open = modal_state.discard_quantity.is_some();
    if scene_kind.is_main_menu() {
        context_menu.clear();
        return;
    }
    if discard_modal_open {
        context_menu.clear();
        return;
    }
    if !trade_active && menu_state.active_panel != Some(UiMenuPanel::Inventory) {
        context_menu.clear();
        return;
    }
    if !buttons.just_pressed(MouseButton::Left) && !buttons.just_pressed(MouseButton::Right) {
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        context_menu.clear();
        return;
    };

    let inventory_hit = find_inventory_click_target(cursor_position, &inventory_targets);
    let equipment_hit =
        equipment_targets
            .iter()
            .find_map(|(target, computed, transform, cursor, visibility)| {
                hover_target_contains_cursor(
                    cursor_position,
                    computed,
                    transform,
                    cursor,
                    visibility,
                )
                .then_some(target)
            });
    let clicked_context_menu =
        context_menu_roots
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

    if buttons.just_pressed(MouseButton::Right) {
        if trade_active {
            context_menu.clear();
            return;
        }
        if let Some(item_id) = inventory_hit {
            menu_state.selected_inventory_item = Some(item_id);
            menu_state.selected_equipment_slot = None;
            context_menu.visible = true;
            context_menu.cursor_position = cursor_position;
            context_menu.target = Some(UiInventoryContextMenuTarget::InventoryItem { item_id });
            return;
        }
        if let Some(target) = equipment_hit {
            if let Some(item_id) = target.item_id {
                context_menu.visible = true;
                context_menu.cursor_position = cursor_position;
                context_menu.target = Some(UiInventoryContextMenuTarget::EquipmentSlot {
                    slot_id: target.slot_id.clone(),
                    item_id,
                });
            } else {
                context_menu.clear();
            }
            return;
        }
        if !clicked_context_menu {
            context_menu.clear();
        }
        return;
    }

    if let Some(item_id) = inventory_hit {
        menu_state.selected_inventory_item = Some(item_id);
        menu_state.selected_equipment_slot = None;
        context_menu.clear();
        return;
    }

    if !trade_active {
        if let Some(target) = equipment_hit {
            context_menu.clear();
            if let Some(actor_id) = player_actor_id(&runtime_state.runtime) {
                if let Some(from_slot) = menu_state.selected_equipment_slot.clone() {
                    menu_state.status_text = runtime_state
                        .runtime
                        .move_equipped_item(actor_id, &from_slot, &target.slot_id, &items.0)
                        .map(|_| {
                            save_runtime_snapshot(&save_path, &runtime_state.runtime);
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
    }

    if !trade_active && !clicked_context_menu {
        context_menu.clear();
    }
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
