use bevy_ecs::prelude::*;
use game_core::{
    apply_npc_action_effects, tick_offline_action, ActionExecutionPhase, NpcBackgroundState,
    NpcRuntimeActionState, OfflineActionState,
};
use game_data::SettlementId;

use crate::{GridPosition, SettlementDefinitions, SmartObjectReservations};

use super::super::helpers::{quantize_need, resolve_anchor_grid};
use super::super::{
    BackgroundLifeState, NeedState, NpcActiveOfflineAction, NpcLifeState,
    NpcPlannedActionQueue, ReservationState, SimClock,
};

pub(super) fn execute_offline_actions_system(
    clock: Res<SimClock>,
    settlements: Option<Res<SettlementDefinitions>>,
    mut registry: ResMut<SmartObjectReservations>,
    mut query: Query<(
        Entity,
        &mut NpcLifeState,
        &mut NeedState,
        &mut NpcPlannedActionQueue,
        &mut NpcActiveOfflineAction,
        &mut ReservationState,
        &mut BackgroundLifeState,
        Option<&mut GridPosition>,
    )>,
) {
    for (
        entity,
        mut life,
        mut need,
        mut current_plan,
        mut current_action,
        mut reservations,
        mut background_state,
        grid_position,
    ) in &mut query
    {
        if life.online {
            background_state.0 = None;
            continue;
        }

        if current_action.0.is_none() && current_plan.next_index < current_plan.steps.len() {
            current_action.0 = Some(OfflineActionState::new(
                current_plan.steps[current_plan.next_index].clone(),
                life.current_anchor.clone(),
            ));
        }

        if current_action.0.is_none() {
            continue;
        }

        let mut reservation_conflict = false;
        let completed_step = current_action
            .0
            .as_ref()
            .map(|action_state| action_state.step.clone());
        let tick = {
            let action_state = current_action.0.as_mut().expect("action exists");
            if action_state.phase == ActionExecutionPhase::AcquireReservation {
                if let Some(target) = action_state.step.reservation_target.clone() {
                    if registry.try_acquire(&target, entity).is_err() {
                        action_state.fail();
                        reservation_conflict = true;
                    } else {
                        reservations.active.insert(target);
                    }
                }
                if !reservation_conflict {
                    action_state.advance_after_acquire();
                }
            }
            tick_offline_action(action_state, u32::from(clock.offline_step_minutes))
        };
        if reservation_conflict {
            life.replan_required = true;
            current_plan.steps.clear();
            current_plan.next_index = 0;
            current_action.0 = None;
            continue;
        }
        if let Some(anchor) = tick.current_anchor {
            life.current_anchor = Some(anchor);
        }
        if tick.failed {
            life.replan_required = true;
            current_action.0 = None;
            continue;
        }
        if tick.finished {
            if completed_step.is_some() && tick.completed_action.is_some() {
                let mut hunger = need.hunger;
                let mut energy = need.energy;
                let mut morale = need.morale;
                apply_npc_action_effects(
                    completed_step.as_ref().expect("completed step exists"),
                    &mut hunger,
                    &mut energy,
                    &mut morale,
                );
                need.hunger = hunger;
                need.energy = energy;
                need.morale = morale;
            }
            for released in tick.released_reservations {
                registry.release(&released, entity);
                reservations.active.remove(&released);
            }
            current_plan.next_index += 1;
            current_action.0 = None;
            if current_plan.next_index >= current_plan.steps.len() {
                life.replan_required = true;
            }
        }

        let resolved_grid = settlements
            .as_ref()
            .and_then(|settlements| settlements.0.get(&SettlementId(life.settlement_id.clone())))
            .and_then(|settlement| {
                life.current_anchor
                    .as_deref()
                    .and_then(|anchor_id| resolve_anchor_grid(settlement, anchor_id))
            })
            .or_else(|| grid_position.as_ref().map(|grid_position| grid_position.0))
            .unwrap_or_default();
        if let Some(mut grid_position) = grid_position {
            grid_position.0 = resolved_grid;
        }

        background_state.0 = Some(NpcBackgroundState {
            definition_id: None,
            display_name: String::new(),
            map_id: None,
            grid_position: resolved_grid,
            current_anchor: life.current_anchor.clone(),
            current_plan: current_plan.steps.clone(),
            plan_next_index: current_plan.next_index,
            current_action: current_action.0.as_ref().map(|action| {
                NpcRuntimeActionState::from_offline_action(
                    action,
                    reservations.active.clone(),
                    None,
                    None,
                )
            }),
            held_reservations: reservations.active.clone(),
            hunger: quantize_need(need.hunger),
            energy: quantize_need(need.energy),
            morale: quantize_need(need.morale),
            on_shift: false,
            meal_window_open: false,
            quiet_hours: false,
            world_alert_active: false,
        });
    }
}
