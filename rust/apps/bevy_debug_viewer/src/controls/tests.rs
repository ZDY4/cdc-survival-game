//! 控制模块测试：覆盖移动取消、快捷键菜单与基础交互输入的回归场景。

use std::collections::BTreeMap;

use super::{
    clear_pending_post_cancel_turn_policy, cursor_interaction_target, enter_attack_targeting,
    enter_skill_targeting, execute_primary_target_interaction, handle_keyboard_input,
    handle_object_primary_click, is_command_actor_self_target, manual_pan_offset_from_follow_focus,
    post_cancel_turn_policy_for_context, refresh_targeting_preview,
    request_cancel_pending_movement, CancelMovementContext, PostCancelTurnPolicy,
};
use crate::console::ViewerConsoleState;
use crate::geometry::{clamp_camera_pan_offset, grid_bounds, selected_actor};
use crate::state::{
    ViewerActorMotionState, ViewerControlMode, ViewerInfoPanelState, ViewerRenderConfig,
    ViewerRuntimeState, ViewerSceneKind, ViewerState, ViewerTargetingSource, ViewerUiSettings,
};
use bevy::prelude::*;
use game_bevy::SettlementDebugSnapshot;
use game_bevy::{SkillDefinitions, UiHotbarState, UiMenuState, UiModalState};
use game_core::{create_demo_runtime, MapObjectDebugState, PendingProgressionStep};
use game_data::{
    ActorSide, GridCoord, InteractionTargetId, MapCellDefinition, MapDefinition,
    MapEntryPointDefinition, MapId, MapLevelDefinition, MapObjectFootprint, MapObjectKind,
    MapRotation, MapSize, SkillActivationDefinition, SkillActivationEffect, SkillDefinition,
    SkillModifierDefinition, SkillTargetingDefinition,
};

#[test]
fn keyboard_cancel_requests_auto_end_turn_out_of_combat() {
    assert_eq!(
        post_cancel_turn_policy_for_context(CancelMovementContext::KeyboardShortcut, false),
        PostCancelTurnPolicy::EndTurnAfterStop
    );
}

#[test]
fn empty_ground_cancel_requests_auto_end_turn_out_of_combat() {
    assert_eq!(
        post_cancel_turn_policy_for_context(CancelMovementContext::EmptyGroundClick, false),
        PostCancelTurnPolicy::EndTurnAfterStop
    );
}

#[test]
fn target_click_cancel_keeps_turn_out_of_combat() {
    assert_eq!(
        post_cancel_turn_policy_for_context(CancelMovementContext::TargetClick, false),
        PostCancelTurnPolicy::KeepCurrentTurn
    );
}

#[test]
fn combat_cancel_never_requests_auto_end_turn() {
    assert_eq!(
        post_cancel_turn_policy_for_context(CancelMovementContext::KeyboardShortcut, true),
        PostCancelTurnPolicy::KeepCurrentTurn
    );
    assert_eq!(
        post_cancel_turn_policy_for_context(CancelMovementContext::EmptyGroundClick, true),
        PostCancelTurnPolicy::KeepCurrentTurn
    );
}

#[test]
fn request_cancel_pending_movement_sets_auto_end_turn_for_keyboard_cancel() {
    let (mut runtime, handles) = create_demo_runtime();
    runtime
        .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
        .expect("path should be planned");
    let mut runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    };
    let mut viewer_state = ViewerState::default();
    viewer_state.select_actor(handles.player, ActorSide::Player);

    let outcome = request_cancel_pending_movement(
        &mut runtime_state,
        &mut viewer_state,
        CancelMovementContext::KeyboardShortcut,
        false,
    );

    assert!(outcome.cancelled);
    assert_eq!(
        outcome.post_cancel_turn_policy,
        PostCancelTurnPolicy::EndTurnAfterStop
    );
    assert!(viewer_state.auto_end_turn_after_stop);
}

#[test]
fn request_cancel_pending_movement_keeps_turn_for_target_click() {
    let (mut runtime, handles) = create_demo_runtime();
    runtime
        .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
        .expect("path should be planned");
    let mut runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    };
    let mut viewer_state = ViewerState::default();
    viewer_state.select_actor(handles.player, ActorSide::Player);

    let outcome = request_cancel_pending_movement(
        &mut runtime_state,
        &mut viewer_state,
        CancelMovementContext::TargetClick,
        false,
    );

    assert!(outcome.cancelled);
    assert_eq!(
        outcome.post_cancel_turn_policy,
        PostCancelTurnPolicy::KeepCurrentTurn
    );
    assert!(!viewer_state.auto_end_turn_after_stop);
}

#[test]
fn clear_pending_post_cancel_turn_policy_resets_state_for_new_move() {
    let mut viewer_state = ViewerState::default();
    viewer_state.auto_end_turn_after_stop = true;

    clear_pending_post_cancel_turn_policy(&mut viewer_state);

    assert!(!viewer_state.auto_end_turn_after_stop);
}

fn sample_los_targeting_map() -> MapDefinition {
    MapDefinition {
        id: MapId("viewer_targeting_los".into()),
        name: "Viewer Targeting LoS".into(),
        size: MapSize {
            width: 6,
            height: 6,
        },
        default_level: 0,
        levels: vec![
            MapLevelDefinition {
                y: 0,
                cells: vec![MapCellDefinition {
                    x: 1,
                    z: 0,
                    blocks_movement: true,
                    blocks_sight: true,
                    terrain: "wall".into(),
                    visual: None,
                    extra: BTreeMap::new(),
                }],
            },
            MapLevelDefinition {
                y: 1,
                cells: Vec::new(),
            },
        ],
        entry_points: vec![MapEntryPointDefinition {
            id: "default_entry".into(),
            grid: GridCoord::new(0, 0, 0),
            facing: None,
            extra: BTreeMap::new(),
        }],
        objects: Vec::new(),
    }
}

fn sample_aoe_occlusion_targeting_map() -> MapDefinition {
    MapDefinition {
        id: MapId("viewer_targeting_aoe_occlusion".into()),
        name: "Viewer Targeting AOE Occlusion".into(),
        size: MapSize {
            width: 6,
            height: 6,
        },
        default_level: 0,
        levels: vec![
            MapLevelDefinition {
                y: 0,
                cells: vec![MapCellDefinition {
                    x: 3,
                    z: 0,
                    blocks_movement: true,
                    blocks_sight: true,
                    terrain: "wall".into(),
                    visual: None,
                    extra: BTreeMap::new(),
                }],
            },
            MapLevelDefinition {
                y: 1,
                cells: Vec::new(),
            },
        ],
        entry_points: vec![MapEntryPointDefinition {
            id: "default_entry".into(),
            grid: GridCoord::new(0, 0, 0),
            facing: None,
            extra: BTreeMap::new(),
        }],
        objects: Vec::new(),
    }
}

fn sample_targeting_skill_definitions() -> SkillDefinitions {
    SkillDefinitions(game_data::SkillLibrary::from(BTreeMap::from([
        (
            "fire_bolt".to_string(),
            SkillDefinition {
                id: "fire_bolt".to_string(),
                name: "Fire Bolt".to_string(),
                activation: Some(SkillActivationDefinition {
                    mode: "active".to_string(),
                    cooldown: 0.0,
                    effect: Some(SkillActivationEffect {
                        modifiers: BTreeMap::from([(
                            "damage".to_string(),
                            SkillModifierDefinition {
                                base: 4.0,
                                per_level: 1.0,
                                max_value: 6.0,
                                ..SkillModifierDefinition::default()
                            },
                        )]),
                        ..SkillActivationEffect::default()
                    }),
                    targeting: Some(SkillTargetingDefinition {
                        enabled: true,
                        range_cells: 5,
                        shape: "single".to_string(),
                        radius: 0,
                        handler_script: "damage_single".to_string(),
                        ..SkillTargetingDefinition::default()
                    }),
                    ..SkillActivationDefinition::default()
                }),
                ..SkillDefinition::default()
            },
        ),
        (
            "shockwave".to_string(),
            SkillDefinition {
                id: "shockwave".to_string(),
                name: "Shockwave".to_string(),
                activation: Some(SkillActivationDefinition {
                    mode: "active".to_string(),
                    cooldown: 0.0,
                    effect: Some(SkillActivationEffect {
                        modifiers: BTreeMap::from([(
                            "damage".to_string(),
                            SkillModifierDefinition {
                                base: 2.0,
                                per_level: 0.5,
                                max_value: 3.0,
                                ..SkillModifierDefinition::default()
                            },
                        )]),
                        ..SkillActivationEffect::default()
                    }),
                    targeting: Some(SkillTargetingDefinition {
                        enabled: true,
                        range_cells: 3,
                        shape: "diamond".to_string(),
                        radius: 1,
                        handler_script: "damage_aoe".to_string(),
                        ..SkillTargetingDefinition::default()
                    }),
                    ..SkillActivationDefinition::default()
                }),
                ..SkillDefinition::default()
            },
        ),
        (
            "shockwave_wide".to_string(),
            SkillDefinition {
                id: "shockwave_wide".to_string(),
                name: "Shockwave Wide".to_string(),
                activation: Some(SkillActivationDefinition {
                    mode: "active".to_string(),
                    cooldown: 0.0,
                    effect: Some(SkillActivationEffect {
                        modifiers: BTreeMap::from([(
                            "damage".to_string(),
                            SkillModifierDefinition {
                                base: 2.0,
                                per_level: 0.5,
                                max_value: 3.0,
                                ..SkillModifierDefinition::default()
                            },
                        )]),
                        ..SkillActivationEffect::default()
                    }),
                    targeting: Some(SkillTargetingDefinition {
                        enabled: true,
                        range_cells: 4,
                        shape: "diamond".to_string(),
                        radius: 2,
                        handler_script: "damage_aoe".to_string(),
                        ..SkillTargetingDefinition::default()
                    }),
                    ..SkillActivationDefinition::default()
                }),
                ..SkillDefinition::default()
            },
        ),
    ])))
}

fn build_spatial_targeting_state() -> (
    ViewerRuntimeState,
    ViewerState,
    SkillDefinitions,
    game_data::ActorId,
    game_data::ActorId,
) {
    let mut simulation = game_core::Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_los_targeting_map());
    let skills = sample_targeting_skill_definitions();
    simulation.set_skill_library(skills.0.clone());

    let player = simulation.register_actor(game_core::RegisterActor {
        definition_id: None,
        display_name: "Player".into(),
        kind: game_data::ActorKind::Player,
        side: game_data::ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(0, 0, 0),
        interaction: None,
        attack_range: 3.0,
        ai_controller: None,
    });
    let hostile = simulation.register_actor(game_core::RegisterActor {
        definition_id: None,
        display_name: "Hostile".into(),
        kind: game_data::ActorKind::Enemy,
        side: game_data::ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation
        .economy_mut()
        .actor_mut(player)
        .expect("player should exist")
        .learned_skills
        .insert("fire_bolt".to_string(), 1);
    simulation
        .economy_mut()
        .actor_mut(player)
        .expect("player should exist")
        .learned_skills
        .insert("shockwave".to_string(), 1);
    simulation.set_actor_ap(player, 2.0);

    let runtime = game_core::SimulationRuntime::from_simulation(simulation);
    let runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    };
    let mut viewer_state = ViewerState::default();
    viewer_state.select_actor(player, ActorSide::Player);

    (runtime_state, viewer_state, skills, player, hostile)
}

#[test]
fn attack_targeting_excludes_occluded_hostile() {
    let (runtime_state, mut viewer_state, _skills, player, hostile) =
        build_spatial_targeting_state();

    let error = enter_attack_targeting(&runtime_state, &mut viewer_state).expect_err(
        "attack targeting should reject when every hostile is blocked by line of sight",
    );

    assert_eq!(error, "范围内没有可攻击目标");
    assert!(viewer_state.targeting_state.is_none());
    let query = runtime_state.runtime.query_attack_targeting(player);
    assert!(!query.valid_actor_ids.contains(&hostile));
    assert!(!query.valid_grids.contains(&GridCoord::new(2, 0, 0)));
}

#[test]
fn skill_targeting_uses_runtime_valid_grids_and_rejects_occluded_center() {
    let (runtime_state, mut viewer_state, skills, _player, _hostile) =
        build_spatial_targeting_state();

    enter_skill_targeting(
        &runtime_state,
        &mut viewer_state,
        &skills,
        "shockwave",
        ViewerTargetingSource::HotbarSlot(0),
    )
    .expect("skill targeting should open");

    let targeting = viewer_state
        .targeting_state
        .as_ref()
        .expect("targeting state should exist");
    assert!(!targeting.valid_grids.contains(&GridCoord::new(2, 0, 0)));
}

#[test]
fn skill_targeting_invalid_hover_has_no_preview_target() {
    let (runtime_state, mut viewer_state, skills, _player, _hostile) =
        build_spatial_targeting_state();

    enter_skill_targeting(
        &runtime_state,
        &mut viewer_state,
        &skills,
        "shockwave",
        ViewerTargetingSource::HotbarSlot(0),
    )
    .expect("skill targeting should open");
    refresh_targeting_preview(
        &runtime_state,
        &mut viewer_state,
        Some(GridCoord::new(2, 0, 0)),
    );

    let targeting = viewer_state
        .targeting_state
        .as_ref()
        .expect("targeting state should exist");
    assert_eq!(targeting.hovered_grid, Some(GridCoord::new(2, 0, 0)));
    assert!(targeting.preview_target.is_none());
    assert!(targeting.preview_hit_grids.is_empty());
    assert!(targeting.preview_hit_actor_ids.is_empty());
}

#[test]
fn skill_targeting_preview_matches_runtime_result() {
    let mut simulation = game_core::Simulation::new();
    simulation.grid_world_mut().load_map(&MapDefinition {
        id: MapId("viewer_targeting_open".into()),
        name: "Viewer Targeting Open".into(),
        size: MapSize {
            width: 6,
            height: 6,
        },
        default_level: 0,
        levels: vec![MapLevelDefinition {
            y: 0,
            cells: Vec::new(),
        }],
        entry_points: vec![MapEntryPointDefinition {
            id: "default_entry".into(),
            grid: GridCoord::new(0, 0, 0),
            facing: None,
            extra: BTreeMap::new(),
        }],
        objects: Vec::new(),
    });
    let skills = sample_targeting_skill_definitions();
    simulation.set_skill_library(skills.0.clone());
    let player = simulation.register_actor(game_core::RegisterActor {
        definition_id: None,
        display_name: "Player".into(),
        kind: game_data::ActorKind::Player,
        side: game_data::ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(0, 0, 0),
        interaction: None,
        attack_range: 3.0,
        ai_controller: None,
    });
    let hostile = simulation.register_actor(game_core::RegisterActor {
        definition_id: None,
        display_name: "Hostile".into(),
        kind: game_data::ActorKind::Enemy,
        side: game_data::ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let flank = simulation.register_actor(game_core::RegisterActor {
        definition_id: None,
        display_name: "Flank".into(),
        kind: game_data::ActorKind::Enemy,
        side: game_data::ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(2, 0, 1),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation
        .economy_mut()
        .actor_mut(player)
        .expect("player should exist")
        .learned_skills
        .insert("shockwave".to_string(), 1);
    simulation.set_actor_ap(player, 2.0);

    let runtime = game_core::SimulationRuntime::from_simulation(simulation);
    let runtime_preview = runtime.preview_skill_target(
        player,
        "shockwave",
        game_data::SkillTargetRequest::Grid(GridCoord::new(2, 0, 0)),
    );
    let runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    };
    let mut viewer_state = ViewerState::default();
    viewer_state.select_actor(player, ActorSide::Player);

    enter_skill_targeting(
        &runtime_state,
        &mut viewer_state,
        &skills,
        "shockwave",
        ViewerTargetingSource::HotbarSlot(0),
    )
    .expect("skill targeting should open");
    refresh_targeting_preview(
        &runtime_state,
        &mut viewer_state,
        Some(GridCoord::new(2, 0, 0)),
    );

    let targeting = viewer_state
        .targeting_state
        .as_ref()
        .expect("targeting state should exist");
    assert_eq!(targeting.preview_target, runtime_preview.resolved_target);
    assert_eq!(
        targeting.preview_hit_grids,
        runtime_preview.preview_hit_grids
    );
    assert_eq!(
        targeting.preview_hit_actor_ids,
        runtime_preview.preview_hit_actor_ids
    );
    assert!(targeting.preview_hit_actor_ids.contains(&hostile));
    assert!(targeting.preview_hit_actor_ids.contains(&flank));
}

#[test]
fn skill_targeting_preview_excludes_aoe_targets_occluded_from_center() {
    let mut simulation = game_core::Simulation::new();
    simulation
        .grid_world_mut()
        .load_map(&sample_aoe_occlusion_targeting_map());
    let skills = sample_targeting_skill_definitions();
    simulation.set_skill_library(skills.0.clone());
    let player = simulation.register_actor(game_core::RegisterActor {
        definition_id: None,
        display_name: "Player".into(),
        kind: game_data::ActorKind::Player,
        side: game_data::ActorSide::Player,
        group_id: "player".into(),
        grid_position: GridCoord::new(0, 0, 0),
        interaction: None,
        attack_range: 3.0,
        ai_controller: None,
    });
    let center_hostile = simulation.register_actor(game_core::RegisterActor {
        definition_id: None,
        display_name: "Center".into(),
        kind: game_data::ActorKind::Enemy,
        side: game_data::ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(2, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    let occluded_hostile = simulation.register_actor(game_core::RegisterActor {
        definition_id: None,
        display_name: "Occluded".into(),
        kind: game_data::ActorKind::Enemy,
        side: game_data::ActorSide::Hostile,
        group_id: "hostile".into(),
        grid_position: GridCoord::new(4, 0, 0),
        interaction: None,
        attack_range: 1.2,
        ai_controller: None,
    });
    simulation
        .economy_mut()
        .actor_mut(player)
        .expect("player should exist")
        .learned_skills
        .insert("shockwave_wide".to_string(), 1);
    simulation.set_actor_ap(player, 2.0);

    let runtime = game_core::SimulationRuntime::from_simulation(simulation);
    let runtime_preview = runtime.preview_skill_target(
        player,
        "shockwave_wide",
        game_data::SkillTargetRequest::Grid(GridCoord::new(2, 0, 0)),
    );
    let runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    };
    let mut viewer_state = ViewerState::default();
    viewer_state.select_actor(player, ActorSide::Player);

    enter_skill_targeting(
        &runtime_state,
        &mut viewer_state,
        &skills,
        "shockwave_wide",
        ViewerTargetingSource::HotbarSlot(0),
    )
    .expect("wide AOE targeting should open");
    refresh_targeting_preview(
        &runtime_state,
        &mut viewer_state,
        Some(GridCoord::new(2, 0, 0)),
    );

    let targeting = viewer_state
        .targeting_state
        .as_ref()
        .expect("targeting state should exist");
    assert_eq!(
        targeting.preview_hit_grids,
        runtime_preview.preview_hit_grids
    );
    assert_eq!(
        targeting.preview_hit_actor_ids,
        runtime_preview.preview_hit_actor_ids
    );
    assert!(targeting.preview_hit_actor_ids.contains(&center_hostile));
    assert!(!targeting.preview_hit_actor_ids.contains(&occluded_hostile));
    assert!(!targeting
        .preview_hit_grids
        .contains(&GridCoord::new(4, 0, 0)));
}

#[test]
fn manual_pan_offset_from_follow_focus_preserves_current_follow_focus() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    };
    let motion_state = ViewerActorMotionState::default();
    let mut viewer_state = ViewerState::default();
    viewer_state.select_actor(handles.player, ActorSide::Player);

    let bounds = grid_bounds(&snapshot, viewer_state.current_level);
    let render_config = ViewerRenderConfig::default();
    let pan_offset = manual_pan_offset_from_follow_focus(
        &runtime_state,
        &motion_state,
        &snapshot,
        &viewer_state,
        bounds,
        1440.0,
        900.0,
        render_config,
    );

    let actor = selected_actor(&snapshot, &viewer_state).expect("selected actor should exist");
    let actor_world = runtime_state.runtime.grid_to_world(actor.grid_position);
    let center_x = (bounds.min_x + bounds.max_x + 1) as f32 * snapshot.grid.grid_size * 0.5;
    let center_z = (bounds.min_z + bounds.max_z + 1) as f32 * snapshot.grid.grid_size * 0.5;
    let expected = clamp_camera_pan_offset(
        bounds,
        snapshot.grid.grid_size,
        bevy::prelude::Vec2::new(actor_world.x - center_x, actor_world.z - center_z),
        1440.0,
        900.0,
        render_config,
    );

    assert_eq!(pan_offset, expected);
}

#[test]
fn object_click_without_interactions_falls_back_to_move_on_walkable_grid() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let mut runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    };
    let mut viewer_state = ViewerState::default();
    viewer_state.select_actor(handles.player, ActorSide::Player);

    let fake_object = MapObjectDebugState {
        object_id: "fake_building".into(),
        kind: MapObjectKind::Building,
        anchor: GridCoord::new(0, 0, 2),
        footprint: MapObjectFootprint {
            width: 1,
            height: 1,
        },
        rotation: MapRotation::North,
        blocks_movement: false,
        blocks_sight: false,
        occupied_cells: vec![GridCoord::new(0, 0, 2)],
        payload_summary: Default::default(),
    };

    handle_object_primary_click(
        &mut runtime_state,
        &mut viewer_state,
        &snapshot,
        &fake_object.object_id,
        GridCoord::new(0, 0, 2),
    );

    assert!(runtime_state.runtime.pending_movement().is_some());
    assert!(viewer_state.status_line.starts_with("move:"));
    assert!(viewer_state.focused_target.is_none());
}

#[test]
fn command_actor_self_target_is_detected_for_wait_interaction() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let actor = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == handles.player)
        .expect("player actor should exist");
    let mut viewer_state = ViewerState::default();
    viewer_state.select_actor(handles.player, ActorSide::Player);

    assert!(is_command_actor_self_target(
        &snapshot,
        &viewer_state,
        actor
    ));
    assert_eq!(
        cursor_interaction_target(Some(handles.player), Some(actor), None),
        Some(InteractionTargetId::Actor(handles.player))
    );
}

#[test]
fn self_primary_interaction_wait_queues_turn_progression() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let mut runtime_state = ViewerRuntimeState {
        runtime,
        recent_events: Vec::new(),
        ai_snapshot: SettlementDebugSnapshot::default(),
    };
    let mut viewer_state = ViewerState::default();
    viewer_state.select_actor(handles.player, ActorSide::Player);

    let executed = execute_primary_target_interaction(
        &mut runtime_state,
        &mut viewer_state,
        &snapshot,
        InteractionTargetId::Actor(handles.player),
        "self".to_string(),
        "test",
    );

    assert!(executed);
    assert_eq!(
        runtime_state.runtime.peek_pending_progression(),
        Some(&PendingProgressionStep::RunNonCombatWorldCycle)
    );
    assert!(runtime_state.runtime.pending_interaction().is_none());
    assert_eq!(
        viewer_state.focused_target,
        Some(InteractionTargetId::Actor(handles.player))
    );
    assert_eq!(
        viewer_state
            .current_prompt
            .as_ref()
            .and_then(|prompt| prompt.primary_option_id.clone())
            .map(|id| id.0),
        Some("wait".to_string())
    );
}

#[test]
fn main_menu_scene_ignores_escape_shortcut() {
    let app = keyboard_input_app(ViewerSceneKind::MainMenu, KeyCode::Escape);

    let menu_state = app.world().resource::<UiMenuState>();
    assert!(!menu_state.any_panel_open());
}

#[test]
fn main_menu_scene_ignores_gameplay_menu_hotkeys() {
    let app = keyboard_input_app(ViewerSceneKind::MainMenu, KeyCode::KeyI);

    let menu_state = app.world().resource::<UiMenuState>();
    assert!(!menu_state.any_panel_open());
}

#[test]
fn gameplay_escape_opens_settings_panel() {
    let app = keyboard_input_app(ViewerSceneKind::Gameplay, KeyCode::Escape);

    let menu_state = app.world().resource::<UiMenuState>();
    let viewer_state = app.world().resource::<ViewerState>();
    assert!(menu_state.is_settings_open());
    assert_eq!(viewer_state.status_line, "menu: settings");
}

#[test]
fn gameplay_escape_closes_trade_before_opening_settings() {
    let mut app = keyboard_input_app(ViewerSceneKind::Gameplay, KeyCode::Escape);
    app.world_mut()
        .resource_mut::<UiMenuState>()
        .close_all_panels();
    app.world_mut().resource_mut::<UiModalState>().trade = Some(Default::default());
    app.world_mut()
        .resource_mut::<ViewerState>()
        .pending_open_trade_target = Some(game_data::InteractionTargetId::MapObject("shop".into()));
    app.world_mut()
        .resource_mut::<ButtonInput<KeyCode>>()
        .press(KeyCode::Escape);

    app.update();

    let menu_state = app.world().resource::<UiMenuState>();
    let modal_state = app.world().resource::<UiModalState>();
    let viewer_state = app.world().resource::<ViewerState>();
    assert!(!menu_state.any_panel_open());
    assert!(modal_state.trade.is_none());
    assert!(viewer_state.pending_open_trade_target.is_none());
    assert_eq!(viewer_state.status_line, "trade: closed");
}

#[test]
fn gameplay_escape_closes_discard_modal_before_trade() {
    let mut app = keyboard_input_app(ViewerSceneKind::Gameplay, KeyCode::Escape);
    app.world_mut()
        .resource_mut::<UiMenuState>()
        .close_all_panels();
    {
        let mut modal_state = app.world_mut().resource_mut::<UiModalState>();
        modal_state.item_quantity = Some(game_bevy::UiItemQuantityModalState {
            item_id: 1006,
            source_count: 3,
            available_count: 3,
            selected_count: 2,
            intent: game_bevy::UiItemQuantityIntent::Discard,
        });
        modal_state.trade = Some(Default::default());
    }
    app.world_mut()
        .resource_mut::<ButtonInput<KeyCode>>()
        .press(KeyCode::Escape);

    app.update();

    let modal_state = app.world().resource::<UiModalState>();
    let viewer_state = app.world().resource::<ViewerState>();
    assert!(modal_state.item_quantity.is_none());
    assert!(modal_state.trade.is_some());
    assert_eq!(viewer_state.status_line, "item quantity: closed");
}

#[test]
fn ctrl_p_no_longer_toggles_free_observe_mode() {
    let (runtime, _) = create_demo_runtime();
    let mut app = App::new();
    app.insert_resource(ButtonInput::<KeyCode>::default())
        .insert_resource(Time::<()>::default())
        .insert_resource(ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        })
        .insert_resource(ViewerState::default())
        .insert_resource(ViewerInfoPanelState::default())
        .insert_resource(ViewerRenderConfig::default())
        .insert_resource(UiMenuState::default())
        .insert_resource(UiModalState::default())
        .insert_resource(UiHotbarState::default())
        .insert_resource(ViewerUiSettings::default())
        .insert_resource(SkillDefinitions(Default::default()))
        .insert_resource(ViewerConsoleState::default())
        .insert_resource(ViewerSceneKind::Gameplay)
        .add_systems(Update, handle_keyboard_input);

    {
        let mut keys = app.world_mut().resource_mut::<ButtonInput<KeyCode>>();
        keys.press(KeyCode::ControlLeft);
        keys.press(KeyCode::KeyP);
    }

    app.update();

    let viewer_state = app.world().resource::<ViewerState>();
    assert!(viewer_state.is_player_control());
}

#[test]
fn space_toggles_ob_playback_in_free_observe_mode() {
    let (runtime, _) = create_demo_runtime();
    let mut app = App::new();
    app.insert_resource(ButtonInput::<KeyCode>::default())
        .insert_resource(Time::<()>::default())
        .insert_resource(ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        })
        .insert_resource(ViewerState {
            control_mode: ViewerControlMode::FreeObserve,
            auto_tick: true,
            ..ViewerState::default()
        })
        .insert_resource(ViewerInfoPanelState::default())
        .insert_resource(ViewerRenderConfig::default())
        .insert_resource(UiMenuState::default())
        .insert_resource(UiModalState::default())
        .insert_resource(UiHotbarState::default())
        .insert_resource(ViewerUiSettings::default())
        .insert_resource(SkillDefinitions(Default::default()))
        .insert_resource(ViewerConsoleState::default())
        .insert_resource(ViewerSceneKind::Gameplay)
        .add_systems(Update, handle_keyboard_input);

    app.world_mut()
        .resource_mut::<ButtonInput<KeyCode>>()
        .press(KeyCode::Space);

    app.update();

    let viewer_state = app.world().resource::<ViewerState>();
    assert!(viewer_state.is_free_observe());
    assert!(!viewer_state.auto_tick);
    assert_eq!(viewer_state.status_line, "ob playback: paused (1X)");
}

fn keyboard_input_app(scene_kind: ViewerSceneKind, key: KeyCode) -> App {
    let (runtime, _) = create_demo_runtime();
    let mut app = App::new();
    app.insert_resource(ButtonInput::<KeyCode>::default())
        .insert_resource(Time::<()>::default())
        .insert_resource(ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        })
        .insert_resource(ViewerState::default())
        .insert_resource(ViewerInfoPanelState::default())
        .insert_resource(ViewerRenderConfig::default())
        .insert_resource(UiMenuState::default())
        .insert_resource(UiModalState::default())
        .insert_resource(UiHotbarState::default())
        .insert_resource(ViewerUiSettings::default())
        .insert_resource(SkillDefinitions(Default::default()))
        .insert_resource(ViewerConsoleState::default())
        .insert_resource(scene_kind)
        .add_systems(Update, handle_keyboard_input);

    app.world_mut()
        .resource_mut::<ButtonInput<KeyCode>>()
        .press(key);
    app.update();
    app
}
