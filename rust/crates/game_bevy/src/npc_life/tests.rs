//! NPC life 域测试模块。
//! 负责覆盖规划、桥接与调试快照行为，不负责定义新的运行时语义。

use std::{collections::BTreeMap, path::PathBuf};

use bevy_app::App;
use game_data::{
    ActorId, CharacterAiProfile, CharacterArchetype, CharacterAttributeTemplate,
    CharacterCombatProfile, CharacterDefinition, CharacterDisposition, CharacterFaction,
    CharacterId, CharacterIdentity, CharacterLibrary, CharacterLifeProfile,
    CharacterPlaceholderColors, CharacterPresentation, CharacterProgression, CharacterResourcePool,
    MapId, NeedProfile, NpcRole, ServiceRules, SettlementAnchorDefinition, SettlementDefinition,
    SettlementId, SettlementLibrary, SettlementRouteDefinition, SmartObjectDefinition,
    SmartObjectKind, TimeWindow,
};

use super::{
    LifeProfileComponent, NpcActiveOfflineAction, NpcDecisionTrace, NpcLifePlugin, NpcLifeState,
    NpcPlannedActionQueue, NpcPlannedGoal, NpcRuntimeAiMode, NpcRuntimeBridgeState,
    ReservationState, ScheduleState, SettlementDebugSnapshot, SettlementSimulationPlugin, SimClock,
    WorldAlertState,
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
    app.world_mut().resource_mut::<WorldAlertState>().active = true;

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
fn combat_alert_bridge_forces_response_goal_and_clears_transient_flags() {
    let mut app = seeded_app();

    let entity = app
        .world_mut()
        .spawn((
            CharacterDefinitionId(CharacterId("survivor_outpost_01_guard_test".into())),
            LifeProfileComponent(sample_guard_life()),
        ))
        .id();

    app.update();

    app.world_mut().resource_mut::<WorldAlertState>().active = false;
    let mut entity_mut = app.world_mut().entity_mut(entity);
    entity_mut
        .get_mut::<NpcLifeState>()
        .expect("life state")
        .online = true;
    *entity_mut
        .get_mut::<NpcPlannedGoal>()
        .expect("goal component") = NpcPlannedGoal(Some(game_core::NpcGoalKey::ReturnHome));
    let mut runtime_bridge = entity_mut
        .get_mut::<NpcRuntimeBridgeState>()
        .expect("runtime bridge");
    runtime_bridge.execution_mode = game_core::NpcExecutionMode::Online;
    runtime_bridge.ai_mode = NpcRuntimeAiMode::Life;
    runtime_bridge.combat_alert_active = true;
    runtime_bridge.combat_threat_actor_id = Some(ActorId(77));
    drop(runtime_bridge);

    app.update();

    let goal = app
        .world()
        .entity(entity)
        .get::<NpcPlannedGoal>()
        .expect("goal component");
    let runtime_bridge = app
        .world()
        .entity(entity)
        .get::<NpcRuntimeBridgeState>()
        .expect("runtime bridge");

    assert_eq!(goal.0, Some(game_core::NpcGoalKey::RespondThreat));
    assert!(!runtime_bridge.combat_alert_active);
    assert!(!runtime_bridge.combat_replan_required);
    assert_eq!(runtime_bridge.combat_threat_actor_id, Some(ActorId(77)));
}

#[test]
fn combat_replan_bridge_forces_online_planner_rebuild() {
    let mut app = seeded_app();

    let entity = app
        .world_mut()
        .spawn((
            CharacterDefinitionId(CharacterId("survivor_outpost_01_guard_test".into())),
            LifeProfileComponent(sample_guard_life()),
        ))
        .id();

    for _ in 0..3 {
        app.update();
    }

    assert!(
        app.world()
            .entity(entity)
            .get::<NpcActiveOfflineAction>()
            .and_then(|action| action.0.as_ref())
            .is_some(),
        "expected an offline action before switching to online replan"
    );

    let mut entity_mut = app.world_mut().entity_mut(entity);
    entity_mut
        .get_mut::<NpcLifeState>()
        .expect("life state")
        .online = true;
    let mut runtime_bridge = entity_mut
        .get_mut::<NpcRuntimeBridgeState>()
        .expect("runtime bridge");
    runtime_bridge.execution_mode = game_core::NpcExecutionMode::Online;
    runtime_bridge.ai_mode = NpcRuntimeAiMode::Life;
    runtime_bridge.combat_replan_required = true;
    drop(runtime_bridge);

    app.update();

    let life = app
        .world()
        .entity(entity)
        .get::<NpcLifeState>()
        .expect("life state");
    let current_action = app
        .world()
        .entity(entity)
        .get::<NpcActiveOfflineAction>()
        .expect("current action");
    let current_plan = app
        .world()
        .entity(entity)
        .get::<NpcPlannedActionQueue>()
        .expect("plan");
    let trace = app
        .world()
        .entity(entity)
        .get::<NpcDecisionTrace>()
        .expect("decision trace");
    let runtime_bridge = app
        .world()
        .entity(entity)
        .get::<NpcRuntimeBridgeState>()
        .expect("runtime bridge");

    assert!(!life.replan_required);
    assert!(current_action.0.is_none());
    assert!(!current_plan.steps.is_empty());
    assert!(trace.selected_goal.is_some());
    assert!(!runtime_bridge.combat_replan_required);
}

#[test]
fn offline_runtime_bridge_refresh_clears_combat_state() {
    let mut app = seeded_app();

    let entity = app
        .world_mut()
        .spawn((
            CharacterDefinitionId(CharacterId("survivor_outpost_01_guard_test".into())),
            LifeProfileComponent(sample_guard_life()),
        ))
        .id();

    app.update();

    let mut entity_mut = app.world_mut().entity_mut(entity);
    let mut runtime_bridge = entity_mut
        .get_mut::<NpcRuntimeBridgeState>()
        .expect("runtime bridge");
    runtime_bridge.ai_mode = NpcRuntimeAiMode::Combat;
    runtime_bridge.combat_alert_active = true;
    runtime_bridge.combat_replan_required = true;
    runtime_bridge.combat_threat_actor_id = Some(ActorId(7));
    runtime_bridge.combat_target_actor_id = Some(ActorId(8));
    runtime_bridge.last_combat_target_actor_id = Some(ActorId(9));
    runtime_bridge.last_combat_intent = Some("territorial:retreat->(4,0,0)".into());
    runtime_bridge.last_combat_outcome = Some("lost_target".into());
    runtime_bridge.runtime_goal_grid = Some(game_data::GridCoord::new(4, 0, 0));
    runtime_bridge.actor_hp_ratio = Some(0.25);
    runtime_bridge.attack_ap_cost = Some(3.0);
    runtime_bridge.target_hp_ratio = Some(0.7);
    runtime_bridge.approach_distance_steps = Some(6);
    runtime_bridge.last_damage_taken = Some(5.0);
    runtime_bridge.last_damage_dealt = Some(2.0);
    runtime_bridge.last_failure_reason = Some("blocked".into());
    drop(runtime_bridge);

    app.update();

    let runtime_bridge = app
        .world()
        .entity(entity)
        .get::<NpcRuntimeBridgeState>()
        .expect("runtime bridge");
    assert_eq!(*runtime_bridge, NpcRuntimeBridgeState::default());
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
        .get::<NpcPlannedActionQueue>()
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
        .get::<NpcPlannedActionQueue>()
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
