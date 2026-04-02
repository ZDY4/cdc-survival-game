use bevy::prelude::*;
use game_bevy::{
    CharacterDefinitionId, CurrentAction, CurrentPlan, GridPosition, NeedState, NpcLifeState,
    ReservationState, RuntimeActorLink, RuntimeExecutionState, SettlementDefinitions,
    SmartObjectReservations, WorldAlertState,
};
use game_core::{ActionExecutionPhase, NpcRuntimeActionState, SimulationEvent};
use game_data::SettlementId;

use crate::state::{ViewerRuntimeState, ViewerSceneKind};

use super::npc_presence::{resolve_anchor_grid, resolve_reachable_runtime_grid};

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
                        action: action.step.action.clone(),
                        phase: action.phase,
                    });
            }
        }

        let Some((action_key, phase, reservation_target, target_anchor, perform_remaining_minutes)) =
            current_action.0.as_ref().map(|action_state| {
                (
                    action_state.step.action.clone(),
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
                    if let Some(set_world_alert_active) =
                        current_action.0.as_ref().and_then(|action_state| {
                            action_state.step.world_state_effects.set_world_alert_active
                        })
                    {
                        world_alert.active = set_world_alert_active;
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
                let completed_step = current_action
                    .0
                    .as_ref()
                    .map(|action_state| action_state.step.clone());
                let mut hunger = need.hunger;
                let mut energy = need.energy;
                let mut morale = need.morale;
                if let Some(step) = &completed_step {
                    game_core::apply_npc_action_effects(
                        step,
                        &mut hunger,
                        &mut energy,
                        &mut morale,
                    );
                }
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
