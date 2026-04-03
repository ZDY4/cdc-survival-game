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
mod interaction;
mod motion;
mod npc_actions;
mod npc_presence;
mod progression;
mod runtime_basics;
mod runtime_bridge;

pub(crate) use event_feedback::collect_events;
pub(crate) use interaction::refresh_interaction_prompt;
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

const ACTOR_MOTION_MIN_DURATION_SEC: f32 = 0.04;
const ACTOR_MOTION_MAX_DURATION_SEC: f32 = 0.16;

#[cfg(test)]
mod tests {
    use super::progression::maybe_auto_end_turn_after_stop;
    use super::{
        advance_online_npc_actions, advance_runtime_progression, collect_events, event_feedback,
        refresh_interaction_prompt, sync_npc_runtime_presence, ACTOR_MOTION_MAX_DURATION_SEC,
        ACTOR_MOTION_MIN_DURATION_SEC,
    };
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
        create_demo_runtime, PendingProgressionStep, SimulationCommand, SimulationEvent,
    };
    use game_data::{ActorSide, GridCoord, InteractionTargetId, WorldCoord};

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
        assert!((event_feedback::actor_motion_duration_sec(0.1) - 0.1).abs() <= 0.0001);
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
}
