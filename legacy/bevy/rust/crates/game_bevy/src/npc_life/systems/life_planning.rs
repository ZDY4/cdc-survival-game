//! NPC life 规划系统。
//! 负责时钟推进、需求衰减与 GOAP 规划，不负责在线执行或 viewer 运行时同步。

use std::collections::BTreeMap;

use bevy_ecs::prelude::*;
use game_core::{
    build_plan_for_goal_with_context, rebuild_facts, score_goals, select_goal, NpcGoalKey,
    NpcPlanRequest,
};
use game_data::{NpcRole, SettlementId, SmartObjectKind};

use crate::{SettlementDefinitions, SmartObjectReservations};

use super::super::components::{
    AiBehaviorProfileComponent, NeedState, NpcActiveOfflineAction, NpcLifeState,
    NpcPlannedActionQueue, NpcPlannedGoal, NpcRuntimeAiMode, NpcRuntimeBridgeState,
    PersonalityState, ReservationState, ResolvedLifeProfileComponent, ScheduleState,
    SmartObjectAccessProfileComponent,
};
use super::super::debug_types::NpcDecisionTrace;
use super::super::helpers::{
    active_schedule_block, build_ai_blackboard, build_decision_summary, build_planning_context,
    minute_in_window, object_anchor_id, select_object_for_kind_for_role,
};
use super::super::resources::{SimClock, WorldAlertState};

pub(super) fn update_schedule_state_system(
    clock: Res<SimClock>,
    settlements: Option<Res<SettlementDefinitions>>,
    mut query: Query<(
        &NpcLifeState,
        &ResolvedLifeProfileComponent,
        &mut ScheduleState,
    )>,
) {
    let Some(settlements) = settlements else {
        return;
    };

    for (life, profile, mut schedule) in &mut query {
        let settlement = match settlements.0.get(&SettlementId(life.settlement_id.clone())) {
            Some(settlement) => settlement,
            None => continue,
        };
        let active_block =
            active_schedule_block(&profile.0.schedule_blocks, clock.day, clock.minute_of_day);
        schedule.active_label = active_block
            .map(|block| block.label.clone())
            .unwrap_or_else(|| "off_shift".to_string());
        schedule.on_shift = active_block
            .map(|block| block.tags.iter().any(|tag| tag == "shift"))
            .unwrap_or(false);
        schedule.shift_starting_soon = profile.0.schedule_blocks.iter().any(|block| {
            block.includes_day(clock.day)
                && block.start_minute >= clock.minute_of_day
                && block.start_minute.saturating_sub(clock.minute_of_day) <= 30
        });
        schedule.meal_window_open = settlement.service_rules.meal_windows.iter().any(|window| {
            minute_in_window(clock.minute_of_day, window.start_minute, window.end_minute)
        });
        schedule.quiet_hours = settlement
            .service_rules
            .quiet_hours
            .as_ref()
            .map(|window| {
                minute_in_window(clock.minute_of_day, window.start_minute, window.end_minute)
            })
            .unwrap_or(false);
    }
}

pub(super) fn update_need_state_system(clock: Res<SimClock>, mut query: Query<&mut NeedState>) {
    let hours = f32::from(clock.offline_step_minutes) / 60.0;
    for mut need in &mut query {
        need.hunger = (need.hunger - need.hunger_decay_per_hour * hours).clamp(0.0, 100.0);
        need.energy = (need.energy - need.energy_decay_per_hour * hours).clamp(0.0, 100.0);
        need.morale = (need.morale - need.morale_decay_per_hour * hours).clamp(0.0, 100.0);
    }
}

pub(super) fn plan_npc_life_system(
    settlements: Option<Res<SettlementDefinitions>>,
    reservation_service: Res<SmartObjectReservations>,
    world_alert: Res<WorldAlertState>,
    mut queries: ParamSet<(
        Query<(
            Entity,
            &NpcLifeState,
            &ScheduleState,
            &NpcActiveOfflineAction,
        )>,
        Query<(
            Entity,
            &AiBehaviorProfileComponent,
            &PersonalityState,
            &SmartObjectAccessProfileComponent,
            &mut NpcLifeState,
            &NeedState,
            &ScheduleState,
            &ReservationState,
            &mut NpcPlannedGoal,
            &mut NpcPlannedActionQueue,
            &mut NpcActiveOfflineAction,
            &mut NpcRuntimeBridgeState,
            &mut NpcDecisionTrace,
        )>,
    )>,
) {
    let Some(settlements) = settlements else {
        return;
    };

    let mut guard_coverage: BTreeMap<String, u32> = BTreeMap::new();
    for (_entity, life, schedule, current_action) in &queries.p0() {
        if life.role != NpcRole::Guard || !schedule.on_shift {
            continue;
        }
        let is_covering = life.current_anchor == life.duty_anchor
            || current_action
                .0
                .as_ref()
                .map(|action| action.step.target_anchor == life.duty_anchor)
                .unwrap_or(false);
        if is_covering {
            *guard_coverage
                .entry(life.settlement_id.clone())
                .or_default() += 1;
        }
    }

    for (
        entity,
        behavior_profile,
        personality,
        access_profile,
        mut life,
        need,
        schedule,
        reservations,
        mut current_goal,
        mut current_plan,
        mut current_action,
        mut runtime_bridge,
        mut trace,
    ) in &mut queries.p1()
    {
        if runtime_bridge.ai_mode == NpcRuntimeAiMode::Combat {
            continue;
        }

        if runtime_bridge.combat_replan_required {
            current_action.0 = None;
            life.replan_required = true;
        }

        let alert_goal = behavior_profile
            .0
            .alert_goal_id
            .as_ref()
            .map(|goal| NpcGoalKey::from(goal.as_str().to_string()));
        let effective_alert_active = world_alert.active || runtime_bridge.combat_alert_active;
        if effective_alert_active && current_goal.0 != alert_goal {
            current_action.0 = None;
            life.replan_required = true;
        }
        let needs_replan = life.replan_required
            || (current_action.0.is_none()
                && (current_plan.steps.is_empty()
                    || current_plan.next_index >= current_plan.steps.len()));
        if !needs_replan {
            continue;
        }

        let settlement = match settlements.0.get(&SettlementId(life.settlement_id.clone())) {
            Some(settlement) => settlement,
            None => continue,
        };
        let selected_guard_post_id = if life.role == NpcRole::Guard {
            select_object_for_kind_for_role(
                settlement,
                SmartObjectKind::GuardPost,
                life.role,
                &access_profile.0,
                &reservation_service,
                entity,
            )
            .map(|object| object.id.clone())
        } else {
            None
        };
        let selected_meal_object_id = select_object_for_kind_for_role(
            settlement,
            SmartObjectKind::CanteenSeat,
            life.role,
            &access_profile.0,
            &reservation_service,
            entity,
        )
        .map(|object| object.id.clone());
        let selected_leisure_object_id = select_object_for_kind_for_role(
            settlement,
            SmartObjectKind::RecreationSpot,
            life.role,
            &access_profile.0,
            &reservation_service,
            entity,
        )
        .map(|object| object.id.clone());
        let selected_medical_station_id = if life.role == NpcRole::Doctor {
            select_object_for_kind_for_role(
                settlement,
                SmartObjectKind::MedicalStation,
                life.role,
                &access_profile.0,
                &reservation_service,
                entity,
            )
            .map(|object| object.id.clone())
        } else {
            None
        };
        life.guard_post_id = selected_guard_post_id.clone();
        life.meal_object_id = selected_meal_object_id.clone();
        life.leisure_object_id = selected_leisure_object_id.clone();
        if life.role == NpcRole::Guard {
            life.duty_anchor = selected_guard_post_id
                .as_deref()
                .and_then(|object_id| object_anchor_id(settlement, object_id))
                .or_else(|| life.duty_anchor.clone());
        } else if life.role == NpcRole::Doctor {
            life.duty_anchor = selected_medical_station_id
                .as_deref()
                .and_then(|object_id| object_anchor_id(settlement, object_id))
                .or_else(|| life.duty_anchor.clone());
        }
        life.canteen_anchor = selected_meal_object_id
            .as_deref()
            .and_then(|object_id| object_anchor_id(settlement, object_id))
            .or_else(|| life.canteen_anchor.clone());
        life.leisure_anchor = selected_leisure_object_id
            .as_deref()
            .and_then(|object_id| object_anchor_id(settlement, object_id))
            .or_else(|| life.leisure_anchor.clone());
        let active_guards = guard_coverage
            .get(&life.settlement_id)
            .copied()
            .unwrap_or_default();
        let blackboard = build_ai_blackboard(
            &life,
            need,
            personality,
            schedule,
            reservations,
            effective_alert_active,
            &runtime_bridge,
            active_guards,
            settlement.service_rules.min_guard_on_duty,
            selected_guard_post_id.is_some(),
            selected_meal_object_id.is_some(),
            selected_leisure_object_id.is_some(),
            selected_medical_station_id.is_some(),
        );
        let facts = rebuild_facts(&behavior_profile.0, &blackboard, life.role);
        let plan_request = NpcPlanRequest {
            role: life.role,
            behavior: behavior_profile.0.clone(),
            blackboard,
            facts,
            home_anchor: Some(life.home_anchor.clone()),
            duty_anchor: life.duty_anchor.clone(),
            canteen_anchor: life.canteen_anchor.clone(),
            leisure_anchor: life.leisure_anchor.clone(),
            alarm_anchor: life.alarm_anchor.clone(),
            guard_post_id: selected_guard_post_id,
            bed_id: life.bed_id.clone(),
            meal_object_id: selected_meal_object_id,
            leisure_object_id: selected_leisure_object_id,
            medical_station_id: selected_medical_station_id,
            patrol_route_id: life.duty_route_id.clone(),
        };
        let selected_goal = select_goal(&plan_request);
        let planning_context =
            build_planning_context(settlement, &plan_request, life.current_anchor.clone());
        let plan = build_plan_for_goal_with_context(&planning_context, selected_goal.clone());
        let mut goal_scores = score_goals(&plan_request);
        goal_scores.sort_by(|left, right| right.score.cmp(&left.score));
        let decision_summary = build_decision_summary(
            &selected_goal,
            &goal_scores,
            &plan_request.facts,
            plan.planned,
        );
        current_goal.0 = Some(selected_goal.clone());
        current_plan.steps = plan.steps;
        current_plan.next_index = 0;
        current_plan.total_cost = plan.total_cost;
        current_plan.debug_plan = plan.debug_plan;
        current_action.0 = None;
        trace.facts = plan_request.facts;
        trace.goal_scores = goal_scores;
        trace.selected_goal = Some(selected_goal);
        trace.decision_summary = decision_summary;
        life.replan_required = false;
        runtime_bridge.combat_replan_required = false;
        runtime_bridge.combat_alert_active = false;
    }
}

pub(super) fn advance_sim_clock_system(mut clock: ResMut<SimClock>) {
    let total = u32::from(clock.minute_of_day) + u32::from(clock.offline_step_minutes);
    clock.minute_of_day = (total % (24 * 60)) as u16;
    if total >= 24 * 60 {
        clock.total_days += total / (24 * 60);
        clock.day = clock.day.next();
    }
}
