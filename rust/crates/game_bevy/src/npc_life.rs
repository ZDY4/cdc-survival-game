use std::collections::BTreeSet;

use bevy_app::prelude::*;
use bevy_ecs::prelude::*;
use game_core::{
    ActionExecutionPhase, NpcActionKey, NpcBackgroundState, NpcExecutionMode, NpcFact, NpcGoalKey,
    NpcGoalScore, NpcPlanStep, OfflineActionState,
};
use game_data::{
    ActorId, AiBehaviorProfile, CharacterLifeProfile, GridCoord, NeedProfile, NpcRole,
    PersonalityProfileDefinition, ResolvedCharacterLifeProfile, ScheduleDay,
    SmartObjectAccessProfileDefinition,
};

mod helpers;
mod systems;

#[derive(SystemSet, Debug, Hash, PartialEq, Eq, Clone)]
pub enum NpcLifeUpdateSet {
    RuntimeState,
}

#[derive(Component, Debug, Clone, PartialEq)]
pub struct LifeProfileComponent(pub CharacterLifeProfile);

#[derive(Component, Debug, Clone, PartialEq)]
pub struct ResolvedLifeProfileComponent(pub ResolvedCharacterLifeProfile);

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
            hunger_decay_per_hour: profile.hunger_decay_per_hour,
            energy_decay_per_hour: profile.energy_decay_per_hour,
            morale_decay_per_hour: profile.morale_decay_per_hour,
        }
    }
}

#[derive(Component, Debug, Clone, PartialEq)]
pub struct PersonalityState {
    pub safety_bias: f32,
    pub social_bias: f32,
    pub duty_bias: f32,
    pub comfort_bias: f32,
    pub alertness_bias: f32,
}

impl From<&PersonalityProfileDefinition> for PersonalityState {
    fn from(profile: &PersonalityProfileDefinition) -> Self {
        Self {
            safety_bias: profile.safety_bias,
            social_bias: profile.social_bias,
            duty_bias: profile.duty_bias,
            comfort_bias: profile.comfort_bias,
            alertness_bias: profile.alertness_bias,
        }
    }
}

#[derive(Component, Debug, Clone, PartialEq)]
pub struct SmartObjectAccessProfileComponent(pub SmartObjectAccessProfileDefinition);

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct ScheduleState {
    pub active_label: String,
    pub on_shift: bool,
    pub shift_starting_soon: bool,
    pub meal_window_open: bool,
    pub quiet_hours: bool,
}

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct NpcPlannedGoal(pub Option<NpcGoalKey>);

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct NpcPlannedActionQueue {
    pub steps: Vec<NpcPlanStep>,
    pub next_index: usize,
    pub total_cost: usize,
    pub debug_plan: String,
}

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct NpcActiveOfflineAction(pub Option<OfflineActionState>);

#[derive(Component, Debug, Clone, PartialEq, Eq, Default)]
pub struct ReservationState {
    pub active: BTreeSet<String>,
}

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct RuntimeActorLink {
    pub actor_id: ActorId,
}

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum NpcRuntimeAiMode {
    #[default]
    Life,
    Combat,
}

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub struct NpcRuntimeBridgeState {
    pub execution_mode: NpcExecutionMode,
    pub ai_mode: NpcRuntimeAiMode,
    pub combat_target_actor_id: Option<ActorId>,
    pub last_combat_intent: Option<String>,
    pub runtime_goal_grid: Option<GridCoord>,
    pub last_failure_reason: Option<String>,
}

impl Default for NpcRuntimeBridgeState {
    fn default() -> Self {
        Self {
            execution_mode: NpcExecutionMode::Background,
            ai_mode: NpcRuntimeAiMode::Life,
            combat_target_actor_id: None,
            last_combat_intent: None,
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
pub struct NpcDecisionTrace {
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
    pub ai_mode: NpcRuntimeAiMode,
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
    pub combat_target_actor_id: Option<ActorId>,
    pub last_combat_intent: Option<String>,
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
        systems::configure(app);
    }
}

pub struct SettlementSimulationPlugin;

impl Plugin for SettlementSimulationPlugin {
    fn build(&self, app: &mut App) {
        systems::initialize_resources(app);
    }
}

#[cfg(test)]
mod tests {
    use std::{collections::BTreeMap, path::PathBuf};

    use super::SimClock;
    use bevy_app::App;
    use game_data::{
        CharacterAiProfile, CharacterArchetype, CharacterAttributeTemplate, CharacterCombatProfile,
        CharacterDefinition, CharacterDisposition, CharacterFaction, CharacterId,
        CharacterIdentity, CharacterLibrary, CharacterLifeProfile, CharacterPlaceholderColors,
        CharacterPresentation, CharacterProgression, CharacterResourcePool, MapId, NeedProfile,
        NpcRole, ServiceRules, SettlementAnchorDefinition, SettlementDefinition, SettlementId,
        SettlementLibrary, SettlementRouteDefinition, SmartObjectDefinition, SmartObjectKind,
        TimeWindow,
    };

    use super::{
        LifeProfileComponent, NpcActiveOfflineAction, NpcLifePlugin, NpcLifeState,
        NpcPlannedGoal, ReservationState, ScheduleState, SettlementDebugSnapshot,
        SettlementSimulationPlugin,
    };
    use crate::{CharacterDefinitionId, CharacterDefinitions, SettlementDefinitions};

    fn seeded_app() -> App {
        let mut app = App::new();
        app.insert_resource(CharacterDefinitions(sample_characters()));
        app.insert_resource(SettlementDefinitions(sample_settlements()));
        let ai_path = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../data/ai");
        app.insert_resource(
            crate::load_ai_definitions(ai_path).expect("load ai definitions for npc_life tests"),
        );
        app.add_plugins((SettlementSimulationPlugin, NpcLifePlugin));
        app
    }

    #[test]
    fn guard_plans_patrol_meal_relax_and_sleep_across_day() {
        use std::collections::BTreeSet;

        let mut app = seeded_app();

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
                .get::<NpcActiveOfflineAction>()
                .and_then(|current| current.0.as_ref().map(|state| state.step.action.clone()))
            {
                seen_actions.insert(action);
            }
        }

        let goal = app
            .world()
            .entity(entity)
            .get::<NpcPlannedGoal>()
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
        let mut app = seeded_app();

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
        let mut app = seeded_app();

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
            .get::<NpcPlannedGoal>()
            .expect("goal component");
        assert_eq!(goal.0, Some(game_core::NpcGoalKey::RespondThreat));
    }

    #[test]
    fn cook_uses_role_tagged_objects_and_exposes_decision_trace() {
        let mut app = seeded_app();

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
        let mut app = seeded_app();

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
            .get::<super::NpcPlannedActionQueue>()
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
        let mut app = seeded_app();
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
            .get::<super::NpcPlannedActionQueue>()
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
            schedule_profile_id: "guard_day_shift_weekday".into(),
            personality_profile_id: "guard_diligent".into(),
            need_profile_id: "guard_standard".into(),
            smart_object_access_profile_id: "guard_settlement_access".into(),
            home_anchor: "guard_home_01".into(),
            duty_route_id: "guard_patrol_north".into(),
            schedule: Vec::new(),
            need_profile_override: Some(NeedProfile {
                hunger_decay_per_hour: 8.0,
                energy_decay_per_hour: 4.0,
                morale_decay_per_hour: 4.0,
                safety_bias: 0.8,
            }),
            personality_override: Default::default(),
        }
    }

    fn sample_cook_life() -> CharacterLifeProfile {
        CharacterLifeProfile {
            settlement_id: "survivor_outpost_01_settlement".into(),
            role: NpcRole::Cook,
            ai_behavior_profile_id: "cook_settlement".into(),
            schedule_profile_id: "cook_morning_shift_weekday".into(),
            personality_profile_id: "cook_caretaker".into(),
            need_profile_id: "cook_standard".into(),
            smart_object_access_profile_id: "cook_settlement_access".into(),
            home_anchor: "cook_home_01".into(),
            duty_route_id: "cook_service_loop".into(),
            schedule: Vec::new(),
            need_profile_override: Some(NeedProfile {
                hunger_decay_per_hour: 4.0,
                energy_decay_per_hour: 2.8,
                morale_decay_per_hour: 1.3,
                safety_bias: 0.4,
            }),
            personality_override: Default::default(),
        }
    }

    fn sample_doctor_life() -> CharacterLifeProfile {
        CharacterLifeProfile {
            settlement_id: "survivor_outpost_01_settlement".into(),
            role: NpcRole::Doctor,
            ai_behavior_profile_id: "doctor_settlement".into(),
            schedule_profile_id: "doctor_clinic_rounds_weekday".into(),
            personality_profile_id: "doctor_compassionate".into(),
            need_profile_id: "doctor_standard".into(),
            smart_object_access_profile_id: "doctor_settlement_access".into(),
            home_anchor: "doctor_home_01".into(),
            duty_route_id: "doctor_clinic_rounds".into(),
            schedule: Vec::new(),
            need_profile_override: Some(NeedProfile {
                hunger_decay_per_hour: 3.2,
                energy_decay_per_hour: 2.4,
                morale_decay_per_hour: 1.1,
                safety_bias: 0.6,
            }),
            personality_override: Default::default(),
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
            appearance_profile_id: "default_humanoid".into(),
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
            map_id: MapId("survivor_outpost_01".into()),
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
