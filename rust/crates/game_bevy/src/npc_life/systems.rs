use std::collections::BTreeMap;

use bevy_app::{App, Update};
use bevy_ecs::prelude::*;
use game_core::{
    apply_npc_action_effects, build_plan_for_goal_with_context, rebuild_facts, score_goals,
    select_goal, tick_offline_action, ActionExecutionPhase, NpcBackgroundState, NpcGoalKey,
    NpcPlanRequest, NpcRuntimeActionState, OfflineActionState,
};
use game_data::{resolve_ai_behavior_profile, NpcRole, SettlementId, SmartObjectKind};

use crate::{
    reservations::ReservationConflict, AiDefinitions, CharacterDefinitionId, SettlementDefinitions,
    SmartObjectReservations,
};

use super::helpers::*;
use super::{
    AiBehaviorProfileComponent, BackgroundLifeState, CurrentAction, CurrentGoal, CurrentPlan,
    DecisionTrace, LifeProfileComponent, NeedState, NpcLifeState, NpcLifeUpdateSet,
    PlannedActionDebug, ReservationState, RuntimeActorLink, RuntimeExecutionState, ScheduleState,
    SettlementContext, SettlementDebugEntry, SettlementDebugSnapshot, SimClock, WorldAlertState,
};

pub(super) fn configure(app: &mut App) {
    app.configure_sets(Update, NpcLifeUpdateSet::RuntimeState);
    app.add_systems(
        Update,
        (
            initialize_npc_life_entities,
            sync_reservation_catalog_system,
            update_schedule_state_system,
            update_need_state_system,
            plan_npc_life_system,
            execute_offline_actions_system,
            refresh_debug_snapshot_system,
            advance_sim_clock_system,
        )
            .chain()
            .in_set(NpcLifeUpdateSet::RuntimeState),
    );
}

pub(super) fn initialize_resources(app: &mut App) {
    app.init_resource::<SimClock>()
        .init_resource::<WorldAlertState>()
        .init_resource::<SettlementContext>()
        .init_resource::<SmartObjectReservations>()
        .init_resource::<SettlementDebugSnapshot>();
}

pub(super) fn initialize_npc_life_entities(
    mut commands: Commands,
    settlements: Option<Res<SettlementDefinitions>>,
    ai_definitions: Option<Res<AiDefinitions>>,
    query: Query<(Entity, &LifeProfileComponent), Without<NpcLifeState>>,
) {
    let Some(settlements) = settlements else {
        return;
    };
    let Some(ai_definitions) = ai_definitions else {
        return;
    };

    for (entity, profile_component) in &query {
        let profile = &profile_component.0;
        let settlement = match settlements
            .0
            .get(&SettlementId(profile.settlement_id.clone()))
        {
            Some(settlement) => settlement,
            None => continue,
        };
        let duty_anchor =
            route_duty_anchor(settlement, &profile.home_anchor, &profile.duty_route_id)
                .or_else(|| default_duty_anchor_for_role(settlement, profile.role));
        let canteen_anchor = first_anchor_for_kind(settlement, SmartObjectKind::CanteenSeat);
        let leisure_anchor = first_anchor_for_kind(settlement, SmartObjectKind::RecreationSpot);
        let alarm_anchor = first_anchor_for_kind(settlement, SmartObjectKind::AlarmPoint);
        let guard_post_id = if profile.role == NpcRole::Guard {
            first_object_for_kind_for_role(settlement, SmartObjectKind::GuardPost, profile.role)
        } else {
            None
        };
        let Ok(ai_behavior_profile) = resolve_ai_behavior_profile(
            &ai_definitions.0,
            &profile.ai_behavior_profile_id.clone().into(),
        ) else {
            continue;
        };

        commands.entity(entity).insert((
            AiBehaviorProfileComponent(ai_behavior_profile),
            NpcLifeState {
                settlement_id: profile.settlement_id.clone(),
                role: profile.role,
                home_anchor: profile.home_anchor.clone(),
                duty_anchor,
                duty_route_id: non_empty(profile.duty_route_id.clone()),
                canteen_anchor,
                leisure_anchor,
                alarm_anchor,
                guard_post_id,
                bed_id: first_object_for_kind_for_role(
                    settlement,
                    SmartObjectKind::Bed,
                    profile.role,
                ),
                meal_object_id: first_object_for_kind_for_role(
                    settlement,
                    SmartObjectKind::CanteenSeat,
                    profile.role,
                ),
                leisure_object_id: first_object_for_kind_for_role(
                    settlement,
                    SmartObjectKind::RecreationSpot,
                    profile.role,
                ),
                current_anchor: Some(profile.home_anchor.clone()),
                replan_required: true,
                online: false,
            },
            NeedState::from_profile(&profile.need_profile),
            ScheduleState::default(),
            CurrentGoal::default(),
            CurrentPlan::default(),
            CurrentAction::default(),
            ReservationState::default(),
            RuntimeExecutionState::default(),
            BackgroundLifeState::default(),
            DecisionTrace::default(),
        ));
    }
}

pub(super) fn update_schedule_state_system(
    clock: Res<SimClock>,
    settlements: Option<Res<SettlementDefinitions>>,
    mut query: Query<(&NpcLifeState, &LifeProfileComponent, &mut ScheduleState)>,
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
            active_schedule_block(&profile.0.schedule, clock.day, clock.minute_of_day);
        schedule.active_label = active_block
            .map(|block| block.label.clone())
            .unwrap_or_else(|| "off_shift".to_string());
        schedule.on_shift = active_block
            .map(|block| block.tags.iter().any(|tag| tag == "shift"))
            .unwrap_or(false);
        schedule.shift_starting_soon = profile.0.schedule.iter().any(|block| {
            block.day == clock.day
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
        Query<(Entity, &NpcLifeState, &ScheduleState, &CurrentAction)>,
        Query<(
            Entity,
            &AiBehaviorProfileComponent,
            &mut NpcLifeState,
            &NeedState,
            &ScheduleState,
            &ReservationState,
            &mut CurrentGoal,
            &mut CurrentPlan,
            &mut CurrentAction,
            &mut DecisionTrace,
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
        mut life,
        need,
        schedule,
        reservations,
        mut current_goal,
        mut current_plan,
        mut current_action,
        mut trace,
    ) in &mut queries.p1()
    {
        let alert_goal = behavior_profile
            .0
            .alert_goal_id
            .as_ref()
            .map(|goal| NpcGoalKey::from(goal.as_str().to_string()));
        if world_alert.active && current_goal.0 != alert_goal {
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
            &reservation_service,
            entity,
        )
        .map(|object| object.id.clone());
        let selected_leisure_object_id = select_object_for_kind_for_role(
            settlement,
            SmartObjectKind::RecreationSpot,
            life.role,
            &reservation_service,
            entity,
        )
        .map(|object| object.id.clone());
        let selected_medical_station_id = if life.role == NpcRole::Doctor {
            select_object_for_kind_for_role(
                settlement,
                SmartObjectKind::MedicalStation,
                life.role,
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
            schedule,
            reservations,
            world_alert.active,
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
    }
}

pub(super) fn execute_offline_actions_system(
    clock: Res<SimClock>,
    settlements: Option<Res<SettlementDefinitions>>,
    mut registry: ResMut<SmartObjectReservations>,
    mut query: Query<(
        Entity,
        &mut NpcLifeState,
        &mut NeedState,
        &mut CurrentPlan,
        &mut CurrentAction,
        &mut ReservationState,
        &mut BackgroundLifeState,
        Option<&mut crate::GridPosition>,
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
                    if let Err(ReservationConflict { .. }) = registry.try_acquire(&target, entity) {
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

pub(super) fn refresh_debug_snapshot_system(
    world_alert: Res<WorldAlertState>,
    settlements: Option<Res<SettlementDefinitions>>,
    mut snapshot: ResMut<SettlementDebugSnapshot>,
    query: Query<(
        Entity,
        &CharacterDefinitionId,
        &NpcLifeState,
        &NeedState,
        &CurrentGoal,
        &CurrentPlan,
        &CurrentAction,
        &ScheduleState,
        &ReservationState,
        &RuntimeExecutionState,
        Option<&RuntimeActorLink>,
        &DecisionTrace,
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
        runtime_execution,
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
        let runtime_goal_grid = runtime_execution.runtime_goal_grid.or_else(|| {
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
            execution_mode: runtime_execution.mode,
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
            runtime_goal_grid,
            reservations: reservations.active.iter().cloned().collect(),
            last_failure_reason: runtime_execution.last_failure_reason.clone(),
        });
    }
    snapshot.entries = entries;
}

pub(super) fn advance_sim_clock_system(mut clock: ResMut<SimClock>) {
    let total = u32::from(clock.minute_of_day) + u32::from(clock.offline_step_minutes);
    clock.minute_of_day = (total % (24 * 60)) as u16;
    if total >= 24 * 60 {
        clock.total_days += total / (24 * 60);
        clock.day = clock.day.next();
    }
}

pub(super) fn sync_reservation_catalog_system(
    settlements: Option<Res<SettlementDefinitions>>,
    mut reservations: ResMut<SmartObjectReservations>,
) {
    let Some(settlements) = settlements else {
        return;
    };
    reservations.sync_settlement_catalog(&settlements.0);
}
