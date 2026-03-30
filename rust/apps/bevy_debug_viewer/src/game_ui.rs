use std::fs;
use std::marker::PhantomData;

use bevy::ecs::system::SystemParam;
use bevy::prelude::*;
use bevy::window::{PresentMode, VideoModeSelection, WindowMode};
use game_bevy::{
    character_snapshot, interaction_prompt_text, inventory_snapshot, journal_snapshot,
    player_actor_id, skills_snapshot, trade_snapshot, world_status_snapshot, EffectDefinitions,
    ItemDefinitions, OverworldDefinitions, QuestDefinitions, RecipeDefinitions, ShopDefinitions,
    SkillDefinitions, SkillTreeDefinitions, UiHotbarState, UiInputBlockState, UiInventoryFilter,
    UiInventoryFilterState, UiMenuPanel, UiMenuState, UiModalState, UiStatusBannerState,
};
use game_core::RuntimeSnapshot;
use game_data::InteractionTargetId;

use crate::bootstrap::load_viewer_bootstrap;
use crate::render::interaction_menu_button_color;
use crate::state::{
    GameUiButtonAction, GameUiRoot, ViewerPalette, ViewerRenderConfig, ViewerRuntimeSavePath,
    ViewerRuntimeState, ViewerState, ViewerUiFont, ViewerUiSettings, ViewerUiSettingsPath,
};

const UI_PANEL_WIDTH: f32 = 420.0;
const HOTBAR_WIDTH: f32 = 820.0;

#[derive(SystemParam)]
pub(crate) struct GameUiViewState<'w, 's> {
    runtime_state: Res<'w, ViewerRuntimeState>,
    viewer_state: Res<'w, ViewerState>,
    menu_state: Res<'w, UiMenuState>,
    modal_state: Res<'w, UiModalState>,
    banner_state: Res<'w, UiStatusBannerState>,
    filter_state: Res<'w, UiInventoryFilterState>,
    hotbar_state: Res<'w, UiHotbarState>,
    settings: Res<'w, ViewerUiSettings>,
    marker: PhantomData<&'s ()>,
}

#[derive(SystemParam)]
pub(crate) struct GameUiCommandState<'w, 's> {
    runtime_state: ResMut<'w, ViewerRuntimeState>,
    viewer_state: ResMut<'w, ViewerState>,
    menu_state: ResMut<'w, UiMenuState>,
    modal_state: ResMut<'w, UiModalState>,
    filter_state: ResMut<'w, UiInventoryFilterState>,
    hotbar_state: ResMut<'w, UiHotbarState>,
    settings: ResMut<'w, ViewerUiSettings>,
    marker: PhantomData<&'s ()>,
}

#[derive(SystemParam)]
pub(crate) struct GameContentRefs<'w, 's> {
    items: Res<'w, ItemDefinitions>,
    effects: Res<'w, EffectDefinitions>,
    skills: Res<'w, SkillDefinitions>,
    skill_trees: Res<'w, SkillTreeDefinitions>,
    quests: Res<'w, QuestDefinitions>,
    recipes: Res<'w, RecipeDefinitions>,
    shops: Res<'w, ShopDefinitions>,
    overworld: Res<'w, OverworldDefinitions>,
    marker: PhantomData<&'s ()>,
}

pub(crate) fn setup_game_ui(mut commands: Commands, mut menu_state: ResMut<UiMenuState>) {
    menu_state.main_menu_open = true;
    menu_state.active_panel = None;
    commands.spawn((
        Node {
            position_type: PositionType::Absolute,
            left: px(0),
            top: px(0),
            width: Val::Percent(100.0),
            height: Val::Percent(100.0),
            ..default()
        },
        GameUiRoot,
    ));
}

pub(crate) fn load_ui_settings_on_startup(
    path: Res<ViewerUiSettingsPath>,
    mut settings: ResMut<ViewerUiSettings>,
) {
    if let Ok(raw) = fs::read_to_string(&path.0) {
        if let Ok(parsed) = serde_json::from_str::<ViewerUiSettings>(&raw) {
            *settings = parsed;
        }
    }
}

pub(crate) fn apply_ui_settings_system(
    settings: Res<ViewerUiSettings>,
    mut render_config: ResMut<ViewerRenderConfig>,
    mut ui_scale: ResMut<UiScale>,
    mut window: Single<&mut Window>,
) {
    if !settings.is_changed() {
        return;
    }
    apply_ui_settings(&settings, &mut render_config, &mut ui_scale, &mut window);
}

pub(crate) fn save_ui_settings_system(
    settings: Res<ViewerUiSettings>,
    path: Res<ViewerUiSettingsPath>,
) {
    if !settings.is_changed() {
        return;
    }
    if let Some(parent) = path.0.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(raw) = serde_json::to_string_pretty(&*settings) {
        let _ = fs::write(&path.0, raw);
    }
}

pub(crate) fn sync_game_ui_state(
    runtime_state: Res<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
    menu_state: ResMut<UiMenuState>,
    mut modal_state: ResMut<UiModalState>,
    mut banner_state: ResMut<UiStatusBannerState>,
    mut input_block_state: ResMut<UiInputBlockState>,
    shops: Res<ShopDefinitions>,
) {
    let context = runtime_state.runtime.current_interaction_context();
    let banner = world_status_snapshot(&context);
    let prompt_text = interaction_prompt_text(viewer_state.current_prompt.as_ref());
    banner_state.visible = banner.visible;
    banner_state.title = banner.title;
    banner_state.detail = [
        Some(banner.detail),
        (!prompt_text.is_empty()).then_some(prompt_text),
    ]
    .into_iter()
    .flatten()
    .chain(
        (!viewer_state.status_line.trim().is_empty()).then_some(viewer_state.status_line.clone()),
    )
    .collect::<Vec<_>>()
    .join(" | ");

    if let Some(target) = viewer_state.pending_open_trade_target.as_ref() {
        if modal_state.trade.is_none() {
            modal_state.trade = trade_session_for_target(&runtime_state, target, &shops.0);
        }
    }

    input_block_state.blocked = menu_state.main_menu_open
        || menu_state.active_panel.is_some()
        || modal_state.trade.is_some()
        || viewer_state.active_dialogue.is_some()
        || viewer_state.interaction_menu.is_some();
    if (menu_state.main_menu_open
        || menu_state.active_panel.is_some()
        || modal_state.trade.is_some()
        || viewer_state.active_dialogue.is_some())
        && viewer_state.interaction_menu.is_some()
    {
        viewer_state.interaction_menu = None;
    }
    input_block_state.reason = if menu_state.main_menu_open {
        "main_menu".to_string()
    } else if modal_state.trade.is_some() {
        "trade".to_string()
    } else if viewer_state.active_dialogue.is_some() {
        "dialogue".to_string()
    } else if menu_state.active_panel.is_some() {
        "menu_panel".to_string()
    } else if viewer_state.interaction_menu.is_some() {
        "interaction_menu".to_string()
    } else {
        String::new()
    };
}

pub(crate) fn tick_hotbar_cooldowns(time: Res<Time>, mut hotbar: ResMut<UiHotbarState>) {
    let delta = time.delta_secs();
    for group in &mut hotbar.groups {
        for slot in group {
            slot.cooldown_remaining = (slot.cooldown_remaining - delta).max(0.0);
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub(crate) fn update_game_ui(
    mut commands: Commands,
    root: Single<(Entity, Option<&Children>), With<GameUiRoot>>,
    palette: Res<ViewerPalette>,
    font: Res<ViewerUiFont>,
    ui: GameUiViewState,
    content: GameContentRefs,
) {
    let (entity, children) = root.into_inner();
    clear_ui_children(&mut commands, children);
    let player_actor = player_actor_id(&ui.runtime_state.runtime);

    commands.entity(entity).with_children(|parent| {
        if ui.banner_state.visible {
            parent.spawn((
                Node {
                    position_type: PositionType::Absolute,
                    top: px(16),
                    left: px(16),
                    width: px(360),
                    padding: UiRect::all(px(12)),
                    flex_direction: FlexDirection::Column,
                    row_gap: px(4),
                    ..default()
                },
                BackgroundColor(palette.hud_panel_background),
                children![
                    text_bundle(&font, &ui.banner_state.title, 13.0, Color::WHITE),
                    text_bundle(
                        &font,
                        &ui.banner_state.detail,
                        11.0,
                        Color::srgba(0.86, 0.89, 0.95, 1.0)
                    )
                ],
            ));
        }

        if ui.menu_state.main_menu_open {
            render_main_menu(parent, &font);
        } else {
            render_menu_bar(parent, &font);
            render_hotbar(
                parent,
                &font,
                &ui.hotbar_state,
                ui.menu_state.selected_skill_id.as_deref(),
            );
        }

        if let Some(actor_id) = player_actor {
            if let Some(panel) = ui.menu_state.active_panel {
                render_panel_shell(parent, &font, panel);
                match panel {
                    UiMenuPanel::Inventory => {
                        let snapshot = inventory_snapshot(
                            &ui.runtime_state.runtime,
                            actor_id,
                            &content.items.0,
                            ui.filter_state.filter,
                            ui.menu_state.selected_inventory_item,
                        );
                        render_inventory_panel(parent, &font, &snapshot);
                    }
                    UiMenuPanel::Character => {
                        let snapshot = character_snapshot(&ui.runtime_state.runtime, actor_id);
                        render_character_panel(parent, &font, &snapshot);
                    }
                    UiMenuPanel::Journal => {
                        let snapshot = journal_snapshot(
                            &ui.runtime_state.runtime,
                            actor_id,
                            &content.quests.0,
                        );
                        render_journal_panel(parent, &font, &snapshot);
                    }
                    UiMenuPanel::Skills => {
                        let snapshot = skills_snapshot(
                            &ui.runtime_state.runtime,
                            actor_id,
                            &content.skills.0,
                            &content.skill_trees.0,
                        );
                        render_skills_panel(parent, &font, &snapshot, &ui.hotbar_state);
                    }
                    UiMenuPanel::Crafting => {
                        let snapshot = game_bevy::crafting_snapshot(
                            &ui.runtime_state.runtime,
                            actor_id,
                            &content.recipes.0,
                        );
                        render_crafting_panel(parent, &font, &snapshot);
                    }
                    UiMenuPanel::Map => {
                        let _ = actor_id;
                        render_map_panel(
                            parent,
                            &font,
                            &ui.runtime_state.runtime.current_overworld_state(),
                            &content.overworld.0,
                            &ui.menu_state,
                        );
                    }
                    UiMenuPanel::Settings => {
                        render_settings_panel(parent, &font, &ui.settings);
                    }
                }
            }

            if let Some(trade) = ui.modal_state.trade.as_ref() {
                let snapshot = trade_snapshot(
                    &ui.runtime_state.runtime,
                    actor_id,
                    trade.target_actor_id,
                    &trade.shop_id,
                    &content.items.0,
                    &content.shops.0,
                );
                render_trade_modal(parent, &font, &snapshot);
            }
        }

        let _ = &ui.viewer_state;
    });
}

#[allow(clippy::too_many_arguments)]
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
                        ui.menu_state.main_menu_open = false;
                        ui.menu_state.active_panel = None;
                        ui.menu_state.status_text = "开始新游戏".to_string();
                        save_runtime_snapshot(&save_path, &ui.runtime_state.runtime);
                    }
                    Err(error) => ui.menu_state.status_text = error,
                }
            }
            GameUiButtonAction::MainMenuContinue => match load_runtime_snapshot(&save_path) {
                Ok(Some(snapshot)) => {
                    if let Ok(mut bootstrap) = load_viewer_bootstrap() {
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
                            ui.menu_state.main_menu_open = false;
                            ui.menu_state.status_text = "已继续最近存档".to_string();
                        }
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
                ui.menu_state.main_menu_open = false;
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
            GameUiButtonAction::SelectInventoryItem(item_id) => {
                ui.menu_state.selected_inventory_item = Some(item_id)
            }
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
                }
            }
            GameUiButtonAction::MoveSelectedEquippedTo(slot_id) => {
                if let Some(actor_id) = player_actor_id(&ui.runtime_state.runtime) {
                    if let Some(from_slot) = ui.menu_state.selected_equipment_slot.clone() {
                        ui.menu_state.status_text = ui
                            .runtime_state
                            .runtime
                            .move_equipped_item(actor_id, &from_slot, &slot_id, &content.items.0)
                            .map(|_| {
                                save_runtime_snapshot(&save_path, &ui.runtime_state.runtime);
                                format!("{from_slot} -> {slot_id}")
                            })
                            .unwrap_or_else(|error| error.to_string());
                        ui.menu_state.selected_equipment_slot = None;
                    } else {
                        ui.menu_state.selected_equipment_slot = Some(slot_id);
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
            GameUiButtonAction::SelectSkill(skill_id) => {
                ui.menu_state.selected_skill_id = Some(skill_id);
            }
            GameUiButtonAction::AssignSkillToHotbar {
                skill_id,
                group,
                slot,
            } => {
                if let Some(group_slots) = ui.hotbar_state.groups.get_mut(group) {
                    if let Some(slot_state) = group_slots.get_mut(slot) {
                        slot_state.skill_id = Some(skill_id);
                        slot_state.cooldown_remaining = 0.0;
                        slot_state.toggled = false;
                        ui.menu_state.selected_skill_id = None;
                    }
                }
            }
            GameUiButtonAction::ActivateHotbarSlot(slot) => {
                activate_hotbar_slot(
                    &mut ui.runtime_state,
                    &content.skills,
                    &mut ui.hotbar_state,
                    slot,
                );
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

fn load_runtime_snapshot(path: &ViewerRuntimeSavePath) -> Result<Option<RuntimeSnapshot>, String> {
    if !path.0.exists() {
        return Ok(None);
    }
    let raw = fs::read_to_string(&path.0).map_err(|error| error.to_string())?;
    serde_json::from_str(&raw)
        .map(Some)
        .map_err(|error| error.to_string())
}

fn save_runtime_snapshot(path: &ViewerRuntimeSavePath, runtime: &game_core::SimulationRuntime) {
    if let Some(parent) = path.0.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(raw) = serde_json::to_string_pretty(&runtime.save_snapshot()) {
        let _ = fs::write(&path.0, raw);
    }
}

fn configure_runtime_after_restore(
    runtime: &mut game_core::SimulationRuntime,
    items: &ItemDefinitions,
    skills: &SkillDefinitions,
    recipes: &RecipeDefinitions,
    quests: &QuestDefinitions,
    shops: &ShopDefinitions,
    overworld: &OverworldDefinitions,
) {
    runtime.set_item_library(items.0.clone());
    runtime.set_skill_library(skills.0.clone());
    runtime.set_recipe_library(recipes.0.clone());
    runtime.set_quest_library(quests.0.clone());
    runtime.set_shop_library(shops.0.clone());
    runtime.set_overworld_library(overworld.0.clone());
}

fn apply_new_game_defaults(
    runtime: &mut game_core::SimulationRuntime,
    items: &ItemDefinitions,
) -> Result<(), String> {
    let actor_id = player_actor_id(runtime).ok_or_else(|| "missing_player".to_string())?;
    runtime
        .clear_actor_loadout(actor_id)
        .map_err(|error| error.to_string())?;
    runtime
        .economy_mut()
        .set_actor_attribute(actor_id, "strength", 5);
    runtime
        .economy_mut()
        .set_actor_attribute(actor_id, "agility", 5);
    runtime
        .economy_mut()
        .set_actor_attribute(actor_id, "constitution", 5);
    for (item_id, count) in [
        (1008, 2),
        (1007, 1),
        (1006, 3),
        (1002, 1),
        (1003, 1),
        (2004, 1),
        (2013, 1),
        (2015, 1),
    ] {
        runtime
            .economy_mut()
            .add_item(actor_id, item_id, count, &items.0)
            .map_err(|error| error.to_string())?;
    }
    runtime
        .economy_mut()
        .add_ammo(actor_id, 1009, 12, &items.0)
        .map_err(|error| error.to_string())?;
    runtime
        .equip_item(actor_id, 1002, Some("main_hand"), &items.0)
        .map_err(|error| error.to_string())?;
    let _ = runtime.equip_item(actor_id, 2004, Some("body"), &items.0);
    let _ = runtime.equip_item(actor_id, 2013, Some("legs"), &items.0);
    let _ = runtime.equip_item(actor_id, 2015, Some("feet"), &items.0);
    for location_id in [
        "survivor_outpost_01",
        "survivor_outpost_01_perimeter",
        "street_a",
        "street_b",
        "factory",
        "supermarket",
    ] {
        let _ = runtime.submit_command(game_core::SimulationCommand::UnlockLocation {
            location_id: location_id.to_string(),
        });
    }
    Ok(())
}

fn rebuild_runtime_with_new_game_defaults(
    items: &ItemDefinitions,
    skills: &SkillDefinitions,
    recipes: &RecipeDefinitions,
    quests: &QuestDefinitions,
    shops: &ShopDefinitions,
    overworld: &OverworldDefinitions,
) -> Result<game_core::SimulationRuntime, String> {
    let mut bootstrap = load_viewer_bootstrap().map_err(|error| error.to_string())?;
    configure_runtime_after_restore(
        &mut bootstrap.runtime,
        items,
        skills,
        recipes,
        quests,
        shops,
        overworld,
    );
    apply_new_game_defaults(&mut bootstrap.runtime, items)?;
    Ok(bootstrap.runtime)
}

pub(crate) fn activate_hotbar_slot(
    runtime_state: &mut ViewerRuntimeState,
    skills: &SkillDefinitions,
    hotbar_state: &mut UiHotbarState,
    slot: usize,
) {
    let Some(group) = hotbar_state.groups.get_mut(hotbar_state.active_group) else {
        return;
    };
    let Some(slot_state) = group.get_mut(slot) else {
        return;
    };
    let Some(skill_id) = slot_state.skill_id.clone() else {
        hotbar_state.last_activation_status = Some(format!("槽位 {} 为空", slot + 1));
        return;
    };
    if slot_state.cooldown_remaining > 0.0 {
        hotbar_state.last_activation_status = Some(format!(
            "{} 冷却中 {:.1}s",
            skill_id, slot_state.cooldown_remaining
        ));
        return;
    }
    let Some(actor_id) = player_actor_id(&runtime_state.runtime) else {
        return;
    };
    let learned_level = runtime_state
        .runtime
        .economy()
        .actor(actor_id)
        .and_then(|actor| actor.learned_skills.get(&skill_id))
        .copied()
        .unwrap_or(0);
    if learned_level <= 0 {
        hotbar_state.last_activation_status = Some(format!("{skill_id} 尚未学习"));
        return;
    }
    if let Some(skill) = skills.0.get(&skill_id) {
        if let Some(activation) = skill.activation.as_ref() {
            slot_state.cooldown_remaining = activation.cooldown.max(0.0);
            if activation.mode == "toggle" {
                slot_state.toggled = !slot_state.toggled;
                hotbar_state.last_activation_status = Some(format!(
                    "{} -> {}",
                    skill.name,
                    if slot_state.toggled { "ON" } else { "OFF" }
                ));
            } else {
                hotbar_state.last_activation_status = Some(format!("激活 {}", skill.name));
            }
        } else {
            hotbar_state.last_activation_status = Some(format!("{} 无主动效果", skill.name));
        }
    }
}

fn cycle_binding(settings: &mut ViewerUiSettings, action_name: &str) {
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

fn clear_ui_children(commands: &mut Commands, children: Option<&Children>) {
    if let Some(children) = children {
        for child in children.iter() {
            commands.entity(child).despawn();
        }
    }
}

fn text_bundle(font: &ViewerUiFont, text: &str, size: f32, color: Color) -> impl Bundle {
    (
        Text::new(text.to_string()),
        TextFont::from_font_size(size).with_font(font.0.clone()),
        TextColor(color),
    )
}

fn action_button(font: &ViewerUiFont, label: &str, action: GameUiButtonAction) -> impl Bundle {
    (
        Button,
        Node {
            padding: UiRect::axes(px(10), px(8)),
            margin: UiRect::bottom(px(4)),
            ..default()
        },
        BackgroundColor(interaction_menu_button_color(false, Interaction::None)),
        action,
        Text::new(label.to_string()),
        TextFont::from_font_size(11.0).with_font(font.0.clone()),
        TextColor(Color::WHITE),
    )
}

fn compact_action_button(
    font: &ViewerUiFont,
    label: &str,
    action: GameUiButtonAction,
    width: f32,
) -> impl Bundle {
    (
        Button,
        Node {
            width: px(width),
            min_height: px(34),
            padding: UiRect::axes(px(8), px(6)),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            ..default()
        },
        BackgroundColor(interaction_menu_button_color(false, Interaction::None)),
        action,
        Text::new(label.to_string()),
        TextFont::from_font_size(10.0).with_font(font.0.clone()),
        TextColor(Color::WHITE),
    )
}

fn hotbar_slot_button(
    font: &ViewerUiFont,
    label: &str,
    action: GameUiButtonAction,
    active: bool,
) -> impl Bundle {
    (
        Button,
        Node {
            width: px(74),
            min_height: px(56),
            padding: UiRect::all(px(6)),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            ..default()
        },
        BackgroundColor(if active {
            Color::srgba(0.24, 0.42, 0.26, 0.95).into()
        } else {
            interaction_menu_button_color(false, Interaction::None).into()
        }),
        action,
        Text::new(label.to_string()),
        TextFont::from_font_size(9.5).with_font(font.0.clone()),
        TextColor(Color::WHITE),
    )
}

fn render_main_menu(parent: &mut ChildSpawnerCommands, font: &ViewerUiFont) {
    parent.spawn((
        Node {
            position_type: PositionType::Absolute,
            left: Val::Percent(50.0),
            top: Val::Percent(50.0),
            margin: UiRect {
                left: px(-220),
                top: px(-150),
                ..default()
            },
            width: px(440),
            padding: UiRect::all(px(18)),
            flex_direction: FlexDirection::Column,
            row_gap: px(8),
            ..default()
        },
        BackgroundColor(Color::srgba(0.02, 0.03, 0.05, 0.96)),
        children![
            text_bundle(font, "CDC Survival Game", 20.0, Color::WHITE),
            text_bundle(
                font,
                "Bevy 主流程界面",
                12.0,
                Color::srgba(0.82, 0.86, 0.93, 1.0)
            ),
            action_button(font, "开始新游戏", GameUiButtonAction::MainMenuNewGame),
            action_button(font, "继续游戏", GameUiButtonAction::MainMenuContinue),
            action_button(font, "退出游戏", GameUiButtonAction::MainMenuExit),
        ],
    ));
}

fn render_menu_bar(parent: &mut ChildSpawnerCommands, font: &ViewerUiFont) {
    parent.spawn((
        Node {
            position_type: PositionType::Absolute,
            top: px(16),
            right: px(16),
            width: px(320),
            padding: UiRect::all(px(12)),
            flex_wrap: FlexWrap::Wrap,
            column_gap: px(6),
            ..default()
        },
        BackgroundColor(Color::srgba(0.03, 0.04, 0.06, 0.85)),
        children![
            action_button(
                font,
                "背包",
                GameUiButtonAction::TogglePanel(UiMenuPanel::Inventory)
            ),
            action_button(
                font,
                "角色",
                GameUiButtonAction::TogglePanel(UiMenuPanel::Character)
            ),
            action_button(
                font,
                "地图",
                GameUiButtonAction::TogglePanel(UiMenuPanel::Map)
            ),
            action_button(
                font,
                "任务",
                GameUiButtonAction::TogglePanel(UiMenuPanel::Journal)
            ),
            action_button(
                font,
                "技能",
                GameUiButtonAction::TogglePanel(UiMenuPanel::Skills)
            ),
            action_button(
                font,
                "制造",
                GameUiButtonAction::TogglePanel(UiMenuPanel::Crafting)
            ),
            action_button(
                font,
                "设置",
                GameUiButtonAction::TogglePanel(UiMenuPanel::Settings)
            ),
            action_button(font, "关闭", GameUiButtonAction::ClosePanels),
        ],
    ));
}

fn render_panel_shell(parent: &mut ChildSpawnerCommands, font: &ViewerUiFont, panel: UiMenuPanel) {
    let title = match panel {
        UiMenuPanel::Inventory => "背包与装备",
        UiMenuPanel::Character => "角色面板",
        UiMenuPanel::Map => "世界地图",
        UiMenuPanel::Journal => "任务面板",
        UiMenuPanel::Skills => "技能面板",
        UiMenuPanel::Crafting => "制造面板",
        UiMenuPanel::Settings => "设置面板",
    };
    parent.spawn((
        Node {
            position_type: PositionType::Absolute,
            top: px(96),
            right: px(16),
            width: px(UI_PANEL_WIDTH),
            padding: UiRect::all(px(14)),
            flex_direction: FlexDirection::Column,
            ..default()
        },
        BackgroundColor(Color::srgba(0.02, 0.03, 0.05, 0.97)),
        children![text_bundle(font, title, 14.0, Color::WHITE)],
    ));
}

fn panel_body(parent: &mut ChildSpawnerCommands) -> Entity {
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(132),
                right: px(16),
                width: px(UI_PANEL_WIDTH),
                max_height: Val::Percent(72.0),
                padding: UiRect::all(px(14)),
                flex_direction: FlexDirection::Column,
                row_gap: px(6),
                overflow: Overflow::clip_y(),
                ..default()
            },
            BackgroundColor(Color::srgba(0.02, 0.03, 0.05, 0.97)),
        ))
        .id()
}

fn render_inventory_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiInventoryPanelSnapshot,
) {
    let body = panel_body(parent);
    parent.commands().entity(body).with_children(|body| {
        body.spawn(text_bundle(
            font,
            &format!(
                "负重 {:.1}/{:.1} · 筛选 {}",
                snapshot.total_weight,
                snapshot.max_weight,
                snapshot.filter.label()
            ),
            11.0,
            Color::WHITE,
        ));
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
            body.spawn(action_button(
                font,
                filter.label(),
                GameUiButtonAction::InventoryFilter(filter),
            ));
        }
        for entry in &snapshot.entries {
            body.spawn(action_button(
                font,
                &format!(
                    "{} x{} · {} · {:.1}kg",
                    entry.name,
                    entry.count,
                    entry.item_type.as_str(),
                    entry.total_weight
                ),
                GameUiButtonAction::SelectInventoryItem(entry.item_id),
            ));
        }
        if snapshot.entries.is_empty() {
            body.spawn(text_bundle(font, "当前筛选下没有物品", 11.0, Color::WHITE));
        }
        if let Some(detail) = snapshot.detail.as_ref() {
            body.spawn(text_bundle(
                font,
                &format!(
                    "详情: {} · {} x{}",
                    detail.name,
                    detail.item_type.as_str(),
                    detail.count
                ),
                11.0,
                Color::srgba(0.80, 0.86, 0.96, 1.0),
            ));
            body.spawn(text_bundle(
                font,
                &format!("重量 {:.1}kg", detail.weight),
                10.5,
                Color::WHITE,
            ));
            body.spawn(text_bundle(font, &detail.description, 10.5, Color::WHITE));
            if detail.attribute_bonuses.is_empty() {
                body.spawn(text_bundle(font, "属性加成: 无", 10.5, Color::WHITE));
            } else {
                for (attribute, bonus) in &detail.attribute_bonuses {
                    body.spawn(text_bundle(
                        font,
                        &format!("属性加成 {attribute}: {bonus:+.1}"),
                        10.5,
                        Color::WHITE,
                    ));
                }
            }
            if snapshot
                .entries
                .iter()
                .find(|entry| entry.item_id == detail.item_id)
                .map(|entry| entry.can_use)
                .unwrap_or(false)
            {
                body.spawn(action_button(
                    font,
                    "使用",
                    GameUiButtonAction::UseInventoryItem,
                ));
            }
            if snapshot
                .entries
                .iter()
                .find(|entry| entry.item_id == detail.item_id)
                .map(|entry| entry.can_equip)
                .unwrap_or(false)
            {
                body.spawn(action_button(
                    font,
                    "装备",
                    GameUiButtonAction::EquipInventoryItem,
                ));
            }
        }
        for slot in &snapshot.equipment {
            body.spawn(action_button(
                font,
                &format!(
                    "{}: {}",
                    slot.slot_label,
                    slot.item_name.clone().unwrap_or_else(|| "空".to_string())
                ),
                GameUiButtonAction::MoveSelectedEquippedTo(slot.slot_id.clone()),
            ));
            body.spawn(action_button(
                font,
                "卸下",
                GameUiButtonAction::UnequipSlot(slot.slot_id.clone()),
            ));
        }
    });
}

fn render_character_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCharacterSnapshot,
) {
    let body = panel_body(parent);
    parent.commands().entity(body).with_children(|body| {
        body.spawn(text_bundle(
            font,
            &format!("可用属性点 {}", snapshot.available_points),
            11.0,
            Color::WHITE,
        ));
        for attribute in ["strength", "agility", "constitution"] {
            let value = snapshot.attributes.get(attribute).copied().unwrap_or(0);
            body.spawn(text_bundle(
                font,
                &format!("{attribute}: {value}"),
                11.0,
                Color::WHITE,
            ));
            body.spawn(action_button(
                font,
                &format!("提升 {attribute}"),
                GameUiButtonAction::AllocateAttribute(attribute.to_string()),
            ));
        }
    });
}

fn render_journal_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiJournalSnapshot,
) {
    let body = panel_body(parent);
    parent.commands().entity(body).with_children(|body| {
        if snapshot.quest_titles.is_empty() {
            body.spawn(text_bundle(
                font,
                "当前没有进行中的任务",
                11.0,
                Color::WHITE,
            ));
        } else {
            for title in &snapshot.quest_titles {
                body.spawn(text_bundle(font, title, 11.0, Color::WHITE));
            }
        }
    });
}

fn render_skills_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiSkillsSnapshot,
    hotbar_state: &UiHotbarState,
) {
    let body = panel_body(parent);
    parent.commands().entity(body).with_children(|body| {
        for entry in &snapshot.entries {
            body.spawn(action_button(
                font,
                &format!(
                    "{} [{}] Lv {}/{}",
                    entry.name, entry.tree_id, entry.learned_level, entry.max_level
                ),
                GameUiButtonAction::SelectSkill(entry.skill_id.clone()),
            ));
            if entry.learned_level > 0 {
                body.spawn(action_button(
                    font,
                    "加入快捷栏第1槽",
                    GameUiButtonAction::AssignSkillToHotbar {
                        skill_id: entry.skill_id.clone(),
                        group: hotbar_state.active_group,
                        slot: 0,
                    },
                ));
            }
        }
    });
}

fn render_crafting_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCraftingSnapshot,
) {
    let body = panel_body(parent);
    parent.commands().entity(body).with_children(|body| {
        if snapshot.recipe_names.is_empty() {
            body.spawn(text_bundle(font, "当前没有可制造配方", 11.0, Color::WHITE));
        } else {
            for (recipe_id, recipe_name) in &snapshot.recipe_names {
                body.spawn(action_button(
                    font,
                    recipe_name,
                    GameUiButtonAction::CraftRecipe(recipe_id.clone()),
                ));
            }
        }
    });
}

fn render_map_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    current: &game_core::OverworldStateSnapshot,
    overworld: &game_data::OverworldLibrary,
    menu_state: &UiMenuState,
) {
    let body = panel_body(parent);
    parent.commands().entity(body).with_children(|body| {
        let Some((_, definition)) = overworld.iter().next() else {
            return;
        };
        for location in &definition.locations {
            let is_unlocked = current
                .unlocked_locations
                .iter()
                .any(|id| id == location.id.as_str());
            let is_current =
                current.active_outdoor_location_id.as_deref() == Some(location.id.as_str());
            body.spawn(action_button(
                font,
                &format!(
                    "{} · {} · {}{}",
                    location.name,
                    match location.kind {
                        game_data::OverworldLocationKind::Outdoor => "outdoor",
                        game_data::OverworldLocationKind::Interior => "interior",
                        game_data::OverworldLocationKind::Dungeon => "dungeon",
                    },
                    if is_unlocked {
                        "已解锁"
                    } else {
                        "未解锁"
                    },
                    if is_current { " · 当前位置" } else { "" }
                ),
                GameUiButtonAction::SelectMapLocation(location.id.as_str().to_string()),
            ));
            if menu_state.selected_map_location_id.as_deref() == Some(location.id.as_str()) {
                body.spawn(text_bundle(
                    font,
                    "地图面板仅提供信息预览。正式旅行请改用场景内入口。",
                    10.5,
                    Color::WHITE,
                ));
                body.spawn(text_bundle(
                    font,
                    "旅行时间/食物/风险预览由 Rust 运行时路由查询提供。",
                    10.5,
                    Color::WHITE,
                ));
            }
        }
    });
}

fn render_settings_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    settings: &ViewerUiSettings,
) {
    let body = panel_body(parent);
    parent.commands().entity(body).with_children(|body| {
        body.spawn(action_button(
            font,
            &format!("Master {:.0}%", settings.master_volume * 100.0),
            GameUiButtonAction::SettingsSetMaster(if settings.master_volume > 0.0 {
                0.0
            } else {
                1.0
            }),
        ));
        body.spawn(action_button(
            font,
            &format!("Music {:.0}%", settings.music_volume * 100.0),
            GameUiButtonAction::SettingsSetMusic(if settings.music_volume > 0.0 {
                0.0
            } else {
                1.0
            }),
        ));
        body.spawn(action_button(
            font,
            &format!("SFX {:.0}%", settings.sfx_volume * 100.0),
            GameUiButtonAction::SettingsSetSfx(if settings.sfx_volume > 0.0 { 0.0 } else { 1.0 }),
        ));
        body.spawn(action_button(
            font,
            &format!("窗口模式 {}", settings.window_mode),
            GameUiButtonAction::SettingsSetWindowMode(match settings.window_mode.as_str() {
                "windowed" => "borderless_fullscreen".to_string(),
                "borderless_fullscreen" => "fullscreen".to_string(),
                _ => "windowed".to_string(),
            }),
        ));
        body.spawn(action_button(
            font,
            &format!("VSync {}", if settings.vsync { "On" } else { "Off" }),
            GameUiButtonAction::SettingsSetVsync(!settings.vsync),
        ));
        body.spawn(action_button(
            font,
            &format!("UI Scale {:.1}", settings.ui_scale),
            GameUiButtonAction::SettingsSetUiScale(if settings.ui_scale < 1.0 {
                1.0
            } else {
                0.85
            }),
        ));
        for action_name in [
            "menu_inventory",
            "menu_character",
            "menu_map",
            "menu_journal",
            "menu_skills",
            "menu_crafting",
        ] {
            let current = settings
                .action_bindings
                .get(action_name)
                .cloned()
                .unwrap_or_else(|| "Unbound".to_string());
            body.spawn(action_button(
                font,
                &format!("{action_name}: {current}"),
                GameUiButtonAction::SettingsCycleBinding(action_name.to_string()),
            ));
        }
        body.spawn(text_bundle(
            font,
            "设置面板快捷键固定为 Escape。",
            10.0,
            Color::WHITE,
        ));
    });
}

fn render_trade_modal(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiTradeSnapshot,
) {
    parent.spawn((
        Node {
            position_type: PositionType::Absolute,
            left: Val::Percent(50.0),
            top: Val::Percent(50.0),
            margin: UiRect {
                left: px(-340),
                top: px(-220),
                ..default()
            },
            width: px(680),
            padding: UiRect::all(px(16)),
            flex_direction: FlexDirection::Column,
            row_gap: px(6),
            ..default()
        },
        BackgroundColor(Color::srgba(0.02, 0.03, 0.05, 0.98)),
        children![
            text_bundle(
                font,
                &format!(
                    "交易 {} · 友好度 {} · 玩家 {} · 商店 {}",
                    snapshot.shop_id,
                    snapshot.relation_score,
                    snapshot.player_money,
                    snapshot.shop_money
                ),
                12.0,
                Color::WHITE
            ),
            action_button(font, "关闭交易", GameUiButtonAction::CloseTrade),
        ],
    ));
    let body = panel_body(parent);
    parent.commands().entity(body).with_children(|body| {
        body.spawn(text_bundle(font, "玩家库存", 11.0, Color::WHITE));
        if snapshot.player_items.is_empty() {
            body.spawn(text_bundle(font, "玩家没有可售物品", 11.0, Color::WHITE));
        }
        for item in &snapshot.player_items {
            body.spawn(action_button(
                font,
                &format!(
                    "卖出 {} x{} · {} · {:.1}kg",
                    item.name, item.count, item.unit_price, item.total_weight
                ),
                GameUiButtonAction::SellTradeItem {
                    shop_id: snapshot.shop_id.clone(),
                    item_id: item.item_id,
                },
            ));
        }
        body.spawn(text_bundle(font, "商店库存", 11.0, Color::WHITE));
        if snapshot.shop_items.is_empty() {
            body.spawn(text_bundle(font, "商店库存为空", 11.0, Color::WHITE));
        }
        for item in &snapshot.shop_items {
            body.spawn(action_button(
                font,
                &format!(
                    "买入 {} x{} · {} · {:.1}kg",
                    item.name, item.count, item.unit_price, item.total_weight
                ),
                GameUiButtonAction::BuyTradeItem {
                    shop_id: snapshot.shop_id.clone(),
                    item_id: item.item_id,
                },
            ));
        }
    });
}

fn render_hotbar(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    hotbar_state: &UiHotbarState,
    selected_skill_id: Option<&str>,
) {
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                bottom: px(16),
                margin: UiRect {
                    left: px(-(HOTBAR_WIDTH / 2.0)),
                    ..default()
                },
                width: px(HOTBAR_WIDTH),
                padding: UiRect::all(px(10)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                ..default()
            },
            BackgroundColor(Color::srgba(0.02, 0.03, 0.05, 0.84)),
            children![text_bundle(
                font,
                &format!(
                    "快捷栏组 {}{}",
                    hotbar_state.active_group + 1,
                    hotbar_state
                        .last_activation_status
                        .as_ref()
                        .map(|status| format!(" · {status}"))
                        .unwrap_or_default()
                ),
                11.0,
                Color::WHITE
            )],
        ))
        .with_children(|body| {
            body.spawn(text_bundle(
                font,
                &selected_skill_id
                    .map(|skill_id| format!("已选技能: {skill_id}，点击下方槽位可绑定"))
                    .unwrap_or_else(|| "快捷栏固定在底部，数字键 1-0 激活当前组槽位".to_string()),
                10.5,
                Color::WHITE,
            ));
            body.spawn(Node {
                width: Val::Percent(100.0),
                flex_direction: FlexDirection::Row,
                column_gap: px(6),
                justify_content: JustifyContent::Center,
                ..default()
            })
            .with_children(|groups| {
                for group_index in 0..hotbar_state.groups.len() {
                    let label = if group_index == hotbar_state.active_group {
                        format!("组{}", group_index + 1)
                    } else {
                        format!("切到{}", group_index + 1)
                    };
                    groups.spawn(compact_action_button(
                        font,
                        &label,
                        GameUiButtonAction::SelectHotbarGroup(group_index),
                        72.0,
                    ));
                }
            });
            if let Some(active_group) = hotbar_state.groups.get(hotbar_state.active_group) {
                body.spawn(Node {
                    width: Val::Percent(100.0),
                    flex_direction: FlexDirection::Row,
                    column_gap: px(6),
                    justify_content: JustifyContent::Center,
                    ..default()
                })
                .with_children(|slots| {
                    for (slot_index, slot) in active_group.iter().enumerate() {
                        let slot_label = match slot.skill_id.as_deref() {
                            Some(skill_id) => {
                                let short = skill_id.chars().take(8).collect::<String>();
                                format!(
                                    "{}\n{}{}{}",
                                    slot_index + 1,
                                    short,
                                    if slot.toggled { "\nON" } else { "" },
                                    if slot.cooldown_remaining > 0.0 {
                                        format!("\n{:.1}s", slot.cooldown_remaining)
                                    } else {
                                        String::new()
                                    }
                                )
                            }
                            None => format!("{}\n空槽", slot_index + 1),
                        };
                        let primary_action = if let Some(skill_id) = selected_skill_id {
                            GameUiButtonAction::AssignSkillToHotbar {
                                skill_id: skill_id.to_string(),
                                group: hotbar_state.active_group,
                                slot: slot_index,
                            }
                        } else {
                            GameUiButtonAction::ActivateHotbarSlot(slot_index)
                        };
                        slots.spawn(hotbar_slot_button(
                            font,
                            &slot_label,
                            primary_action,
                            slot.toggled,
                        ));
                    }
                });
                body.spawn(Node {
                    width: Val::Percent(100.0),
                    flex_direction: FlexDirection::Row,
                    column_gap: px(6),
                    justify_content: JustifyContent::Center,
                    ..default()
                })
                .with_children(|clears| {
                    for (slot_index, slot) in active_group.iter().enumerate() {
                        let label = if slot.skill_id.is_some() {
                            format!("清空{}", slot_index + 1)
                        } else {
                            format!("槽位{}", slot_index + 1)
                        };
                        clears.spawn(compact_action_button(
                            font,
                            &label,
                            GameUiButtonAction::ClearHotbarSlot {
                                group: hotbar_state.active_group,
                                slot: slot_index,
                            },
                            74.0,
                        ));
                    }
                });
            }
        });
}

fn apply_ui_settings(
    _settings: &ViewerUiSettings,
    _render_config: &mut ViewerRenderConfig,
    ui_scale: &mut UiScale,
    window: &mut Window,
) {
    ui_scale.0 = _settings.ui_scale.max(0.5);
    window.mode = match _settings.window_mode.as_str() {
        "fullscreen" => {
            WindowMode::Fullscreen(MonitorSelection::Primary, VideoModeSelection::Current)
        }
        "borderless_fullscreen" => WindowMode::BorderlessFullscreen(MonitorSelection::Primary),
        _ => WindowMode::Windowed,
    };
    window.present_mode = if _settings.vsync {
        PresentMode::AutoVsync
    } else {
        PresentMode::AutoNoVsync
    };
}

fn trade_session_for_target(
    runtime_state: &ViewerRuntimeState,
    target: &InteractionTargetId,
    shops: &game_data::ShopLibrary,
) -> Option<game_bevy::UiTradeSessionState> {
    let target_actor_id = match target {
        InteractionTargetId::Actor(actor_id) => Some(*actor_id),
        _ => None,
    };
    let snapshot = runtime_state.runtime.snapshot();
    let mut resolved_shop_id = None;
    if let Some(target_actor_id) = target_actor_id {
        if let Some(actor) = snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == target_actor_id)
        {
            if let Some(definition_id) = actor.definition_id.as_ref() {
                let candidate = format!("{}_shop", definition_id.as_str());
                if shops.get(&candidate).is_some() {
                    resolved_shop_id = Some(candidate);
                }
            }
        }
    }
    resolved_shop_id
        .or_else(|| shops.iter().next().map(|(shop_id, _)| shop_id.clone()))
        .map(|shop_id| game_bevy::UiTradeSessionState {
            shop_id,
            target_actor_id,
        })
}
