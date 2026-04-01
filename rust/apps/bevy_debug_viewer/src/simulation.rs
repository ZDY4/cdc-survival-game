use std::collections::BTreeMap;

use bevy::prelude::*;
use game_bevy::{
    advance_map_ai_spawn_runtime, register_runtime_actor_from_definition, BackgroundLifeState,
    CharacterDefinitionId, CharacterDefinitions, CurrentAction, CurrentPlan, DisplayName,
    GridPosition, MapAiSpawnRuntimeState, MapDefinitions, NeedState, NpcLifeState,
    ReservationState, RuntimeActorLink, RuntimeExecutionState, ScheduleState,
    SettlementDefinitions, SmartObjectReservations, WorldAlertState,
};
use game_core::runtime::action_result_status;
use game_core::{
    ActionExecutionPhase, AutoMoveInterruptReason, NpcBackgroundState, NpcRuntimeActionState,
    PendingProgressionStep, ProgressionAdvanceResult, SimulationCommand, SimulationCommandResult,
    SimulationEvent,
};
use game_data::{ActorId, ActorSide, GridCoord, MapId, SettlementId};

use crate::dialogue::sync_dialogue_from_event;
use crate::state::{
    HudEventCategory, ViewerActorFeedbackState, ViewerActorMotionState, ViewerCameraShakeState,
    ViewerDamageNumberState, ViewerEventEntry, ViewerRuntimeState, ViewerSceneKind, ViewerState,
};

const ACTOR_MOTION_MIN_DURATION_SEC: f32 = 0.04;
const ACTOR_MOTION_MAX_DURATION_SEC: f32 = 0.16;

#[derive(Resource, Debug, Default)]
pub(crate) struct ViewerVisionTrackerState {
    tracked_actors: BTreeMap<ActorId, ViewerVisionTracker>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
struct ViewerVisionTracker {
    active_map_id: Option<MapId>,
    grid_position: Option<GridCoord>,
    topology_version: u64,
    runtime_obstacle_version: u64,
}

pub(crate) fn prime_viewer_state(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    sync_viewer_runtime_basics(&mut runtime_state, &mut viewer_state);
}

pub(crate) fn sync_viewer_runtime_basics(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) {
    viewer_state.selected_actor = None;
    viewer_state.controlled_player_actor = None;
    let snapshot = runtime_state.runtime.snapshot();
    if let Some(actor) = snapshot
        .actors
        .iter()
        .find(|actor| actor.side == ActorSide::Player)
        .or_else(|| snapshot.actors.first())
    {
        viewer_state.select_actor(actor.actor_id, actor.side);
    }
    viewer_state.current_level = snapshot.grid.default_level.unwrap_or(0);
    let initial_events = runtime_state.runtime.drain_events();
    runtime_state.recent_events = initial_events
        .into_iter()
        .map(|event| viewer_event_entry(event, snapshot.combat.current_turn_index))
        .collect();
}

pub(crate) fn reset_viewer_runtime_transients(viewer_state: &mut ViewerState) {
    viewer_state.focused_target = None;
    viewer_state.current_prompt = None;
    viewer_state.interaction_menu = None;
    viewer_state.active_dialogue = None;
    viewer_state.hovered_grid = None;
    viewer_state.targeting_state = None;
    viewer_state.pending_open_trade_target = None;
    viewer_state.auto_end_turn_after_stop = false;
    viewer_state.end_turn_hold_sec = 0.0;
    viewer_state.end_turn_repeat_elapsed_sec = 0.0;
    viewer_state.progression_elapsed_sec = 0.0;
    viewer_state.resume_camera_follow();
}

pub(crate) fn tick_runtime(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    scene_kind: Option<Res<ViewerSceneKind>>,
    viewer_state: Res<ViewerState>,
) {
    if scene_kind.is_some_and(|scene_kind| scene_kind.is_main_menu()) {
        return;
    }
    if viewer_state.auto_tick {
        runtime_state.runtime.tick();
        if !runtime_state.runtime.has_pending_progression()
            && viewer_state.active_dialogue.is_none()
            && runtime_state.runtime.pending_interaction().is_none()
        {
            let snapshot = runtime_state.runtime.snapshot();
            if let Some(player_actor) = snapshot
                .actors
                .iter()
                .find(|actor| actor.side == ActorSide::Player)
            {
                let _ = runtime_state
                    .runtime
                    .submit_command(SimulationCommand::EndTurn {
                        actor_id: player_actor.actor_id,
                    });
            }
        }
    }
}

pub(crate) fn refresh_viewer_vision(
    mut trackers: ResMut<ViewerVisionTrackerState>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
    scene_kind: Option<Res<ViewerSceneKind>>,
) {
    if scene_kind.is_some_and(|scene_kind| scene_kind.is_main_menu()) {
        let stale_actor_ids = trackers.tracked_actors.keys().copied().collect::<Vec<_>>();
        for actor_id in stale_actor_ids {
            trackers.tracked_actors.remove(&actor_id);
            runtime_state.runtime.clear_actor_vision(actor_id);
        }
        return;
    }

    let snapshot = runtime_state.runtime.snapshot();
    let tracked_actor_id = viewer_state.focus_actor_id(&snapshot);

    let stale_actor_ids = trackers
        .tracked_actors
        .keys()
        .copied()
        .filter(|actor_id| Some(*actor_id) != tracked_actor_id)
        .collect::<Vec<_>>();
    for actor_id in stale_actor_ids {
        trackers.tracked_actors.remove(&actor_id);
        runtime_state.runtime.clear_actor_vision(actor_id);
    }

    let Some(actor_id) = tracked_actor_id else {
        return;
    };
    let Some(actor) = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == actor_id)
    else {
        return;
    };

    runtime_state
        .runtime
        .set_actor_vision_radius(actor_id, game_core::vision::DEFAULT_VISION_RADIUS);

    let active_map_id = snapshot.grid.map_id.clone();
    let topology_version = snapshot.grid.topology_version;
    let runtime_obstacle_version = snapshot.grid.runtime_obstacle_version;
    let tracker = trackers.tracked_actors.entry(actor_id).or_default();
    let should_refresh = tracker.active_map_id != active_map_id
        || tracker.grid_position != Some(actor.grid_position)
        || tracker.topology_version != topology_version
        || tracker.runtime_obstacle_version != runtime_obstacle_version
        || runtime_state
            .runtime
            .actor_vision_snapshot(actor_id)
            .is_none();
    if !should_refresh {
        return;
    }

    if let Some(update) = runtime_state.runtime.refresh_actor_vision(actor_id) {
        runtime_state
            .runtime
            .push_event(SimulationEvent::ActorVisionUpdated {
                actor_id: update.actor_id,
                active_map_id: update.active_map_id,
                visible_cells: update.visible_cells,
                explored_cells: update.explored_cells,
            });
    }

    *tracker = ViewerVisionTracker {
        active_map_id,
        grid_position: Some(actor.grid_position),
        topology_version,
        runtime_obstacle_version,
    };
}

pub(crate) fn advance_map_ai_spawns(
    time: Res<Time>,
    definitions: Res<CharacterDefinitions>,
    maps: Res<MapDefinitions>,
    mut spawn_state: ResMut<MapAiSpawnRuntimeState>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    scene_kind: Option<Res<ViewerSceneKind>>,
) {
    if scene_kind.is_some_and(|scene_kind| scene_kind.is_main_menu()) {
        return;
    }
    advance_map_ai_spawn_runtime(
        &mut spawn_state,
        &mut runtime_state.runtime,
        &definitions.0,
        &maps.0,
        time.delta_secs(),
    );
}

pub(crate) fn sync_npc_runtime_presence(
    mut commands: Commands,
    definitions: Option<Res<CharacterDefinitions>>,
    settlements: Option<Res<SettlementDefinitions>>,
    mut reservations: ResMut<SmartObjectReservations>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    scene_kind: Option<Res<ViewerSceneKind>>,
    mut query: Query<(
        Entity,
        &CharacterDefinitionId,
        &DisplayName,
        &mut GridPosition,
        &mut NpcLifeState,
        &NeedState,
        &ScheduleState,
        &CurrentPlan,
        &CurrentAction,
        &ReservationState,
        &mut RuntimeExecutionState,
        &mut BackgroundLifeState,
        Option<&RuntimeActorLink>,
    )>,
) {
    if scene_kind.is_some_and(|scene_kind| scene_kind.is_main_menu()) {
        return;
    }
    let (Some(definitions), Some(settlements)) = (definitions, settlements) else {
        return;
    };

    let snapshot = runtime_state.runtime.snapshot();
    let active_map_id = snapshot.grid.map_id.clone();
    let mut runtime_actors_by_definition = snapshot
        .actors
        .iter()
        .filter_map(|actor| {
            actor
                .definition_id
                .as_ref()
                .map(|definition_id| (definition_id.as_str().to_string(), actor.actor_id))
        })
        .collect::<std::collections::HashMap<_, _>>();

    for (
        entity,
        definition_id,
        display_name,
        mut grid_position,
        mut life,
        need,
        schedule,
        current_plan,
        current_action,
        reservation_state,
        mut runtime_execution,
        mut background_state,
        runtime_link,
    ) in &mut query
    {
        let Some(settlement) = settlements.0.get(&SettlementId(life.settlement_id.clone())) else {
            continue;
        };
        let should_be_online = active_map_id
            .as_ref()
            .map(|map_id| settlement.map_id == *map_id)
            .unwrap_or(false);
        let runtime_actor_exists = runtime_link
            .map(|link| {
                snapshot
                    .actors
                    .iter()
                    .any(|actor| actor.actor_id == link.actor_id)
            })
            .unwrap_or(false);

        if should_be_online {
            life.online = true;
            runtime_execution.mode = game_core::NpcExecutionMode::Online;
            let actor_id = if let Some(link) = runtime_link.filter(|_| runtime_actor_exists) {
                link.actor_id
            } else if let Some(actor_id) = runtime_actors_by_definition
                .get(definition_id.0.as_str())
                .copied()
            {
                commands
                    .entity(entity)
                    .insert(RuntimeActorLink { actor_id });
                actor_id
            } else {
                let Some(definition) = definitions.0.get(&definition_id.0) else {
                    continue;
                };
                let desired_spawn_grid = background_state
                    .0
                    .as_ref()
                    .and_then(|background| {
                        background
                            .current_anchor
                            .as_deref()
                            .and_then(|anchor| resolve_anchor_grid(settlement, anchor))
                            .or(Some(background.grid_position))
                    })
                    .unwrap_or(grid_position.0);
                let spawn_grid =
                    resolve_reachable_runtime_grid(&snapshot, desired_spawn_grid, None)
                        .unwrap_or(desired_spawn_grid);
                let actor_id = register_runtime_actor_from_definition(
                    &mut runtime_state.runtime,
                    definition,
                    spawn_grid,
                );
                runtime_actors_by_definition.insert(definition_id.0.as_str().to_string(), actor_id);
                commands
                    .entity(entity)
                    .insert(RuntimeActorLink { actor_id });
                if let Some(background) = background_state.0.as_ref() {
                    runtime_state
                        .runtime
                        .import_actor_background_state(actor_id, background);
                }
                actor_id
            };

            if let Some(runtime_grid) = runtime_state.runtime.get_actor_grid_position(actor_id) {
                grid_position.0 = runtime_grid;
            }
            runtime_execution.last_failure_reason = None;
            background_state.0 = None;
        } else {
            life.online = false;
            runtime_execution.mode = game_core::NpcExecutionMode::Background;
            runtime_execution.runtime_goal_grid = None;

            if let Some(link) = runtime_link {
                let mut exported = runtime_state
                    .runtime
                    .export_actor_background_state(link.actor_id)
                    .unwrap_or_else(|| {
                        build_background_state(
                            definition_id.0.as_str(),
                            display_name.0.as_str(),
                            settlement.map_id.clone(),
                            grid_position.0,
                            &life,
                            &need,
                            &schedule,
                            &current_plan,
                            &current_action,
                            &reservation_state,
                            &runtime_execution,
                        )
                    });
                exported.definition_id = Some(definition_id.0.as_str().to_string());
                exported.display_name = display_name.0.clone();
                exported.map_id = Some(settlement.map_id.clone());
                exported.grid_position = grid_position.0;
                exported.current_anchor = life.current_anchor.clone();
                exported.current_plan = current_plan.steps.clone();
                exported.plan_next_index = current_plan.next_index;
                exported.current_action = current_action.0.as_ref().map(|action| {
                    NpcRuntimeActionState::from_offline_action(
                        action,
                        reservation_state.active.clone(),
                        runtime_execution.last_failure_reason.clone(),
                        runtime_execution.runtime_goal_grid,
                    )
                });
                exported.held_reservations = reservation_state.active.clone();
                exported.hunger = quantize_need(need.hunger);
                exported.energy = quantize_need(need.energy);
                exported.morale = quantize_need(need.morale);
                exported.on_shift = schedule.on_shift;
                exported.meal_window_open = schedule.meal_window_open;
                exported.quiet_hours = schedule.quiet_hours;
                background_state.0 = Some(exported);

                for reservation in &reservation_state.active {
                    reservations.release(reservation, entity);
                }
                runtime_state
                    .runtime
                    .clear_actor_autonomous_movement_goal(link.actor_id);
                runtime_state
                    .runtime
                    .clear_actor_runtime_action_state(link.actor_id);
                runtime_state.runtime.unregister_actor(link.actor_id);
                commands.entity(entity).remove::<RuntimeActorLink>();
            } else if background_state.0.is_none() {
                background_state.0 = Some(build_background_state(
                    definition_id.0.as_str(),
                    display_name.0.as_str(),
                    settlement.map_id.clone(),
                    grid_position.0,
                    &life,
                    &need,
                    &schedule,
                    &current_plan,
                    &current_action,
                    &reservation_state,
                    &runtime_execution,
                ));
            }
        }
    }
}

pub(crate) fn advance_online_npc_actions(
    settlements: Option<Res<SettlementDefinitions>>,
    clock: Res<game_bevy::SimClock>,
    mut world_alert: ResMut<WorldAlertState>,
    mut reservations: ResMut<SmartObjectReservations>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    scene_kind: Option<Res<ViewerSceneKind>>,
    mut query: Query<(
        Entity,
        &CharacterDefinitionId,
        &mut GridPosition,
        &mut NpcLifeState,
        &mut NeedState,
        &mut CurrentPlan,
        &mut CurrentAction,
        &mut ReservationState,
        &mut RuntimeExecutionState,
        &RuntimeActorLink,
    )>,
) {
    if scene_kind.is_some_and(|scene_kind| scene_kind.is_main_menu()) {
        return;
    }
    let Some(settlements) = settlements else {
        return;
    };
    let step_minutes = u32::from(clock.offline_step_minutes);
    let snapshot = runtime_state.runtime.snapshot();

    for (
        entity,
        _definition_id,
        mut grid_position,
        mut life,
        mut need,
        mut current_plan,
        mut current_action,
        mut reservation_state,
        mut runtime_execution,
        runtime_link,
    ) in &mut query
    {
        if !life.online {
            continue;
        }

        if current_action.0.is_none() && current_plan.next_index < current_plan.steps.len() {
            current_action.0 = Some(game_core::OfflineActionState::new(
                current_plan.steps[current_plan.next_index].clone(),
                life.current_anchor.clone(),
            ));
            if let Some(action) = current_action.0.as_ref() {
                runtime_state
                    .runtime
                    .push_event(SimulationEvent::NpcActionStarted {
                        actor_id: runtime_link.actor_id,
                        action: action.step.action,
                        phase: action.phase,
                    });
            }
        }

        let Some((action_key, phase, reservation_target, target_anchor, perform_remaining_minutes)) =
            current_action.0.as_ref().map(|action_state| {
                (
                    action_state.step.action,
                    action_state.phase,
                    action_state.step.reservation_target.clone(),
                    action_state.step.target_anchor.clone(),
                    action_state.perform_remaining_minutes,
                )
            })
        else {
            runtime_execution.runtime_goal_grid = None;
            runtime_state
                .runtime
                .clear_actor_autonomous_movement_goal(runtime_link.actor_id);
            runtime_state
                .runtime
                .clear_actor_runtime_action_state(runtime_link.actor_id);
            continue;
        };

        let Some(settlement) = settlements.0.get(&SettlementId(life.settlement_id.clone())) else {
            mark_online_replan_failure(
                &mut reservations,
                entity,
                &mut runtime_state,
                &mut life,
                &mut current_plan,
                &mut current_action,
                &mut runtime_execution,
                &mut reservation_state,
                runtime_link.actor_id,
                action_key,
                "missing_settlement",
            );
            continue;
        };

        let runtime_grid = runtime_state
            .runtime
            .get_actor_grid_position(runtime_link.actor_id)
            .unwrap_or(grid_position.0);
        grid_position.0 = runtime_grid;

        match phase {
            ActionExecutionPhase::AcquireReservation => {
                if let Some(target) = reservation_target.as_deref() {
                    if let Err(_conflict) = reservations.try_acquire(target, entity) {
                        mark_online_replan_failure(
                            &mut reservations,
                            entity,
                            &mut runtime_state,
                            &mut life,
                            &mut current_plan,
                            &mut current_action,
                            &mut runtime_execution,
                            &mut reservation_state,
                            runtime_link.actor_id,
                            action_key,
                            "reservation_conflict",
                        );
                        continue;
                    }
                    reservation_state.active.insert(target.to_string());
                }
                let next_phase = {
                    let action_state = current_action.0.as_mut().expect("online action exists");
                    action_state.advance_after_acquire();
                    action_state.phase
                };
                runtime_state
                    .runtime
                    .push_event(SimulationEvent::NpcActionPhaseChanged {
                        actor_id: runtime_link.actor_id,
                        action: action_key,
                        phase: next_phase,
                    });
            }
            ActionExecutionPhase::Travel => {
                let target_grid = target_anchor
                    .as_deref()
                    .and_then(|anchor| resolve_anchor_grid(settlement, anchor))
                    .and_then(|anchor_grid| {
                        resolve_reachable_runtime_grid(
                            &snapshot,
                            anchor_grid,
                            Some(runtime_link.actor_id),
                        )
                    });
                runtime_execution.runtime_goal_grid = target_grid;
                if let Some(target_grid) = target_grid {
                    runtime_state
                        .runtime
                        .set_actor_autonomous_movement_goal(runtime_link.actor_id, target_grid);
                    if runtime_grid == target_grid {
                        runtime_state
                            .runtime
                            .clear_actor_autonomous_movement_goal(runtime_link.actor_id);
                        runtime_execution.runtime_goal_grid = None;
                        if let Some(anchor) = target_anchor.clone() {
                            life.current_anchor = Some(anchor);
                        }
                        let next_phase = {
                            let action_state =
                                current_action.0.as_mut().expect("online action exists");
                            action_state.travel_remaining_minutes = 0;
                            action_state.phase = if action_state.perform_remaining_minutes == 0 {
                                ActionExecutionPhase::ReleaseReservation
                            } else {
                                ActionExecutionPhase::Perform
                            };
                            action_state.phase
                        };
                        runtime_state
                            .runtime
                            .push_event(SimulationEvent::NpcActionPhaseChanged {
                                actor_id: runtime_link.actor_id,
                                action: action_key,
                                phase: next_phase,
                            });
                    }
                } else {
                    mark_online_replan_failure(
                        &mut reservations,
                        entity,
                        &mut runtime_state,
                        &mut life,
                        &mut current_plan,
                        &mut current_action,
                        &mut runtime_execution,
                        &mut reservation_state,
                        runtime_link.actor_id,
                        action_key,
                        "missing_target_anchor",
                    );
                    continue;
                }
            }
            ActionExecutionPhase::Perform => {
                runtime_execution.runtime_goal_grid = None;
                if perform_remaining_minutes <= step_minutes {
                    if action_key == game_core::NpcActionKey::RaiseAlarm {
                        world_alert.active = true;
                    }
                    let next_phase = {
                        let action_state = current_action.0.as_mut().expect("online action exists");
                        action_state.perform_remaining_minutes = 0;
                        action_state.phase = ActionExecutionPhase::ReleaseReservation;
                        action_state.phase
                    };
                    runtime_state
                        .runtime
                        .push_event(SimulationEvent::NpcActionPhaseChanged {
                            actor_id: runtime_link.actor_id,
                            action: action_key,
                            phase: next_phase,
                        });
                } else {
                    let action_state = current_action.0.as_mut().expect("online action exists");
                    action_state.perform_remaining_minutes -= step_minutes;
                }
            }
            ActionExecutionPhase::ReleaseReservation => {
                for reservation in reservation_state.active.clone() {
                    reservations.release(&reservation, entity);
                    reservation_state.active.remove(&reservation);
                }
                let next_phase = {
                    let action_state = current_action.0.as_mut().expect("online action exists");
                    action_state.phase = ActionExecutionPhase::Complete;
                    action_state.phase
                };
                runtime_state
                    .runtime
                    .push_event(SimulationEvent::NpcActionPhaseChanged {
                        actor_id: runtime_link.actor_id,
                        action: action_key,
                        phase: next_phase,
                    });
            }
            ActionExecutionPhase::Complete => {
                let action = action_key;
                let mut hunger = need.hunger;
                let mut energy = need.energy;
                let mut morale = need.morale;
                game_core::apply_npc_action_effects(action, &mut hunger, &mut energy, &mut morale);
                need.hunger = hunger;
                need.energy = energy;
                need.morale = morale;
                current_plan.next_index += 1;
                current_action.0 = None;
                runtime_execution.last_failure_reason = None;
                runtime_state
                    .runtime
                    .push_event(SimulationEvent::NpcActionCompleted {
                        actor_id: runtime_link.actor_id,
                        action,
                    });
                if current_plan.next_index >= current_plan.steps.len() {
                    life.replan_required = true;
                }
            }
            ActionExecutionPhase::Failed => {
                mark_online_replan_failure(
                    &mut reservations,
                    entity,
                    &mut runtime_state,
                    &mut life,
                    &mut current_plan,
                    &mut current_action,
                    &mut runtime_execution,
                    &mut reservation_state,
                    runtime_link.actor_id,
                    action_key,
                    "action_failed",
                );
                continue;
            }
        }

        if let Some(action) = current_action.0.as_ref() {
            runtime_state.runtime.set_actor_runtime_action_state(
                runtime_link.actor_id,
                NpcRuntimeActionState::from_offline_action(
                    action,
                    reservation_state.active.clone(),
                    runtime_execution.last_failure_reason.clone(),
                    runtime_execution.runtime_goal_grid,
                ),
            );
        } else {
            runtime_state
                .runtime
                .clear_actor_runtime_action_state(runtime_link.actor_id);
        }
    }
}

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
        viewer_state.status_line = progression_result_status(&result);
    }
    maybe_auto_end_turn_after_stop(&mut runtime_state, &mut viewer_state);
}

pub(crate) fn collect_events(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut feedback_state: ResMut<ViewerActorFeedbackState>,
    mut camera_shake_state: ResMut<ViewerCameraShakeState>,
    mut damage_number_state: ResMut<ViewerDamageNumberState>,
    mut motion_state: ResMut<ViewerActorMotionState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    let turn_index = snapshot.combat.current_turn_index;
    for event in runtime_state.runtime.drain_events() {
        if let SimulationEvent::ActorMoved {
            actor_id, from, to, ..
        } = &event
        {
            queue_actor_motion(
                &mut motion_state,
                &runtime_state,
                *actor_id,
                *from,
                *to,
                viewer_state.min_progression_interval_sec,
            );
        }
        if let SimulationEvent::ActorDamaged {
            actor_id,
            target_actor,
            damage,
            ..
        } = &event
        {
            queue_attack_and_hit_feedback(
                &mut feedback_state,
                &mut camera_shake_state,
                &mut damage_number_state,
                &runtime_state,
                &snapshot,
                *actor_id,
                *target_actor,
                *damage,
            );
        }
        if scene_transition_invalidates_interaction_ui(&event) {
            clear_interaction_ui_for_scene_transition(&mut viewer_state);
        }
        sync_dialogue_from_event(&runtime_state, &mut viewer_state, &event);
        runtime_state
            .recent_events
            .push(viewer_event_entry(event, turn_index));
    }
    const MAX_EVENTS: usize = 48;
    if runtime_state.recent_events.len() > MAX_EVENTS {
        let overflow = runtime_state.recent_events.len() - MAX_EVENTS;
        runtime_state.recent_events.drain(0..overflow);
    }
}

fn scene_transition_invalidates_interaction_ui(event: &SimulationEvent) -> bool {
    matches!(
        event,
        SimulationEvent::SceneTransitionRequested { .. }
            | SimulationEvent::LocationEntered { .. }
            | SimulationEvent::ReturnedToOverworld { .. }
    )
}

fn clear_interaction_ui_for_scene_transition(viewer_state: &mut ViewerState) {
    viewer_state.focused_target = None;
    viewer_state.current_prompt = None;
    viewer_state.interaction_menu = None;
    viewer_state.active_dialogue = None;
    viewer_state.targeting_state = None;
    viewer_state.pending_open_trade_target = None;
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
            || horizontal_world_distance(track.to_world, authority_world) > grid_size + 0.001;
        if should_snap {
            track.snap_to(authority_world, authority_level);
            motion_state.tracks.remove(&actor_id);
            continue;
        }

        track.advance(time.delta_secs());
        if !track.active {
            if !approx_world_coord(track.current_world, authority_world) {
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

fn queue_actor_motion(
    motion_state: &mut ViewerActorMotionState,
    runtime_state: &ViewerRuntimeState,
    actor_id: game_data::ActorId,
    from: GridCoord,
    to: GridCoord,
    min_progression_interval_sec: f32,
) {
    let from_world = motion_state
        .tracks
        .get(&actor_id)
        .filter(|track| track.active)
        .map(|track| track.current_world)
        .unwrap_or_else(|| runtime_state.runtime.grid_to_world(from));
    let to_world = runtime_state.runtime.grid_to_world(to);
    motion_state.track_movement(
        actor_id,
        from_world,
        to_world,
        to.y,
        actor_motion_duration_sec(min_progression_interval_sec),
    );
}

fn actor_motion_duration_sec(min_progression_interval_sec: f32) -> f32 {
    min_progression_interval_sec.clamp(ACTOR_MOTION_MIN_DURATION_SEC, ACTOR_MOTION_MAX_DURATION_SEC)
}

fn queue_attack_and_hit_feedback(
    feedback_state: &mut ViewerActorFeedbackState,
    camera_shake_state: &mut ViewerCameraShakeState,
    damage_number_state: &mut ViewerDamageNumberState,
    runtime_state: &ViewerRuntimeState,
    snapshot: &game_core::SimulationSnapshot,
    attacker_id: game_data::ActorId,
    target_actor_id: game_data::ActorId,
    damage: f32,
) {
    let attacker_world = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == attacker_id)
        .map(|actor| runtime_state.runtime.grid_to_world(actor.grid_position));
    let target_world = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == target_actor_id)
        .map(|actor| runtime_state.runtime.grid_to_world(actor.grid_position));

    if let (Some(attacker_world), Some(target_world)) = (attacker_world, target_world) {
        feedback_state.queue_attack_lunge(attacker_id, attacker_world, target_world);
    }
    if let Some(target_world) = target_world {
        damage_number_state.queue_damage_number(target_world, damage.round() as i32, false);
    }
    if target_world.is_some() {
        feedback_state.queue_hit_reaction(target_actor_id);
        camera_shake_state.trigger_default_damage_shake();
    }
}

fn horizontal_world_distance(a: game_data::WorldCoord, b: game_data::WorldCoord) -> f32 {
    ((a.x - b.x).powi(2) + (a.z - b.z).powi(2)).sqrt()
}

fn approx_world_coord(a: game_data::WorldCoord, b: game_data::WorldCoord) -> bool {
    (a.x - b.x).abs() <= 0.001 && (a.y - b.y).abs() <= 0.001 && (a.z - b.z).abs() <= 0.001
}

fn progression_result_status(result: &ProgressionAdvanceResult) -> String {
    let step = result
        .applied_step
        .map(format_progression_step)
        .unwrap_or("idle");

    if result.interrupted {
        return format!(
            "progression: {} interrupted ({})",
            step,
            format_interrupt_reason(result.interrupt_reason)
        );
    }

    if result.reached_goal {
        if let Some(position) = result.final_position {
            return format!(
                "progression: {} reached goal at ({}, {}, {})",
                step, position.x, position.y, position.z
            );
        }
        return format!("progression: {} reached goal", step);
    }

    match result.final_position {
        Some(position) => format!(
            "progression: {} now at ({}, {}, {})",
            step, position.x, position.y, position.z
        ),
        None => format!("progression: {}", step),
    }
}

fn format_progression_step(step: PendingProgressionStep) -> &'static str {
    match step {
        PendingProgressionStep::EndCurrentCombatTurn => "end current combat turn",
        PendingProgressionStep::RunNonCombatWorldCycle => "run non-combat world cycle",
        PendingProgressionStep::StartNextNonCombatPlayerTurn => "start next non-combat player turn",
        PendingProgressionStep::ContinuePendingMovement => "continue pending movement",
    }
}

fn format_interrupt_reason(reason: Option<AutoMoveInterruptReason>) -> &'static str {
    match reason {
        Some(AutoMoveInterruptReason::ReachedGoal) => "reached_goal",
        Some(AutoMoveInterruptReason::EnteredCombat) => "entered_combat",
        Some(AutoMoveInterruptReason::InteractionTargetUnavailable) => {
            "interaction_target_unavailable"
        }
        Some(AutoMoveInterruptReason::ActorNotPlayerControlled) => "actor_not_player_controlled",
        Some(AutoMoveInterruptReason::InputNotAllowed) => "input_not_allowed",
        Some(AutoMoveInterruptReason::TargetOutOfBounds) => "target_out_of_bounds",
        Some(AutoMoveInterruptReason::TargetInvalidLevel) => "target_invalid_level",
        Some(AutoMoveInterruptReason::TargetBlocked) => "target_blocked",
        Some(AutoMoveInterruptReason::TargetOccupied) => "target_occupied",
        Some(AutoMoveInterruptReason::NoPath) => "no_path",
        Some(AutoMoveInterruptReason::NoProgress) => "no_progress",
        Some(AutoMoveInterruptReason::CancelledByNewCommand) => "cancelled_by_new_command",
        Some(AutoMoveInterruptReason::UnknownActor) => "unknown_actor",
        None => "unknown",
    }
}

fn resolve_anchor_grid(
    settlement: &game_data::SettlementDefinition,
    anchor_id: &str,
) -> Option<GridCoord> {
    settlement
        .anchors
        .iter()
        .find(|anchor| anchor.id == anchor_id)
        .map(|anchor| anchor.grid)
}

fn resolve_reachable_runtime_grid(
    snapshot: &game_core::SimulationSnapshot,
    desired_grid: GridCoord,
    actor_id: Option<game_data::ActorId>,
) -> Option<GridCoord> {
    if is_runtime_grid_walkable(snapshot, desired_grid, actor_id) {
        return Some(desired_grid);
    }

    let max_radius = snapshot
        .grid
        .map_width
        .zip(snapshot.grid.map_height)
        .map(|(width, height)| width.max(height) as i32)
        .unwrap_or(8)
        .max(1);

    for radius in 1..=max_radius {
        for candidate in collect_ring_cells(desired_grid, radius) {
            if is_runtime_grid_walkable(snapshot, candidate, actor_id) {
                return Some(candidate);
            }
        }
    }

    None
}

fn is_runtime_grid_walkable(
    snapshot: &game_core::SimulationSnapshot,
    grid: GridCoord,
    actor_id: Option<game_data::ActorId>,
) -> bool {
    if grid.x < 0 || grid.z < 0 {
        return false;
    }

    if let Some(width) = snapshot.grid.map_width {
        if grid.x as u32 >= width {
            return false;
        }
    }
    if let Some(height) = snapshot.grid.map_height {
        if grid.z as u32 >= height {
            return false;
        }
    }
    if !snapshot.grid.levels.is_empty() && !snapshot.grid.levels.contains(&grid.y) {
        return false;
    }
    if snapshot.grid.map_blocked_cells.contains(&grid) {
        return false;
    }
    if snapshot.grid.runtime_blocked_cells.contains(&grid) {
        return actor_id
            .and_then(|actor_id| {
                snapshot
                    .actors
                    .iter()
                    .find(|actor| actor.actor_id == actor_id)
                    .map(|actor| actor.grid_position == grid)
            })
            .unwrap_or(false);
    }

    true
}

fn collect_ring_cells(center: GridCoord, radius: i32) -> Vec<GridCoord> {
    let mut cells = Vec::new();
    for dx in -radius..=radius {
        for dz in -radius..=radius {
            if dx.abs().max(dz.abs()) != radius {
                continue;
            }
            cells.push(GridCoord::new(center.x + dx, center.y, center.z + dz));
        }
    }
    cells
}

fn quantize_need(value: f32) -> u8 {
    value.round().clamp(0.0, 100.0) as u8
}

fn build_background_state(
    definition_id: &str,
    display_name: &str,
    map_id: game_data::MapId,
    grid_position: GridCoord,
    life: &NpcLifeState,
    need: &NeedState,
    schedule: &ScheduleState,
    current_plan: &CurrentPlan,
    current_action: &CurrentAction,
    reservation_state: &ReservationState,
    runtime_execution: &RuntimeExecutionState,
) -> NpcBackgroundState {
    NpcBackgroundState {
        definition_id: Some(definition_id.to_string()),
        display_name: display_name.to_string(),
        map_id: Some(map_id),
        grid_position,
        current_anchor: life.current_anchor.clone(),
        current_plan: current_plan.steps.clone(),
        plan_next_index: current_plan.next_index,
        current_action: current_action.0.as_ref().map(|action| {
            NpcRuntimeActionState::from_offline_action(
                action,
                reservation_state.active.clone(),
                runtime_execution.last_failure_reason.clone(),
                runtime_execution.runtime_goal_grid,
            )
        }),
        held_reservations: reservation_state.active.clone(),
        hunger: quantize_need(need.hunger),
        energy: quantize_need(need.energy),
        morale: quantize_need(need.morale),
        on_shift: schedule.on_shift,
        meal_window_open: schedule.meal_window_open,
        quiet_hours: schedule.quiet_hours,
        world_alert_active: false,
    }
}

fn mark_online_replan_failure(
    reservations: &mut SmartObjectReservations,
    entity: Entity,
    runtime_state: &mut ViewerRuntimeState,
    life: &mut NpcLifeState,
    current_plan: &mut CurrentPlan,
    current_action: &mut CurrentAction,
    runtime_execution: &mut RuntimeExecutionState,
    reservation_state: &mut ReservationState,
    actor_id: game_data::ActorId,
    action: game_core::NpcActionKey,
    reason: &str,
) {
    life.replan_required = true;
    current_plan.steps.clear();
    current_plan.next_index = 0;
    current_action.0 = None;
    for reservation in reservation_state.active.clone() {
        reservations.release(&reservation, entity);
    }
    reservation_state.active.clear();
    runtime_execution.runtime_goal_grid = None;
    runtime_execution.last_failure_reason = Some(reason.to_string());
    runtime_state
        .runtime
        .clear_actor_autonomous_movement_goal(actor_id);
    runtime_state
        .runtime
        .clear_actor_runtime_action_state(actor_id);
    runtime_state
        .runtime
        .push_event(SimulationEvent::NpcActionFailed {
            actor_id,
            action,
            reason: reason.to_string(),
        });
}

#[cfg(test)]
mod tests {
    use super::{
        actor_motion_duration_sec, advance_online_npc_actions, advance_runtime_progression,
        collect_events, maybe_auto_end_turn_after_stop, queue_actor_motion,
        queue_attack_and_hit_feedback, refresh_interaction_prompt, sync_npc_runtime_presence,
        ACTOR_MOTION_MAX_DURATION_SEC, ACTOR_MOTION_MIN_DURATION_SEC,
    };
    use crate::state::{
        ViewerActorFeedbackState, ViewerActorMotionState, ViewerCameraShakeState,
        ViewerDamageNumberState, ViewerRuntimeState, ViewerState,
    };
    use bevy::ecs::message::Messages;
    use bevy::prelude::*;
    use game_bevy::{
        build_runtime_from_default_startup_seed, load_runtime_bootstrap,
        load_settlement_definitions, spawn_characters_from_definition, CharacterDefinitionPath,
        CharacterDefinitions, CharacterSpawnRejected, CurrentAction, CurrentPlan, NpcLifePlugin,
        NpcLifeState, RuntimeActorLink, RuntimeExecutionState, SettlementDebugSnapshot,
        SettlementDefinitionPath, SettlementSimulationPlugin, SpawnCharacterRequest,
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
        let runtime =
            build_runtime_from_default_startup_seed(&bootstrap).expect("runtime should build");

        let mut app = App::new();
        app.add_plugins((SettlementSimulationPlugin, NpcLifePlugin));
        app.add_message::<SpawnCharacterRequest>();
        app.add_message::<CharacterSpawnRejected>();
        app.insert_resource(bootstrap.character_definitions);
        app.insert_resource(settlements);
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
            actor_motion_duration_sec(0.0),
            ACTOR_MOTION_MIN_DURATION_SEC
        );
        assert_eq!(
            actor_motion_duration_sec(1.0),
            ACTOR_MOTION_MAX_DURATION_SEC
        );
        assert!((actor_motion_duration_sec(0.1) - 0.1).abs() <= 0.0001);
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

        queue_actor_motion(
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

        queue_attack_and_hit_feedback(
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
