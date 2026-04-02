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
mod npc_actions;
mod npc_presence;
mod runtime_basics;

pub(crate) use event_feedback::collect_events;
pub(crate) use npc_actions::advance_online_npc_actions;
pub(crate) use npc_presence::sync_npc_runtime_presence;
pub(crate) use runtime_basics::{
    advance_map_ai_spawns, prime_viewer_state, refresh_viewer_vision,
    reset_viewer_runtime_transients, sync_viewer_runtime_basics, tick_runtime,
    ViewerVisionTrackerState,
};

const ACTOR_MOTION_MIN_DURATION_SEC: f32 = 0.04;
const ACTOR_MOTION_MAX_DURATION_SEC: f32 = 0.16;

pub(crate) fn cancel_pending_movement(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) -> bool {
    let Some(intent) = runtime_state.runtime.pending_movement().copied() else {
        return false;
    };
    if runtime_state.runtime.get_actor_side(intent.actor_id) != Some(ActorSide::Player) {
        return false;
    }

    let stop_after_current_step = runtime_state.runtime.peek_pending_progression()
        == Some(&PendingProgressionStep::ContinuePendingMovement);
    runtime_state
        .runtime
        .request_pending_movement_stop(intent.actor_id);
    viewer_state.progression_elapsed_sec = 0.0;
    viewer_state.end_turn_hold_sec = 0.0;
    viewer_state.end_turn_repeat_elapsed_sec = 0.0;
    viewer_state.status_line = if stop_after_current_step {
        format!(
            "move: stopping after current step for actor {:?}",
            intent.actor_id
        )
    } else {
        format!("move: cancelled actor {:?}", intent.actor_id)
    };
    true
}

pub(crate) fn submit_end_turn(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) {
    viewer_state.auto_end_turn_after_stop = false;
    let snapshot = runtime_state.runtime.snapshot();
    if let Some(actor_id) = viewer_state.command_actor_id(&snapshot) {
        viewer_state.progression_elapsed_sec = 0.0;
        let result = runtime_state
            .runtime
            .submit_command(SimulationCommand::EndTurn { actor_id });
        viewer_state.status_line = command_result_status("end turn", result);
    }
}

fn maybe_auto_end_turn_after_stop(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) {
    if !viewer_state.auto_end_turn_after_stop {
        return;
    }
    if runtime_state.runtime.has_pending_progression()
        || runtime_state.runtime.pending_movement().is_some()
    {
        return;
    }
    if viewer_state.active_dialogue.is_some()
        || runtime_state.runtime.pending_interaction().is_some()
    {
        return;
    }

    let snapshot = runtime_state.runtime.snapshot();
    if snapshot.combat.in_combat || viewer_state.command_actor_id(&snapshot).is_none() {
        viewer_state.auto_end_turn_after_stop = false;
        return;
    }

    submit_end_turn(runtime_state, viewer_state);
}

pub(crate) fn advance_runtime_progression(
    time: Res<Time>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if !runtime_state.runtime.has_pending_progression() {
        viewer_state.progression_elapsed_sec = 0.0;
        maybe_auto_end_turn_after_stop(&mut runtime_state, &mut viewer_state);
        return;
    }

    viewer_state.progression_elapsed_sec += time.delta_secs();
    if viewer_state.progression_elapsed_sec < viewer_state.min_progression_interval_sec {
        return;
    }
    viewer_state.progression_elapsed_sec = 0.0;

    let result = runtime_state.runtime.advance_pending_progression();
    if result.applied_step.is_some() {
        viewer_state.status_line = event_feedback::progression_result_status(&result);
    }
    maybe_auto_end_turn_after_stop(&mut runtime_state, &mut viewer_state);
}

pub(crate) fn advance_actor_motion(
    time: Res<Time>,
    runtime_state: Res<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    mut motion_state: ResMut<ViewerActorMotionState>,
) {
    if motion_state.tracks.is_empty() {
        return;
    }

    let snapshot = runtime_state.runtime.snapshot();
    let grid_size = snapshot.grid.grid_size;
    let tracked_actor_ids: Vec<_> = motion_state.tracks.keys().copied().collect();

    for actor_id in tracked_actor_ids {
        let Some(actor) = snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == actor_id)
        else {
            motion_state.tracks.remove(&actor_id);
            continue;
        };

        let authority_world = runtime_state.runtime.grid_to_world(actor.grid_position);
        let authority_level = actor.grid_position.y;
        let Some(track) = motion_state.tracks.get_mut(&actor_id) else {
            continue;
        };

        let should_snap = authority_level != track.level
            || authority_level != viewer_state.current_level
            || event_feedback::horizontal_world_distance(track.to_world, authority_world)
                > grid_size + 0.001;
        if should_snap {
            track.snap_to(authority_world, authority_level);
            motion_state.tracks.remove(&actor_id);
            continue;
        }

        track.advance(time.delta_secs());
        if !track.active {
            if !event_feedback::approx_world_coord(track.current_world, authority_world) {
                track.snap_to(authority_world, authority_level);
            }
            motion_state.tracks.remove(&actor_id);
        }
    }
}

pub(crate) fn advance_actor_feedback(
    time: Res<Time>,
    mut feedback_state: ResMut<ViewerActorFeedbackState>,
) {
    if feedback_state.tracks.is_empty() {
        return;
    }

    feedback_state.advance(time.delta_secs());
}

pub(crate) fn refresh_interaction_prompt(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if viewer_state.is_free_observe() {
        viewer_state.current_prompt = None;
        return;
    }

    let snapshot = runtime_state.runtime.snapshot();
    let Some(actor_id) = viewer_state.command_actor_id(&snapshot) else {
        viewer_state.current_prompt = None;
        return;
    };
    let Some(target_id) = viewer_state.focused_target.clone() else {
        viewer_state.current_prompt = None;
        return;
    };
    viewer_state.current_prompt = runtime_state
        .runtime
        .query_interaction_prompt(actor_id, target_id);
}

pub(crate) fn command_result_status(label: &str, result: SimulationCommandResult) -> String {
    match result {
        SimulationCommandResult::Action(action) => {
            format!("{label}: {}", action_result_status(&action))
        }
        SimulationCommandResult::SkillActivation(result) => {
            let status = if result.action_result.success {
                action_result_status(&result.action_result)
            } else {
                result
                    .failure_reason
                    .clone()
                    .or(result.action_result.reason.clone())
                    .unwrap_or_else(|| "unknown".to_string())
            };
            format!("{label}: {status}")
        }
        SimulationCommandResult::Path(result) => match result {
            Ok(path) => format!("{label}: path cells={}", path.len()),
            Err(error) => format!("{label}: path error={error:?}"),
        },
        SimulationCommandResult::InteractionPrompt(prompt) => {
            format!("{label}: options={}", prompt.options.len())
        }
        SimulationCommandResult::InteractionExecution(result) => {
            format!(
                "{label}: {}",
                if result.success {
                    "ok".to_string()
                } else {
                    format!(
                        "failed {}",
                        result.reason.unwrap_or_else(|| "unknown".to_string())
                    )
                }
            )
        }
        SimulationCommandResult::DialogueState(result) => match result {
            Ok(state) => format!(
                "{label}: dialogue node={} finished={}",
                state.session.current_node_id, state.finished
            ),
            Err(error) => format!("{label}: dialogue error={error}"),
        },
        SimulationCommandResult::OverworldRoute(result) => match result {
            Ok(route) => format!(
                "{label}: route {} -> {} mins={}",
                route.from_location_id, route.to_location_id, route.travel_minutes
            ),
            Err(error) => format!("{label}: route error={error}"),
        },
        SimulationCommandResult::OverworldState(result) => match result {
            Ok(state) => format!(
                "{label}: mode={:?} location={}",
                state.world_mode,
                state.active_location_id.as_deref().unwrap_or("unknown")
            ),
            Err(error) => format!("{label}: world error={error}"),
        },
        SimulationCommandResult::LocationTransition(result) => match result {
            Ok(context) => format!(
                "{label}: entered {} map={} entry={}",
                context.location_id, context.map_id, context.entry_point_id
            ),
            Err(error) => format!("{label}: transition error={error}"),
        },
        SimulationCommandResult::InteractionContext(result) => match result {
            Ok(context) => format!(
                "{label}: mode={:?} map={:?} outdoor={:?} subscene={:?}",
                context.world_mode,
                context.current_map_id,
                context.active_outdoor_location_id,
                context.current_subscene_location_id
            ),
            Err(error) => format!("{label}: interaction context error={error}"),
        },
        SimulationCommandResult::None => format!("{label}: ok"),
    }
}

#[cfg(test)]
mod tests {
    use super::{
        advance_online_npc_actions, advance_runtime_progression, collect_events, event_feedback,
        maybe_auto_end_turn_after_stop, refresh_interaction_prompt, sync_npc_runtime_presence,
        ACTOR_MOTION_MAX_DURATION_SEC, ACTOR_MOTION_MIN_DURATION_SEC,
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
}

pub(crate) fn viewer_event_entry(event: SimulationEvent, turn_index: u64) -> ViewerEventEntry {
    let category = classify_event(&event);
    let text = format_event_text(event);
    ViewerEventEntry {
        category,
        turn_index,
        text,
    }
}

pub(crate) fn classify_event(event: &SimulationEvent) -> HudEventCategory {
    match event {
        SimulationEvent::ActorTurnStarted { .. }
        | SimulationEvent::ActorTurnEnded { .. }
        | SimulationEvent::CombatStateChanged { .. }
        | SimulationEvent::ActionRejected { .. }
        | SimulationEvent::ActionResolved { .. }
        | SimulationEvent::SkillActivated { .. }
        | SimulationEvent::SkillActivationFailed { .. }
        | SimulationEvent::ActorDamaged { .. }
        | SimulationEvent::ActorDefeated { .. } => HudEventCategory::Combat,
        SimulationEvent::InteractionOptionsResolved { .. }
        | SimulationEvent::InteractionApproachPlanned { .. }
        | SimulationEvent::InteractionStarted { .. }
        | SimulationEvent::InteractionSucceeded { .. }
        | SimulationEvent::InteractionFailed { .. }
        | SimulationEvent::DialogueStarted { .. }
        | SimulationEvent::DialogueAdvanced { .. }
        | SimulationEvent::PickupGranted { .. }
        | SimulationEvent::RelationChanged { .. }
        | SimulationEvent::NpcActionStarted { .. }
        | SimulationEvent::NpcActionPhaseChanged { .. }
        | SimulationEvent::NpcActionCompleted { .. }
        | SimulationEvent::NpcActionFailed { .. } => HudEventCategory::Interaction,
        SimulationEvent::GroupRegistered { .. }
        | SimulationEvent::ActorRegistered { .. }
        | SimulationEvent::ActorUnregistered { .. }
        | SimulationEvent::ActorMoved { .. }
        | SimulationEvent::ActorVisionUpdated { .. }
        | SimulationEvent::WorldCycleCompleted
        | SimulationEvent::PathComputed { .. }
        | SimulationEvent::SceneTransitionRequested { .. }
        | SimulationEvent::LootDropped { .. }
        | SimulationEvent::ExperienceGranted { .. }
        | SimulationEvent::ActorLeveledUp { .. }
        | SimulationEvent::QuestStarted { .. }
        | SimulationEvent::QuestObjectiveProgressed { .. }
        | SimulationEvent::QuestCompleted { .. }
        | SimulationEvent::OverworldRouteComputed { .. }
        | SimulationEvent::OverworldTravelStarted { .. }
        | SimulationEvent::OverworldTravelProgressed { .. }
        | SimulationEvent::OverworldTravelCompleted { .. }
        | SimulationEvent::LocationEntered { .. }
        | SimulationEvent::ReturnedToOverworld { .. }
        | SimulationEvent::LocationUnlocked { .. } => HudEventCategory::World,
    }
}

fn format_event_text(event: SimulationEvent) -> String {
    match event {
        SimulationEvent::GroupRegistered { group_id, order } => {
            format!("group registered {group_id} -> {order}")
        }
        SimulationEvent::ActorRegistered {
            actor_id,
            group_id,
            side,
        } => format!(
            "actor {:?} registered group={} side={:?}",
            actor_id, group_id, side
        ),
        SimulationEvent::ActorUnregistered { actor_id } => {
            format!("actor {:?} unregistered", actor_id)
        }
        SimulationEvent::ActorTurnStarted {
            actor_id,
            group_id,
            ap,
        } => format!(
            "turn started {:?} group={} ap={:.1}",
            actor_id, group_id, ap
        ),
        SimulationEvent::ActorTurnEnded {
            actor_id,
            group_id,
            remaining_ap,
        } => format!(
            "turn ended {:?} group={} remaining_ap={:.1}",
            actor_id, group_id, remaining_ap
        ),
        SimulationEvent::CombatStateChanged { in_combat } => {
            format!("combat state -> {}", in_combat)
        }
        SimulationEvent::ActionRejected {
            actor_id,
            action_type,
            reason,
        } => format!(
            "action rejected actor={:?} type={:?} reason={}",
            actor_id, action_type, reason
        ),
        SimulationEvent::ActionResolved {
            actor_id,
            action_type,
            result,
        } => format!(
            "action resolved actor={:?} type={:?} ap={:.1}->{:.1} consumed={:.1}",
            actor_id, action_type, result.ap_before, result.ap_after, result.consumed
        ),
        SimulationEvent::SkillActivated {
            actor_id,
            skill_id,
            target,
            hit_actor_ids,
        } => format!(
            "skill activated actor={:?} skill={} target={:?} hits={}",
            actor_id,
            skill_id,
            target,
            hit_actor_ids.len()
        ),
        SimulationEvent::SkillActivationFailed {
            actor_id,
            skill_id,
            reason,
        } => format!(
            "skill failed actor={:?} skill={} reason={}",
            actor_id, skill_id, reason
        ),
        SimulationEvent::WorldCycleCompleted => "world cycle completed".to_string(),
        SimulationEvent::NpcActionStarted {
            actor_id,
            action,
            phase,
        } => format!(
            "npc action started actor={:?} action={:?} phase={:?}",
            actor_id, action, phase
        ),
        SimulationEvent::NpcActionPhaseChanged {
            actor_id,
            action,
            phase,
        } => format!(
            "npc action phase actor={:?} action={:?} phase={:?}",
            actor_id, action, phase
        ),
        SimulationEvent::NpcActionCompleted { actor_id, action } => format!(
            "npc action completed actor={:?} action={:?}",
            actor_id, action
        ),
        SimulationEvent::NpcActionFailed {
            actor_id,
            action,
            reason,
        } => format!(
            "npc action failed actor={:?} action={:?} reason={}",
            actor_id, action, reason
        ),
        SimulationEvent::ActorMoved {
            actor_id,
            from,
            to,
            step_index,
            total_steps,
        } => format!(
            "actor moved {:?} ({}, {}, {}) -> ({}, {}, {}) step={}/{}",
            actor_id, from.x, from.y, from.z, to.x, to.y, to.z, step_index, total_steps
        ),
        SimulationEvent::ActorVisionUpdated {
            actor_id,
            active_map_id,
            visible_cells,
            explored_cells,
        } => format!(
            "vision updated actor={:?} map={} visible={} explored={}",
            actor_id,
            active_map_id
                .as_ref()
                .map(|map_id| map_id.as_str())
                .unwrap_or("none"),
            visible_cells.len(),
            explored_cells.len()
        ),
        SimulationEvent::PathComputed {
            actor_id,
            path_length,
        } => format!("path computed actor={:?} len={}", actor_id, path_length),
        SimulationEvent::InteractionOptionsResolved {
            actor_id,
            target_id,
            option_count,
        } => format!(
            "interaction options actor={:?} target={:?} count={}",
            actor_id, target_id, option_count
        ),
        SimulationEvent::InteractionApproachPlanned {
            actor_id,
            target_id,
            option_id,
            goal,
            path_length,
        } => format!(
            "interaction approach actor={:?} target={:?} option={} goal=({}, {}, {}) len={}",
            actor_id, target_id, option_id, goal.x, goal.y, goal.z, path_length
        ),
        SimulationEvent::InteractionStarted {
            actor_id,
            target_id,
            option_id,
        } => format!(
            "interaction started actor={:?} target={:?} option={}",
            actor_id, target_id, option_id
        ),
        SimulationEvent::InteractionSucceeded {
            actor_id,
            target_id,
            option_id,
        } => format!(
            "interaction ok actor={:?} target={:?} option={}",
            actor_id, target_id, option_id
        ),
        SimulationEvent::InteractionFailed {
            actor_id,
            target_id,
            option_id,
            reason,
        } => format!(
            "interaction failed actor={:?} target={:?} option={} reason={}",
            actor_id, target_id, option_id, reason
        ),
        SimulationEvent::DialogueStarted {
            actor_id,
            target_id,
            dialogue_id,
        } => format!(
            "dialogue started actor={:?} target={:?} id={}",
            actor_id, target_id, dialogue_id
        ),
        SimulationEvent::DialogueAdvanced {
            actor_id,
            dialogue_id,
            node_id,
        } => format!(
            "dialogue advanced actor={:?} id={} node={}",
            actor_id, dialogue_id, node_id
        ),
        SimulationEvent::SceneTransitionRequested {
            actor_id,
            option_id,
            target_id,
            world_mode,
            ..
        } => format!(
            "scene transition actor={:?} option={} target={} mode={:?}",
            actor_id, option_id, target_id, world_mode
        ),
        SimulationEvent::OverworldRouteComputed {
            actor_id,
            target_location_id,
            travel_minutes,
            path_length,
        } => format!(
            "overworld route actor={:?} target={} mins={} path={}",
            actor_id, target_location_id, travel_minutes, path_length
        ),
        SimulationEvent::OverworldTravelStarted {
            actor_id,
            target_location_id,
            travel_minutes,
        } => format!(
            "overworld travel started actor={:?} target={} mins={}",
            actor_id, target_location_id, travel_minutes
        ),
        SimulationEvent::OverworldTravelProgressed {
            actor_id,
            target_location_id,
            progressed_minutes,
            remaining_minutes,
        } => format!(
            "overworld travel actor={:?} target={} progress={} remaining={}",
            actor_id, target_location_id, progressed_minutes, remaining_minutes
        ),
        SimulationEvent::OverworldTravelCompleted {
            actor_id,
            target_location_id,
        } => format!(
            "overworld travel completed actor={:?} target={}",
            actor_id, target_location_id
        ),
        SimulationEvent::LocationEntered {
            actor_id,
            location_id,
            map_id,
            entry_point_id,
            world_mode,
        } => format!(
            "location entered actor={:?} location={} map={} entry={} mode={:?}",
            actor_id, location_id, map_id, entry_point_id, world_mode
        ),
        SimulationEvent::ReturnedToOverworld {
            actor_id,
            active_outdoor_location_id,
        } => format!(
            "returned to overworld actor={:?} location={}",
            actor_id,
            active_outdoor_location_id.as_deref().unwrap_or("unknown")
        ),
        SimulationEvent::LocationUnlocked { location_id } => {
            format!("location unlocked {}", location_id)
        }
        SimulationEvent::PickupGranted {
            actor_id,
            target_id,
            item_id,
            count,
        } => format!(
            "pickup granted actor={:?} target={:?} item={} count={}",
            actor_id, target_id, item_id, count
        ),
        SimulationEvent::ActorDamaged {
            actor_id,
            target_actor,
            damage,
            remaining_hp,
        } => format!(
            "actor damaged attacker={:?} target={:?} damage={:.1} hp={:.1}",
            actor_id, target_actor, damage, remaining_hp
        ),
        SimulationEvent::ActorDefeated {
            actor_id,
            target_actor,
        } => format!(
            "actor defeated attacker={:?} target={:?}",
            actor_id, target_actor
        ),
        SimulationEvent::LootDropped {
            actor_id,
            target_actor,
            object_id,
            item_id,
            count,
            grid,
        } => format!(
            "loot dropped attacker={:?} target={:?} object={} item={} count={} grid=({}, {}, {})",
            actor_id, target_actor, object_id, item_id, count, grid.x, grid.y, grid.z
        ),
        SimulationEvent::ExperienceGranted {
            actor_id,
            amount,
            total_xp,
        } => format!(
            "xp granted actor={:?} amount={} total={}",
            actor_id, amount, total_xp
        ),
        SimulationEvent::ActorLeveledUp {
            actor_id,
            new_level,
            available_stat_points,
            available_skill_points,
        } => format!(
            "level up actor={:?} level={} stat_points={} skill_points={}",
            actor_id, new_level, available_stat_points, available_skill_points
        ),
        SimulationEvent::QuestStarted { actor_id, quest_id } => {
            format!("quest started actor={:?} quest={}", actor_id, quest_id)
        }
        SimulationEvent::QuestObjectiveProgressed {
            actor_id,
            quest_id,
            node_id,
            current,
            target,
        } => format!(
            "quest progress actor={:?} quest={} node={} {}/{}",
            actor_id, quest_id, node_id, current, target
        ),
        SimulationEvent::QuestCompleted { actor_id, quest_id } => {
            format!("quest completed actor={:?} quest={}", actor_id, quest_id)
        }
        SimulationEvent::RelationChanged {
            actor_id,
            target_id,
            disposition,
        } => format!(
            "relation changed actor={:?} target={:?} side={:?}",
            actor_id, target_id, disposition
        ),
    }
}
