use bevy::prelude::*;
use game_bevy::{
    register_runtime_actor_from_definition, BackgroundLifeState, CharacterDefinitionId,
    CharacterDefinitions, CurrentAction, CurrentPlan, DisplayName, GridPosition, NeedState,
    NpcLifeState, ReservationState, RuntimeActorLink, RuntimeExecutionState, ScheduleState,
    SettlementDefinitions, SmartObjectReservations, WorldAlertState,
};
use game_core::runtime::action_result_status;
use game_core::{
    ActionExecutionPhase, AutoMoveInterruptReason, NpcBackgroundState, NpcRuntimeActionState,
    PendingProgressionStep, ProgressionAdvanceResult, SimulationCommand, SimulationCommandResult,
    SimulationEvent,
};
use game_data::{ActorSide, GridCoord, SettlementId};

use crate::dialogue::sync_dialogue_from_event;
use crate::state::{HudEventCategory, ViewerEventEntry, ViewerRuntimeState, ViewerState};

pub(crate) fn prime_viewer_state(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    let snapshot = runtime_state.runtime.snapshot();
    viewer_state.selected_actor = snapshot
        .actors
        .iter()
        .find(|actor| actor.side == ActorSide::Player)
        .or_else(|| snapshot.actors.first())
        .map(|actor| actor.actor_id);
    viewer_state.current_level = snapshot.grid.default_level.unwrap_or(0);
    let initial_events = runtime_state.runtime.drain_events();
    runtime_state.recent_events.extend(
        initial_events
            .into_iter()
            .map(|event| viewer_event_entry(event, snapshot.combat.current_turn_index)),
    );
}

pub(crate) fn tick_runtime(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    viewer_state: Res<ViewerState>,
) {
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

pub(crate) fn sync_npc_runtime_presence(
    mut commands: Commands,
    definitions: Option<Res<CharacterDefinitions>>,
    settlements: Option<Res<SettlementDefinitions>>,
    mut reservations: ResMut<SmartObjectReservations>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
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
                let spawn_grid = background_state
                    .0
                    .as_ref()
                    .map(|background| background.grid_position)
                    .unwrap_or(grid_position.0);
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
    let Some(settlements) = settlements else {
        return;
    };
    let step_minutes = u32::from(clock.offline_step_minutes);

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
                    .and_then(|anchor| resolve_anchor_grid(settlement, anchor));
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

    runtime_state
        .runtime
        .clear_pending_movement(intent.actor_id);
    viewer_state.progression_elapsed_sec = 0.0;
    viewer_state.end_turn_hold_sec = 0.0;
    viewer_state.end_turn_repeat_elapsed_sec = 0.0;
    viewer_state.status_line = format!("move: cancelled actor {:?}", intent.actor_id);
    true
}

pub(crate) fn submit_end_turn(
    runtime_state: &mut ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) {
    if let Some(actor_id) = viewer_state.selected_actor {
        viewer_state.progression_elapsed_sec = 0.0;
        let result = runtime_state
            .runtime
            .submit_command(SimulationCommand::EndTurn { actor_id });
        viewer_state.status_line = command_result_status("end turn", result);
    }
}

pub(crate) fn advance_runtime_progression(
    time: Res<Time>,
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    if !runtime_state.runtime.has_pending_progression() {
        viewer_state.progression_elapsed_sec = 0.0;
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
}

pub(crate) fn collect_events(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    let turn_index = runtime_state.runtime.snapshot().combat.current_turn_index;
    for event in runtime_state.runtime.drain_events() {
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

pub(crate) fn refresh_interaction_prompt(
    mut runtime_state: ResMut<ViewerRuntimeState>,
    mut viewer_state: ResMut<ViewerState>,
) {
    let Some(actor_id) = viewer_state.selected_actor else {
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
