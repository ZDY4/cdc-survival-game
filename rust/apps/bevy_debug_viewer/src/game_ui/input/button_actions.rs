//! 按钮动作子模块：负责主菜单、背包、技能、地图与设置按钮触发的运行时写操作。

use super::*;

#[derive(Debug, Clone, PartialEq, Eq)]
enum InventoryDropPlan {
    Immediate { count: i32 },
    OpenModal(game_bevy::UiDiscardQuantityModalState),
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
        if handle_trade_button_action(action, &mut ui, &save_path, &content) {
            continue;
        }
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
                ui.modal_state.discard_quantity = None;
                ui.modal_state.trade = None;
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
            GameUiButtonAction::DropInventoryItem => {
                if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                    if let Some(item_id) = ui.menu_state.selected_inventory_item {
                        if let Some(plan) =
                            plan_inventory_drop(&ui.runtime_state.runtime, actor_id, item_id)
                        {
                            match plan {
                                InventoryDropPlan::Immediate { count } => execute_inventory_drop(
                                    &mut ui.runtime_state,
                                    &mut ui.viewer_state,
                                    &mut ui.menu_state,
                                    &mut ui.modal_state,
                                    &save_path,
                                    &content.items,
                                    actor_id,
                                    item_id,
                                    count,
                                ),
                                InventoryDropPlan::OpenModal(modal) => {
                                    ui.modal_state.discard_quantity = Some(modal);
                                }
                            }
                        }
                    }
                }
            }
            GameUiButtonAction::DecreaseDiscardQuantity => {
                if let Some(modal) = ui.modal_state.discard_quantity.as_mut() {
                    modal.selected_count =
                        adjust_discard_quantity(modal.selected_count, modal.available_count, -1);
                }
            }
            GameUiButtonAction::IncreaseDiscardQuantity => {
                if let Some(modal) = ui.modal_state.discard_quantity.as_mut() {
                    modal.selected_count =
                        adjust_discard_quantity(modal.selected_count, modal.available_count, 1);
                }
            }
            GameUiButtonAction::SetDiscardQuantityToMax => {
                if let Some(modal) = ui.modal_state.discard_quantity.as_mut() {
                    modal.selected_count = modal.available_count.max(1);
                }
            }
            GameUiButtonAction::ConfirmDiscardQuantity => {
                if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                    if let Some(modal) = ui.modal_state.discard_quantity.clone() {
                        execute_inventory_drop(
                            &mut ui.runtime_state,
                            &mut ui.viewer_state,
                            &mut ui.menu_state,
                            &mut ui.modal_state,
                            &save_path,
                            &content.items,
                            actor_id,
                            modal.item_id,
                            modal.selected_count,
                        );
                    }
                }
            }
            GameUiButtonAction::CancelDiscardQuantity => {
                ui.modal_state.discard_quantity = None;
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
            GameUiButtonAction::EnterOverworldLocation(location_id) => {
                if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                    match ui
                        .runtime_state
                        .runtime
                        .enter_location(actor_id, &location_id, None)
                    {
                        Ok(_) => {
                            let location_name = content
                                .overworld
                                .0
                                .iter()
                                .flat_map(|(_, definition)| definition.locations.iter())
                                .find(|location| location.id.as_str() == location_id.as_str())
                                .map(|location| location.name.clone())
                                .unwrap_or_else(|| location_id.clone());
                            reset_viewer_runtime_transients(&mut ui.viewer_state);
                            sync_viewer_runtime_basics(&mut ui.runtime_state, &mut ui.viewer_state);
                            let status = format!("已进入 {location_name}");
                            ui.viewer_state.status_line = status.clone();
                            ui.menu_state.status_text = status;
                            save_runtime_snapshot(&save_path, &ui.runtime_state.runtime);
                        }
                        Err(error) => {
                            ui.viewer_state.status_line = error.clone();
                            ui.menu_state.status_text = error;
                        }
                    }
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
            GameUiButtonAction::CloseTrade
            | GameUiButtonAction::BuyTradeItem { .. }
            | GameUiButtonAction::SellTradeItem { .. } => unreachable!(),
        }
    }
}

fn plan_inventory_drop(
    runtime: &game_core::SimulationRuntime,
    actor_id: ActorId,
    item_id: u32,
) -> Option<InventoryDropPlan> {
    let available_count = runtime
        .economy()
        .inventory_count(actor_id, item_id)
        .unwrap_or(0);
    if available_count <= 0 {
        return None;
    }
    if available_count == 1 {
        return Some(InventoryDropPlan::Immediate { count: 1 });
    }
    Some(InventoryDropPlan::OpenModal(
        game_bevy::UiDiscardQuantityModalState {
            item_id,
            available_count,
            selected_count: 1,
        },
    ))
}

fn adjust_discard_quantity(current: i32, available_count: i32, delta: i32) -> i32 {
    (current + delta).clamp(1, available_count.max(1))
}

fn execute_inventory_drop(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    menu_state: &mut UiMenuState,
    modal_state: &mut UiModalState,
    save_path: &ViewerRuntimeSavePath,
    items: &ItemDefinitions,
    actor_id: ActorId,
    item_id: u32,
    count: i32,
) {
    let item_name = items
        .0
        .get(item_id)
        .map(|item| item.name.clone())
        .unwrap_or_else(|| format!("item:{item_id}"));
    let status = runtime_state
        .runtime
        .drop_item_to_ground(actor_id, item_id, count, &items.0)
        .map(|outcome| {
            save_runtime_snapshot(save_path, &runtime_state.runtime);
            format!(
                "已丢弃 {} x{} 到 ({}, {}, {})",
                item_name, outcome.count, outcome.grid.x, outcome.grid.y, outcome.grid.z
            )
        })
        .unwrap_or_else(|error| error);
    modal_state.discard_quantity = None;
    viewer_state.status_line = status.clone();
    menu_state.status_text = status;
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

#[cfg(test)]
mod tests {
    use super::{
        adjust_discard_quantity, execute_inventory_drop, plan_inventory_drop, InventoryDropPlan,
    };
    use crate::state::{ViewerRuntimeSavePath, ViewerRuntimeState, ViewerState};
    use game_bevy::{ItemDefinitions, UiMenuState, UiModalState};
    use game_core::{create_demo_runtime, SimulationCommand};
    use game_data::{ItemDefinition, ItemFragment};
    use std::collections::BTreeMap;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn single_item_drop_is_planned_as_immediate() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_item_definitions();
        let _ = runtime.submit_command(SimulationCommand::SetActorAp {
            actor_id: handles.player,
            ap: 2.0,
        });
        runtime
            .economy_mut()
            .add_item(handles.player, 1006, 1, &items.0)
            .expect("item should be added");

        let plan = plan_inventory_drop(&runtime, handles.player, 1006);

        assert_eq!(plan, Some(InventoryDropPlan::Immediate { count: 1 }));
    }

    #[test]
    fn stacked_item_drop_opens_quantity_modal() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_item_definitions();
        let _ = runtime.submit_command(SimulationCommand::SetActorAp {
            actor_id: handles.player,
            ap: 2.0,
        });
        runtime
            .economy_mut()
            .add_item(handles.player, 1006, 4, &items.0)
            .expect("item should be added");

        let plan = plan_inventory_drop(&runtime, handles.player, 1006);

        assert_eq!(
            plan,
            Some(InventoryDropPlan::OpenModal(
                game_bevy::UiDiscardQuantityModalState {
                    item_id: 1006,
                    available_count: 4,
                    selected_count: 1,
                }
            ))
        );
    }

    #[test]
    fn discard_quantity_adjustment_clamps_to_valid_range() {
        assert_eq!(adjust_discard_quantity(1, 4, -1), 1);
        assert_eq!(adjust_discard_quantity(1, 4, 1), 2);
        assert_eq!(adjust_discard_quantity(4, 4, 1), 4);
        assert_eq!(adjust_discard_quantity(2, 1, 3), 1);
    }

    #[test]
    fn execute_discard_updates_status_and_closes_modal() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_item_definitions();
        let _ = runtime.submit_command(SimulationCommand::SetActorAp {
            actor_id: handles.player,
            ap: 2.0,
        });
        runtime
            .economy_mut()
            .add_item(handles.player, 1006, 3, &items.0)
            .expect("item should be added");
        let mut runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: Default::default(),
        };
        let mut viewer_state = ViewerState::default();
        let mut menu_state = UiMenuState::default();
        let mut modal_state = UiModalState {
            discard_quantity: Some(game_bevy::UiDiscardQuantityModalState {
                item_id: 1006,
                available_count: 3,
                selected_count: 2,
            }),
            ..UiModalState::default()
        };
        let save_path = temp_save_path();

        execute_inventory_drop(
            &mut runtime_state,
            &mut viewer_state,
            &mut menu_state,
            &mut modal_state,
            &save_path,
            &items,
            handles.player,
            1006,
            2,
        );

        assert!(modal_state.discard_quantity.is_none());
        assert!(viewer_state.status_line.contains("已丢弃 绷带 x2 到"));
        assert_eq!(menu_state.status_text, viewer_state.status_line);
        assert_eq!(
            runtime_state
                .runtime
                .economy()
                .inventory_count(handles.player, 1006),
            Some(1)
        );
    }

    fn sample_item_definitions() -> ItemDefinitions {
        ItemDefinitions(game_data::ItemLibrary::from(BTreeMap::from([(
            1006,
            ItemDefinition {
                id: 1006,
                name: "绷带".to_string(),
                fragments: vec![ItemFragment::Stacking {
                    stackable: true,
                    max_stack: 99,
                }],
                ..ItemDefinition::default()
            },
        )])))
    }

    fn temp_save_path() -> ViewerRuntimeSavePath {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock should be available")
            .as_nanos();
        ViewerRuntimeSavePath(
            std::env::temp_dir().join(format!("bevy_viewer_drop_test_{nanos}.json")),
        )
    }
}
