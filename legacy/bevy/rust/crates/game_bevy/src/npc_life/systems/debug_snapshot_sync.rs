//! NPC life 调试快照同步系统。
//! 负责整理共享调试快照资源，不负责 viewer 面板展示逻辑。

use bevy_ecs::prelude::*;
use game_data::SettlementId;

use crate::SettlementDefinitions;

use super::super::components::{
    NeedState, NpcActiveOfflineAction, NpcLifeState, NpcPlannedActionQueue, NpcPlannedGoal,
    NpcRuntimeBridgeState, ReservationState, RuntimeActorLink, ScheduleState,
};
use super::super::debug_types::{NpcDecisionTrace, PlannedActionDebug, SettlementDebugEntry};
use super::super::helpers::quantize_need;
use super::super::resources::{SettlementDebugSnapshot, WorldAlertState};

pub(super) fn refresh_debug_snapshot_system(
    world_alert: Res<WorldAlertState>,
    settlements: Option<Res<SettlementDefinitions>>,
    mut snapshot: ResMut<SettlementDebugSnapshot>,
    query: Query<(
        Entity,
        &crate::CharacterDefinitionId,
        &NpcLifeState,
        &NeedState,
        &NpcPlannedGoal,
        &NpcPlannedActionQueue,
        &NpcActiveOfflineAction,
        &ScheduleState,
        &ReservationState,
        &NpcRuntimeBridgeState,
        Option<&RuntimeActorLink>,
        &NpcDecisionTrace,
    )>,
) {
    let settlements = settlements.as_deref();
    let mut entries = Vec::new();
    for (
        entity,
        definition_id,
        life,
        need,
        goal,
        plan,
        action,
        schedule,
        reservations,
        runtime_bridge,
        runtime_link,
        trace,
    ) in &query
    {
        let (
            action_key,
            action_phase,
            action_travel_remaining_minutes,
            action_perform_remaining_minutes,
        ) = if let Some(current_action) = action.0.as_ref() {
            (
                Some(current_action.step.action.clone()),
                Some(current_action.phase),
                Some(current_action.travel_remaining_minutes),
                Some(current_action.perform_remaining_minutes),
            )
        } else {
            (None, None, None, None)
        };
        let pending_plan = plan
            .steps
            .iter()
            .skip(plan.next_index)
            .take(4)
            .map(|step| PlannedActionDebug {
                action: step.action.clone(),
                target_anchor: step.target_anchor.clone(),
                reservation_target: step.reservation_target.clone(),
            })
            .collect();
        let runtime_goal_grid = runtime_bridge.runtime_goal_grid.or_else(|| {
            action
                .0
                .as_ref()
                .and_then(|current_action| current_action.step.target_anchor.as_deref())
                .and_then(|anchor_id| {
                    settlements.and_then(|settlements| {
                        settlements
                            .0
                            .get(&SettlementId(life.settlement_id.clone()))
                            .and_then(|settlement| {
                                settlement
                                    .anchors
                                    .iter()
                                    .find(|anchor| anchor.id == anchor_id)
                                    .map(|anchor| anchor.grid)
                            })
                    })
                })
        });
        entries.push(SettlementDebugEntry {
            entity,
            definition_id: definition_id.0.as_str().to_string(),
            runtime_actor_id: runtime_link.map(|link| link.actor_id),
            execution_mode: runtime_bridge.execution_mode,
            ai_mode: runtime_bridge.ai_mode,
            settlement_id: life.settlement_id.clone(),
            role: life.role,
            goal: goal.0.clone(),
            selected_goal: trace.selected_goal.clone(),
            action: action_key,
            action_phase,
            action_travel_remaining_minutes,
            action_perform_remaining_minutes,
            schedule_label: schedule.active_label.clone(),
            on_shift: schedule.on_shift,
            shift_starting_soon: schedule.shift_starting_soon,
            meal_window_open: schedule.meal_window_open,
            quiet_hours: schedule.quiet_hours,
            world_alert_active: world_alert.active,
            replan_required: life.replan_required,
            need_hunger: quantize_need(need.hunger),
            need_energy: quantize_need(need.energy),
            need_morale: quantize_need(need.morale),
            facts: trace.facts.clone(),
            goal_scores: trace.goal_scores.clone(),
            decision_summary: trace.decision_summary.clone(),
            plan_next_index: plan.next_index,
            plan_total_steps: plan.steps.len(),
            plan_total_cost: plan.total_cost,
            pending_plan,
            current_anchor: life.current_anchor.clone(),
            combat_alert_active: runtime_bridge.combat_alert_active,
            combat_replan_required: runtime_bridge.combat_replan_required,
            combat_threat_actor_id: runtime_bridge.combat_threat_actor_id,
            combat_target_actor_id: runtime_bridge.combat_target_actor_id,
            last_combat_target_actor_id: runtime_bridge.last_combat_target_actor_id,
            last_combat_intent: runtime_bridge.last_combat_intent.clone(),
            last_combat_outcome: runtime_bridge.last_combat_outcome.clone(),
            runtime_goal_grid,
            actor_hp_ratio: runtime_bridge.actor_hp_ratio,
            attack_ap_cost: runtime_bridge.attack_ap_cost,
            target_hp_ratio: runtime_bridge.target_hp_ratio,
            approach_distance_steps: runtime_bridge.approach_distance_steps,
            last_damage_taken: runtime_bridge.last_damage_taken,
            last_damage_dealt: runtime_bridge.last_damage_dealt,
            reservations: reservations.active.iter().cloned().collect(),
            last_failure_reason: runtime_bridge.last_failure_reason.clone(),
        });
    }
    snapshot.entries = entries;
}
