use std::collections::{BTreeMap, BTreeSet};

use bevy_app::prelude::*;
use bevy_ecs::prelude::*;
use game_core::{
    apply_npc_action_effects, build_plan_for_goal_with_context, rebuild_facts, score_goals,
    select_goal, tick_offline_action, ActionExecutionPhase, AiBlackboard, NpcActionKey,
    NpcBackgroundState, NpcExecutionMode, NpcFact, NpcGoalKey, NpcGoalScore, NpcPlanRequest,
    NpcPlanStep, NpcPlanningContext, NpcRuntimeActionState, OfflineActionState,
};
use game_data::{
    resolve_ai_behavior_profile, ActorId, AiBehaviorProfile, CharacterLifeProfile, GridCoord,
    NeedProfile, NpcRole, ScheduleBlock, ScheduleDay, SettlementDefinition, SettlementId,
    SmartObjectDefinition, SmartObjectKind,
};

use crate::{
    reservations::ReservationConflict, AiDefinitions, CharacterDefinitionId, SettlementDefinitions,
    SmartObjectReservations,
};

#[derive(SystemSet, Debug, Hash, PartialEq, Eq, Clone)]
pub enum NpcLifeUpdateSet {
    RuntimeState,
}

#[derive(Component, Debug, Clone, PartialEq)]
pub struct LifeProfileComponent(pub CharacterLifeProfile);

#[derive(Component, Debug, Clone, PartialEq, Default)]
pub struct AiBehaviorProfileComponent(pub AiBehaviorProfile);

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct NpcLifeState {
    pub settlement_id: String,
    pub role: NpcRole,
    pub home_anchor: String,
    pub duty_anchor: Option<String>,
    pub duty_route_id: Option<String>,
    pub canteen_anchor: Option<String>,
    pub leisure_anchor: Option<String>,
    pub alarm_anchor: Option<String>,
    pub guard_post_id: Option<String>,
    pub bed_id: Option<String>,
    pub meal_object_id: Option<String>,
    pub leisure_object_id: Option<String>,
    pub current_anchor: Option<String>,
    pub replan_required: bool,
    pub online: bool,
}

#[derive(Component, Debug, Clone, PartialEq)]
pub struct NeedState {
    pub hunger: f32,
    pub energy: f32,
    pub morale: f32,
    pub safety_bias: f32,
    pub hunger_decay_per_hour: f32,
    pub energy_decay_per_hour: f32,
    pub morale_decay_per_hour: f32,
}

impl NeedState {
    pub fn from_profile(profile: &NeedProfile) -> Self {
        Self {
            hunger: 60.0,
            energy: 85.0,
            morale: 50.0,
            safety_bias: profile.safety_bias,
            hunger_decay_per_hour: profile.hunger_decay_per_hour,
            energy_decay_per_hour: profile.energy_decay_per_hour,
            morale_decay_per_hour: profile.morale_decay_per_hour,
        }
    }
}

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct ScheduleState {
    pub active_label: String,
    pub on_shift: bool,
    pub shift_starting_soon: bool,
    pub meal_window_open: bool,
    pub quiet_hours: bool,
}

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct CurrentGoal(pub Option<NpcGoalKey>);

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct CurrentPlan {
    pub steps: Vec<NpcPlanStep>,
    pub next_index: usize,
    pub total_cost: usize,
    pub debug_plan: String,
}

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct CurrentAction(pub Option<OfflineActionState>);

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct ReservationState {
    pub active: BTreeSet<String>,
}

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct RuntimeActorLink {
    pub actor_id: ActorId,
}

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct RuntimeExecutionState {
    pub mode: NpcExecutionMode,
    pub runtime_goal_grid: Option<GridCoord>,
    pub last_failure_reason: Option<String>,
}

impl Default for RuntimeExecutionState {
    fn default() -> Self {
        Self {
            mode: NpcExecutionMode::Background,
            runtime_goal_grid: None,
            last_failure_reason: None,
        }
    }
}

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct BackgroundLifeState(pub Option<NpcBackgroundState>);

#[derive(Resource, Debug, Clone, PartialEq, Eq)]
pub struct SimClock {
    pub day: ScheduleDay,
    pub minute_of_day: u16,
    pub offline_step_minutes: u16,
    pub total_days: u32,
}

impl Default for SimClock {
    fn default() -> Self {
        Self {
            day: ScheduleDay::Monday,
            minute_of_day: 7 * 60,
            offline_step_minutes: 5,
            total_days: 1,
        }
    }
}

#[derive(Resource, Debug, Clone, PartialEq, Eq, Default)]
pub struct WorldAlertState {
    pub active: bool,
}

#[derive(Resource, Debug, Clone, PartialEq, Eq, Default)]
pub struct SettlementContext {
    pub player_present: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlannedActionDebug {
    pub action: NpcActionKey,
    pub target_anchor: Option<String>,
    pub reservation_target: Option<String>,
}

#[derive(Component, Debug, Clone, PartialEq, Default)]
pub struct DecisionTrace {
    pub facts: Vec<NpcFact>,
    pub goal_scores: Vec<NpcGoalScore>,
    pub selected_goal: Option<NpcGoalKey>,
    pub decision_summary: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct SettlementDebugEntry {
    pub entity: Entity,
    pub definition_id: String,
    pub runtime_actor_id: Option<ActorId>,
    pub execution_mode: NpcExecutionMode,
    pub settlement_id: String,
    pub role: NpcRole,
    pub goal: Option<NpcGoalKey>,
    pub selected_goal: Option<NpcGoalKey>,
    pub action: Option<NpcActionKey>,
    pub action_phase: Option<ActionExecutionPhase>,
    pub action_travel_remaining_minutes: Option<u32>,
    pub action_perform_remaining_minutes: Option<u32>,
    pub schedule_label: String,
    pub on_shift: bool,
    pub shift_starting_soon: bool,
    pub meal_window_open: bool,
    pub quiet_hours: bool,
    pub world_alert_active: bool,
    pub replan_required: bool,
    pub need_hunger: u8,
    pub need_energy: u8,
    pub need_morale: u8,
    pub facts: Vec<NpcFact>,
    pub goal_scores: Vec<NpcGoalScore>,
    pub decision_summary: String,
    pub plan_next_index: usize,
    pub plan_total_steps: usize,
    pub plan_total_cost: usize,
    pub pending_plan: Vec<PlannedActionDebug>,
    pub current_anchor: Option<String>,
    pub runtime_goal_grid: Option<GridCoord>,
    pub reservations: Vec<String>,
    pub last_failure_reason: Option<String>,
}

#[derive(Resource, Debug, Clone, PartialEq, Default)]
pub struct SettlementDebugSnapshot {
    pub entries: Vec<SettlementDebugEntry>,
}

pub struct NpcLifePlugin;

impl Plugin for NpcLifePlugin {
    fn build(&self, app: &mut App) {
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
}

pub struct SettlementSimulationPlugin;

impl Plugin for SettlementSimulationPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<SimClock>()
            .init_resource::<WorldAlertState>()
            .init_resource::<SettlementContext>()
            .init_resource::<SmartObjectReservations>()
            .init_resource::<SettlementDebugSnapshot>();
    }
}

fn initialize_npc_life_entities(
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

fn update_schedule_state_system(
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

fn update_need_state_system(clock: Res<SimClock>, mut query: Query<&mut NeedState>) {
    let hours = f32::from(clock.offline_step_minutes) / 60.0;
    for mut need in &mut query {
        need.hunger = (need.hunger - need.hunger_decay_per_hour * hours).clamp(0.0, 100.0);
        need.energy = (need.energy - need.energy_decay_per_hour * hours).clamp(0.0, 100.0);
        need.morale = (need.morale - need.morale_decay_per_hour * hours).clamp(0.0, 100.0);
    }
}

fn plan_npc_life_system(
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

fn execute_offline_actions_system(
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

fn refresh_debug_snapshot_system(
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

fn advance_sim_clock_system(mut clock: ResMut<SimClock>) {
    let total = u32::from(clock.minute_of_day) + u32::from(clock.offline_step_minutes);
    clock.minute_of_day = (total % (24 * 60)) as u16;
    if total >= 24 * 60 {
        clock.total_days += total / (24 * 60);
        clock.day = clock.day.next();
    }
}

fn route_duty_anchor(
    settlement: &SettlementDefinition,
    home_anchor: &str,
    route_id: &str,
) -> Option<String> {
    settlement
        .routes
        .iter()
        .find(|route| route.id == route_id)
        .and_then(|route| {
            route
                .anchors
                .iter()
                .find(|anchor| anchor.as_str() != home_anchor)
                .cloned()
                .or_else(|| route.anchors.first().cloned())
        })
}

fn default_duty_anchor_for_role(
    settlement: &SettlementDefinition,
    role: NpcRole,
) -> Option<String> {
    match role {
        NpcRole::Guard => first_anchor_for_kind(settlement, SmartObjectKind::GuardPost),
        NpcRole::Cook => first_anchor_for_kind(settlement, SmartObjectKind::CanteenSeat),
        NpcRole::Doctor => first_anchor_for_kind(settlement, SmartObjectKind::MedicalStation),
        NpcRole::Resident => None,
    }
}

fn resolve_anchor_grid(settlement: &SettlementDefinition, anchor_id: &str) -> Option<GridCoord> {
    settlement
        .anchors
        .iter()
        .find(|anchor| anchor.id == anchor_id)
        .map(|anchor| anchor.grid)
}

fn first_anchor_for_kind(
    settlement: &SettlementDefinition,
    kind: SmartObjectKind,
) -> Option<String> {
    settlement
        .smart_objects
        .iter()
        .find(|object| object.kind == kind)
        .map(|object| object.anchor_id.clone())
}

fn first_object_for_kind_for_role(
    settlement: &SettlementDefinition,
    kind: SmartObjectKind,
    role: NpcRole,
) -> Option<String> {
    let role_tag = role_tag(role);
    settlement
        .smart_objects
        .iter()
        .find(|object| object.kind == kind && object.tags.iter().any(|tag| tag == role_tag))
        .or_else(|| {
            settlement
                .smart_objects
                .iter()
                .find(|object| object.kind == kind)
        })
        .map(|object| object.id.clone())
}

fn select_object_for_kind_for_role<'a>(
    settlement: &'a SettlementDefinition,
    kind: SmartObjectKind,
    role: NpcRole,
    reservations: &SmartObjectReservations,
    owner: Entity,
) -> Option<&'a SmartObjectDefinition> {
    let role_tag = role_tag(role);
    select_available_object(
        settlement.smart_objects.iter().filter(move |object| {
            object.kind == kind && object.tags.iter().any(|tag| tag == role_tag)
        }),
        reservations,
        owner,
    )
    .or_else(|| {
        select_available_object(
            settlement
                .smart_objects
                .iter()
                .filter(move |object| object.kind == kind),
            reservations,
            owner,
        )
    })
}

fn select_available_object<'a>(
    candidates: impl Iterator<Item = &'a SmartObjectDefinition>,
    reservations: &SmartObjectReservations,
    owner: Entity,
) -> Option<&'a SmartObjectDefinition> {
    let mut first_available = None;
    for object in candidates {
        if reservations.holds(&object.id, owner) {
            return Some(object);
        }
        if first_available.is_none() && reservations.can_acquire(&object.id, owner) {
            first_available = Some(object);
        }
    }
    first_available
}

fn object_anchor_id(settlement: &SettlementDefinition, object_id: &str) -> Option<String> {
    settlement
        .smart_objects
        .iter()
        .find(|object| object.id == object_id)
        .map(|object| object.anchor_id.clone())
}

fn role_tag(role: NpcRole) -> &'static str {
    match role {
        NpcRole::Resident => "resident",
        NpcRole::Guard => "guard",
        NpcRole::Cook => "cook",
        NpcRole::Doctor => "doctor",
    }
}

fn active_schedule_block(
    schedule: &[ScheduleBlock],
    day: ScheduleDay,
    minute_of_day: u16,
) -> Option<&ScheduleBlock> {
    schedule.iter().find(|block| {
        block.day == day && minute_in_window(minute_of_day, block.start_minute, block.end_minute)
    })
}

fn minute_in_window(minute: u16, start_minute: u16, end_minute: u16) -> bool {
    minute >= start_minute && minute < end_minute
}

fn non_empty(value: String) -> Option<String> {
    if value.trim().is_empty() {
        None
    } else {
        Some(value)
    }
}

fn quantize_need(value: f32) -> u8 {
    value.round().clamp(0.0, 100.0) as u8
}

fn build_ai_blackboard(
    life: &NpcLifeState,
    need: &NeedState,
    schedule: &ScheduleState,
    reservations: &ReservationState,
    world_alert_active: bool,
    active_guards: u32,
    min_guard_on_duty: u32,
    guard_post_available: bool,
    meal_object_available: bool,
    leisure_object_available: bool,
    medical_station_available: bool,
) -> AiBlackboard {
    let mut blackboard = AiBlackboard::default();
    blackboard.set_number("need.hunger", need.hunger);
    blackboard.set_number("need.energy", need.energy);
    blackboard.set_number("need.morale", need.morale);
    blackboard.set_number("settlement.active_guards", active_guards as f32);
    blackboard.set_number("settlement.min_guard_on_duty", min_guard_on_duty as f32);
    blackboard.set_bool("schedule.on_shift", schedule.on_shift);
    blackboard.set_bool("schedule.shift_starting_soon", schedule.shift_starting_soon);
    blackboard.set_bool("schedule.meal_window_open", schedule.meal_window_open);
    blackboard.set_bool("schedule.quiet_hours", schedule.quiet_hours);
    blackboard.set_bool("world.alert_active", world_alert_active);
    blackboard.set_bool(
        "reservation.bed.active",
        life.bed_id
            .as_ref()
            .map(|id| reservations.active.contains(id))
            .unwrap_or(false),
    );
    blackboard.set_bool(
        "reservation.meal_object.active",
        life.meal_object_id
            .as_ref()
            .map(|id| reservations.active.contains(id))
            .unwrap_or(false),
    );
    blackboard.set_bool(
        "settlement.guard_coverage_insufficient",
        life.role == NpcRole::Guard && schedule.on_shift && active_guards < min_guard_on_duty,
    );
    blackboard.set_bool("availability.guard_post", guard_post_available);
    blackboard.set_bool("availability.meal_object", meal_object_available);
    blackboard.set_bool("availability.leisure_object", leisure_object_available);
    blackboard.set_bool("availability.medical_station", medical_station_available);
    blackboard.set_bool("availability.patrol_route", life.duty_route_id.is_some());
    blackboard.set_optional_text("anchor.current", life.current_anchor.clone());
    blackboard.set_text("anchor.home", life.home_anchor.clone());
    blackboard.set_optional_text("anchor.duty", life.duty_anchor.clone());
    blackboard.set_optional_text("anchor.canteen", life.canteen_anchor.clone());
    blackboard.set_optional_text("anchor.leisure", life.leisure_anchor.clone());
    blackboard.set_optional_text("anchor.alarm", life.alarm_anchor.clone());
    blackboard
}

fn build_decision_summary(
    selected_goal: &NpcGoalKey,
    goal_scores: &[NpcGoalScore],
    facts: &[NpcFact],
    planned: bool,
) -> String {
    let top_scores: Vec<String> = goal_scores
        .iter()
        .take(3)
        .map(|entry| {
            if entry.matched_rule_ids.is_empty() {
                format!("{:?}:{}", entry.goal, entry.score)
            } else {
                format!(
                    "{:?}:{} ({})",
                    entry.goal,
                    entry.score,
                    entry.matched_rule_ids.join("+")
                )
            }
        })
        .collect();
    let top_facts: Vec<String> = facts
        .iter()
        .take(5)
        .map(|fact| format!("{fact:?}"))
        .collect();
    let plan_state = if planned { "planned" } else { "no_plan" };
    format!(
        "goal={selected_goal:?} state={plan_state} top_scores=[{}] facts=[{}]",
        top_scores.join(","),
        top_facts.join(",")
    )
}

fn sync_reservation_catalog_system(
    settlements: Option<Res<SettlementDefinitions>>,
    mut reservations: ResMut<SmartObjectReservations>,
) {
    let Some(settlements) = settlements else {
        return;
    };
    reservations.sync_settlement_catalog(&settlements.0);
}

fn build_planning_context(
    settlement: &SettlementDefinition,
    request: &NpcPlanRequest,
    current_anchor: Option<String>,
) -> NpcPlanningContext {
    let mut context =
        NpcPlanningContext::from_plan_request(request).with_current_anchor(current_anchor.clone());
    let Some(current_anchor) = current_anchor else {
        return context;
    };

    let anchor_lookup: BTreeMap<&str, game_data::GridCoord> = settlement
        .anchors
        .iter()
        .map(|anchor| (anchor.id.as_str(), anchor.grid))
        .collect();

    for anchor in [
        request.home_anchor.as_deref(),
        request.duty_anchor.as_deref(),
        request.canteen_anchor.as_deref(),
        request.leisure_anchor.as_deref(),
        request.alarm_anchor.as_deref(),
    ]
    .into_iter()
    .flatten()
    {
        if let Some(minutes) =
            travel_minutes_between_anchors(&anchor_lookup, &current_anchor, anchor)
        {
            context.register_reachable_anchor(anchor.to_string(), minutes);
        }
    }

    context
}

fn travel_minutes_between_anchors(
    anchors: &BTreeMap<&str, game_data::GridCoord>,
    from_anchor: &str,
    to_anchor: &str,
) -> Option<u32> {
    let from = anchors.get(from_anchor)?;
    let to = anchors.get(to_anchor)?;
    let distance =
        (from.x - to.x).abs() as u32 + (from.y - to.y).abs() as u32 + (from.z - to.z).abs() as u32;
    Some(distance.saturating_mul(5))
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::SimClock;
    use bevy_app::App;
    use game_data::{
        CharacterAiProfile, CharacterArchetype, CharacterAttributeTemplate, CharacterCombatProfile,
        CharacterDefinition, CharacterDisposition, CharacterFaction, CharacterId,
        CharacterIdentity, CharacterLibrary, CharacterLifeProfile, CharacterPlaceholderColors,
        CharacterPresentation, CharacterProgression, CharacterResourcePool, MapId, NeedProfile,
        NpcRole, ScheduleBlock, ScheduleDay, ServiceRules, SettlementAnchorDefinition,
        SettlementDefinition, SettlementId, SettlementLibrary, SettlementRouteDefinition,
        SmartObjectDefinition, SmartObjectKind, TimeWindow,
    };

    use super::{
        CurrentAction, CurrentGoal, LifeProfileComponent, NpcLifePlugin, NpcLifeState,
        ReservationState, ScheduleState, SettlementDebugSnapshot, SettlementSimulationPlugin,
    };
    use crate::{CharacterDefinitionId, CharacterDefinitions, SettlementDefinitions};

    #[test]
    fn guard_plans_patrol_meal_relax_and_sleep_across_day() {
        use std::collections::BTreeSet;

        let mut app = App::new();
        app.insert_resource(CharacterDefinitions(sample_characters()));
        app.insert_resource(SettlementDefinitions(sample_settlements()));
        app.add_plugins((SettlementSimulationPlugin, NpcLifePlugin));

        let entity = app
            .world_mut()
            .spawn((
                CharacterDefinitionId(CharacterId("survivor_outpost_01_guard_test".into())),
                LifeProfileComponent(sample_guard_life()),
            ))
            .id();

        let mut seen_actions = BTreeSet::new();
        for _ in 0..220 {
            app.update();
            if let Some(action) = app
                .world()
                .entity(entity)
                .get::<CurrentAction>()
                .and_then(|current| current.0.as_ref().map(|state| state.step.action.clone()))
            {
                seen_actions.insert(action);
            }
        }

        let goal = app
            .world()
            .entity(entity)
            .get::<CurrentGoal>()
            .expect("goal component");
        let life = app
            .world()
            .entity(entity)
            .get::<NpcLifeState>()
            .expect("life component");
        let schedule = app
            .world()
            .entity(entity)
            .get::<ScheduleState>()
            .expect("schedule component");

        assert!(goal.0.is_some());
        assert!(seen_actions.contains(&game_core::NpcActionKey::PatrolRoute));
        assert!(seen_actions.contains(&game_core::NpcActionKey::EatMeal));
        assert!(
            seen_actions.contains(&game_core::NpcActionKey::TravelHome)
                || seen_actions.contains(&game_core::NpcActionKey::Sleep)
        );
        assert!(life.current_anchor.is_some());
        assert!(!schedule.active_label.is_empty());
    }

    #[test]
    fn reservation_conflicts_force_replan() {
        let mut app = App::new();
        app.insert_resource(CharacterDefinitions(sample_characters()));
        app.insert_resource(SettlementDefinitions(sample_settlements()));
        app.add_plugins((SettlementSimulationPlugin, NpcLifePlugin));

        let life = sample_guard_life();
        let one = app
            .world_mut()
            .spawn((
                CharacterDefinitionId(CharacterId("guard_one".into())),
                LifeProfileComponent(life.clone()),
            ))
            .id();
        let two = app
            .world_mut()
            .spawn((
                CharacterDefinitionId(CharacterId("guard_two".into())),
                LifeProfileComponent(CharacterLifeProfile {
                    home_anchor: "guard_home_02".into(),
                    ..life
                }),
            ))
            .id();

        for _ in 0..120 {
            app.update();
        }

        let one_res = app
            .world()
            .entity(one)
            .get::<ReservationState>()
            .expect("reservations");
        let two_res = app
            .world()
            .entity(two)
            .get::<ReservationState>()
            .expect("reservations");

        let overlap: Vec<String> = one_res
            .active
            .intersection(&two_res.active)
            .cloned()
            .collect();
        assert!(
            overlap.is_empty(),
            "guards should not hold the same reservation"
        );
    }

    #[test]
    fn alert_forces_response_goal() {
        let mut app = App::new();
        app.insert_resource(CharacterDefinitions(sample_characters()));
        app.insert_resource(SettlementDefinitions(sample_settlements()));
        app.add_plugins((SettlementSimulationPlugin, NpcLifePlugin));

        let entity = app
            .world_mut()
            .spawn((
                CharacterDefinitionId(CharacterId("survivor_outpost_01_guard_test".into())),
                LifeProfileComponent(sample_guard_life()),
            ))
            .id();
        app.world_mut()
            .resource_mut::<super::WorldAlertState>()
            .active = true;

        for _ in 0..5 {
            app.update();
        }

        let goal = app
            .world()
            .entity(entity)
            .get::<CurrentGoal>()
            .expect("goal component");
        assert_eq!(goal.0, Some(game_core::NpcGoalKey::RespondThreat));
    }

    #[test]
    fn cook_uses_role_tagged_objects_and_exposes_decision_trace() {
        let mut app = App::new();
        app.insert_resource(CharacterDefinitions(sample_characters()));
        app.insert_resource(SettlementDefinitions(sample_settlements()));
        app.add_plugins((SettlementSimulationPlugin, NpcLifePlugin));

        let cook = app
            .world_mut()
            .spawn((
                CharacterDefinitionId(CharacterId("survivor_outpost_01_cook_test".into())),
                LifeProfileComponent(sample_cook_life()),
            ))
            .id();

        for _ in 0..40 {
            app.update();
        }

        let life = app
            .world()
            .entity(cook)
            .get::<NpcLifeState>()
            .expect("life component");
        assert_eq!(life.role, NpcRole::Cook);
        assert_eq!(life.guard_post_id, None);
        assert_eq!(life.bed_id.as_deref(), Some("cook_bed_01"));
        assert_eq!(life.meal_object_id.as_deref(), Some("canteen_seat_cook_01"));

        let snapshot = app.world().resource::<SettlementDebugSnapshot>();
        let entry = snapshot
            .entries
            .iter()
            .find(|entry| entry.entity == cook)
            .expect("cook entry in debug snapshot");
        assert!(!entry.goal_scores.is_empty());
        assert!(!entry.decision_summary.is_empty());
        assert_eq!(entry.role, NpcRole::Cook);
        assert_eq!(entry.definition_id, "survivor_outpost_01_cook_test");
    }

    #[test]
    fn doctor_uses_medical_station_and_records_treatment_plan() {
        let mut app = App::new();
        app.insert_resource(CharacterDefinitions(sample_characters()));
        app.insert_resource(SettlementDefinitions(sample_settlements()));
        app.add_plugins((SettlementSimulationPlugin, NpcLifePlugin));

        let doctor = app
            .world_mut()
            .spawn((
                CharacterDefinitionId(CharacterId("survivor_outpost_01_doctor_test".into())),
                LifeProfileComponent(sample_doctor_life()),
            ))
            .id();

        for _ in 0..30 {
            app.update();
        }

        let life = app
            .world()
            .entity(doctor)
            .get::<NpcLifeState>()
            .expect("life component");
        assert_eq!(life.role, NpcRole::Doctor);
        assert_eq!(life.duty_anchor.as_deref(), Some("clinic_room"));
        assert_eq!(life.bed_id.as_deref(), Some("doctor_bed_01"));

        let plan = app
            .world()
            .entity(doctor)
            .get::<super::CurrentPlan>()
            .expect("plan component");
        assert!(plan
            .steps
            .iter()
            .any(|step| step.action == game_core::NpcActionKey::TreatPatients));
        assert!(plan
            .steps
            .iter()
            .any(|step| step.target_anchor.as_deref() == Some("clinic_room")));

        let snapshot = app.world().resource::<SettlementDebugSnapshot>();
        let entry = snapshot
            .entries
            .iter()
            .find(|entry| entry.entity == doctor)
            .expect("doctor entry in debug snapshot");
        assert_eq!(entry.role, NpcRole::Doctor);
        assert_eq!(entry.definition_id, "survivor_outpost_01_doctor_test");
        assert!(!entry.goal_scores.is_empty());
    }

    #[test]
    fn route_aware_travel_minutes_flow_into_online_plan_steps() {
        let mut app = App::new();
        app.insert_resource(CharacterDefinitions(sample_characters()));
        app.insert_resource(SettlementDefinitions(sample_settlements()));
        app.add_plugins((SettlementSimulationPlugin, NpcLifePlugin));
        app.world_mut().resource_mut::<SimClock>().minute_of_day = 9 * 60;

        let doctor = app
            .world_mut()
            .spawn((
                CharacterDefinitionId(CharacterId("survivor_outpost_01_doctor_test".into())),
                LifeProfileComponent(sample_doctor_life()),
            ))
            .id();

        app.update();

        let plan = app
            .world()
            .entity(doctor)
            .get::<super::CurrentPlan>()
            .expect("plan component");
        let travel = plan
            .steps
            .iter()
            .find(|step| step.action == game_core::NpcActionKey::TravelToDutyArea)
            .expect("travel to duty");
        assert!(travel.travel_minutes > 0);
    }

    fn sample_guard_life() -> CharacterLifeProfile {
        CharacterLifeProfile {
            settlement_id: "survivor_outpost_01_settlement".into(),
            role: NpcRole::Guard,
            ai_behavior_profile_id: "guard_settlement".into(),
            home_anchor: "guard_home_01".into(),
            duty_route_id: "guard_patrol_north".into(),
            schedule: vec![ScheduleBlock {
                day: ScheduleDay::Monday,
                start_minute: 8 * 60,
                end_minute: 16 * 60,
                label: "白班执勤".into(),
                tags: vec!["shift".into(), "guard".into()],
            }],
            smart_object_access: vec![
                "guard_post".into(),
                "bed".into(),
                "canteen_seat".into(),
                "recreation_spot".into(),
                "alarm_point".into(),
            ],
            need_profile: NeedProfile {
                hunger_decay_per_hour: 8.0,
                energy_decay_per_hour: 4.0,
                morale_decay_per_hour: 4.0,
                safety_bias: 0.8,
            },
        }
    }

    fn sample_cook_life() -> CharacterLifeProfile {
        CharacterLifeProfile {
            settlement_id: "survivor_outpost_01_settlement".into(),
            role: NpcRole::Cook,
            ai_behavior_profile_id: "cook_settlement".into(),
            home_anchor: "cook_home_01".into(),
            duty_route_id: "cook_service_loop".into(),
            schedule: vec![ScheduleBlock {
                day: ScheduleDay::Monday,
                start_minute: 6 * 60,
                end_minute: 14 * 60,
                label: "厨房轮值".into(),
                tags: vec!["shift".into(), "cook".into()],
            }],
            smart_object_access: vec![
                "bed".into(),
                "canteen_seat".into(),
                "recreation_spot".into(),
            ],
            need_profile: NeedProfile {
                hunger_decay_per_hour: 4.0,
                energy_decay_per_hour: 2.8,
                morale_decay_per_hour: 1.3,
                safety_bias: 0.4,
            },
        }
    }

    fn sample_doctor_life() -> CharacterLifeProfile {
        CharacterLifeProfile {
            settlement_id: "survivor_outpost_01_settlement".into(),
            role: NpcRole::Doctor,
            ai_behavior_profile_id: "doctor_settlement".into(),
            home_anchor: "doctor_home_01".into(),
            duty_route_id: "doctor_clinic_rounds".into(),
            schedule: vec![ScheduleBlock {
                day: ScheduleDay::Monday,
                start_minute: 9 * 60,
                end_minute: 17 * 60,
                label: "诊所轮值".into(),
                tags: vec!["shift".into(), "doctor".into()],
            }],
            smart_object_access: vec![
                "bed".into(),
                "medical_station".into(),
                "recreation_spot".into(),
            ],
            need_profile: NeedProfile {
                hunger_decay_per_hour: 3.2,
                energy_decay_per_hour: 2.4,
                morale_decay_per_hour: 1.1,
                safety_bias: 0.6,
            },
        }
    }

    fn sample_characters() -> CharacterLibrary {
        let mut definitions = BTreeMap::new();
        definitions.insert(
            CharacterId("survivor_outpost_01_guard_test".into()),
            sample_character("survivor_outpost_01_guard_test", sample_guard_life()),
        );
        definitions.insert(
            CharacterId("guard_one".into()),
            sample_character("guard_one", sample_guard_life()),
        );
        definitions.insert(
            CharacterId("guard_two".into()),
            sample_character(
                "guard_two",
                CharacterLifeProfile {
                    home_anchor: "guard_home_02".into(),
                    ..sample_guard_life()
                },
            ),
        );
        definitions.insert(
            CharacterId("survivor_outpost_01_cook_test".into()),
            sample_character("survivor_outpost_01_cook_test", sample_cook_life()),
        );
        definitions.insert(
            CharacterId("survivor_outpost_01_doctor_test".into()),
            sample_character("survivor_outpost_01_doctor_test", sample_doctor_life()),
        );
        CharacterLibrary::from(definitions)
    }

    fn sample_character(id: &str, life: CharacterLifeProfile) -> CharacterDefinition {
        CharacterDefinition {
            id: CharacterId(id.to_string()),
            archetype: CharacterArchetype::Npc,
            identity: CharacterIdentity {
                display_name: id.to_string(),
                description: "guard".into(),
            },
            faction: CharacterFaction {
                camp_id: "survivor".into(),
                disposition: CharacterDisposition::Friendly,
            },
            presentation: CharacterPresentation {
                portrait_path: String::new(),
                avatar_path: String::new(),
                model_path: String::new(),
                placeholder_colors: CharacterPlaceholderColors {
                    head: "#ffffff".into(),
                    body: "#cccccc".into(),
                    legs: "#999999".into(),
                },
            },
            progression: CharacterProgression { level: 2 },
            combat: CharacterCombatProfile {
                behavior: "neutral".into(),
                xp_reward: 5,
                loot: Vec::new(),
            },
            ai: CharacterAiProfile {
                aggro_range: 0.0,
                attack_range: 1.2,
                wander_radius: 1.0,
                leash_distance: 2.0,
                decision_interval: 1.0,
                attack_cooldown: 999.0,
            },
            attributes: CharacterAttributeTemplate {
                sets: BTreeMap::from([("base".into(), BTreeMap::from([("strength".into(), 5.0)]))]),
                resources: BTreeMap::from([("hp".into(), CharacterResourcePool { current: 60.0 })]),
            },
            interaction: None,
            life: Some(life),
        }
    }

    fn sample_settlements() -> SettlementLibrary {
        let settlement = SettlementDefinition {
            id: SettlementId("survivor_outpost_01_settlement".into()),
            map_id: MapId("survivor_outpost_01_grid".into()),
            anchors: vec![
                SettlementAnchorDefinition {
                    id: "guard_home_01".into(),
                    grid: game_data::GridCoord::new(1, 0, 1),
                },
                SettlementAnchorDefinition {
                    id: "guard_home_02".into(),
                    grid: game_data::GridCoord::new(2, 0, 1),
                },
                SettlementAnchorDefinition {
                    id: "north_gate".into(),
                    grid: game_data::GridCoord::new(5, 0, 1),
                },
                SettlementAnchorDefinition {
                    id: "canteen_main".into(),
                    grid: game_data::GridCoord::new(2, 0, 5),
                },
                SettlementAnchorDefinition {
                    id: "recreation_corner".into(),
                    grid: game_data::GridCoord::new(6, 0, 5),
                },
                SettlementAnchorDefinition {
                    id: "alarm_bell".into(),
                    grid: game_data::GridCoord::new(4, 0, 2),
                },
                SettlementAnchorDefinition {
                    id: "cook_home_01".into(),
                    grid: game_data::GridCoord::new(3, 0, 2),
                },
                SettlementAnchorDefinition {
                    id: "kitchen_station".into(),
                    grid: game_data::GridCoord::new(3, 0, 5),
                },
                SettlementAnchorDefinition {
                    id: "doctor_home_01".into(),
                    grid: game_data::GridCoord::new(1, 0, 3),
                },
                SettlementAnchorDefinition {
                    id: "clinic_room".into(),
                    grid: game_data::GridCoord::new(5, 0, 4),
                },
            ],
            routes: vec![
                SettlementRouteDefinition {
                    id: "guard_patrol_north".into(),
                    anchors: vec!["north_gate".into(), "alarm_bell".into()],
                },
                SettlementRouteDefinition {
                    id: "cook_service_loop".into(),
                    anchors: vec!["kitchen_station".into(), "canteen_main".into()],
                },
                SettlementRouteDefinition {
                    id: "doctor_clinic_rounds".into(),
                    anchors: vec![
                        "doctor_home_01".into(),
                        "clinic_room".into(),
                        "canteen_main".into(),
                    ],
                },
            ],
            smart_objects: vec![
                SmartObjectDefinition {
                    id: "guard_post_north".into(),
                    kind: SmartObjectKind::GuardPost,
                    anchor_id: "north_gate".into(),
                    capacity: 1,
                    tags: vec!["guard".into()],
                },
                SmartObjectDefinition {
                    id: "guard_bed_01".into(),
                    kind: SmartObjectKind::Bed,
                    anchor_id: "guard_home_01".into(),
                    capacity: 1,
                    tags: vec!["guard".into()],
                },
                SmartObjectDefinition {
                    id: "guard_bed_02".into(),
                    kind: SmartObjectKind::Bed,
                    anchor_id: "guard_home_02".into(),
                    capacity: 1,
                    tags: vec!["guard".into()],
                },
                SmartObjectDefinition {
                    id: "canteen_seat_01".into(),
                    kind: SmartObjectKind::CanteenSeat,
                    anchor_id: "canteen_main".into(),
                    capacity: 1,
                    tags: vec!["meal".into()],
                },
                SmartObjectDefinition {
                    id: "canteen_seat_cook_01".into(),
                    kind: SmartObjectKind::CanteenSeat,
                    anchor_id: "kitchen_station".into(),
                    capacity: 1,
                    tags: vec!["meal".into(), "cook".into()],
                },
                SmartObjectDefinition {
                    id: "recreation_bench_01".into(),
                    kind: SmartObjectKind::RecreationSpot,
                    anchor_id: "recreation_corner".into(),
                    capacity: 1,
                    tags: vec!["morale".into()],
                },
                SmartObjectDefinition {
                    id: "cook_bed_01".into(),
                    kind: SmartObjectKind::Bed,
                    anchor_id: "cook_home_01".into(),
                    capacity: 1,
                    tags: vec!["cook".into()],
                },
                SmartObjectDefinition {
                    id: "doctor_bed_01".into(),
                    kind: SmartObjectKind::Bed,
                    anchor_id: "doctor_home_01".into(),
                    capacity: 1,
                    tags: vec!["doctor".into()],
                },
                SmartObjectDefinition {
                    id: "clinic_station_01".into(),
                    kind: SmartObjectKind::MedicalStation,
                    anchor_id: "clinic_room".into(),
                    capacity: 1,
                    tags: vec!["doctor".into()],
                },
                SmartObjectDefinition {
                    id: "alarm_bell_01".into(),
                    kind: SmartObjectKind::AlarmPoint,
                    anchor_id: "alarm_bell".into(),
                    capacity: 1,
                    tags: vec!["alert".into()],
                },
            ],
            service_rules: ServiceRules {
                min_guard_on_duty: 1,
                meal_windows: vec![TimeWindow {
                    start_minute: 12 * 60,
                    end_minute: 13 * 60,
                }],
                quiet_hours: Some(TimeWindow {
                    start_minute: 22 * 60,
                    end_minute: 24 * 60,
                }),
            },
        };
        SettlementLibrary::from(BTreeMap::from([(settlement.id.clone(), settlement)]))
    }
}
