use std::fs;
use std::marker::PhantomData;

use bevy::ecs::system::SystemParam;
use bevy::prelude::*;
use bevy::ui::{FocusPolicy, RelativeCursorPosition};
use bevy::window::{PresentMode, VideoModeSelection, WindowMode};
use game_bevy::{
    character_snapshot, interaction_prompt_text, inventory_snapshot, journal_snapshot,
    player_actor_id, skills_snapshot, trade_snapshot, world_status_snapshot, EffectDefinitions,
    ItemDefinitions, OverworldDefinitions, QuestDefinitions, RecipeDefinitions, ShopDefinitions,
    SkillDefinitions, SkillTreeDefinitions, UiHotbarState, UiInputBlockState, UiInventoryFilter,
    UiInventoryFilterState, UiMenuPanel, UiMenuState, UiModalState, UiStatusBannerState,
};
use game_core::RuntimeSnapshot;
use game_data::{ActorId, InteractionTargetId};

use crate::bootstrap::load_viewer_gameplay_bootstrap;
use crate::controls::{cancel_targeting, enter_attack_targeting, enter_skill_targeting};
use crate::render::interaction_menu_button_color;
use crate::simulation::{reset_viewer_runtime_transients, sync_viewer_runtime_basics};
use crate::state::{
    GameUiButtonAction, GameUiRoot, UiMouseBlocker, ViewerPalette, ViewerRenderConfig,
    ViewerRuntimeSavePath, ViewerRuntimeState, ViewerSceneKind, ViewerState, ViewerUiFont,
    ViewerUiSettings, ViewerUiSettingsPath,
};

const UI_PANEL_WIDTH: f32 = 448.0;
const SKILLS_PANEL_WIDTH: f32 = 940.0;
const SCREEN_EDGE_PADDING: f32 = 18.0;
const TOP_INFO_WIDTH: f32 = 372.0;
const TOP_BADGE_WIDTH: f32 = 348.0;
const RIGHT_PANEL_TOP: f32 = 74.0;
const RIGHT_PANEL_BOTTOM: f32 = 174.0;
const RIGHT_PANEL_HEADER_HEIGHT: f32 = 58.0;
pub(crate) const HOTBAR_DOCK_WIDTH: f32 = 1088.0;
pub(crate) const HOTBAR_DOCK_HEIGHT: f32 = 124.0;
const HOTBAR_SLOT_SIZE: f32 = 56.0;
const HOTBAR_ACTION_WIDTH: f32 = 88.0;
const HOTBAR_LEFT_TABS_WIDTH: f32 = 154.0;
const HOTBAR_RIGHT_TABS_WIDTH: f32 = 254.0;
const BOTTOM_TAB_HEIGHT: f32 = 22.0;

#[derive(Debug, Clone)]
struct PlayerHudStats {
    display_name: String,
    level: i32,
    hp: f32,
    max_hp: f32,
    ap: f32,
    available_steps: i32,
    in_combat: bool,
}

#[derive(SystemParam)]
pub(crate) struct GameUiViewState<'w, 's> {
    runtime_state: Res<'w, ViewerRuntimeState>,
    scene_kind: Res<'w, ViewerSceneKind>,
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
    scene_kind: ResMut<'w, ViewerSceneKind>,
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
    menu_state.main_menu_open = false;
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
    scene_kind: Res<ViewerSceneKind>,
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
    let targeting_prompt = viewer_state
        .targeting_state
        .as_ref()
        .map(|targeting| targeting.prompt_text.clone());
    banner_state.detail = [
        Some(banner.detail),
        (!prompt_text.is_empty()).then_some(prompt_text),
        targeting_prompt,
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

    let in_main_menu_scene = should_render_main_menu(*scene_kind);
    input_block_state.blocked = in_main_menu_scene
        || menu_state.active_panel.is_some()
        || modal_state.trade.is_some()
        || viewer_state.active_dialogue.is_some()
        || viewer_state.interaction_menu.is_some();
    if (in_main_menu_scene
        || menu_state.active_panel.is_some()
        || modal_state.trade.is_some()
        || viewer_state.active_dialogue.is_some())
        && viewer_state.interaction_menu.is_some()
    {
        viewer_state.interaction_menu = None;
    }
    input_block_state.reason = if in_main_menu_scene {
        "main_menu_scene".to_string()
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

    if input_block_state.blocked && viewer_state.targeting_state.is_some() {
        cancel_targeting(&mut viewer_state, "targeting: 已取消");
    }
}

pub(crate) fn tick_hotbar_cooldowns(
    time: Res<Time>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut hotbar: ResMut<UiHotbarState>,
) {
    runtime_state
        .runtime
        .advance_skill_timers(time.delta_secs());
    let Some(actor_id) = player_actor_id(&runtime_state.runtime) else {
        return;
    };

    for group in &mut hotbar.groups {
        for slot in group {
            if let Some(skill_id) = slot.skill_id.as_deref() {
                slot.cooldown_remaining = runtime_state
                    .runtime
                    .skill_cooldown_remaining(actor_id, skill_id);
                slot.toggled = runtime_state
                    .runtime
                    .is_skill_toggled_active(actor_id, skill_id);
            } else {
                slot.cooldown_remaining = 0.0;
                slot.toggled = false;
            }
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
    let _ = palette;
    let player_actor = player_actor_id(&ui.runtime_state.runtime);
    let player_stats =
        player_actor.and_then(|actor_id| player_hud_stats(&ui.runtime_state, actor_id));
    let esc_menu_open = ui.menu_state.active_panel == Some(UiMenuPanel::Settings);

    commands.entity(entity).with_children(|parent| {
        let in_main_menu_scene = should_render_main_menu(*ui.scene_kind);

        if in_main_menu_scene {
            render_main_menu(parent, &font, &ui.menu_state.status_text);
        } else if !esc_menu_open {
            render_top_left_info(
                parent,
                &font,
                &ui.banner_state,
                &ui.viewer_state,
                player_stats.as_ref(),
            );
            render_top_center_badges(
                parent,
                &font,
                *ui.scene_kind,
                &ui.viewer_state,
                player_stats.as_ref(),
                &ui.menu_state,
            );
            render_hotbar(
                parent,
                &font,
                &ui.viewer_state,
                &ui.hotbar_state,
                &content.skills.0,
                &ui.menu_state,
                player_stats.as_ref(),
                ui.menu_state.active_panel == Some(UiMenuPanel::Skills),
                ui.menu_state.selected_skill_id.as_deref(),
            );
        }

        if let Some(actor_id) = player_actor {
            if let Some(panel) = ui.menu_state.active_panel {
                match panel {
                    UiMenuPanel::Inventory => {
                        render_panel_shell(parent, &font, panel);
                        let snapshot = inventory_snapshot(
                            &ui.runtime_state.runtime,
                            actor_id,
                            &content.items.0,
                            ui.filter_state.filter,
                            ui.menu_state.selected_inventory_item,
                        );
                        render_inventory_panel(parent, &font, &snapshot, &ui.menu_state);
                    }
                    UiMenuPanel::Character => {
                        render_panel_shell(parent, &font, panel);
                        let snapshot = character_snapshot(&ui.runtime_state.runtime, actor_id);
                        render_character_panel(parent, &font, &snapshot);
                    }
                    UiMenuPanel::Journal => {
                        render_panel_shell(parent, &font, panel);
                        let snapshot = journal_snapshot(
                            &ui.runtime_state.runtime,
                            actor_id,
                            &content.quests.0,
                        );
                        render_journal_panel(parent, &font, &snapshot);
                    }
                    UiMenuPanel::Skills => {
                        render_panel_shell(parent, &font, panel);
                        let snapshot = skills_snapshot(
                            &ui.runtime_state.runtime,
                            actor_id,
                            &content.skills.0,
                            &content.skill_trees.0,
                        );
                        render_skills_panel(
                            parent,
                            &font,
                            &snapshot,
                            &ui.menu_state,
                            &ui.hotbar_state,
                        );
                    }
                    UiMenuPanel::Crafting => {
                        render_panel_shell(parent, &font, panel);
                        let snapshot = game_bevy::crafting_snapshot(
                            &ui.runtime_state.runtime,
                            actor_id,
                            &content.recipes.0,
                        );
                        render_crafting_panel(parent, &font, &snapshot);
                    }
                    UiMenuPanel::Map => {
                        render_panel_shell(parent, &font, panel);
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

            if !esc_menu_open {
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

fn transition_to_gameplay_scene(
    scene_kind: &mut ViewerSceneKind,
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    menu_state: &mut UiMenuState,
    modal_state: &mut UiModalState,
    status_text: &str,
) {
    *scene_kind = ViewerSceneKind::Gameplay;
    reset_viewer_runtime_transients(viewer_state);
    sync_viewer_runtime_basics(runtime_state, viewer_state);
    viewer_state.status_line = status_text.to_string();
    menu_state.main_menu_open = false;
    menu_state.active_panel = None;
    menu_state.selected_inventory_item = None;
    menu_state.selected_equipment_slot = None;
    menu_state.selected_skill_tree_id = None;
    menu_state.selected_skill_id = None;
    menu_state.selected_recipe_id = None;
    menu_state.selected_map_location_id = None;
    menu_state.status_text = status_text.to_string();
    modal_state.trade = None;
}

fn should_render_main_menu(scene_kind: ViewerSceneKind) -> bool {
    scene_kind.is_main_menu()
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
        .economy_mut()
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
        .economy_mut()
        .equip_item(actor_id, 1002, Some("main_hand"), &items.0)
        .map_err(|error| error.to_string())?;
    let _ = runtime
        .economy_mut()
        .equip_item(actor_id, 2004, Some("body"), &items.0);
    let _ = runtime
        .economy_mut()
        .equip_item(actor_id, 2013, Some("legs"), &items.0);
    let _ = runtime
        .economy_mut()
        .equip_item(actor_id, 2015, Some("feet"), &items.0);
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
    let mut bootstrap = load_viewer_gameplay_bootstrap().map_err(|error| error.to_string())?;
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

fn skills_snapshot_for_player(
    runtime_state: &ViewerRuntimeState,
    skills: &SkillDefinitions,
    trees: &SkillTreeDefinitions,
) -> Option<game_bevy::UiSkillsSnapshot> {
    let actor_id = player_actor_id(&runtime_state.runtime)?;
    Some(skills_snapshot(
        &runtime_state.runtime,
        actor_id,
        &skills.0,
        &trees.0,
    ))
}

fn find_skill_tree_id<'a>(
    snapshot: &'a game_bevy::UiSkillsSnapshot,
    skill_id: &str,
) -> Option<&'a str> {
    snapshot.trees.iter().find_map(|tree| {
        tree.entries
            .iter()
            .any(|entry| entry.skill_id == skill_id)
            .then_some(tree.tree_id.as_str())
    })
}

fn sync_skill_selection_state(
    menu_state: &mut UiMenuState,
    runtime_state: &ViewerRuntimeState,
    skills: &SkillDefinitions,
    trees: &SkillTreeDefinitions,
) {
    let Some(snapshot) = skills_snapshot_for_player(runtime_state, skills, trees) else {
        menu_state.selected_skill_tree_id = None;
        menu_state.selected_skill_id = None;
        return;
    };

    let tree_from_selected_skill = menu_state
        .selected_skill_id
        .as_deref()
        .and_then(|skill_id| find_skill_tree_id(&snapshot, skill_id));
    let selected_tree = tree_from_selected_skill
        .and_then(|tree_id| snapshot.trees.iter().find(|tree| tree.tree_id == tree_id))
        .or_else(|| {
            menu_state
                .selected_skill_tree_id
                .as_deref()
                .and_then(|tree_id| snapshot.trees.iter().find(|tree| tree.tree_id == tree_id))
        })
        .or_else(|| snapshot.trees.iter().find(|tree| !tree.entries.is_empty()))
        .or_else(|| snapshot.trees.first());

    let Some(selected_tree) = selected_tree else {
        menu_state.selected_skill_tree_id = None;
        menu_state.selected_skill_id = None;
        return;
    };

    menu_state.selected_skill_tree_id = Some(selected_tree.tree_id.clone());
    let selected_skill_is_in_tree = menu_state
        .selected_skill_id
        .as_deref()
        .and_then(|skill_id| {
            selected_tree
                .entries
                .iter()
                .find(|entry| entry.skill_id == skill_id)
        })
        .is_some();
    if !selected_skill_is_in_tree {
        menu_state.selected_skill_id = selected_tree
            .entries
            .first()
            .map(|entry| entry.skill_id.clone());
    }
}

fn validate_hotbar_skill_binding(
    runtime_state: &ViewerRuntimeState,
    skills: &SkillDefinitions,
    skill_id: &str,
) -> Result<(), String> {
    let Some(actor_id) = player_actor_id(&runtime_state.runtime) else {
        return Err("missing_player".to_string());
    };
    let Some(skill) = skills.0.get(skill_id) else {
        return Err(format!("未知技能 {skill_id}"));
    };
    let learned_level = runtime_state
        .runtime
        .economy()
        .actor(actor_id)
        .and_then(|actor| actor.learned_skills.get(skill_id))
        .copied()
        .unwrap_or(0);
    if learned_level <= 0 {
        return Err(format!("{} 尚未学习", skill.name));
    }
    let activation_mode = skill
        .activation
        .as_ref()
        .map(|activation| activation.mode.as_str())
        .unwrap_or("passive");
    if activation_mode == "passive" {
        return Err(format!("{} 为被动技能，无法绑定快捷栏", skill.name));
    }
    Ok(())
}

fn assign_skill_to_hotbar_slot(
    hotbar_state: &mut UiHotbarState,
    menu_state: &mut UiMenuState,
    skill_id: String,
    group: usize,
    slot: usize,
) -> bool {
    let Some(group_slots) = hotbar_state.groups.get_mut(group) else {
        menu_state.status_text = format!("快捷栏第 {} 组不存在", group.saturating_add(1));
        return false;
    };
    let Some(slot_state) = group_slots.get_mut(slot) else {
        menu_state.status_text = format!(
            "快捷栏第 {} 组不存在第 {} 槽",
            group.saturating_add(1),
            slot.saturating_add(1)
        );
        return false;
    };

    slot_state.skill_id = Some(skill_id.clone());
    slot_state.cooldown_remaining = 0.0;
    slot_state.toggled = false;
    menu_state.status_text = format!(
        "已将 {skill_id} 绑定到第 {} 组第 {} 槽",
        group.saturating_add(1),
        slot.saturating_add(1)
    );
    true
}

pub(crate) fn activate_hotbar_slot(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
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
    let Some(actor_id) = player_actor_id(&runtime_state.runtime) else {
        return;
    };
    let runtime_skill_state = runtime_state.runtime.skill_state(actor_id, &skill_id);
    if runtime_skill_state.cooldown_remaining > 0.0 {
        hotbar_state.last_activation_status = Some(format!(
            "{} 冷却中 {:.1}s",
            skill_id, runtime_skill_state.cooldown_remaining
        ));
        return;
    }
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
            if activation
                .targeting
                .as_ref()
                .is_some_and(|targeting| targeting.enabled)
            {
                match enter_skill_targeting(
                    runtime_state,
                    viewer_state,
                    skills,
                    &skill_id,
                    crate::state::ViewerTargetingSource::HotbarSlot(slot),
                ) {
                    Ok(()) => {
                        hotbar_state.last_activation_status =
                            Some(format!("{}: 选择目标", skill.name));
                    }
                    Err(error) => {
                        hotbar_state.last_activation_status = Some(error);
                    }
                }
            } else {
                let actor_grid = runtime_state
                    .runtime
                    .get_actor_grid_position(actor_id)
                    .unwrap_or_default();
                let result = runtime_state.runtime.activate_skill(
                    actor_id,
                    &skill_id,
                    game_data::SkillTargetRequest::Grid(actor_grid),
                );
                slot_state.cooldown_remaining = runtime_state
                    .runtime
                    .skill_cooldown_remaining(actor_id, &skill_id);
                slot_state.toggled = runtime_state
                    .runtime
                    .is_skill_toggled_active(actor_id, &skill_id);
                hotbar_state.last_activation_status = Some(if result.action_result.success {
                    format!(
                        "{}: {}",
                        skill.name,
                        game_core::runtime::action_result_status(&result.action_result)
                    )
                } else {
                    format!(
                        "{}: {}",
                        skill.name,
                        result
                            .failure_reason
                            .clone()
                            .or(result.action_result.reason.clone())
                            .unwrap_or_else(|| "failed".to_string())
                    )
                });
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
            padding: UiRect::axes(px(10), px(7)),
            margin: UiRect::bottom(px(4)),
            border: UiRect::all(px(1)),
            ..default()
        },
        BackgroundColor(interaction_menu_button_color(false, Interaction::None)),
        BorderColor::all(Color::srgba(0.19, 0.24, 0.32, 1.0)),
        action,
        Text::new(label.to_string()),
        TextFont::from_font_size(11.0).with_font(font.0.clone()),
        TextColor(Color::WHITE),
    )
}

fn panel_title(panel: UiMenuPanel) -> &'static str {
    match panel {
        UiMenuPanel::Inventory => "行囊",
        UiMenuPanel::Character => "角色",
        UiMenuPanel::Map => "地图",
        UiMenuPanel::Journal => "任务",
        UiMenuPanel::Skills => "技能",
        UiMenuPanel::Crafting => "制造",
        UiMenuPanel::Settings => "设置",
    }
}

fn panel_tab_label(panel: UiMenuPanel) -> &'static str {
    match panel {
        UiMenuPanel::Inventory => "Inventory",
        UiMenuPanel::Character => "Character",
        UiMenuPanel::Map => "Map",
        UiMenuPanel::Journal => "Quest",
        UiMenuPanel::Skills => "Skills",
        UiMenuPanel::Crafting => "Crafting",
        UiMenuPanel::Settings => "Menu",
    }
}

fn panel_width(panel: UiMenuPanel) -> f32 {
    match panel {
        UiMenuPanel::Skills => SKILLS_PANEL_WIDTH,
        _ => UI_PANEL_WIDTH,
    }
}

fn player_hud_stats(
    runtime_state: &ViewerRuntimeState,
    actor_id: ActorId,
) -> Option<PlayerHudStats> {
    runtime_state
        .runtime
        .snapshot()
        .actors
        .into_iter()
        .find(|actor| actor.actor_id == actor_id)
        .map(|actor| PlayerHudStats {
            display_name: actor.display_name,
            level: actor.level,
            hp: actor.hp,
            max_hp: actor.max_hp,
            ap: actor.ap,
            available_steps: actor.available_steps,
            in_combat: actor.in_combat,
        })
}

fn action_meter_ratio(stats: &PlayerHudStats) -> f32 {
    if stats.in_combat {
        (stats.ap / 10.0).clamp(0.0, 1.0)
    } else {
        ((stats.available_steps as f32) / 12.0).clamp(0.0, 1.0)
    }
}

fn render_top_left_info(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    banner_state: &UiStatusBannerState,
    viewer_state: &ViewerState,
    player_stats: Option<&PlayerHudStats>,
) {
    let mut detail_lines = Vec::new();
    if !banner_state.detail.trim().is_empty() {
        detail_lines.push(banner_state.detail.trim().to_string());
    }
    if let Some(stats) = player_stats {
        detail_lines.push(format!(
            "{} · Lv {} · AP {:.1} · 步数 {}",
            stats.display_name, stats.level, stats.ap, stats.available_steps
        ));
    }
    if !viewer_state.status_line.trim().is_empty()
        && !detail_lines
            .iter()
            .any(|line| line == &viewer_state.status_line)
    {
        detail_lines.push(viewer_state.status_line.trim().to_string());
    }
    if detail_lines.is_empty() && !banner_state.visible {
        return;
    }

    let title = if banner_state.title.trim().is_empty() {
        "当前状态"
    } else {
        banner_state.title.as_str()
    };
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(SCREEN_EDGE_PADDING),
                left: px(SCREEN_EDGE_PADDING),
                width: px(TOP_INFO_WIDTH),
                padding: UiRect::axes(px(14), px(12)),
                flex_direction: FlexDirection::Column,
                row_gap: px(4),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.04, 0.05, 0.07, 0.93)),
            BorderColor::all(Color::srgba(0.18, 0.21, 0.29, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .with_children(|panel| {
            panel.spawn(text_bundle(font, title, 12.8, Color::WHITE));
            for line in detail_lines {
                panel.spawn(text_bundle(
                    font,
                    &line,
                    10.4,
                    Color::srgba(0.82, 0.86, 0.93, 1.0),
                ));
            }
        });
}

fn render_top_center_badges(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    scene_kind: ViewerSceneKind,
    viewer_state: &ViewerState,
    player_stats: Option<&PlayerHudStats>,
    menu_state: &UiMenuState,
) {
    if scene_kind.is_main_menu() {
        return;
    }
    let badges = [
        if let Some(stats) = player_stats {
            format!("HP {:.0}/{:.0}", stats.hp, stats.max_hp)
        } else {
            "HP --".to_string()
        },
        if let Some(stats) = player_stats {
            format!("行动 {:.1} / {}", stats.ap, stats.available_steps)
        } else {
            "行动 --".to_string()
        },
        format!("楼层 {}", viewer_state.current_level),
        format!("模式 {}", viewer_state.control_mode.label()),
        menu_state
            .active_panel
            .map(|panel| format!("面板 {}", panel_title(panel)))
            .unwrap_or_else(|| "探索".to_string()),
    ];
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(SCREEN_EDGE_PADDING),
                left: Val::Percent(50.0),
                margin: UiRect {
                    left: px(-(TOP_BADGE_WIDTH / 2.0)),
                    ..default()
                },
                width: px(TOP_BADGE_WIDTH),
                justify_content: JustifyContent::Center,
                ..default()
            },
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .with_children(|wrap| {
            wrap.spawn(Node {
                padding: UiRect::axes(px(10), px(8)),
                column_gap: px(6),
                flex_wrap: FlexWrap::Wrap,
                justify_content: JustifyContent::Center,
                ..default()
            })
            .with_children(|row| {
                for badge in badges {
                    row.spawn((
                        Node {
                            padding: UiRect::axes(px(10), px(5)),
                            margin: UiRect::all(px(2)),
                            border: UiRect::all(px(1)),
                            ..default()
                        },
                        BackgroundColor(Color::srgba(0.08, 0.09, 0.13, 0.94)),
                        BorderColor::all(Color::srgba(0.24, 0.27, 0.37, 1.0)),
                        children![text_bundle(
                            font,
                            &badge,
                            9.6,
                            Color::srgba(0.92, 0.95, 1.0, 1.0)
                        )],
                    ));
                }
            });
        });
}

fn render_stat_meter(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    label: &str,
    value_text: &str,
    ratio: f32,
    fill_color: Color,
    border_color: Color,
) {
    parent
        .spawn((
            Node {
                flex_grow: 1.0,
                min_width: px(120),
                flex_direction: FlexDirection::Column,
                row_gap: px(4),
                ..default()
            },
            BackgroundColor(Color::NONE),
        ))
        .with_children(|meter| {
            meter
                .spawn(Node {
                    width: Val::Percent(100.0),
                    flex_direction: FlexDirection::Row,
                    justify_content: JustifyContent::SpaceBetween,
                    ..default()
                })
                .with_children(|labels| {
                    labels.spawn(text_bundle(
                        font,
                        label,
                        9.6,
                        Color::srgba(0.84, 0.88, 0.95, 1.0),
                    ));
                    labels.spawn(text_bundle(font, value_text, 9.6, Color::WHITE));
                });
            meter
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        height: px(18),
                        padding: UiRect::all(px(2)),
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(Color::srgba(0.05, 0.06, 0.08, 0.98)),
                    BorderColor::all(border_color),
                ))
                .with_children(|track| {
                    track.spawn((
                        Node {
                            width: Val::Percent((ratio.clamp(0.0, 1.0)) * 100.0),
                            height: Val::Percent(100.0),
                            ..default()
                        },
                        BackgroundColor(fill_color),
                    ));
                });
        });
}

fn dock_tab_button(
    font: &ViewerUiFont,
    label: &str,
    active: bool,
    action: GameUiButtonAction,
) -> impl Bundle {
    (
        Button,
        Node {
            height: px(BOTTOM_TAB_HEIGHT),
            padding: UiRect::axes(px(7), px(3)),
            border: UiRect::all(px(if active { 2.0 } else { 1.0 })),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            ..default()
        },
        BackgroundColor(if active {
            Color::srgba(0.15, 0.18, 0.26, 0.98).into()
        } else {
            Color::srgba(0.07, 0.08, 0.11, 0.95).into()
        }),
        BorderColor::all(if active {
            Color::srgba(0.62, 0.72, 0.90, 1.0)
        } else {
            Color::srgba(0.21, 0.24, 0.31, 1.0)
        }),
        action,
        Text::new(label.to_string()),
        TextFont::from_font_size(8.3).with_font(font.0.clone()),
        TextColor(if active {
            Color::WHITE
        } else {
            Color::srgba(0.80, 0.84, 0.90, 1.0)
        }),
    )
}

fn activation_mode_label(mode: &str) -> String {
    match mode {
        "passive" => "被动".to_string(),
        "toggle" => "开关".to_string(),
        "active" => "主动".to_string(),
        "instant" => "瞬发".to_string(),
        "channeled" => "引导".to_string(),
        other => other.to_string(),
    }
}

fn truncate_ui_text(text: &str, max_chars: usize) -> String {
    let trimmed = text.trim();
    let total_chars = trimmed.chars().count();
    if total_chars <= max_chars {
        return trimmed.to_string();
    }
    let visible = max_chars.saturating_sub(1);
    let prefix = trimmed.chars().take(visible).collect::<String>();
    format!("{prefix}…")
}

fn compact_skill_name(name: &str, max_chars: usize) -> String {
    truncate_ui_text(name, max_chars)
}

fn abbreviated_skill_name(name: &str) -> String {
    let initials = name
        .split(|ch: char| ch.is_whitespace() || ch == '_' || ch == '-')
        .filter(|part| !part.is_empty())
        .filter_map(|part| part.chars().next())
        .take(2)
        .collect::<String>()
        .to_uppercase();
    if !initials.is_empty() {
        return initials;
    }
    let fallback = name.trim();
    if fallback.is_empty() {
        "·".to_string()
    } else {
        fallback.chars().take(2).collect::<String>().to_uppercase()
    }
}

fn hotbar_key_label(slot_index: usize) -> &'static str {
    match slot_index {
        0 => "1",
        1 => "2",
        2 => "3",
        3 => "4",
        4 => "5",
        5 => "6",
        6 => "7",
        7 => "8",
        8 => "9",
        9 => "0",
        _ => "?",
    }
}

fn skill_tree_progress(tree: &game_bevy::UiSkillTreeView) -> (usize, usize) {
    let learned = tree
        .entries
        .iter()
        .filter(|entry| entry.learned_level > 0)
        .count();
    (learned, tree.entries.len())
}

fn selected_skill_tree<'a>(
    snapshot: &'a game_bevy::UiSkillsSnapshot,
    menu_state: &UiMenuState,
) -> Option<&'a game_bevy::UiSkillTreeView> {
    menu_state
        .selected_skill_tree_id
        .as_deref()
        .and_then(|tree_id| snapshot.trees.iter().find(|tree| tree.tree_id == tree_id))
        .or_else(|| {
            menu_state
                .selected_skill_id
                .as_deref()
                .and_then(|skill_id| find_skill_tree_id(snapshot, skill_id))
                .and_then(|tree_id| snapshot.trees.iter().find(|tree| tree.tree_id == tree_id))
        })
        .or_else(|| snapshot.trees.iter().find(|tree| !tree.entries.is_empty()))
        .or_else(|| snapshot.trees.first())
}

fn selected_skill_entry<'a>(
    tree: &'a game_bevy::UiSkillTreeView,
    selected_skill_id: Option<&str>,
) -> Option<&'a game_bevy::UiSkillEntryView> {
    selected_skill_id
        .and_then(|skill_id| tree.entries.iter().find(|entry| entry.skill_id == skill_id))
        .or_else(|| tree.entries.first())
}

fn current_group_skill_slot(hotbar_state: &UiHotbarState, skill_id: &str) -> Option<usize> {
    hotbar_state
        .groups
        .get(hotbar_state.active_group)
        .and_then(|group| {
            group
                .iter()
                .position(|slot| slot.skill_id.as_deref() == Some(skill_id))
        })
}

fn format_skill_prerequisites(entry: &game_bevy::UiSkillEntryView) -> String {
    if entry.prerequisite_names.is_empty() {
        "无".to_string()
    } else {
        entry.prerequisite_names.join(" · ")
    }
}

fn format_skill_attribute_requirements(entry: &game_bevy::UiSkillEntryView) -> String {
    if entry.attribute_requirements.is_empty() {
        "无".to_string()
    } else {
        entry
            .attribute_requirements
            .iter()
            .map(|(attribute, value)| format!("{attribute} {value}"))
            .collect::<Vec<_>>()
            .join(" · ")
    }
}

fn render_main_menu(parent: &mut ChildSpawnerCommands, font: &ViewerUiFont, status_text: &str) {
    parent
        .spawn((
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
        ))
        .with_children(|menu| {
            menu.spawn(text_bundle(font, "CDC Survival Game", 20.0, Color::WHITE));
            menu.spawn(text_bundle(
                font,
                "Bevy 主流程界面",
                12.0,
                Color::srgba(0.82, 0.86, 0.93, 1.0),
            ));
            if !status_text.trim().is_empty() {
                menu.spawn(text_bundle(
                    font,
                    status_text,
                    11.5,
                    Color::srgba(0.92, 0.8, 0.56, 1.0),
                ));
            }
            menu.spawn(action_button(
                font,
                "开始新游戏",
                GameUiButtonAction::MainMenuNewGame,
            ));
            menu.spawn(action_button(
                font,
                "继续游戏",
                GameUiButtonAction::MainMenuContinue,
            ));
            menu.spawn(action_button(
                font,
                "退出游戏",
                GameUiButtonAction::MainMenuExit,
            ));
        });
}

fn render_panel_shell(parent: &mut ChildSpawnerCommands, font: &ViewerUiFont, panel: UiMenuPanel) {
    let width = panel_width(panel);
    parent.spawn((
        Node {
            position_type: PositionType::Absolute,
            top: px(RIGHT_PANEL_TOP),
            right: px(SCREEN_EDGE_PADDING),
            width: px(width),
            height: px(RIGHT_PANEL_HEADER_HEIGHT),
            padding: UiRect::axes(px(16), px(12)),
            justify_content: JustifyContent::SpaceBetween,
            align_items: AlignItems::Center,
            flex_direction: FlexDirection::Row,
            border: UiRect::all(px(1)),
            ..default()
        },
        BackgroundColor(Color::srgba(0.05, 0.06, 0.09, 0.98)),
        BorderColor::all(Color::srgba(0.26, 0.29, 0.38, 1.0)),
        FocusPolicy::Block,
        RelativeCursorPosition::default(),
        UiMouseBlocker,
        children![
            text_bundle(font, panel_title(panel), 15.0, Color::WHITE),
            text_bundle(
                font,
                panel_tab_label(panel),
                10.0,
                Color::srgba(0.76, 0.81, 0.88, 1.0)
            )
        ],
    ));
}

fn panel_body(parent: &mut ChildSpawnerCommands, panel: UiMenuPanel) -> Entity {
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(RIGHT_PANEL_TOP + RIGHT_PANEL_HEADER_HEIGHT - 1.0),
                right: px(SCREEN_EDGE_PADDING),
                width: px(panel_width(panel)),
                bottom: px(RIGHT_PANEL_BOTTOM),
                padding: UiRect::all(px(14)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                overflow: Overflow::clip_y(),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.04, 0.045, 0.06, 0.97)),
            BorderColor::all(Color::srgba(0.22, 0.25, 0.33, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .id()
}

fn render_inventory_panel(
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
            flex_direction: FlexDirection::Row,
            column_gap: px(12),
            align_items: AlignItems::Stretch,
            ..default()
        })
        .with_children(|layout| {
            layout
                .spawn((
                    Node {
                        width: px(146),
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
                    if snapshot.equipment.is_empty() {
                        equipment.spawn(text_bundle(
                            font,
                            "当前没有装备槽数据",
                            10.0,
                            Color::srgba(0.72, 0.76, 0.82, 1.0),
                        ));
                    }
                    for slot in &snapshot.equipment {
                        let is_selected = menu_state.selected_equipment_slot.as_deref()
                            == Some(slot.slot_id.as_str());
                        equipment
                            .spawn((
                                Button,
                                Node {
                                    width: Val::Percent(100.0),
                                    min_height: px(56),
                                    padding: UiRect::all(px(8)),
                                    flex_direction: FlexDirection::Column,
                                    justify_content: JustifyContent::SpaceBetween,
                                    border: UiRect::all(px(if is_selected { 2.0 } else { 1.0 })),
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
                                GameUiButtonAction::MoveSelectedEquippedTo(slot.slot_id.clone()),
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
                        if slot.item_id.is_some() {
                            equipment.spawn(action_button(
                                font,
                                "卸下",
                                GameUiButtonAction::UnequipSlot(slot.slot_id.clone()),
                            ));
                        }
                    }
                });

            layout
                .spawn((
                    Node {
                        flex_grow: 1.0,
                        flex_direction: FlexDirection::Column,
                        row_gap: px(8),
                        ..default()
                    },
                    BackgroundColor(Color::NONE),
                ))
                .with_children(|inventory| {
                    inventory
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
                    inventory
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
                            if snapshot.entries.is_empty() {
                                entries.spawn(text_bundle(
                                    font,
                                    "当前筛选下没有物品",
                                    10.4,
                                    Color::srgba(0.72, 0.76, 0.82, 1.0),
                                ));
                            }
                            for entry in &snapshot.entries {
                                entries.spawn(action_button(
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
                        });

                    inventory
                        .spawn((
                            Node {
                                width: Val::Percent(100.0),
                                padding: UiRect::all(px(10)),
                                flex_direction: FlexDirection::Column,
                                row_gap: px(6),
                                border: UiRect::all(px(1)),
                                ..default()
                            },
                            BackgroundColor(Color::srgba(0.06, 0.07, 0.10, 0.96)),
                            BorderColor::all(Color::srgba(0.18, 0.22, 0.30, 1.0)),
                        ))
                        .with_children(|detail_box| {
                            if let Some(detail) = snapshot.detail.as_ref() {
                                detail_box.spawn(text_bundle(
                                    font,
                                    &format!(
                                        "{} · {} x{}",
                                        detail.name,
                                        detail.item_type.as_str(),
                                        detail.count
                                    ),
                                    11.3,
                                    Color::WHITE,
                                ));
                                detail_box.spawn(text_bundle(
                                    font,
                                    &format!("重量 {:.1}kg", detail.weight),
                                    10.1,
                                    Color::srgba(0.78, 0.84, 0.92, 1.0),
                                ));
                                if !detail.description.trim().is_empty() {
                                    detail_box.spawn(text_bundle(
                                        font,
                                        &detail.description,
                                        10.1,
                                        Color::srgba(0.86, 0.89, 0.95, 1.0),
                                    ));
                                }
                                if detail.attribute_bonuses.is_empty() {
                                    detail_box.spawn(text_bundle(
                                        font,
                                        "属性加成: 无",
                                        10.0,
                                        Color::srgba(0.72, 0.76, 0.82, 1.0),
                                    ));
                                } else {
                                    for (attribute, bonus) in &detail.attribute_bonuses {
                                        detail_box.spawn(text_bundle(
                                            font,
                                            &format!("{attribute} {bonus:+.1}"),
                                            10.0,
                                            Color::srgba(0.84, 0.88, 0.95, 1.0),
                                        ));
                                    }
                                }
                                detail_box
                                    .spawn(Node {
                                        width: Val::Percent(100.0),
                                        flex_direction: FlexDirection::Row,
                                        flex_wrap: FlexWrap::Wrap,
                                        column_gap: px(8),
                                        row_gap: px(6),
                                        ..default()
                                    })
                                    .with_children(|actions| {
                                        if snapshot
                                            .entries
                                            .iter()
                                            .find(|entry| entry.item_id == detail.item_id)
                                            .map(|entry| entry.can_use)
                                            .unwrap_or(false)
                                        {
                                            actions.spawn(action_button(
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
                                            actions.spawn(action_button(
                                                font,
                                                "装备",
                                                GameUiButtonAction::EquipInventoryItem,
                                            ));
                                        }
                                    });
                            } else {
                                detail_box.spawn(text_bundle(
                                    font,
                                    "选择一个物品后，这里会显示详情、属性和可执行操作。",
                                    10.2,
                                    Color::srgba(0.72, 0.76, 0.82, 1.0),
                                ));
                            }
                        });
                });
        });
    });
}

fn render_character_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCharacterSnapshot,
) {
    let body = panel_body(parent, UiMenuPanel::Character);
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
    let body = panel_body(parent, UiMenuPanel::Journal);
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
    menu_state: &UiMenuState,
    hotbar_state: &UiHotbarState,
) {
    let body = panel_body(parent, UiMenuPanel::Skills);
    parent.commands().entity(body).insert(Node {
        position_type: PositionType::Absolute,
        top: px(RIGHT_PANEL_TOP + RIGHT_PANEL_HEADER_HEIGHT - 1.0),
        right: px(SCREEN_EDGE_PADDING),
        width: px(SKILLS_PANEL_WIDTH),
        bottom: px(RIGHT_PANEL_BOTTOM),
        padding: UiRect::all(px(14)),
        flex_direction: FlexDirection::Column,
        row_gap: px(10),
        overflow: Overflow::clip_y(),
        border: UiRect::all(px(1)),
        ..default()
    });
    let selected_tree = selected_skill_tree(snapshot, menu_state);
    let selected_entry = selected_tree
        .and_then(|tree| selected_skill_entry(tree, menu_state.selected_skill_id.as_deref()));
    let current_group_fill = hotbar_state
        .groups
        .get(hotbar_state.active_group)
        .map(|group| group.iter().filter(|slot| slot.skill_id.is_some()).count())
        .unwrap_or(0);

    parent.commands().entity(body).with_children(|body| {
        body.spawn(text_bundle(
            font,
            "左侧切技能树，中列浏览当前树，右侧查看详情；选中技能后可加入当前组空槽，或直接点击底栏槽位精确绑定。",
            10.5,
            Color::srgba(0.78, 0.84, 0.92, 1.0),
        ));
        body.spawn(Node {
            width: Val::Percent(100.0),
            column_gap: px(12),
            flex_direction: FlexDirection::Row,
            align_items: AlignItems::Stretch,
            ..default()
        })
        .with_children(|columns| {
            columns
                .spawn((
                    Node {
                        width: px(190),
                        padding: UiRect::all(px(10)),
                        flex_direction: FlexDirection::Column,
                        row_gap: px(6),
                        overflow: Overflow::clip_y(),
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(Color::srgba(0.05, 0.07, 0.10, 0.96)),
                    BorderColor::all(Color::srgba(0.18, 0.25, 0.33, 1.0)),
                ))
                .with_children(|tree_column| {
                    tree_column.spawn(text_bundle(
                        font,
                        "技能树",
                        11.5,
                        Color::srgba(0.92, 0.95, 1.0, 1.0),
                    ));
                    if snapshot.trees.is_empty() {
                        tree_column.spawn(text_bundle(
                            font,
                            "当前没有可显示的技能树",
                            10.5,
                            Color::srgba(0.72, 0.76, 0.82, 1.0),
                        ));
                    }
                    for tree in &snapshot.trees {
                        let (learned_count, total_count) = skill_tree_progress(tree);
                        let is_selected = selected_tree
                            .map(|selected| selected.tree_id == tree.tree_id)
                            .unwrap_or(false);
                        tree_column
                            .spawn((
                                Button,
                                Node {
                                    width: Val::Percent(100.0),
                                    padding: UiRect::all(px(9)),
                                    margin: UiRect::bottom(px(2)),
                                    flex_direction: FlexDirection::Column,
                                    row_gap: px(2),
                                    border: UiRect::all(px(if is_selected { 2.0 } else { 1.0 })),
                                    ..default()
                                },
                                BackgroundColor(if is_selected {
                                    Color::srgba(0.16, 0.22, 0.31, 0.98).into()
                                } else {
                                    Color::srgba(0.08, 0.10, 0.15, 0.94).into()
                                }),
                                BorderColor::all(if is_selected {
                                    Color::srgba(0.56, 0.72, 0.92, 1.0)
                                } else {
                                    Color::srgba(0.18, 0.25, 0.33, 1.0)
                                }),
                                GameUiButtonAction::SelectSkillTree(tree.tree_id.clone()),
                            ))
                            .with_children(|button| {
                                button.spawn(text_bundle(
                                    font,
                                    &tree.tree_name,
                                    10.8,
                                    if is_selected {
                                        Color::WHITE
                                    } else {
                                        Color::srgba(0.86, 0.90, 0.96, 1.0)
                                    },
                                ));
                                button.spawn(text_bundle(
                                    font,
                                    &format!("{learned_count}/{total_count} 已学习"),
                                    9.2,
                                    Color::srgba(0.67, 0.73, 0.80, 1.0),
                                ));
                            });
                    }
                });

            columns
                .spawn((
                    Node {
                        width: px(300),
                        padding: UiRect::all(px(10)),
                        flex_direction: FlexDirection::Column,
                        row_gap: px(6),
                        overflow: Overflow::clip_y(),
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(Color::srgba(0.05, 0.07, 0.10, 0.96)),
                    BorderColor::all(Color::srgba(0.18, 0.25, 0.33, 1.0)),
                ))
                .with_children(|list_column| {
                    let title = selected_tree
                        .map(|tree| format!("{} 技能", tree.tree_name))
                        .unwrap_or_else(|| "技能列表".to_string());
                    list_column.spawn(text_bundle(
                        font,
                        &title,
                        11.5,
                        Color::srgba(0.92, 0.95, 1.0, 1.0),
                    ));
                    if let Some(tree) = selected_tree {
                        if tree.entries.is_empty() {
                            list_column.spawn(text_bundle(
                                font,
                                "该技能树暂无技能条目",
                                10.5,
                                Color::srgba(0.72, 0.76, 0.82, 1.0),
                            ));
                        }
                        for entry in &tree.entries {
                            let is_selected = selected_entry
                                .map(|selected| selected.skill_id == entry.skill_id)
                                .unwrap_or(false);
                            let state_label = if entry.learned_level > 0 {
                                if entry.hotbar_eligible {
                                    "可绑定"
                                } else {
                                    "已学习"
                                }
                            } else {
                                "未学习"
                            };
                            let state_color = if entry.learned_level > 0 {
                                Color::srgba(0.72, 0.92, 0.72, 1.0)
                            } else {
                                Color::srgba(0.58, 0.63, 0.70, 1.0)
                            };
                            list_column
                                .spawn((
                                    Button,
                                    Node {
                                        width: Val::Percent(100.0),
                                        padding: UiRect::all(px(9)),
                                        margin: UiRect::bottom(px(2)),
                                        flex_direction: FlexDirection::Column,
                                        row_gap: px(3),
                                        border: UiRect::all(px(if is_selected { 2.0 } else { 1.0 })),
                                        ..default()
                                    },
                                    BackgroundColor(if is_selected {
                                        Color::srgba(0.16, 0.22, 0.31, 0.98).into()
                                    } else {
                                        Color::srgba(0.08, 0.10, 0.15, 0.94).into()
                                    }),
                                    BorderColor::all(if is_selected {
                                        Color::srgba(0.64, 0.76, 0.94, 1.0)
                                    } else {
                                        Color::srgba(0.18, 0.25, 0.33, 1.0)
                                    }),
                                    GameUiButtonAction::SelectSkill(entry.skill_id.clone()),
                                ))
                                .with_children(|button| {
                                    button.spawn(text_bundle(
                                        font,
                                        &format!(
                                            "{} · Lv {}/{}",
                                            entry.name, entry.learned_level, entry.max_level
                                        ),
                                        10.6,
                                        if entry.learned_level > 0 {
                                            Color::WHITE
                                        } else {
                                            Color::srgba(0.78, 0.82, 0.88, 1.0)
                                        },
                                    ));
                                    button.spawn(text_bundle(
                                        font,
                                        &format!(
                                            "{} · {}",
                                            activation_mode_label(&entry.activation_mode),
                                            state_label
                                        ),
                                        9.2,
                                        state_color,
                                    ));
                                });
                        }
                    } else {
                        list_column.spawn(text_bundle(
                            font,
                            "没有可供选择的技能",
                            10.5,
                            Color::srgba(0.72, 0.76, 0.82, 1.0),
                        ));
                    }
                });

            columns
                .spawn((
                    Node {
                        flex_grow: 1.0,
                        padding: UiRect::all(px(12)),
                        flex_direction: FlexDirection::Column,
                        row_gap: px(6),
                        overflow: Overflow::clip_y(),
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(Color::srgba(0.05, 0.07, 0.10, 0.96)),
                    BorderColor::all(Color::srgba(0.18, 0.25, 0.33, 1.0)),
                ))
                .with_children(|detail_column| {
                    if let Some(tree) = selected_tree {
                        detail_column.spawn(text_bundle(
                            font,
                            &tree.tree_name,
                            12.0,
                            Color::srgba(0.82, 0.88, 0.96, 1.0),
                        ));
                        if !tree.tree_description.trim().is_empty() {
                            detail_column.spawn(text_bundle(
                                font,
                                &tree.tree_description,
                                10.0,
                                Color::srgba(0.70, 0.75, 0.82, 1.0),
                            ));
                        }
                    }
                    if let Some(entry) = selected_entry {
                        detail_column.spawn(text_bundle(font, &entry.name, 14.0, Color::WHITE));
                        detail_column.spawn(text_bundle(
                            font,
                            &format!(
                                "等级 {}/{} · {} · 冷却 {:.1}s",
                                entry.learned_level,
                                entry.max_level,
                                activation_mode_label(&entry.activation_mode),
                                entry.cooldown_seconds
                            ),
                            10.8,
                            Color::srgba(0.80, 0.86, 0.96, 1.0),
                        ));
                        if !entry.description.trim().is_empty() {
                            detail_column.spawn(text_bundle(
                                font,
                                &entry.description,
                                10.5,
                                Color::WHITE,
                            ));
                        }
                        detail_column.spawn(text_bundle(
                            font,
                            &format!("前置需求: {}", format_skill_prerequisites(entry)),
                            10.0,
                            Color::srgba(0.84, 0.88, 0.94, 1.0),
                        ));
                        detail_column.spawn(text_bundle(
                            font,
                            &format!(
                                "属性需求: {}",
                                format_skill_attribute_requirements(entry)
                            ),
                            10.0,
                            Color::srgba(0.84, 0.88, 0.94, 1.0),
                        ));
                        detail_column.spawn(text_bundle(
                            font,
                            &format!(
                                "当前快捷栏组 {} · 已占用 {}/10",
                                hotbar_state.active_group + 1,
                                current_group_fill
                            ),
                            10.0,
                            Color::srgba(0.72, 0.78, 0.86, 1.0),
                        ));
                        if let Some(slot_index) =
                            current_group_skill_slot(hotbar_state, &entry.skill_id)
                        {
                            detail_column.spawn(text_bundle(
                                font,
                                &format!("当前组已绑定到第 {} 槽", slot_index + 1),
                                10.0,
                                Color::srgba(0.90, 0.80, 0.58, 1.0),
                            ));
                        }
                        if entry.hotbar_eligible {
                            detail_column.spawn(action_button(
                                font,
                                "加入当前组空槽",
                                GameUiButtonAction::AssignSkillToFirstEmptyHotbarSlot(
                                    entry.skill_id.clone(),
                                ),
                            ));
                        } else {
                            detail_column.spawn(text_bundle(
                                font,
                                if entry.learned_level > 0 {
                                    "该技能当前不进入快捷栏。"
                                } else {
                                    "尚未学习，暂时不能加入快捷栏。"
                                },
                                10.2,
                                Color::srgba(0.72, 0.76, 0.82, 1.0),
                            ));
                        }
                    } else {
                        detail_column.spawn(text_bundle(
                            font,
                            "选择一个技能后，这里会显示完整描述、前置要求和快捷栏操作。",
                            10.5,
                            Color::srgba(0.72, 0.76, 0.82, 1.0),
                        ));
                    }
                });
        });
    });
}

fn render_crafting_panel(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    snapshot: &game_bevy::UiCraftingSnapshot,
) {
    let body = panel_body(parent, UiMenuPanel::Crafting);
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
    let body = panel_body(parent, UiMenuPanel::Map);
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
    parent.spawn((
        Node {
            position_type: PositionType::Absolute,
            left: px(0),
            top: px(0),
            width: Val::Percent(100.0),
            height: Val::Percent(100.0),
            ..default()
        },
        BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.58)),
        FocusPolicy::Block,
        RelativeCursorPosition::default(),
        UiMouseBlocker,
    ));

    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                top: Val::Percent(50.0),
                margin: UiRect {
                    left: px(-250),
                    top: px(-210),
                    ..default()
                },
                width: px(500),
                min_height: px(420),
                padding: UiRect::all(px(18)),
                flex_direction: FlexDirection::Column,
                row_gap: px(10),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.04, 0.045, 0.06, 0.985)),
            BorderColor::all(Color::srgba(0.28, 0.31, 0.40, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .with_children(|body| {
            body.spawn(text_bundle(font, "游戏菜单", 18.0, Color::WHITE));
            body.spawn(text_bundle(
                font,
                "按 Esc 关闭菜单并返回游戏",
                10.4,
                Color::srgba(0.80, 0.84, 0.91, 1.0),
            ));
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
                GameUiButtonAction::SettingsSetSfx(if settings.sfx_volume > 0.0 {
                    0.0
                } else {
                    1.0
                }),
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
        FocusPolicy::Block,
        RelativeCursorPosition::default(),
        UiMouseBlocker,
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
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                top: Val::Percent(50.0),
                margin: UiRect {
                    left: px(-340),
                    top: px(-154),
                    ..default()
                },
                width: px(680),
                height: px(288),
                padding: UiRect::all(px(14)),
                flex_direction: FlexDirection::Column,
                row_gap: px(6),
                overflow: Overflow::clip_y(),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.04, 0.045, 0.06, 0.98)),
            BorderColor::all(Color::srgba(0.22, 0.25, 0.33, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .with_children(|body| {
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

fn render_hotbar_slots(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    hotbar_state: &UiHotbarState,
    skills: &game_data::SkillLibrary,
    show_clear_controls: bool,
    selected_skill_id: Option<&str>,
) {
    let Some(active_group) = hotbar_state.groups.get(hotbar_state.active_group) else {
        return;
    };

    parent
        .spawn(Node {
            width: Val::Percent(100.0),
            flex_direction: FlexDirection::Row,
            column_gap: px(4),
            justify_content: JustifyContent::Center,
            ..default()
        })
        .with_children(|slots| {
            for (slot_index, slot) in active_group.iter().enumerate() {
                let skill_name = slot
                    .skill_id
                    .as_deref()
                    .and_then(|skill_id| skills.get(skill_id))
                    .map(|skill| skill.name.as_str());
                let short_name = skill_name
                    .map(|name| compact_skill_name(name, 8))
                    .unwrap_or_else(|| "空槽".to_string());
                let skill_abbreviation = skill_name
                    .map(abbreviated_skill_name)
                    .unwrap_or_else(|| "·".to_string());
                let footer_label = if slot.cooldown_remaining > 0.0 {
                    format!("{:.1}s", slot.cooldown_remaining)
                } else {
                    short_name.clone()
                };
                let is_selected_skill = selected_skill_id
                    .map(|skill_id| slot.skill_id.as_deref() == Some(skill_id))
                    .unwrap_or(false);
                let primary_action = if let Some(skill_id) = selected_skill_id {
                    GameUiButtonAction::AssignSkillToHotbar {
                        skill_id: skill_id.to_string(),
                        group: hotbar_state.active_group,
                        slot: slot_index,
                    }
                } else {
                    GameUiButtonAction::ActivateHotbarSlot(slot_index)
                };
                let border_color = if slot.toggled {
                    Color::srgba(0.42, 0.78, 0.56, 1.0)
                } else if is_selected_skill {
                    Color::srgba(0.92, 0.74, 0.38, 1.0)
                } else if slot.skill_id.is_some() {
                    Color::srgba(0.22, 0.32, 0.44, 1.0)
                } else {
                    Color::srgba(0.14, 0.18, 0.24, 1.0)
                };
                let background = if slot.skill_id.is_none() {
                    Color::srgba(0.05, 0.06, 0.09, 0.94)
                } else if slot.cooldown_remaining > 0.0 {
                    Color::srgba(0.08, 0.10, 0.16, 0.96)
                } else {
                    Color::srgba(0.08, 0.11, 0.17, 0.98)
                };
                slots
                    .spawn(Node {
                        width: px(HOTBAR_SLOT_SIZE),
                        min_height: px(HOTBAR_SLOT_SIZE),
                        position_type: PositionType::Relative,
                        ..default()
                    })
                    .with_children(|slot_wrapper| {
                        slot_wrapper
                            .spawn((
                                Button,
                                Node {
                                    width: px(HOTBAR_SLOT_SIZE),
                                    min_height: px(HOTBAR_SLOT_SIZE),
                                    padding: UiRect::all(px(6)),
                                    flex_direction: FlexDirection::Column,
                                    justify_content: JustifyContent::SpaceBetween,
                                    border: UiRect::all(px(if slot.toggled || is_selected_skill {
                                        2.0
                                    } else {
                                        1.0
                                    })),
                                    ..default()
                                },
                                BackgroundColor(background.into()),
                                BorderColor::all(border_color),
                                primary_action,
                            ))
                            .with_children(|button| {
                                button
                                    .spawn(Node {
                                        width: Val::Percent(100.0),
                                        flex_direction: FlexDirection::Row,
                                        justify_content: JustifyContent::SpaceBetween,
                                        ..default()
                                    })
                                    .with_children(|top_row| {
                                        top_row.spawn(text_bundle(
                                            font,
                                            hotbar_key_label(slot_index),
                                            8.2,
                                            if slot.skill_id.is_some() {
                                                Color::srgba(0.82, 0.86, 0.94, 1.0)
                                            } else {
                                                Color::srgba(0.52, 0.57, 0.66, 1.0)
                                            },
                                        ));
                                        if slot.toggled {
                                            top_row.spawn(text_bundle(
                                                font,
                                                "ON",
                                                7.8,
                                                Color::srgba(0.56, 0.88, 0.62, 1.0),
                                            ));
                                        }
                                    });
                                button.spawn(text_bundle(
                                    font,
                                    &skill_abbreviation,
                                    13.0,
                                    if slot.skill_id.is_some() {
                                        Color::WHITE
                                    } else {
                                        Color::srgba(0.46, 0.50, 0.58, 1.0)
                                    },
                                ));
                                button.spawn(text_bundle(
                                    font,
                                    &footer_label,
                                    8.0,
                                    if slot.skill_id.is_some() {
                                        Color::srgba(0.80, 0.84, 0.92, 1.0)
                                    } else {
                                        Color::srgba(0.44, 0.48, 0.56, 1.0)
                                    },
                                ));
                                if slot.cooldown_remaining > 0.0 {
                                    button
                                        .spawn((
                                            Node {
                                                position_type: PositionType::Absolute,
                                                left: px(0),
                                                top: px(0),
                                                width: Val::Percent(100.0),
                                                height: Val::Percent(100.0),
                                                justify_content: JustifyContent::FlexEnd,
                                                align_items: AlignItems::FlexEnd,
                                                padding: UiRect::all(px(6)),
                                                ..default()
                                            },
                                            BackgroundColor(Color::srgba(0.01, 0.02, 0.04, 0.55)),
                                        ))
                                        .with_children(|overlay| {
                                            overlay.spawn(text_bundle(
                                                font,
                                                &format!("{:.1}s", slot.cooldown_remaining),
                                                8.2,
                                                Color::WHITE,
                                            ));
                                        });
                                }
                            });

                        if show_clear_controls && slot.skill_id.is_some() {
                            slot_wrapper
                                .spawn((
                                    Button,
                                    Node {
                                        position_type: PositionType::Absolute,
                                        top: px(-4),
                                        right: px(-4),
                                        width: px(18),
                                        height: px(18),
                                        justify_content: JustifyContent::Center,
                                        align_items: AlignItems::Center,
                                        border: UiRect::all(px(1)),
                                        ..default()
                                    },
                                    BackgroundColor(Color::srgba(0.22, 0.08, 0.08, 0.94).into()),
                                    BorderColor::all(Color::srgba(0.74, 0.40, 0.40, 1.0)),
                                    GameUiButtonAction::ClearHotbarSlot {
                                        group: hotbar_state.active_group,
                                        slot: slot_index,
                                    },
                                ))
                                .with_children(|clear| {
                                    clear.spawn(text_bundle(font, "×", 8.8, Color::WHITE));
                                });
                        }
                    });
            }
        });
}

#[allow(dead_code)]
fn render_hotbar_legacy(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    viewer_state: &ViewerState,
    hotbar_state: &UiHotbarState,
    skills: &game_data::SkillLibrary,
    menu_state: &UiMenuState,
    player_stats: Option<&PlayerHudStats>,
    show_clear_controls: bool,
    selected_skill_id: Option<&str>,
) {
    let binding_hint = selected_skill_id
        .and_then(|skill_id| skills.get(skill_id).map(|skill| skill.name.as_str()))
        .map(|skill_name| {
            format!(
                "绑定模式 · 已选 {}，点击底栏槽位可精确放入当前组",
                skill_name
            )
        })
        .unwrap_or_else(|| "数字键 1-0 激活当前组槽位".to_string());
    let status_hint = hotbar_state
        .last_activation_status
        .as_deref()
        .map(|status| truncate_ui_text(status, 36))
        .unwrap_or_else(|| "上次激活状态会显示在这里".to_string());
    let attack_targeting_active = viewer_state
        .targeting_state
        .as_ref()
        .is_some_and(|targeting| targeting.is_attack());
    let attack_enabled = !viewer_state.is_free_observe() && viewer_state.selected_actor.is_some();
    let hp_text = player_stats
        .map(|stats| format!("{:.0} / {:.0}", stats.hp, stats.max_hp))
        .unwrap_or_else(|| "-- / --".to_string());
    let hp_ratio = player_stats
        .map(|stats| {
            if stats.max_hp <= 0.0 {
                0.0
            } else {
                (stats.hp / stats.max_hp).clamp(0.0, 1.0)
            }
        })
        .unwrap_or(0.0);
    let action_text = player_stats
        .map(|stats| format!("{:.1} AP · {}步", stats.ap, stats.available_steps))
        .unwrap_or_else(|| "--".to_string());
    let action_ratio = player_stats.map(action_meter_ratio).unwrap_or(0.0);

    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                bottom: px(SCREEN_EDGE_PADDING),
                margin: UiRect {
                    left: px(-(HOTBAR_DOCK_WIDTH / 2.0)),
                    ..default()
                },
                width: px(HOTBAR_DOCK_WIDTH),
                min_height: px(HOTBAR_DOCK_HEIGHT),
                padding: UiRect::all(px(12)),
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.03, 0.035, 0.05, 0.93)),
            BorderColor::all(Color::srgba(0.24, 0.28, 0.37, 1.0)),
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
        ))
        .with_children(|body| {
            body.spawn(Node {
                width: Val::Percent(100.0),
                flex_direction: FlexDirection::Row,
                justify_content: JustifyContent::SpaceBetween,
                align_items: AlignItems::Center,
                ..default()
            })
            .with_children(|header| {
                header
                    .spawn(Node {
                        flex_direction: FlexDirection::Row,
                        column_gap: px(8),
                        align_items: AlignItems::Center,
                        ..default()
                    })
                    .with_children(|left| {
                        left.spawn((
                            Node {
                                padding: UiRect::axes(px(10), px(4)),
                                border: UiRect::all(px(1)),
                                ..default()
                            },
                            BackgroundColor(Color::srgba(0.10, 0.13, 0.18, 1.0)),
                            BorderColor::all(Color::srgba(0.34, 0.46, 0.62, 1.0)),
                            children![text_bundle(
                                font,
                                &format!("组 {}", hotbar_state.active_group + 1),
                                9.8,
                                Color::WHITE
                            )],
                        ));
                        left.spawn((
                            Button,
                            Node {
                                padding: UiRect::axes(px(10), px(5)),
                                border: UiRect::all(px(if attack_targeting_active {
                                    2.0
                                } else {
                                    1.0
                                })),
                                ..default()
                            },
                            BackgroundColor(if attack_targeting_active {
                                Color::srgba(0.28, 0.12, 0.10, 0.98).into()
                            } else if attack_enabled {
                                Color::srgba(0.12, 0.09, 0.08, 0.96).into()
                            } else {
                                Color::srgba(0.07, 0.07, 0.08, 0.94).into()
                            }),
                            BorderColor::all(if attack_targeting_active {
                                Color::srgba(0.96, 0.54, 0.44, 1.0)
                            } else if attack_enabled {
                                Color::srgba(0.56, 0.32, 0.28, 1.0)
                            } else {
                                Color::srgba(0.20, 0.20, 0.22, 1.0)
                            }),
                            GameUiButtonAction::EnterAttackTargeting,
                        ))
                        .with_children(|button| {
                            button.spawn(text_bundle(
                                font,
                                if attack_targeting_active {
                                    "攻击中"
                                } else {
                                    "普通攻击"
                                },
                                9.6,
                                if attack_enabled {
                                    Color::WHITE
                                } else {
                                    Color::srgba(0.52, 0.54, 0.58, 1.0)
                                },
                            ));
                        });
                    });
                header.spawn(text_bundle(
                    font,
                    &status_hint,
                    9.8,
                    Color::srgba(0.78, 0.83, 0.92, 1.0),
                ));
            });
            body.spawn(Node {
                width: Val::Percent(100.0),
                flex_direction: FlexDirection::Row,
                column_gap: px(10),
                align_items: AlignItems::FlexStart,
                ..default()
            })
            .with_children(|content| {
                content
                    .spawn((
                        Node {
                            width: px(214),
                            padding: UiRect::all(px(10)),
                            flex_direction: FlexDirection::Column,
                            row_gap: px(8),
                            border: UiRect::all(px(1)),
                            ..default()
                        },
                        BackgroundColor(Color::srgba(0.05, 0.06, 0.09, 0.98)),
                        BorderColor::all(Color::srgba(0.18, 0.21, 0.29, 1.0)),
                    ))
                    .with_children(|left| {
                        left.spawn(text_bundle(
                            font,
                            &binding_hint,
                            9.4,
                            Color::srgba(0.70, 0.75, 0.84, 1.0),
                        ));
                        left.spawn(Node {
                            width: Val::Percent(100.0),
                            flex_direction: FlexDirection::Row,
                            column_gap: px(6),
                            flex_wrap: FlexWrap::Wrap,
                            ..default()
                        })
                        .with_children(|groups| {
                            for group_index in 0..hotbar_state.groups.len() {
                                let is_selected = group_index == hotbar_state.active_group;
                                groups
                                    .spawn((
                                        Button,
                                        Node {
                                            width: px(34),
                                            height: px(28),
                                            justify_content: JustifyContent::Center,
                                            align_items: AlignItems::Center,
                                            border: UiRect::all(px(if is_selected {
                                                2.0
                                            } else {
                                                1.0
                                            })),
                                            ..default()
                                        },
                                        BackgroundColor(if is_selected {
                                            Color::srgba(0.16, 0.22, 0.31, 1.0).into()
                                        } else {
                                            Color::srgba(0.08, 0.10, 0.15, 0.94).into()
                                        }),
                                        BorderColor::all(if is_selected {
                                            Color::srgba(0.64, 0.76, 0.94, 1.0)
                                        } else {
                                            Color::srgba(0.18, 0.25, 0.33, 1.0)
                                        }),
                                        GameUiButtonAction::SelectHotbarGroup(group_index),
                                    ))
                                    .with_children(|button| {
                                        button.spawn(text_bundle(
                                            font,
                                            &(group_index + 1).to_string(),
                                            9.2,
                                            if is_selected {
                                                Color::WHITE
                                            } else {
                                                Color::srgba(0.76, 0.80, 0.88, 1.0)
                                            },
                                        ));
                                    });
                            }
                        });
                        render_stat_meter(
                            left,
                            font,
                            "生命",
                            &hp_text,
                            hp_ratio,
                            Color::srgba(0.68, 0.16, 0.18, 1.0),
                            Color::srgba(0.54, 0.20, 0.22, 1.0),
                        );
                        render_stat_meter(
                            left,
                            font,
                            "行动",
                            &action_text,
                            action_ratio,
                            Color::srgba(0.18, 0.44, 0.70, 1.0),
                            Color::srgba(0.24, 0.40, 0.58, 1.0),
                        );
                    });

                content
                    .spawn(Node {
                        flex_grow: 1.0,
                        flex_direction: FlexDirection::Column,
                        row_gap: px(8),
                        ..default()
                    })
                    .with_children(|main| {
                        render_hotbar_slots(
                            main,
                            font,
                            hotbar_state,
                            skills,
                            show_clear_controls,
                            selected_skill_id,
                        );
                        main.spawn(Node {
                            width: Val::Percent(100.0),
                            flex_direction: FlexDirection::Row,
                            justify_content: JustifyContent::SpaceBetween,
                            align_items: AlignItems::Center,
                            column_gap: px(8),
                            ..default()
                        })
                        .with_children(|footer| {
                            footer
                                .spawn(Node {
                                    flex_direction: FlexDirection::Row,
                                    column_gap: px(6),
                                    flex_wrap: FlexWrap::Wrap,
                                    ..default()
                                })
                                .with_children(|tabs| {
                                    for panel in [
                                        UiMenuPanel::Inventory,
                                        UiMenuPanel::Journal,
                                        UiMenuPanel::Character,
                                        UiMenuPanel::Skills,
                                        UiMenuPanel::Crafting,
                                        UiMenuPanel::Map,
                                        UiMenuPanel::Settings,
                                    ] {
                                        tabs.spawn(dock_tab_button(
                                            font,
                                            panel_tab_label(panel),
                                            menu_state.active_panel == Some(panel),
                                            GameUiButtonAction::TogglePanel(panel),
                                        ));
                                    }
                                });
                            footer.spawn(dock_tab_button(
                                font,
                                "关闭",
                                menu_state.active_panel.is_none(),
                                GameUiButtonAction::ClosePanels,
                            ));
                        });
                    });
            });
        });
}

fn render_hotbar(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    viewer_state: &ViewerState,
    hotbar_state: &UiHotbarState,
    skills: &game_data::SkillLibrary,
    menu_state: &UiMenuState,
    player_stats: Option<&PlayerHudStats>,
    show_clear_controls: bool,
    selected_skill_id: Option<&str>,
) {
    let binding_hint = selected_skill_id
        .and_then(|skill_id| skills.get(skill_id).map(|skill| skill.name.as_str()))
        .map(|skill_name| {
            format!(
                "绑定模式 · 已选 {}，点击底栏槽位可精确放入当前组",
                skill_name
            )
        })
        .unwrap_or_else(|| "数字键 1-0 激活当前组槽位".to_string());
    let attack_targeting_active = viewer_state
        .targeting_state
        .as_ref()
        .is_some_and(|targeting| targeting.is_attack());
    let attack_enabled = !viewer_state.is_free_observe() && viewer_state.selected_actor.is_some();
    let hp_text = player_stats
        .map(|stats| format!("{:.0} / {:.0}", stats.hp, stats.max_hp))
        .unwrap_or_else(|| "-- / --".to_string());
    let hp_ratio = player_stats
        .map(|stats| {
            if stats.max_hp <= 0.0 {
                0.0
            } else {
                (stats.hp / stats.max_hp).clamp(0.0, 1.0)
            }
        })
        .unwrap_or(0.0);
    let action_text = player_stats
        .map(|stats| format!("{:.1} AP · {}步", stats.ap, stats.available_steps))
        .unwrap_or_else(|| "--".to_string());
    let action_ratio = player_stats.map(action_meter_ratio).unwrap_or(0.0);
    let left_tabs = [
        UiMenuPanel::Character,
        UiMenuPanel::Journal,
        UiMenuPanel::Skills,
    ];
    let right_tabs = [
        UiMenuPanel::Inventory,
        UiMenuPanel::Crafting,
        UiMenuPanel::Map,
        UiMenuPanel::Settings,
    ];

    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                left: Val::Percent(50.0),
                bottom: px(0),
                margin: UiRect {
                    left: px(-(HOTBAR_DOCK_WIDTH / 2.0)),
                    ..default()
                },
                width: px(HOTBAR_DOCK_WIDTH),
                min_height: px(HOTBAR_DOCK_HEIGHT),
                padding: UiRect {
                    left: px(12),
                    right: px(12),
                    top: px(10),
                    bottom: px(8),
                },
                flex_direction: FlexDirection::Column,
                row_gap: px(8),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(Color::srgba(0.03, 0.035, 0.05, 0.93)),
            BorderColor::all(Color::srgba(0.24, 0.28, 0.37, 1.0)),
        ))
        .with_children(|body| {
            body.spawn(Node {
                width: Val::Percent(100.0),
                flex_direction: FlexDirection::Row,
                column_gap: px(10),
                align_items: AlignItems::Center,
                ..default()
            })
            .with_children(|header| {
                header
                    .spawn(Node {
                        width: px(HOTBAR_ACTION_WIDTH),
                        flex_direction: FlexDirection::Row,
                        justify_content: JustifyContent::FlexStart,
                        align_items: AlignItems::Center,
                        ..default()
                    })
                    .with_children(|left| {
                        left.spawn((
                            Button,
                            Node {
                                padding: UiRect::axes(px(10), px(5)),
                                border: UiRect::all(px(if attack_targeting_active {
                                    2.0
                                } else {
                                    1.0
                                })),
                                ..default()
                            },
                            BackgroundColor(if attack_targeting_active {
                                Color::srgba(0.28, 0.12, 0.10, 0.98).into()
                            } else if attack_enabled {
                                Color::srgba(0.12, 0.09, 0.08, 0.96).into()
                            } else {
                                Color::srgba(0.07, 0.07, 0.08, 0.94).into()
                            }),
                            BorderColor::all(if attack_targeting_active {
                                Color::srgba(0.96, 0.54, 0.44, 1.0)
                            } else if attack_enabled {
                                Color::srgba(0.56, 0.32, 0.28, 1.0)
                            } else {
                                Color::srgba(0.20, 0.20, 0.22, 1.0)
                            }),
                            GameUiButtonAction::EnterAttackTargeting,
                        ))
                        .with_children(|button| {
                            button.spawn(text_bundle(
                                font,
                                if attack_targeting_active {
                                    "攻击中"
                                } else {
                                    "普通攻击"
                                },
                                9.2,
                                if attack_enabled {
                                    Color::WHITE
                                } else {
                                    Color::srgba(0.52, 0.54, 0.58, 1.0)
                                },
                            ));
                        });
                    });

                header
                    .spawn((
                        Node {
                            flex_grow: 1.0,
                            padding: UiRect::axes(px(10), px(8)),
                            flex_direction: FlexDirection::Column,
                            row_gap: px(6),
                            border: UiRect::all(px(1)),
                            ..default()
                        },
                        BackgroundColor(Color::srgba(0.05, 0.06, 0.09, 0.98)),
                        BorderColor::all(Color::srgba(0.18, 0.21, 0.29, 1.0)),
                    ))
                    .with_children(|stats_panel| {
                        stats_panel
                            .spawn(Node {
                                width: Val::Percent(100.0),
                                flex_direction: FlexDirection::Row,
                                column_gap: px(10),
                                align_items: AlignItems::FlexStart,
                                ..default()
                            })
                            .with_children(|meters| {
                                render_stat_meter(
                                    meters,
                                    font,
                                    "生命",
                                    &hp_text,
                                    hp_ratio,
                                    Color::srgba(0.68, 0.16, 0.18, 1.0),
                                    Color::srgba(0.54, 0.20, 0.22, 1.0),
                                );
                                render_stat_meter(
                                    meters,
                                    font,
                                    "行动",
                                    &action_text,
                                    action_ratio,
                                    Color::srgba(0.18, 0.44, 0.70, 1.0),
                                    Color::srgba(0.24, 0.40, 0.58, 1.0),
                                );
                            });
                        stats_panel.spawn(text_bundle(
                            font,
                            &binding_hint,
                            9.0,
                            Color::srgba(0.70, 0.75, 0.84, 1.0),
                        ));
                    });
            });

            body.spawn(Node {
                width: Val::Percent(100.0),
                flex_direction: FlexDirection::Row,
                align_items: AlignItems::Center,
                column_gap: px(8),
                ..default()
            })
            .with_children(|row| {
                row.spawn(Node {
                    width: px(HOTBAR_LEFT_TABS_WIDTH),
                    flex_direction: FlexDirection::Row,
                    column_gap: px(6),
                    justify_content: JustifyContent::FlexStart,
                    align_items: AlignItems::Center,
                    ..default()
                })
                .with_children(|tabs| {
                    for panel in left_tabs {
                        tabs.spawn(dock_tab_button(
                            font,
                            panel_tab_label(panel),
                            menu_state.active_panel == Some(panel),
                            GameUiButtonAction::TogglePanel(panel),
                        ));
                    }
                });

                row.spawn(Node {
                    flex_grow: 1.0,
                    ..default()
                })
                .with_children(|slots_wrap| {
                    render_hotbar_slots(
                        slots_wrap,
                        font,
                        hotbar_state,
                        skills,
                        show_clear_controls,
                        selected_skill_id,
                    );
                });

                row.spawn(Node {
                    width: px(HOTBAR_RIGHT_TABS_WIDTH),
                    flex_direction: FlexDirection::Row,
                    column_gap: px(6),
                    justify_content: JustifyContent::FlexEnd,
                    align_items: AlignItems::Center,
                    ..default()
                })
                .with_children(|tabs| {
                    for panel in right_tabs {
                        tabs.spawn(dock_tab_button(
                            font,
                            panel_tab_label(panel),
                            menu_state.active_panel == Some(panel),
                            GameUiButtonAction::TogglePanel(panel),
                        ));
                    }
                    tabs.spawn(dock_tab_button(
                        font,
                        "关闭",
                        menu_state.active_panel.is_none(),
                        GameUiButtonAction::ClosePanels,
                    ));
                });
            });
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

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::{apply_new_game_defaults, should_render_main_menu, transition_to_gameplay_scene};
    use crate::state::{
        ActiveDialogueState, InteractionMenuState, ViewerRuntimeState, ViewerSceneKind, ViewerState,
    };
    use game_bevy::{ItemDefinitions, UiMenuPanel, UiMenuState, UiModalState};
    use game_core::create_demo_runtime;
    use game_data::{DialogueData, InteractionTargetId, ItemDefinition, ItemFragment};

    fn sample_new_game_item_definitions() -> ItemDefinitions {
        let stackable = |id: u32, name: &str| ItemDefinition {
            id,
            name: name.to_string(),
            fragments: vec![ItemFragment::Stacking {
                stackable: true,
                max_stack: 99,
            }],
            ..ItemDefinition::default()
        };
        let equippable = |id: u32, name: &str, slot: &str| ItemDefinition {
            id,
            name: name.to_string(),
            fragments: vec![
                ItemFragment::Stacking {
                    stackable: false,
                    max_stack: 1,
                },
                ItemFragment::Equip {
                    slots: vec![slot.to_string()],
                    level_requirement: 1,
                    equip_effect_ids: Vec::new(),
                    unequip_effect_ids: Vec::new(),
                },
            ],
            ..ItemDefinition::default()
        };

        ItemDefinitions(game_data::ItemLibrary::from(BTreeMap::from([
            (1002, equippable(1002, "Knife", "main_hand")),
            (1003, stackable(1003, "Bandage")),
            (1006, stackable(1006, "Ration")),
            (1007, stackable(1007, "Water")),
            (1008, stackable(1008, "Scrap")),
            (1009, stackable(1009, "Pistol Ammo")),
            (2004, equippable(2004, "Jacket", "body")),
            (2013, equippable(2013, "Pants", "legs")),
            (2015, equippable(2015, "Boots", "feet")),
        ])))
    }

    #[test]
    fn transition_to_gameplay_scene_resets_viewer_and_ui_state() {
        let mut scene_kind = ViewerSceneKind::MainMenu;
        let (runtime, _) = create_demo_runtime();
        let mut runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: Default::default(),
        };
        let mut viewer_state = ViewerState {
            focused_target: Some(InteractionTargetId::MapObject("door".into())),
            interaction_menu: Some(InteractionMenuState {
                target_id: InteractionTargetId::MapObject("door".into()),
                cursor_position: bevy::prelude::Vec2::new(32.0, 48.0),
            }),
            active_dialogue: Some(ActiveDialogueState {
                actor_id: game_data::ActorId(1),
                target_id: None,
                dialogue_key: "intro".into(),
                dialog_id: "intro".into(),
                data: DialogueData::default(),
                current_node_id: "start".into(),
                target_name: "door".into(),
            }),
            hovered_grid: Some(game_data::GridCoord::new(1, 0, 1)),
            pending_open_trade_target: Some(InteractionTargetId::MapObject("shop".into())),
            status_line: "menu".into(),
            ..ViewerState::default()
        };
        let mut menu_state = UiMenuState {
            active_panel: Some(UiMenuPanel::Inventory),
            selected_inventory_item: Some(42),
            selected_equipment_slot: Some("body".into()),
            selected_skill_tree_id: Some("tree_a".into()),
            selected_skill_id: Some("skill_a".into()),
            selected_recipe_id: Some("recipe_a".into()),
            selected_map_location_id: Some("street_a".into()),
            ..UiMenuState::default()
        };
        let mut modal_state = UiModalState {
            trade: Some(Default::default()),
            ..UiModalState::default()
        };

        transition_to_gameplay_scene(
            &mut scene_kind,
            &mut runtime_state,
            &mut viewer_state,
            &mut menu_state,
            &mut modal_state,
            "开始新游戏",
        );

        assert_eq!(scene_kind, ViewerSceneKind::Gameplay);
        assert!(viewer_state.focused_target.is_none());
        assert!(viewer_state.interaction_menu.is_none());
        assert!(viewer_state.active_dialogue.is_none());
        assert!(viewer_state.hovered_grid.is_none());
        assert_eq!(viewer_state.status_line, "开始新游戏");
        assert!(viewer_state.selected_actor.is_some());
        assert_eq!(
            viewer_state.current_level,
            runtime_state
                .runtime
                .snapshot()
                .grid
                .default_level
                .unwrap_or(0)
        );
        assert!(menu_state.active_panel.is_none());
        assert!(menu_state.selected_inventory_item.is_none());
        assert!(menu_state.selected_skill_tree_id.is_none());
        assert_eq!(menu_state.status_text, "开始新游戏");
        assert!(modal_state.trade.is_none());
    }

    #[test]
    fn main_menu_ui_renders_only_in_main_menu_scene() {
        assert!(should_render_main_menu(ViewerSceneKind::MainMenu));
        assert!(!should_render_main_menu(ViewerSceneKind::Gameplay));
    }

    #[test]
    fn apply_new_game_defaults_does_not_require_ap() {
        let (mut runtime, handles) = create_demo_runtime();
        let items = sample_new_game_item_definitions();
        runtime.economy_mut().set_actor_level(handles.player, 1);
        let _ = runtime.submit_command(game_core::SimulationCommand::SetActorAp {
            actor_id: handles.player,
            ap: 0.0,
        });

        apply_new_game_defaults(&mut runtime, &items).expect("new game setup should succeed");

        assert_eq!(runtime.get_actor_ap(handles.player), 0.0);
        assert_eq!(runtime.get_actor_inventory_count(handles.player, "1008"), 2);
        assert!(runtime
            .economy()
            .equipped_item(handles.player, "main_hand")
            .is_some());
        assert!(runtime.economy().equipped_item(handles.player, "body").is_some());
    }
}
