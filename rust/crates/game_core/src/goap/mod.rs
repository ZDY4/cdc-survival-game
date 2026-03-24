pub mod actions;
pub mod facts;
pub mod goals;
pub mod offline_sim;
pub mod plan_runtime;
pub mod planner;

use game_data::NpcRole;

pub use facts::rebuild_facts;
pub use offline_sim::{advance_offline_sim, NpcOfflineSimState, OfflineSimAdvanceResult};
pub use plan_runtime::{
    tick_offline_action, ActionExecutionPhase, ActionTickResult, OfflineActionState,
};
pub use planner::{build_plan, build_plan_for_goal};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum NpcFact {
    Hungry,
    VeryHungry,
    Sleepy,
    Exhausted,
    NeedMorale,
    OnShift,
    ShiftStartingSoon,
    ThreatDetected,
    MealWindowOpen,
    AtHome,
    AtDutyArea,
    HasReservedBed,
    HasReservedMealSeat,
    GuardCoverageInsufficient,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NpcFactInput {
    pub hunger: f32,
    pub energy: f32,
    pub morale: f32,
    pub current_anchor: Option<String>,
    pub home_anchor: Option<String>,
    pub duty_anchor: Option<String>,
    pub on_shift: bool,
    pub shift_starting_soon: bool,
    pub threat_detected: bool,
    pub meal_window_open: bool,
    pub has_reserved_bed: bool,
    pub has_reserved_meal_seat: bool,
    pub guard_coverage_insufficient: bool,
}

impl Default for NpcFactInput {
    fn default() -> Self {
        Self {
            hunger: 100.0,
            energy: 100.0,
            morale: 100.0,
            current_anchor: None,
            home_anchor: None,
            duty_anchor: None,
            on_shift: false,
            shift_starting_soon: false,
            threat_detected: false,
            meal_window_open: false,
            has_reserved_bed: false,
            has_reserved_meal_seat: false,
            guard_coverage_insufficient: false,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum NpcGoalKey {
    RespondThreat,
    PreserveLife,
    SatisfyShift,
    EatMeal,
    Sleep,
    RecoverMorale,
    ReturnHome,
    IdleSafely,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub enum NpcActionKey {
    TravelToDutyArea,
    ReserveGuardPost,
    StandGuard,
    PatrolRoute,
    TravelToCanteen,
    EatMeal,
    RestockMealService,
    TravelToLeisure,
    Relax,
    TravelHome,
    ReserveBed,
    Sleep,
    RaiseAlarm,
    RespondAlarm,
    IdleSafely,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NpcPlanStep {
    pub action: NpcActionKey,
    pub target_anchor: Option<String>,
    pub reservation_target: Option<String>,
    pub travel_minutes: u32,
    pub perform_minutes: u32,
    pub expected_facts: Vec<NpcFact>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct NpcPlanRequest {
    pub role: NpcRole,
    pub facts: Vec<NpcFact>,
    pub home_anchor: Option<String>,
    pub duty_anchor: Option<String>,
    pub canteen_anchor: Option<String>,
    pub leisure_anchor: Option<String>,
    pub alarm_anchor: Option<String>,
    pub guard_post_id: Option<String>,
    pub bed_id: Option<String>,
    pub meal_object_id: Option<String>,
    pub leisure_object_id: Option<String>,
    pub patrol_route_id: Option<String>,
}

impl Default for NpcPlanRequest {
    fn default() -> Self {
        Self {
            role: NpcRole::Resident,
            facts: Vec::new(),
            home_anchor: None,
            duty_anchor: None,
            canteen_anchor: None,
            leisure_anchor: None,
            alarm_anchor: None,
            guard_post_id: None,
            bed_id: None,
            meal_object_id: None,
            leisure_object_id: None,
            patrol_route_id: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct NpcPlanResult {
    pub selected_goal: NpcGoalKey,
    pub steps: Vec<NpcPlanStep>,
    pub total_cost: usize,
    pub facts: Vec<NpcFact>,
    pub debug_plan: String,
    pub planned: bool,
}

#[cfg(test)]
mod tests {
    use game_data::NpcRole;

    use super::{
        advance_offline_sim, build_plan, rebuild_facts, tick_offline_action, ActionExecutionPhase,
        NpcActionKey, NpcFact, NpcFactInput, NpcGoalKey, NpcOfflineSimState, NpcPlanRequest,
        NpcPlanStep, OfflineActionState,
    };

    #[test]
    fn rebuild_facts_marks_thresholds() {
        let facts = rebuild_facts(&NpcFactInput {
            hunger: 20.0,
            energy: 24.0,
            morale: 30.0,
            current_anchor: Some("home".into()),
            home_anchor: Some("home".into()),
            duty_anchor: Some("duty".into()),
            on_shift: false,
            shift_starting_soon: true,
            threat_detected: false,
            meal_window_open: true,
            has_reserved_bed: false,
            has_reserved_meal_seat: false,
            guard_coverage_insufficient: false,
        });

        assert!(facts.contains(&NpcFact::Hungry));
        assert!(facts.contains(&NpcFact::VeryHungry));
        assert!(facts.contains(&NpcFact::Sleepy));
        assert!(facts.contains(&NpcFact::Exhausted));
        assert!(facts.contains(&NpcFact::NeedMorale));
        assert!(facts.contains(&NpcFact::ShiftStartingSoon));
        assert!(facts.contains(&NpcFact::MealWindowOpen));
        assert!(facts.contains(&NpcFact::AtHome));
    }

    #[test]
    fn guard_shift_plan_prefers_patrol() {
        let result = build_plan(&NpcPlanRequest {
            role: NpcRole::Guard,
            facts: vec![NpcFact::OnShift],
            home_anchor: Some("guard_home".into()),
            duty_anchor: Some("north_gate".into()),
            canteen_anchor: Some("canteen".into()),
            leisure_anchor: Some("bench".into()),
            alarm_anchor: Some("alarm".into()),
            guard_post_id: Some("guard_post_north".into()),
            bed_id: Some("guard_bed".into()),
            meal_object_id: Some("seat_01".into()),
            leisure_object_id: Some("bench_01".into()),
            patrol_route_id: Some("guard_patrol".into()),
        });

        assert_eq!(result.selected_goal, NpcGoalKey::SatisfyShift);
        assert!(result
            .steps
            .iter()
            .any(|step| step.action == NpcActionKey::PatrolRoute));
    }

    #[test]
    fn hungry_guard_plans_meal() {
        let result = build_plan(&NpcPlanRequest {
            role: NpcRole::Guard,
            facts: vec![
                NpcFact::Hungry,
                NpcFact::MealWindowOpen,
                NpcFact::AtDutyArea,
            ],
            home_anchor: Some("guard_home".into()),
            duty_anchor: Some("north_gate".into()),
            canteen_anchor: Some("canteen".into()),
            leisure_anchor: Some("bench".into()),
            alarm_anchor: Some("alarm".into()),
            guard_post_id: Some("guard_post_north".into()),
            bed_id: Some("guard_bed".into()),
            meal_object_id: Some("seat_01".into()),
            leisure_object_id: Some("bench_01".into()),
            patrol_route_id: Some("guard_patrol".into()),
        });

        assert_eq!(result.selected_goal, NpcGoalKey::EatMeal);
        assert!(result
            .steps
            .iter()
            .any(|step| step.action == NpcActionKey::EatMeal));
    }

    #[test]
    fn low_morale_guard_plans_relaxation() {
        let result = build_plan(&NpcPlanRequest {
            role: NpcRole::Guard,
            facts: vec![NpcFact::NeedMorale, NpcFact::AtHome],
            home_anchor: Some("guard_home".into()),
            duty_anchor: Some("north_gate".into()),
            canteen_anchor: Some("canteen".into()),
            leisure_anchor: Some("bench".into()),
            alarm_anchor: Some("alarm".into()),
            guard_post_id: Some("guard_post_north".into()),
            bed_id: Some("guard_bed".into()),
            meal_object_id: Some("seat_01".into()),
            leisure_object_id: Some("bench_01".into()),
            patrol_route_id: Some("guard_patrol".into()),
        });

        assert_eq!(result.selected_goal, NpcGoalKey::RecoverMorale);
        assert!(result
            .steps
            .iter()
            .any(|step| step.action == NpcActionKey::Relax));
    }

    #[test]
    fn sleepy_guard_returns_home_and_sleeps() {
        let result = build_plan(&NpcPlanRequest {
            role: NpcRole::Guard,
            facts: vec![NpcFact::Sleepy],
            home_anchor: Some("guard_home".into()),
            duty_anchor: Some("north_gate".into()),
            canteen_anchor: Some("canteen".into()),
            leisure_anchor: Some("bench".into()),
            alarm_anchor: Some("alarm".into()),
            guard_post_id: Some("guard_post_north".into()),
            bed_id: Some("guard_bed".into()),
            meal_object_id: Some("seat_01".into()),
            leisure_object_id: Some("bench_01".into()),
            patrol_route_id: Some("guard_patrol".into()),
        });

        assert_eq!(result.selected_goal, NpcGoalKey::Sleep);
        assert!(result
            .steps
            .iter()
            .any(|step| step.action == NpcActionKey::TravelHome));
        assert!(result
            .steps
            .iter()
            .any(|step| step.action == NpcActionKey::Sleep));
    }

    #[test]
    fn alert_preempts_other_goals() {
        let result = build_plan(&NpcPlanRequest {
            role: NpcRole::Guard,
            facts: vec![
                NpcFact::ThreatDetected,
                NpcFact::Hungry,
                NpcFact::MealWindowOpen,
            ],
            home_anchor: Some("guard_home".into()),
            duty_anchor: Some("north_gate".into()),
            canteen_anchor: Some("canteen".into()),
            leisure_anchor: Some("bench".into()),
            alarm_anchor: Some("alarm".into()),
            guard_post_id: Some("guard_post_north".into()),
            bed_id: Some("guard_bed".into()),
            meal_object_id: Some("seat_01".into()),
            leisure_object_id: Some("bench_01".into()),
            patrol_route_id: Some("guard_patrol".into()),
        });

        assert_eq!(result.selected_goal, NpcGoalKey::RespondThreat);
        assert!(result
            .steps
            .iter()
            .any(|step| step.action == NpcActionKey::RespondAlarm));
    }

    #[test]
    fn cook_shift_plan_restocks_meal_service() {
        let result = build_plan(&NpcPlanRequest {
            role: NpcRole::Cook,
            facts: vec![NpcFact::OnShift],
            home_anchor: Some("cook_home".into()),
            duty_anchor: None,
            canteen_anchor: Some("canteen".into()),
            leisure_anchor: Some("bench".into()),
            alarm_anchor: Some("alarm".into()),
            guard_post_id: None,
            bed_id: Some("cook_bed".into()),
            meal_object_id: Some("kitchen_station".into()),
            leisure_object_id: Some("bench_01".into()),
            patrol_route_id: None,
        });

        assert_eq!(result.selected_goal, NpcGoalKey::SatisfyShift);
        assert!(result
            .steps
            .iter()
            .any(|step| step.action == NpcActionKey::RestockMealService));
    }

    #[test]
    fn tick_offline_action_runs_sleep_lifecycle() {
        let mut action = OfflineActionState::new(
            NpcPlanStep {
                action: NpcActionKey::Sleep,
                target_anchor: Some("guard_home".into()),
                reservation_target: Some("guard_bed".into()),
                travel_minutes: 0,
                perform_minutes: 5,
                expected_facts: vec![NpcFact::AtHome],
            },
            Some("guard_home".into()),
        );
        action.advance_after_acquire();

        let tick = tick_offline_action(&mut action, 5);

        assert!(tick.finished);
        assert_eq!(tick.completed_action, Some(NpcActionKey::Sleep));
        assert_eq!(tick.released_reservations, vec!["guard_bed".to_string()]);
    }

    #[test]
    fn offline_sim_tracks_completed_steps() {
        let mut state = NpcOfflineSimState::default();
        state.queued_steps.push_back(NpcPlanStep {
            action: NpcActionKey::TravelHome,
            target_anchor: Some("guard_home".into()),
            reservation_target: None,
            travel_minutes: 5,
            perform_minutes: 0,
            expected_facts: vec![NpcFact::AtHome],
        });
        state.queued_steps.push_back(NpcPlanStep {
            action: NpcActionKey::IdleSafely,
            target_anchor: Some("guard_home".into()),
            reservation_target: None,
            travel_minutes: 0,
            perform_minutes: 5,
            expected_facts: vec![NpcFact::AtHome],
        });

        let result = advance_offline_sim(&mut state, 10);

        assert_eq!(
            result.finished_actions,
            vec![NpcActionKey::TravelHome, NpcActionKey::IdleSafely]
        );
        assert_eq!(result.current_anchor, Some("guard_home".into()));
    }

    #[test]
    fn acquire_phase_can_be_held_by_runtime() {
        let mut action = OfflineActionState::new(
            NpcPlanStep {
                action: NpcActionKey::ReserveBed,
                target_anchor: Some("guard_home".into()),
                reservation_target: Some("guard_bed".into()),
                travel_minutes: 0,
                perform_minutes: 0,
                expected_facts: Vec::new(),
            },
            Some("guard_home".into()),
        );

        assert_eq!(action.phase, ActionExecutionPhase::AcquireReservation);
        action.advance_after_acquire();
        assert_eq!(action.phase, ActionExecutionPhase::Travel);
    }
}
