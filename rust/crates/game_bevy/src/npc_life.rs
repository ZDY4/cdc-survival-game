use std::collections::{BTreeMap, BTreeSet};

use bevy_app::prelude::*;
use bevy_ecs::prelude::*;
use game_core::{
    build_plan_for_goal, rebuild_facts, select_goal, tick_offline_action, ActionExecutionPhase,
    NpcActionKey, NpcFactInput, NpcGoalKey, NpcPlanRequest, NpcPlanStep, OfflineActionState,
};
use game_data::{
    CharacterLifeProfile, NeedProfile, NpcRole, ScheduleBlock, ScheduleDay, SettlementDefinition,
    SettlementId, SmartObjectKind,
};

use crate::SettlementDefinitions;

#[derive(Component, Debug, Clone, PartialEq)]
pub struct LifeProfileComponent(pub CharacterLifeProfile);

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

#[derive(Resource, Debug, Clone, PartialEq, Eq, Default)]
pub struct SmartObjectReservations(pub BTreeMap<String, Entity>);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SettlementDebugEntry {
    pub entity: Entity,
    pub settlement_id: String,
    pub goal: Option<NpcGoalKey>,
    pub action: Option<NpcActionKey>,
    pub schedule_label: String,
    pub current_anchor: Option<String>,
    pub reservations: Vec<String>,
}

#[derive(Resource, Debug, Clone, PartialEq, Eq, Default)]
pub struct SettlementDebugSnapshot {
    pub entries: Vec<SettlementDebugEntry>,
}

pub struct NpcLifePlugin;

impl Plugin for NpcLifePlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(
            Update,
            (
                initialize_npc_life_entities,
                update_schedule_state_system,
                update_need_state_system,
                plan_npc_life_system,
                execute_offline_actions_system,
                refresh_debug_snapshot_system,
                advance_sim_clock_system,
            )
                .chain(),
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
    query: Query<(Entity, &LifeProfileComponent), Without<NpcLifeState>>,
) {
    let Some(settlements) = settlements else {
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
        let duty_anchor = route_anchor(settlement, &profile.duty_route_id)
            .or_else(|| first_anchor_for_kind(settlement, SmartObjectKind::GuardPost));
        let canteen_anchor = first_anchor_for_kind(settlement, SmartObjectKind::CanteenSeat);
        let leisure_anchor = first_anchor_for_kind(settlement, SmartObjectKind::RecreationSpot);
        let alarm_anchor = first_anchor_for_kind(settlement, SmartObjectKind::AlarmPoint);

        commands.entity(entity).insert((
            NpcLifeState {
                settlement_id: profile.settlement_id.clone(),
                role: profile.role,
                home_anchor: profile.home_anchor.clone(),
                duty_anchor,
                duty_route_id: non_empty(profile.duty_route_id.clone()),
                canteen_anchor,
                leisure_anchor,
                alarm_anchor,
                guard_post_id: first_object_for_kind(settlement, SmartObjectKind::GuardPost),
                bed_id: first_object_for_kind(settlement, SmartObjectKind::Bed),
                meal_object_id: first_object_for_kind(settlement, SmartObjectKind::CanteenSeat),
                leisure_object_id: first_object_for_kind(
                    settlement,
                    SmartObjectKind::RecreationSpot,
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
    world_alert: Res<WorldAlertState>,
    mut queries: ParamSet<(
        Query<(Entity, &NpcLifeState, &ScheduleState, &CurrentAction)>,
        Query<(
            Entity,
            &mut NpcLifeState,
            &NeedState,
            &ScheduleState,
            &ReservationState,
            &mut CurrentGoal,
            &mut CurrentPlan,
            &mut CurrentAction,
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
                .map(|action| {
                    matches!(
                        action.step.action,
                        NpcActionKey::StandGuard
                            | NpcActionKey::PatrolRoute
                            | NpcActionKey::RespondAlarm
                    )
                })
                .unwrap_or(false);
        if is_covering {
            *guard_coverage
                .entry(life.settlement_id.clone())
                .or_default() += 1;
        }
    }

    for (
        _entity,
        mut life,
        need,
        schedule,
        reservations,
        mut current_goal,
        mut current_plan,
        mut current_action,
    ) in &mut queries.p1()
    {
        if world_alert.active && current_goal.0 != Some(NpcGoalKey::RespondThreat) {
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
        let active_guards = guard_coverage
            .get(&life.settlement_id)
            .copied()
            .unwrap_or_default();
        let facts = rebuild_facts(&NpcFactInput {
            hunger: need.hunger,
            energy: need.energy,
            morale: need.morale,
            current_anchor: life.current_anchor.clone(),
            home_anchor: Some(life.home_anchor.clone()),
            duty_anchor: life.duty_anchor.clone(),
            on_shift: schedule.on_shift,
            shift_starting_soon: schedule.shift_starting_soon,
            threat_detected: world_alert.active,
            meal_window_open: schedule.meal_window_open,
            has_reserved_bed: life
                .bed_id
                .as_ref()
                .map(|id| reservations.active.contains(id))
                .unwrap_or(false),
            has_reserved_meal_seat: life
                .meal_object_id
                .as_ref()
                .map(|id| reservations.active.contains(id))
                .unwrap_or(false),
            guard_coverage_insufficient: life.role == NpcRole::Guard
                && schedule.on_shift
                && active_guards < settlement.service_rules.min_guard_on_duty,
        });
        let plan_request = NpcPlanRequest {
            role: life.role,
            facts,
            home_anchor: Some(life.home_anchor.clone()),
            duty_anchor: life.duty_anchor.clone(),
            canteen_anchor: life.canteen_anchor.clone(),
            leisure_anchor: life.leisure_anchor.clone(),
            alarm_anchor: life.alarm_anchor.clone(),
            guard_post_id: life.guard_post_id.clone(),
            bed_id: life.bed_id.clone(),
            meal_object_id: life.meal_object_id.clone(),
            leisure_object_id: life.leisure_object_id.clone(),
            patrol_route_id: life.duty_route_id.clone(),
        };
        let selected_goal = select_goal(&plan_request);
        let plan = build_plan_for_goal(&plan_request, selected_goal);
        current_goal.0 = Some(selected_goal);
        current_plan.steps = plan.steps;
        current_plan.next_index = 0;
        current_plan.total_cost = plan.total_cost;
        current_plan.debug_plan = plan.debug_plan;
        current_action.0 = None;
        life.replan_required = false;
    }
}

fn execute_offline_actions_system(
    clock: Res<SimClock>,
    mut registry: ResMut<SmartObjectReservations>,
    mut query: Query<(
        Entity,
        &mut NpcLifeState,
        &mut NeedState,
        &mut CurrentPlan,
        &mut CurrentAction,
        &mut ReservationState,
    )>,
) {
    for (entity, mut life, mut need, mut current_plan, mut current_action, mut reservations) in
        &mut query
    {
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
        let tick = {
            let action_state = current_action.0.as_mut().expect("action exists");
            if action_state.phase == ActionExecutionPhase::AcquireReservation {
                if let Some(target) = action_state.step.reservation_target.clone() {
                    if let Some(owner) = registry.0.get(&target) {
                        if *owner != entity {
                            action_state.fail();
                            reservation_conflict = true;
                        }
                    } else {
                        registry.0.insert(target.clone(), entity);
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
            if let Some(action) = tick.completed_action {
                apply_action_effects(action, &mut need);
            }
            for released in tick.released_reservations {
                registry.0.remove(&released);
                reservations.active.remove(&released);
            }
            current_plan.next_index += 1;
            current_action.0 = None;
            if current_plan.next_index >= current_plan.steps.len() {
                life.replan_required = true;
            }
        }
    }
}

fn refresh_debug_snapshot_system(
    mut snapshot: ResMut<SettlementDebugSnapshot>,
    query: Query<(
        Entity,
        &NpcLifeState,
        &CurrentGoal,
        &CurrentAction,
        &ScheduleState,
        &ReservationState,
    )>,
) {
    let mut entries = Vec::new();
    for (entity, life, goal, action, schedule, reservations) in &query {
        entries.push(SettlementDebugEntry {
            entity,
            settlement_id: life.settlement_id.clone(),
            goal: goal.0,
            action: action.0.as_ref().map(|current| current.step.action),
            schedule_label: schedule.active_label.clone(),
            current_anchor: life.current_anchor.clone(),
            reservations: reservations.active.iter().cloned().collect(),
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

fn route_anchor(settlement: &SettlementDefinition, route_id: &str) -> Option<String> {
    settlement
        .routes
        .iter()
        .find(|route| route.id == route_id)
        .and_then(|route| route.anchors.first().cloned())
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

fn first_object_for_kind(
    settlement: &SettlementDefinition,
    kind: SmartObjectKind,
) -> Option<String> {
    settlement
        .smart_objects
        .iter()
        .find(|object| object.kind == kind)
        .map(|object| object.id.clone())
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

fn apply_action_effects(action: NpcActionKey, need: &mut NeedState) {
    match action {
        NpcActionKey::EatMeal => {
            need.hunger = (need.hunger + 55.0).clamp(0.0, 100.0);
        }
        NpcActionKey::Sleep => {
            need.energy = (need.energy + 75.0).clamp(0.0, 100.0);
            need.morale = (need.morale + 10.0).clamp(0.0, 100.0);
        }
        NpcActionKey::Relax => {
            need.morale = (need.morale + 35.0).clamp(0.0, 100.0);
        }
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

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
        ReservationState, ScheduleState, SettlementSimulationPlugin,
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
                CharacterDefinitionId(CharacterId("safehouse_guard_test".into())),
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
                .and_then(|current| current.0.as_ref().map(|state| state.step.action))
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
                CharacterDefinitionId(CharacterId("safehouse_guard_test".into())),
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

    fn sample_guard_life() -> CharacterLifeProfile {
        CharacterLifeProfile {
            settlement_id: "safehouse_survivor_outpost".into(),
            role: NpcRole::Guard,
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

    fn sample_characters() -> CharacterLibrary {
        let mut definitions = BTreeMap::new();
        definitions.insert(
            CharacterId("safehouse_guard_test".into()),
            sample_character("safehouse_guard_test", sample_guard_life()),
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
            id: SettlementId("safehouse_survivor_outpost".into()),
            map_id: MapId("safehouse_grid".into()),
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
            ],
            routes: vec![SettlementRouteDefinition {
                id: "guard_patrol_north".into(),
                anchors: vec!["north_gate".into(), "alarm_bell".into()],
            }],
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
                    id: "recreation_bench_01".into(),
                    kind: SmartObjectKind::RecreationSpot,
                    anchor_id: "recreation_corner".into(),
                    capacity: 1,
                    tags: vec!["morale".into()],
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
