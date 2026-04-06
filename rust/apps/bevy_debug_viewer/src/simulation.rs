//! 模拟门面：统一组织运行时桥接、推进、交互、移动和反馈系统的对外入口。

use std::collections::BTreeMap;

use bevy::prelude::*;
use game_bevy::{
    advance_map_ai_spawn_runtime, CharacterDefinitions, MapAiSpawnRuntimeState, MapDefinitions,
};
use game_core::runtime::action_result_status;
use game_core::{
    AutoMoveInterruptReason, PendingProgressionStep, ProgressionAdvanceResult, SimulationCommand,
    SimulationCommandResult, SimulationEvent,
};
use game_data::{ActorId, ActorSide, GridCoord, MapId};

use crate::dialogue::sync_dialogue_from_event;
use crate::state::{
    HudEventCategory, ViewerActorFeedbackState, ViewerActorMotionState, ViewerCameraShakeState,
    ViewerDamageNumberState, ViewerEventEntry, ViewerRuntimeState, ViewerSceneKind, ViewerState,
};

mod event_feedback;
mod interaction_prompt_sync;
mod motion;
mod npc_actions;
mod npc_presence;
mod progression;
mod runtime_basics;
mod runtime_bridge;

pub(crate) use event_feedback::collect_events;
pub(crate) use interaction_prompt_sync::refresh_interaction_prompt;
pub(crate) use motion::{advance_actor_feedback, advance_actor_motion};
pub(crate) use npc_actions::advance_online_npc_actions;
pub(crate) use npc_presence::sync_npc_runtime_presence;
pub(crate) use progression::{
    advance_runtime_progression, cancel_pending_movement, submit_end_turn,
};
pub(crate) use runtime_basics::{
    advance_map_ai_spawns, prime_viewer_state, refresh_viewer_vision,
    reset_viewer_runtime_transients, sync_viewer_runtime_basics, tick_runtime,
    ViewerVisionTrackerState,
};
pub(crate) use runtime_bridge::viewer_event_entry;

const ACTOR_MOTION_DURATION_SCALE: f32 = 2.0 / 3.0;
const ACTOR_MOTION_MIN_DURATION_SEC: f32 = 0.04 * ACTOR_MOTION_DURATION_SCALE;
const ACTOR_MOTION_MAX_DURATION_SEC: f32 = 0.16 * ACTOR_MOTION_DURATION_SCALE;

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::progression::maybe_auto_end_turn_after_stop;
    use super::{
        advance_online_npc_actions, advance_runtime_progression, collect_events, event_feedback,
        refresh_interaction_prompt, sync_npc_runtime_presence, ACTOR_MOTION_DURATION_SCALE,
        ACTOR_MOTION_MAX_DURATION_SEC, ACTOR_MOTION_MIN_DURATION_SEC,
    };
    use crate::dialogue::apply_interaction_result;
    use crate::state::{
        ViewerActorFeedbackState, ViewerActorMotionState, ViewerCameraShakeState,
        ViewerDamageNumberState, ViewerRuntimeState, ViewerState,
    };
    use bevy::ecs::message::Messages;
    use bevy::prelude::*;
    use game_bevy::{
        build_runtime_from_default_startup_seed, load_ai_definitions, load_runtime_bootstrap,
        load_settlement_definitions, spawn_characters_from_definition, AiDefinitionPath,
        CharacterDefinitionPath, CharacterDefinitions, CharacterSpawnRejected, CurrentAction,
        CurrentPlan, NpcLifePlugin, NpcLifeState, RuntimeActorLink, RuntimeExecutionState,
        SettlementDebugSnapshot, SettlementDefinitionPath, SettlementSimulationPlugin,
        SpawnCharacterRequest,
    };
    use game_core::{
        create_demo_runtime, PendingProgressionStep, RegisterActor, Simulation,
        SimulationCommand, SimulationEvent, SimulationRuntime,
    };
    use game_data::{
        ActorId, ActorKind, ActorSide, GridCoord, InteractionOptionId, InteractionTargetId,
        MapBuildingLayoutSpec, MapBuildingProps, MapBuildingStairSpec, MapBuildingStorySpec,
        MapDefinition, MapEntryPointDefinition, MapId, MapLevelDefinition, MapObjectDefinition,
        MapObjectFootprint, MapObjectKind, MapObjectProps, MapPickupProps, MapRotation,
        MapSize, MapTriggerProps, OverworldCellDefinition, OverworldDefinition, OverworldId,
        OverworldLibrary, OverworldLocationDefinition, OverworldLocationId,
        OverworldLocationKind, OverworldTravelRuleSet, RelativeGridCell, StairKind, WorldCoord,
        WorldMode,
    };

    fn seed_life_debug_spawns(app: &mut App) {
        let definition_ids = app
            .world()
            .resource::<CharacterDefinitions>()
            .0
            .iter()
            .filter_map(|(definition_id, definition)| {
                definition.life.as_ref().map(|_| definition_id.clone())
            })
            .collect::<Vec<_>>();
        let mut next_spawn_x = 8;
        let mut requests = app
            .world_mut()
            .resource_mut::<Messages<SpawnCharacterRequest>>();
        for definition_id in definition_ids {
            requests.write(SpawnCharacterRequest {
                definition_id,
                grid_position: GridCoord::new(next_spawn_x, 0, 8),
            });
            next_spawn_x += 1;
        }
    }

    #[test]
    fn online_life_npcs_receive_runtime_goals_and_register_runtime_travel_intent() {
        let bootstrap = load_runtime_bootstrap(
            &CharacterDefinitionPath::default().0,
            &game_bevy::MapDefinitionPath::default().0,
            &game_bevy::OverworldDefinitionPath::default().0,
            &game_bevy::RuntimeStartupConfigPath::default().0,
        )
        .expect("viewer bootstrap should load");
        let settlements = load_settlement_definitions(&SettlementDefinitionPath::default().0)
            .expect("settlement definitions should load");
        let ai_definitions = load_ai_definitions(&AiDefinitionPath::default().0)
            .expect("ai definitions should load");
        let runtime =
            build_runtime_from_default_startup_seed(&bootstrap).expect("runtime should build");

        let mut app = App::new();
        app.add_plugins((SettlementSimulationPlugin, NpcLifePlugin));
        app.add_message::<SpawnCharacterRequest>();
        app.add_message::<CharacterSpawnRejected>();
        app.insert_resource(bootstrap.character_definitions);
        app.insert_resource(settlements);
        app.insert_resource(ai_definitions);
        app.insert_resource(ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        });
        app.insert_resource(ViewerState::default());
        app.add_systems(
            Update,
            (
                spawn_characters_from_definition,
                sync_npc_runtime_presence,
                advance_online_npc_actions,
            )
                .chain(),
        );

        seed_life_debug_spawns(&mut app);
        for _ in 0..6 {
            app.update();
        }
        let world = app.world_mut();
        let mut query = world.query::<(
            &NpcLifeState,
            &CurrentPlan,
            &CurrentAction,
            &RuntimeExecutionState,
            &RuntimeActorLink,
        )>();

        let mut online_count = 0usize;
        let mut goal_count = 0usize;
        let mut moving_candidates = Vec::new();
        for (life, plan, action, runtime_execution, runtime_link) in query.iter(world) {
            if !life.online {
                continue;
            }
            online_count += 1;
            assert!(
                !plan.steps.is_empty() || action.0.is_some(),
                "online NPC should have a plan or current action"
            );

            if let Some(goal) = runtime_execution.runtime_goal_grid {
                goal_count += 1;
                moving_candidates.push((runtime_link.actor_id, goal));
            }
        }
        let runtime = &app.world().resource::<ViewerRuntimeState>().runtime;
        let moving_candidates = moving_candidates
            .into_iter()
            .filter_map(|(actor_id, goal)| {
                runtime
                    .get_actor_grid_position(actor_id)
                    .map(|start| (actor_id, start, goal))
            })
            .collect::<Vec<_>>();

        assert!(online_count > 0, "expected at least one online life NPC");
        assert!(
            goal_count > 0,
            "expected at least one online life NPC to receive a runtime movement goal"
        );
        assert!(
            !moving_candidates.is_empty(),
            "expected at least one online NPC with a tracked start position"
        );

        let player_actor_id = app
            .world()
            .resource::<ViewerRuntimeState>()
            .runtime
            .snapshot()
            .actors
            .iter()
            .find(|actor| actor.side == ActorSide::Player)
            .map(|actor| actor.actor_id)
            .expect("player actor should exist");

        {
            let mut runtime_state = app.world_mut().resource_mut::<ViewerRuntimeState>();
            let result = runtime_state
                .runtime
                .submit_command(SimulationCommand::EndTurn {
                    actor_id: player_actor_id,
                });
            match result {
                game_core::SimulationCommandResult::Action(action) => {
                    assert!(action.success, "end turn should succeed");
                }
                other => panic!("unexpected end turn result: {other:?}"),
            }

            while runtime_state.runtime.has_pending_progression() {
                runtime_state.runtime.advance_pending_progression();
            }
        }

        let runtime = &app.world().resource::<ViewerRuntimeState>().runtime;
        let moved_any =
            moving_candidates
                .iter()
                .any(|(actor_id, start_position, expected_goal)| {
                    runtime
                        .get_actor_grid_position(*actor_id)
                        .is_some_and(|end_position| {
                            end_position != *start_position && *start_position != *expected_goal
                        })
                });
        let still_has_runtime_travel_intent =
            moving_candidates
                .iter()
                .any(|(actor_id, start_position, expected_goal)| {
                    *start_position != *expected_goal
                        && runtime.get_actor_autonomous_movement_goal(*actor_id)
                            == Some(*expected_goal)
                });

        assert!(
            moved_any || still_has_runtime_travel_intent,
            "expected at least one online NPC to either move or keep a registered runtime travel goal"
        );
    }

    #[test]
    fn actor_motion_duration_is_clamped() {
        assert_eq!(
            event_feedback::actor_motion_duration_sec(0.0),
            ACTOR_MOTION_MIN_DURATION_SEC
        );
        assert_eq!(
            event_feedback::actor_motion_duration_sec(1.0),
            ACTOR_MOTION_MAX_DURATION_SEC
        );
        assert!(
            (event_feedback::actor_motion_duration_sec(0.1)
                - (0.1 * ACTOR_MOTION_DURATION_SCALE))
                .abs()
                <= 0.0001
        );
    }

    #[test]
    fn queue_actor_motion_uses_active_interpolated_position_as_next_start() {
        let (runtime, handles) = create_demo_runtime();
        let mut motion_state = ViewerActorMotionState::default();
        motion_state.track_movement(
            handles.player,
            WorldCoord::new(0.5, 0.5, 0.5),
            WorldCoord::new(1.5, 0.5, 0.5),
            0,
            0.1,
        );
        motion_state
            .tracks
            .get_mut(&handles.player)
            .expect("track should exist")
            .advance(0.05);
        let current_world = motion_state
            .tracks
            .get(&handles.player)
            .expect("track should still exist")
            .current_world;
        let runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };

        event_feedback::queue_actor_motion(
            &mut motion_state,
            &runtime_state,
            handles.player,
            GridCoord::new(1, 0, 0),
            GridCoord::new(2, 0, 0),
            0.1,
        );

        let next_track = motion_state
            .tracks
            .get(&handles.player)
            .expect("next track should exist");
        assert_eq!(next_track.from_world, current_world);
        assert_eq!(next_track.to_world, WorldCoord::new(2.5, 0.5, 0.5));
    }

    #[test]
    fn queue_attack_and_hit_feedback_tracks_attacker_and_target() {
        let (runtime, handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        let runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let target_actor = snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id != handles.player)
            .expect("fixture should include a non-player target");
        let mut feedback_state = ViewerActorFeedbackState::default();
        let mut camera_shake_state = ViewerCameraShakeState::default();
        let mut damage_number_state = ViewerDamageNumberState::default();

        event_feedback::queue_attack_and_hit_feedback(
            &mut feedback_state,
            &mut camera_shake_state,
            &mut damage_number_state,
            &runtime_state,
            &snapshot,
            handles.player,
            target_actor.actor_id,
            11.0,
        );

        assert!(feedback_state
            .tracks
            .get(&handles.player)
            .and_then(|tracks| tracks.attack_lunge)
            .is_some());
        assert!(feedback_state
            .tracks
            .get(&target_actor.actor_id)
            .and_then(|tracks| tracks.hit_reaction)
            .is_some());
        assert!(!damage_number_state.entries.is_empty());
        camera_shake_state.advance(0.05);
        assert!(camera_shake_state.current_offset().length() > 0.0);
    }

    #[test]
    fn auto_end_turn_after_stop_submits_once_movement_fully_stops() {
        let (mut runtime, handles) = create_demo_runtime();
        runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 3))
            .expect("path should be planned");

        assert_eq!(
            runtime.advance_pending_progression().applied_step,
            Some(game_core::PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert_eq!(
            runtime.advance_pending_progression().applied_step,
            Some(game_core::PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );
        assert!(runtime.request_pending_movement_stop(handles.player));
        let stop_result = runtime.advance_pending_progression();
        assert_eq!(
            stop_result.interrupt_reason,
            Some(game_core::AutoMoveInterruptReason::CancelledByNewCommand)
        );
        assert_eq!(
            runtime.advance_pending_progression().applied_step,
            Some(game_core::PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert_eq!(
            runtime.advance_pending_progression().applied_step,
            Some(game_core::PendingProgressionStep::StartNextNonCombatPlayerTurn)
        );
        assert!(!runtime.has_pending_progression());
        assert!(runtime.actor_turn_open(handles.player));

        let mut runtime_state = ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        };
        let mut viewer_state = ViewerState::default();
        viewer_state.select_actor(handles.player, ActorSide::Player);
        viewer_state.auto_end_turn_after_stop = true;

        maybe_auto_end_turn_after_stop(&mut runtime_state, &mut viewer_state);

        assert!(!viewer_state.auto_end_turn_after_stop);
        assert_eq!(
            runtime_state.runtime.peek_pending_progression(),
            Some(&game_core::PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert!(!runtime_state.runtime.actor_turn_open(handles.player));
    }

    #[test]
    fn scene_transition_events_preserve_pending_progression_during_prompt_refresh() {
        let (mut runtime, handles) = create_demo_runtime();
        runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 1))
            .expect("path should be planned");
        runtime.push_event(SimulationEvent::LocationEntered {
            actor_id: handles.player,
            location_id: "survivor_outpost_01".into(),
            map_id: "survivor_outpost_01_grid".into(),
            entry_point_id: "default_entry".into(),
            world_mode: game_core::WorldMode::Outdoor,
        });

        let mut app = App::new();
        app.insert_resource(Time::<()>::default())
            .insert_resource(ViewerRuntimeState {
                runtime,
                recent_events: Vec::new(),
                ai_snapshot: SettlementDebugSnapshot::default(),
            })
            .insert_resource(ViewerActorFeedbackState::default())
            .insert_resource(ViewerCameraShakeState::default())
            .insert_resource(ViewerDamageNumberState::default())
            .insert_resource(ViewerActorMotionState::default())
            .insert_resource(ViewerState::default())
            .add_systems(
                Update,
                (
                    advance_runtime_progression,
                    collect_events,
                    refresh_interaction_prompt,
                )
                    .chain(),
            );

        {
            let mut viewer_state = app.world_mut().resource_mut::<ViewerState>();
            viewer_state.select_actor(handles.player, ActorSide::Player);
            viewer_state.min_progression_interval_sec = 0.0;
            viewer_state.focused_target =
                Some(InteractionTargetId::MapObject("stale_exit_trigger".into()));
        }

        app.update();

        {
            let runtime_state = app.world().resource::<ViewerRuntimeState>();
            let viewer_state = app.world().resource::<ViewerState>();
            assert_eq!(
                runtime_state.runtime.peek_pending_progression(),
                Some(&PendingProgressionStep::StartNextNonCombatPlayerTurn)
            );
            assert!(viewer_state.focused_target.is_none());
            assert!(viewer_state.current_prompt.is_none());
            assert!(!runtime_state.runtime.actor_turn_open(handles.player));
        }

        app.update();

        let runtime_state = app.world().resource::<ViewerRuntimeState>();
        assert!(!runtime_state.runtime.has_pending_progression());
        assert!(runtime_state.runtime.actor_turn_open(handles.player));
    }

    #[test]
    fn prompt_refresh_preserves_pending_progression() {
        let (mut runtime, handles) = create_demo_runtime();
        let move_result = runtime.submit_command(SimulationCommand::MoveActorTo {
            actor_id: handles.player,
            goal: GridCoord::new(0, 0, 1),
        });
        assert!(matches!(
            move_result,
            game_core::SimulationCommandResult::Action(_)
        ));
        assert_eq!(
            runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );

        let mut app = App::new();
        app.insert_resource(ViewerRuntimeState {
            runtime,
            recent_events: Vec::new(),
            ai_snapshot: SettlementDebugSnapshot::default(),
        })
        .insert_resource(ViewerState::default())
        .add_systems(Update, refresh_interaction_prompt);

        {
            let mut viewer_state = app.world_mut().resource_mut::<ViewerState>();
            viewer_state.select_actor(handles.player, ActorSide::Player);
            viewer_state.focused_target = Some(InteractionTargetId::Actor(handles.friendly));
        }

        app.update();

        let runtime_state = app.world().resource::<ViewerRuntimeState>();
        let viewer_state = app.world().resource::<ViewerState>();
        assert_eq!(
            runtime_state.runtime.peek_pending_progression(),
            Some(&PendingProgressionStep::RunNonCombatWorldCycle)
        );
        assert!(viewer_state.current_prompt.is_some());
    }

    #[test]
    fn free_observe_pause_freezes_pending_progression_consumption() {
        let (mut runtime, handles) = create_demo_runtime();
        runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");

        let mut app = App::new();
        app.insert_resource(Time::<()>::default())
            .insert_resource(ViewerRuntimeState {
                runtime,
                recent_events: Vec::new(),
                ai_snapshot: SettlementDebugSnapshot::default(),
            })
            .insert_resource(ViewerState::default())
            .add_systems(Update, advance_runtime_progression);

        {
            let mut viewer_state = app.world_mut().resource_mut::<ViewerState>();
            viewer_state.control_mode = crate::state::ViewerControlMode::FreeObserve;
            viewer_state.auto_tick = false;
            viewer_state.min_progression_interval_sec = 0.0;
        }

        let before = app
            .world()
            .resource::<ViewerRuntimeState>()
            .runtime
            .peek_pending_progression()
            .copied();
        app.update();
        let runtime_state = app.world().resource::<ViewerRuntimeState>();
        let viewer_state = app.world().resource::<ViewerState>();

        assert_eq!(runtime_state.runtime.peek_pending_progression().copied(), before);
        assert_eq!(viewer_state.progression_elapsed_sec, 0.0);
    }

    #[test]
    fn pickup_after_approach_clears_consumed_target_ui() {
        let player = ActorId(1);
        let pickup_target = InteractionTargetId::MapObject("pickup".into());
        let mut app = App::new();
        app.insert_resource(Time::<()>::default())
            .insert_resource(ViewerRuntimeState {
                runtime: viewer_pickup_runtime(player),
                recent_events: Vec::new(),
                ai_snapshot: SettlementDebugSnapshot::default(),
            })
            .insert_resource(ViewerActorFeedbackState::default())
            .insert_resource(ViewerCameraShakeState::default())
            .insert_resource(ViewerDamageNumberState::default())
            .insert_resource(ViewerActorMotionState::default())
            .insert_resource(ViewerState::default())
            .add_systems(
                Update,
                (
                    advance_runtime_progression,
                    collect_events,
                    refresh_interaction_prompt,
                )
                    .chain(),
            );

        app.world_mut().resource_scope(
            |world, mut runtime_state: Mut<ViewerRuntimeState>| {
                let mut viewer_state = world.resource_mut::<ViewerState>();
            viewer_state.select_actor(player, ActorSide::Player);
            viewer_state.min_progression_interval_sec = 0.0;
            viewer_state.focused_target = Some(pickup_target.clone());
            viewer_state.current_prompt = runtime_state
                .runtime
                .query_interaction_prompt(player, pickup_target.clone());

            let result = runtime_state.runtime.issue_interaction(
                player,
                pickup_target.clone(),
                InteractionOptionId("pickup".into()),
            );
            apply_interaction_result(&runtime_state, &mut viewer_state, result.clone());

            assert!(result.approach_required);
            assert!(viewer_state.focused_target.is_some());
            assert!(viewer_state.current_prompt.is_some());
            },
        );

        app.update();

        {
            let runtime_state = app.world().resource::<ViewerRuntimeState>();
            let viewer_state = app.world().resource::<ViewerState>();
            assert_eq!(
                runtime_state.runtime.peek_pending_progression(),
                Some(&PendingProgressionStep::StartNextNonCombatPlayerTurn)
            );
            assert_eq!(viewer_state.focused_target, Some(pickup_target.clone()));
        }

        app.update();

        let runtime_state = app.world().resource::<ViewerRuntimeState>();
        let viewer_state = app.world().resource::<ViewerState>();
        assert!(runtime_state.runtime.pending_interaction().is_none());
        assert_eq!(runtime_state.runtime.get_actor_inventory_count(player, "1005"), 1);
        assert!(viewer_state.focused_target.is_none());
        assert!(viewer_state.current_prompt.is_none());
    }

    #[test]
    fn generated_door_after_approach_opens_and_refreshes_prompt() {
        let mut app = App::new();
        let (runtime, player, door_object_id) = viewer_generated_door_runtime();
        app.insert_resource(Time::<()>::default())
            .insert_resource(ViewerRuntimeState {
                runtime,
                recent_events: Vec::new(),
                ai_snapshot: SettlementDebugSnapshot::default(),
            })
            .insert_resource(ViewerActorFeedbackState::default())
            .insert_resource(ViewerCameraShakeState::default())
            .insert_resource(ViewerDamageNumberState::default())
            .insert_resource(ViewerActorMotionState::default())
            .insert_resource(ViewerState::default())
            .add_systems(
                Update,
                (
                    advance_runtime_progression,
                    collect_events,
                    refresh_interaction_prompt,
                )
                    .chain(),
            );

        app.world_mut().resource_scope(
            |world, mut runtime_state: Mut<ViewerRuntimeState>| {
                let mut viewer_state = world.resource_mut::<ViewerState>();
                let snapshot = runtime_state.runtime.snapshot();
                viewer_state.select_actor(player, ActorSide::Player);
                viewer_state.min_progression_interval_sec = 0.0;
                viewer_state.focused_target =
                    Some(InteractionTargetId::MapObject(door_object_id.clone()));
                viewer_state.current_prompt = runtime_state.runtime.query_interaction_prompt(
                    player,
                    InteractionTargetId::MapObject(door_object_id.clone()),
                );

                let result = runtime_state.runtime.issue_interaction(
                    player,
                    InteractionTargetId::MapObject(door_object_id.clone()),
                    InteractionOptionId("open_door".into()),
                );
                apply_interaction_result(&runtime_state, &mut viewer_state, result.clone());

                assert!(result.approach_required);
                assert!(snapshot
                    .generated_doors
                    .iter()
                    .any(|door| door.map_object_id == door_object_id));
            },
        );

        update_until(&mut app, 12, |app| {
            app.world()
                .resource::<ViewerRuntimeState>()
                .runtime
                .snapshot()
                .generated_doors
                .iter()
                .find(|door| door.map_object_id == door_object_id)
                .is_some_and(|door| door.is_open)
        });

        let runtime_state = app.world().resource::<ViewerRuntimeState>();
        let viewer_state = app.world().resource::<ViewerState>();
        assert!(runtime_state
            .runtime
            .snapshot()
            .generated_doors
            .iter()
            .find(|door| door.map_object_id == door_object_id)
            .is_some_and(|door| door.is_open));
        assert_eq!(
            viewer_state.focused_target,
            Some(InteractionTargetId::MapObject(door_object_id.clone()))
        );
        assert_eq!(
            viewer_state
                .current_prompt
                .as_ref()
                .and_then(|prompt| prompt.primary_option_id.clone())
                .map(|id| id.0),
            Some("close_door".to_string())
        );
    }


    #[test]
    fn stepping_onto_scene_trigger_enters_location_and_clears_interaction_ui() {
        let mut app = App::new();
        let (runtime, player) = viewer_trigger_runtime();
        let trigger_target = InteractionTargetId::MapObject("exit_trigger".into());
        app.insert_resource(Time::<()>::default())
            .insert_resource(ViewerRuntimeState {
                runtime,
                recent_events: Vec::new(),
                ai_snapshot: SettlementDebugSnapshot::default(),
            })
            .insert_resource(ViewerActorFeedbackState::default())
            .insert_resource(ViewerCameraShakeState::default())
            .insert_resource(ViewerDamageNumberState::default())
            .insert_resource(ViewerActorMotionState::default())
            .insert_resource(ViewerState::default())
            .add_systems(
                Update,
                (
                    advance_runtime_progression,
                    collect_events,
                    refresh_interaction_prompt,
                )
                    .chain(),
            );

        app.world_mut().resource_scope(
            |world, mut runtime_state: Mut<ViewerRuntimeState>| {
                let mut viewer_state = world.resource_mut::<ViewerState>();
                viewer_state.select_actor(player, ActorSide::Player);
                viewer_state.min_progression_interval_sec = 0.0;
                viewer_state.focused_target = Some(trigger_target.clone());

                let move_outcome = runtime_state
                    .runtime
                    .issue_actor_move(player, GridCoord::new(3, 0, 7))
                    .expect("trigger tile should be reachable");
                assert!(move_outcome.result.success);
                assert!(viewer_state.focused_target.is_some());
            },
        );

        update_until(&mut app, 12, |app| {
            let runtime_state = app.world().resource::<ViewerRuntimeState>();
            runtime_state.runtime.snapshot().interaction_context.world_mode == WorldMode::Outdoor
                && runtime_state
                    .runtime
                    .snapshot()
                    .interaction_context
                    .current_map_id
                    .as_deref()
                    == Some("survivor_outpost_01_grid")
        });

        let runtime_state = app.world().resource::<ViewerRuntimeState>();
        let viewer_state = app.world().resource::<ViewerState>();
        let context = &runtime_state.runtime.snapshot().interaction_context;
        assert_eq!(context.world_mode, WorldMode::Outdoor);
        assert_eq!(context.current_map_id.as_deref(), Some("survivor_outpost_01_grid"));
        assert_eq!(
            context.active_outdoor_location_id.as_deref(),
            Some("survivor_outpost_01")
        );
        assert!(viewer_state.focused_target.is_none());
        assert!(viewer_state.current_prompt.is_none());
        assert!(viewer_state.interaction_menu.is_none());
    }

    fn viewer_pickup_runtime(player: ActorId) -> SimulationRuntime {
        let mut simulation = Simulation::new();
        simulation.grid_world_mut().load_map(&viewer_pickup_map_definition());
        simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 1),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_actor_ap(player, 1.0);
        SimulationRuntime::from_simulation(simulation)
    }

    fn viewer_pickup_map_definition() -> MapDefinition {
        MapDefinition {
            id: MapId("viewer_pickup_map".into()),
            name: "Viewer Pickup".into(),
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
                grid: GridCoord::new(0, 0, 1),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: vec![MapObjectDefinition {
                object_id: "pickup".into(),
                kind: MapObjectKind::Pickup,
                anchor: GridCoord::new(2, 0, 1),
                footprint: MapObjectFootprint::default(),
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    pickup: Some(MapPickupProps {
                        item_id: "1005".into(),
                        min_count: 1,
                        max_count: 1,
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            }],
        }
    }

    fn viewer_generated_door_runtime() -> (SimulationRuntime, ActorId, String) {
        let mut simulation = Simulation::new();
        simulation
            .grid_world_mut()
            .load_map(&viewer_generated_building_map_definition());
        let door = simulation
            .grid_world()
            .generated_doors()
            .first()
            .cloned()
            .expect("generated building should produce at least one door");
        let player_grid = offset_start_grid_for_target(&simulation, door.anchor_grid);
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: player_grid,
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_actor_ap(player, 1.0);
        (
            SimulationRuntime::from_simulation(simulation),
            player,
            door.map_object_id,
        )
    }

    fn viewer_trigger_runtime() -> (SimulationRuntime, ActorId) {
        let mut simulation = Simulation::new();
        simulation.set_map_library(viewer_scene_transition_map_library());
        simulation.set_overworld_library(viewer_scene_transition_overworld_library());
        simulation.grid_world_mut().load_map(&viewer_trigger_map_definition());
        let player = simulation.register_actor(RegisterActor {
            definition_id: None,
            display_name: "Player".into(),
            kind: ActorKind::Player,
            side: ActorSide::Player,
            group_id: "player".into(),
            grid_position: GridCoord::new(0, 0, 7),
            interaction: None,
            attack_range: 1.2,
            ai_controller: None,
        });
        simulation.set_actor_ap(player, 1.0);
        (SimulationRuntime::from_simulation(simulation), player)
    }

    fn viewer_generated_building_map_definition() -> MapDefinition {
        MapDefinition {
            id: MapId("generated_building_map".into()),
            name: "Generated Building".into(),
            size: MapSize {
                width: 8,
                height: 8,
            },
            default_level: 0,
            levels: vec![
                MapLevelDefinition {
                    y: 0,
                    cells: Vec::new(),
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
            objects: vec![MapObjectDefinition {
                object_id: "layout_building".into(),
                kind: MapObjectKind::Building,
                anchor: GridCoord::new(1, 0, 1),
                footprint: MapObjectFootprint {
                    width: 5,
                    height: 5,
                },
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    building: Some(MapBuildingProps {
                        prefab_id: "generated_house".into(),
                        layout: Some(MapBuildingLayoutSpec {
                            seed: 7,
                            target_room_count: 3,
                            min_room_size: MapSize {
                                width: 2,
                                height: 2,
                            },
                            shape_cells: (0..5)
                                .flat_map(|z| (0..5).map(move |x| RelativeGridCell::new(x, z)))
                                .collect(),
                            stories: vec![
                                MapBuildingStorySpec {
                                    level: 0,
                                    shape_cells: Vec::new(),
                                },
                                MapBuildingStorySpec {
                                    level: 1,
                                    shape_cells: Vec::new(),
                                },
                            ],
                            stairs: vec![MapBuildingStairSpec {
                                from_level: 0,
                                to_level: 1,
                                from_cells: vec![RelativeGridCell::new(1, 1)],
                                to_cells: vec![RelativeGridCell::new(1, 1)],
                                width: 1,
                                kind: StairKind::Straight,
                            }],
                            ..MapBuildingLayoutSpec::default()
                        }),
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            }],
        }
    }

    fn viewer_trigger_map_definition() -> MapDefinition {
        MapDefinition {
            id: MapId("trigger_map".into()),
            name: "Trigger".into(),
            size: MapSize {
                width: 12,
                height: 12,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(1, 0, 7),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: vec![MapObjectDefinition {
                object_id: "exit_trigger".into(),
                kind: MapObjectKind::Trigger,
                anchor: GridCoord::new(3, 0, 7),
                footprint: MapObjectFootprint::default(),
                rotation: MapRotation::North,
                blocks_movement: false,
                blocks_sight: false,
                props: MapObjectProps {
                    trigger: Some(MapTriggerProps {
                        display_name: "进入幸存者据点".into(),
                        interaction_distance: 1.4,
                        interaction_kind: "enter_outdoor_location".into(),
                        target_id: Some("survivor_outpost_01".into()),
                        options: Vec::new(),
                        extra: BTreeMap::new(),
                    }),
                    ..MapObjectProps::default()
                },
            }],
        }
    }

    fn viewer_scene_transition_map_library() -> game_data::MapLibrary {
        game_data::MapLibrary::from(BTreeMap::from([(
            MapId("survivor_outpost_01_grid".into()),
            viewer_scene_transition_outdoor_map_definition(),
        )]))
    }

    fn viewer_scene_transition_outdoor_map_definition() -> MapDefinition {
        MapDefinition {
            id: MapId("survivor_outpost_01_grid".into()),
            name: "Outpost Outdoor".into(),
            size: MapSize {
                width: 12,
                height: 12,
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
        }
    }

    fn viewer_scene_transition_overworld_library() -> OverworldLibrary {
        OverworldLibrary::from(BTreeMap::from([(
            OverworldId("viewer_world".into()),
            OverworldDefinition {
                id: OverworldId("viewer_world".into()),
                locations: vec![OverworldLocationDefinition {
                    id: OverworldLocationId("survivor_outpost_01".into()),
                    name: "Outpost".into(),
                    description: String::new(),
                    kind: OverworldLocationKind::Outdoor,
                    map_id: MapId("survivor_outpost_01_grid".into()),
                    entry_point_id: "default_entry".into(),
                    parent_outdoor_location_id: None,
                    return_entry_point_id: None,
                    default_unlocked: true,
                    visible: true,
                    overworld_cell: GridCoord::new(0, 0, 0),
                    danger_level: 0,
                    icon: String::new(),
                    extra: BTreeMap::new(),
                }],
                walkable_cells: vec![OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                }],
                travel_rules: OverworldTravelRuleSet::default(),
            },
        )]))
    }

    fn update_until(app: &mut App, max_updates: usize, predicate: impl Fn(&App) -> bool) {
        for _ in 0..max_updates {
            if predicate(app) {
                return;
            }
            app.update();
        }
        assert!(predicate(app), "condition was not met within {max_updates} updates");
    }

    fn offset_start_grid_for_target(simulation: &Simulation, anchor: GridCoord) -> GridCoord {
        let approach = [
            GridCoord::new(anchor.x - 1, anchor.y, anchor.z),
            GridCoord::new(anchor.x + 1, anchor.y, anchor.z),
            GridCoord::new(anchor.x, anchor.y, anchor.z - 1),
            GridCoord::new(anchor.x, anchor.y, anchor.z + 1),
        ]
        .into_iter()
        .find(|grid| simulation.grid_world().is_walkable(*grid))
        .expect("target should have at least one walkable adjacent cell");
        let delta_x = approach.x - anchor.x;
        let delta_z = approach.z - anchor.z;
        let offset = GridCoord::new(approach.x + delta_x, approach.y, approach.z + delta_z);
        if simulation.grid_world().is_walkable(offset) {
            offset
        } else {
            [
                GridCoord::new(approach.x - 1, approach.y, approach.z),
                GridCoord::new(approach.x + 1, approach.y, approach.z),
                GridCoord::new(approach.x, approach.y, approach.z - 1),
                GridCoord::new(approach.x, approach.y, approach.z + 1),
            ]
            .into_iter()
            .find(|grid| simulation.grid_world().is_walkable(*grid) && *grid != anchor)
            .expect("target should have a walkable start cell one step beyond approach")
        }
    }
}
