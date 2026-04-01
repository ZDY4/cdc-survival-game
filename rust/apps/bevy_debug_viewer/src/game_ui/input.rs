use super::*;

pub(crate) fn update_hover_tooltip_state(
    window: Single<&Window>,
    scene_kind: Res<ViewerSceneKind>,
    menu_state: Res<UiMenuState>,
    modal_state: Res<UiModalState>,
    inventory_context_menu: Res<UiInventoryContextMenuState>,
    mut tooltip_state: ResMut<UiHoverTooltipState>,
    inventory_targets: Query<
        (
            &InventoryItemHoverTarget,
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<Button>,
    >,
    skill_targets: Query<
        (
            &SkillHoverTarget,
            &ComputedNode,
            &UiGlobalTransform,
            Option<&RelativeCursorPosition>,
            Option<&Visibility>,
        ),
        With<Button>,
    >,
) {
    let Some(cursor_position) = window.cursor_position() else {
        tooltip_state.clear();
        return;
    };

    tooltip_state.cursor_position = cursor_position;

    if scene_kind.is_main_menu() || modal_state.trade.is_some() || inventory_context_menu.visible {
        tooltip_state.clear();
        return;
    }

    let hovered = match menu_state.active_panel {
        Some(UiMenuPanel::Inventory) => {
            find_inventory_hover_target(cursor_position, &inventory_targets)
                .map(|item_id| UiHoverTooltipContent::InventoryItem { item_id })
        }
        Some(UiMenuPanel::Skills) => find_skill_hover_target(cursor_position, &skill_targets)
            .map(|(tree_id, skill_id)| UiHoverTooltipContent::Skill { tree_id, skill_id }),
        _ => None,
    };

    match hovered {
        Some(content) => {
            tooltip_state.visible = true;
            tooltip_state.content = Some(content);
        }
        None => tooltip_state.clear(),
    }
}

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
    if scene_kind.is_main_menu() || modal_state.trade.is_some() {
        context_menu.clear();
        return;
    }
    if menu_state.active_panel != Some(UiMenuPanel::Inventory) {
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

    if !clicked_context_menu {
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

pub(crate) fn handle_game_ui_buttons(
    mut buttons: Query<
        (&Interaction, &mut BackgroundColor, &GameUiButtonAction),
        (Changed<Interaction>, With<Button>),
    >,
    mut ui: GameUiCommandState,
    save_path: Res<ViewerRuntimeSavePath>,
    content: GameContentRefs,
    mut exit: MessageWriter<AppExit>,
) {
    for (interaction, mut background, action) in &mut buttons {
        *background = BackgroundColor(interaction_menu_button_color(false, *interaction));
        if *interaction != Interaction::Pressed {
            continue;
        }
        ui.inventory_context_menu.clear();
        match action.clone() {
            GameUiButtonAction::MainMenuNewGame => {
                match rebuild_runtime_with_new_game_defaults(
                    &content.items,
                    &content.skills,
                    &content.recipes,
                    &content.quests,
                    &content.shops,
                    &content.overworld,
                ) {
                    Ok(runtime) => {
                        ui.runtime_state.runtime = runtime;
                        transition_to_gameplay_scene(
                            &mut ui.scene_kind,
                            &mut ui.runtime_state,
                            &mut ui.viewer_state,
                            &mut ui.menu_state,
                            &mut ui.modal_state,
                            "开始新游戏",
                        );
                        save_runtime_snapshot(&save_path, &ui.runtime_state.runtime);
                    }
                    Err(error) => ui.menu_state.status_text = error,
                }
            }
            GameUiButtonAction::MainMenuContinue => match load_runtime_snapshot(&save_path) {
                Ok(Some(snapshot)) => {
                    if let Ok(mut bootstrap) = load_viewer_gameplay_bootstrap() {
                        if bootstrap.runtime.load_snapshot(snapshot).is_ok() {
                            configure_runtime_after_restore(
                                &mut bootstrap.runtime,
                                &content.items,
                                &content.skills,
                                &content.recipes,
                                &content.quests,
                                &content.shops,
                                &content.overworld,
                            );
                            ui.runtime_state.runtime = bootstrap.runtime;
                            transition_to_gameplay_scene(
                                &mut ui.scene_kind,
                                &mut ui.runtime_state,
                                &mut ui.viewer_state,
                                &mut ui.menu_state,
                                &mut ui.modal_state,
                                "已继续最近存档",
                            );
                        } else {
                            ui.menu_state.status_text = "存档恢复失败".to_string();
                        }
                    } else {
                        ui.menu_state.status_text = "加载 gameplay runtime 失败".to_string();
                    }
                }
                Ok(None) => ui.menu_state.status_text = "没有可继续的存档".to_string(),
                Err(error) => ui.menu_state.status_text = error,
            },
            GameUiButtonAction::MainMenuExit => {
                exit.write(AppExit::Success);
            }
            GameUiButtonAction::TogglePanel(panel) => {
                ui.menu_state.active_panel = if ui.menu_state.active_panel == Some(panel) {
                    None
                } else {
                    Some(panel)
                };
                if ui.menu_state.active_panel == Some(UiMenuPanel::Skills) {
                    sync_skill_selection_state(
                        &mut ui.menu_state,
                        &ui.runtime_state,
                        &content.skills,
                        &content.skill_trees,
                    );
                }
            }
            GameUiButtonAction::ClosePanels => {
                ui.menu_state.active_panel = None;
                ui.modal_state.trade = None;
            }
            GameUiButtonAction::CloseTrade => {
                ui.modal_state.trade = None;
                ui.viewer_state.pending_open_trade_target = None;
            }
            GameUiButtonAction::InventoryFilter(filter) => ui.filter_state.filter = filter,
            GameUiButtonAction::UseInventoryItem => {
                if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                    if let Some(item_id) = ui.menu_state.selected_inventory_item {
                        ui.menu_state.status_text = ui
                            .runtime_state
                            .runtime
                            .use_item(actor_id, item_id, &content.items.0, &content.effects.0)
                            .map(|name| {
                                save_runtime_snapshot(&save_path, &ui.runtime_state.runtime);
                                format!("已使用 {name}")
                            })
                            .unwrap_or_else(|error| error);
                    }
                }
            }
            GameUiButtonAction::EquipInventoryItem => {
                if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                    if let Some(item_id) = ui.menu_state.selected_inventory_item {
                        ui.menu_state.status_text = ui
                            .runtime_state
                            .runtime
                            .equip_item(actor_id, item_id, None, &content.items.0)
                            .map(|_| {
                                save_runtime_snapshot(&save_path, &ui.runtime_state.runtime);
                                "装备成功".to_string()
                            })
                            .unwrap_or_else(|error| error.to_string());
                    }
                }
            }
            GameUiButtonAction::UnequipSlot(slot_id) => {
                if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                    ui.menu_state.status_text = ui
                        .runtime_state
                        .runtime
                        .unequip_item(actor_id, &slot_id)
                        .map(|_| {
                            save_runtime_snapshot(&save_path, &ui.runtime_state.runtime);
                            format!("已卸下 {slot_id}")
                        })
                        .unwrap_or_else(|error| error.to_string());
                    if ui.menu_state.selected_equipment_slot.as_deref() == Some(slot_id.as_str()) {
                        ui.menu_state.selected_equipment_slot = None;
                    }
                }
            }
            GameUiButtonAction::AllocateAttribute(attribute) => {
                if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                    ui.menu_state.status_text = ui
                        .runtime_state
                        .runtime
                        .allocate_attribute_point(actor_id, &attribute)
                        .map(|value| {
                            save_runtime_snapshot(&save_path, &ui.runtime_state.runtime);
                            format!("{attribute} -> {value}")
                        })
                        .unwrap_or_else(|error| error);
                }
            }
            GameUiButtonAction::SelectSkillTree(tree_id) => {
                ui.menu_state.selected_skill_tree_id = Some(tree_id.clone());
                if let Some(snapshot) = skills_snapshot_for_player(
                    &ui.runtime_state,
                    &content.skills,
                    &content.skill_trees,
                ) {
                    if let Some(tree) = snapshot.trees.iter().find(|tree| tree.tree_id == tree_id) {
                        let keep_current = ui
                            .menu_state
                            .selected_skill_id
                            .as_ref()
                            .and_then(|skill_id| {
                                tree.entries
                                    .iter()
                                    .find(|entry| &entry.skill_id == skill_id)
                            })
                            .is_some();
                        if !keep_current {
                            ui.menu_state.selected_skill_id =
                                tree.entries.first().map(|entry| entry.skill_id.clone());
                        }
                    } else {
                        ui.menu_state.selected_skill_id = None;
                    }
                }
            }
            GameUiButtonAction::SelectSkill(skill_id) => {
                if let Some(snapshot) = skills_snapshot_for_player(
                    &ui.runtime_state,
                    &content.skills,
                    &content.skill_trees,
                ) {
                    if let Some(tree_id) = find_skill_tree_id(&snapshot, &skill_id) {
                        ui.menu_state.selected_skill_tree_id = Some(tree_id.to_string());
                    }
                }
                ui.menu_state.selected_skill_id = Some(skill_id);
            }
            GameUiButtonAction::AssignSkillToFirstEmptyHotbarSlot(skill_id) => {
                if let Err(error) =
                    validate_hotbar_skill_binding(&ui.runtime_state, &content.skills, &skill_id)
                {
                    ui.menu_state.status_text = error;
                    continue;
                }
                let group_index = ui.hotbar_state.active_group;
                if let Some(slot) = ui.hotbar_state.groups.get(group_index).and_then(|group| {
                    group
                        .iter()
                        .position(|slot| slot.skill_id.as_deref() == Some(skill_id.as_str()))
                }) {
                    ui.menu_state.status_text =
                        format!("{} 已在当前组第 {} 槽", skill_id, slot.saturating_add(1));
                    continue;
                }
                let first_empty_slot = ui
                    .hotbar_state
                    .groups
                    .get(group_index)
                    .and_then(|group| group.iter().position(|slot| slot.skill_id.is_none()));
                if let Some(slot) = first_empty_slot {
                    if assign_skill_to_hotbar_slot(
                        &mut ui.hotbar_state,
                        &mut ui.menu_state,
                        skill_id,
                        group_index,
                        slot,
                    ) {
                        ui.menu_state.selected_skill_id = None;
                    }
                } else {
                    ui.menu_state.status_text =
                        format!("快捷栏第 {} 组已满", group_index.saturating_add(1));
                }
            }
            GameUiButtonAction::AssignSkillToHotbar {
                skill_id,
                group,
                slot,
            } => {
                ui.menu_state.status_text = match validate_hotbar_skill_binding(
                    &ui.runtime_state,
                    &content.skills,
                    &skill_id,
                ) {
                    Ok(()) => {
                        assign_skill_to_hotbar_slot(
                            &mut ui.hotbar_state,
                            &mut ui.menu_state,
                            skill_id,
                            group,
                            slot,
                        );
                        ui.menu_state.status_text.clone()
                    }
                    Err(error) => error,
                };
            }
            GameUiButtonAction::EnterAttackTargeting => {
                if ui
                    .viewer_state
                    .targeting_state
                    .as_ref()
                    .is_some_and(|targeting| targeting.is_attack())
                {
                    cancel_targeting(&mut ui.viewer_state, "普通攻击: 已取消");
                } else if let Err(error) =
                    enter_attack_targeting(&ui.runtime_state, &mut ui.viewer_state)
                {
                    ui.viewer_state.status_line = error.clone();
                    ui.menu_state.status_text = error;
                } else {
                    ui.menu_state.status_text = ui.viewer_state.status_line.clone();
                }
            }
            GameUiButtonAction::ActivateHotbarSlot(slot) => {
                activate_hotbar_slot(
                    &mut ui.runtime_state,
                    &mut ui.viewer_state,
                    &content.skills,
                    &mut ui.hotbar_state,
                    slot,
                );
                if let Some(status) = ui.hotbar_state.last_activation_status.clone() {
                    ui.viewer_state.status_line = status.clone();
                    ui.menu_state.status_text = status;
                }
            }
            GameUiButtonAction::SelectHotbarGroup(group) => {
                ui.hotbar_state.active_group =
                    group.min(ui.hotbar_state.groups.len().saturating_sub(1));
            }
            GameUiButtonAction::ClearHotbarSlot { group, slot } => {
                if let Some(group_slots) = ui.hotbar_state.groups.get_mut(group) {
                    if let Some(slot_state) = group_slots.get_mut(slot) {
                        *slot_state = Default::default();
                    }
                }
            }
            GameUiButtonAction::CraftRecipe(recipe_id) => {
                if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                    ui.menu_state.status_text = ui
                        .runtime_state
                        .runtime
                        .craft_recipe(actor_id, &recipe_id, &content.recipes.0, &content.items.0)
                        .map(|outcome| {
                            save_runtime_snapshot(&save_path, &ui.runtime_state.runtime);
                            format!(
                                "已制造 {} x{}",
                                outcome.output_item_id, outcome.output_count
                            )
                        })
                        .unwrap_or_else(|error| error.to_string());
                }
            }
            GameUiButtonAction::SelectMapLocation(location_id) => {
                ui.menu_state.selected_map_location_id = Some(location_id);
            }
            GameUiButtonAction::BuyTradeItem { shop_id, item_id } => {
                if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                    ui.menu_state.status_text = ui
                        .runtime_state
                        .runtime
                        .buy_item_from_shop(actor_id, &shop_id, item_id, 1, &content.items.0)
                        .map(|_| {
                            save_runtime_snapshot(&save_path, &ui.runtime_state.runtime);
                            "买入成功".to_string()
                        })
                        .unwrap_or_else(|error| error.to_string());
                }
            }
            GameUiButtonAction::SellTradeItem { shop_id, item_id } => {
                if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                    ui.menu_state.status_text = ui
                        .runtime_state
                        .runtime
                        .sell_item_to_shop(actor_id, &shop_id, item_id, 1, &content.items.0)
                        .map(|_| {
                            save_runtime_snapshot(&save_path, &ui.runtime_state.runtime);
                            "卖出成功".to_string()
                        })
                        .unwrap_or_else(|error| error.to_string());
                }
            }
            GameUiButtonAction::SettingsSetMaster(value) => ui.settings.master_volume = value,
            GameUiButtonAction::SettingsSetMusic(value) => ui.settings.music_volume = value,
            GameUiButtonAction::SettingsSetSfx(value) => ui.settings.sfx_volume = value,
            GameUiButtonAction::SettingsSetWindowMode(value) => ui.settings.window_mode = value,
            GameUiButtonAction::SettingsSetVsync(value) => ui.settings.vsync = value,
            GameUiButtonAction::SettingsSetUiScale(value) => ui.settings.ui_scale = value,
            GameUiButtonAction::SettingsCycleBinding(action_name) => {
                cycle_binding(&mut ui.settings, &action_name);
            }
        }
    }
}

pub(super) fn cycle_binding(settings: &mut ViewerUiSettings, action_name: &str) {
    let candidates = [
        "KeyI", "KeyC", "KeyM", "KeyJ", "KeyK", "KeyL", "KeyU", "KeyO", "KeyP",
    ];
    let current = settings
        .action_bindings
        .get(action_name)
        .cloned()
        .unwrap_or_else(|| candidates[0].to_string());
    let current_index = candidates
        .iter()
        .position(|candidate| *candidate == current)
        .unwrap_or(0);
    for step in 1..=candidates.len() {
        let candidate = candidates[(current_index + step) % candidates.len()].to_string();
        let conflict = settings
            .action_bindings
            .iter()
            .any(|(action, binding)| action != action_name && *binding == candidate);
        if !conflict {
            settings
                .action_bindings
                .insert(action_name.to_string(), candidate);
            break;
        }
    }
}
