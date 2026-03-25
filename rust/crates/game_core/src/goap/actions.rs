use dogoap::prelude::{Action, Compare, LocalState, Mutator};
use game_data::NpcRole;

use super::{NpcActionKey, NpcFact, NpcPlanRequest, NpcPlanStep, NpcPlanningContext};

pub fn build_action_set(request: &NpcPlanRequest) -> Vec<Action> {
    let context = NpcPlanningContext::from_plan_request(request);
    build_action_set_for_context(&context)
}

pub fn build_action_set_for_context(context: &NpcPlanningContext) -> Vec<Action> {
    let request = &context.request;
    let mut actions = common_life_actions(context);

    if request.duty_anchor.is_some() && context.is_anchor_reachable(request.duty_anchor.as_deref())
    {
        actions.push(
            Action::new(action_name(NpcActionKey::TravelToDutyArea))
                .with_precondition(("at_duty_area", Compare::not_equals(true)))
                .with_mutator(Mutator::set("at_duty_area", true))
                .with_mutator(Mutator::set("at_home", false))
                .with_mutator(Mutator::set("at_canteen", false))
                .with_mutator(Mutator::set("at_leisure", false))
                .set_cost(1),
        );
    }

    actions.extend(guard_actions(request));
    actions.extend(cook_actions(context));
    actions.extend(doctor_actions(request));

    actions
}

pub fn build_start_state(request: &NpcPlanRequest) -> LocalState {
    let mut state = LocalState::new();

    for key in [
        "is_hungry",
        "is_very_hungry",
        "sleepy",
        "exhausted",
        "need_morale",
        "on_shift",
        "shift_starting_soon",
        "threat_detected",
        "meal_window_open",
        "at_home",
        "at_duty_area",
        "has_reserved_bed",
        "has_reserved_meal_seat",
        "guard_coverage_insufficient",
        "has_reserved_guard_post",
        "guard_duty_satisfied",
        "guard_coverage_secured",
        "patrol_completed",
        "meal_service_restocked",
        "patients_treated",
        "morale_recovered",
        "threat_resolved",
        "is_idle_safe",
        "is_rested",
        "at_canteen",
        "at_leisure",
        "alarm_raised",
    ] {
        state = state.with_datum(key, false);
    }

    for fact in &request.facts {
        state = state.with_datum(fact_key(*fact), true);
    }

    state
}

pub fn step_for_action(action: NpcActionKey, request: &NpcPlanRequest) -> NpcPlanStep {
    let context = NpcPlanningContext::from_plan_request(request);
    step_for_action_with_context(action, &context)
}

pub fn step_for_action_with_context(
    action: NpcActionKey,
    context: &NpcPlanningContext,
) -> NpcPlanStep {
    let request = &context.request;
    let (target_anchor, reservation_target, expected_facts) = match action {
        NpcActionKey::TravelToDutyArea => {
            (request.duty_anchor.clone(), None, vec![NpcFact::AtDutyArea])
        }
        NpcActionKey::ReserveGuardPost => (
            request.duty_anchor.clone(),
            request.guard_post_id.clone(),
            Vec::new(),
        ),
        NpcActionKey::StandGuard => (
            request.duty_anchor.clone(),
            request.guard_post_id.clone(),
            Vec::new(),
        ),
        NpcActionKey::PatrolRoute => (request.duty_anchor.clone(), None, vec![NpcFact::AtDutyArea]),
        NpcActionKey::TravelToCanteen => (
            request.canteen_anchor.clone(),
            request.meal_object_id.clone(),
            Vec::new(),
        ),
        NpcActionKey::EatMeal => (
            request.canteen_anchor.clone(),
            request.meal_object_id.clone(),
            Vec::new(),
        ),
        NpcActionKey::RestockMealService => (
            request.canteen_anchor.clone(),
            request.meal_object_id.clone(),
            Vec::new(),
        ),
        NpcActionKey::TreatPatients => (
            request.duty_anchor.clone(),
            request.medical_station_id.clone(),
            vec![NpcFact::AtDutyArea],
        ),
        NpcActionKey::TravelToLeisure => (
            request.leisure_anchor.clone(),
            request.leisure_object_id.clone(),
            Vec::new(),
        ),
        NpcActionKey::Relax => (
            request.leisure_anchor.clone(),
            request.leisure_object_id.clone(),
            Vec::new(),
        ),
        NpcActionKey::TravelHome => (request.home_anchor.clone(), None, vec![NpcFact::AtHome]),
        NpcActionKey::ReserveBed => (
            request.home_anchor.clone(),
            request.bed_id.clone(),
            Vec::new(),
        ),
        NpcActionKey::Sleep => (
            request.home_anchor.clone(),
            request.bed_id.clone(),
            vec![NpcFact::AtHome],
        ),
        NpcActionKey::RaiseAlarm => (request.alarm_anchor.clone(), None, Vec::new()),
        NpcActionKey::RespondAlarm => (
            request
                .duty_anchor
                .clone()
                .or_else(|| request.alarm_anchor.clone()),
            request.guard_post_id.clone(),
            vec![NpcFact::AtDutyArea],
        ),
        NpcActionKey::IdleSafely => (request.home_anchor.clone(), None, vec![NpcFact::AtHome]),
    };

    let (default_travel_minutes, perform_minutes) = action_timing(action);
    let travel_minutes =
        context.travel_minutes_to(target_anchor.as_deref(), default_travel_minutes);
    NpcPlanStep {
        action,
        target_anchor,
        reservation_target,
        travel_minutes,
        perform_minutes,
        expected_facts,
    }
}

pub fn action_name(action: NpcActionKey) -> &'static str {
    match action {
        NpcActionKey::TravelToDutyArea => "travel_to_duty_area",
        NpcActionKey::ReserveGuardPost => "reserve_guard_post",
        NpcActionKey::StandGuard => "stand_guard",
        NpcActionKey::PatrolRoute => "patrol_route",
        NpcActionKey::TravelToCanteen => "travel_to_canteen",
        NpcActionKey::EatMeal => "eat_meal",
        NpcActionKey::RestockMealService => "restock_meal_service",
        NpcActionKey::TreatPatients => "treat_patients",
        NpcActionKey::TravelToLeisure => "travel_to_leisure",
        NpcActionKey::Relax => "relax",
        NpcActionKey::TravelHome => "travel_home",
        NpcActionKey::ReserveBed => "reserve_bed",
        NpcActionKey::Sleep => "sleep",
        NpcActionKey::RaiseAlarm => "raise_alarm",
        NpcActionKey::RespondAlarm => "respond_alarm",
        NpcActionKey::IdleSafely => "idle_safely",
    }
}

pub fn parse_action_key(name: &str) -> Option<NpcActionKey> {
    Some(match name {
        "travel_to_duty_area" => NpcActionKey::TravelToDutyArea,
        "reserve_guard_post" => NpcActionKey::ReserveGuardPost,
        "stand_guard" => NpcActionKey::StandGuard,
        "patrol_route" => NpcActionKey::PatrolRoute,
        "travel_to_canteen" => NpcActionKey::TravelToCanteen,
        "eat_meal" => NpcActionKey::EatMeal,
        "restock_meal_service" => NpcActionKey::RestockMealService,
        "treat_patients" => NpcActionKey::TreatPatients,
        "travel_to_leisure" => NpcActionKey::TravelToLeisure,
        "relax" => NpcActionKey::Relax,
        "travel_home" => NpcActionKey::TravelHome,
        "reserve_bed" => NpcActionKey::ReserveBed,
        "sleep" => NpcActionKey::Sleep,
        "raise_alarm" => NpcActionKey::RaiseAlarm,
        "respond_alarm" => NpcActionKey::RespondAlarm,
        "idle_safely" => NpcActionKey::IdleSafely,
        _ => return None,
    })
}

fn action_timing(action: NpcActionKey) -> (u32, u32) {
    match action {
        NpcActionKey::TravelToDutyArea => (15, 0),
        NpcActionKey::ReserveGuardPost => (0, 0),
        NpcActionKey::StandGuard => (0, 60),
        NpcActionKey::PatrolRoute => (0, 120),
        NpcActionKey::TravelToCanteen => (15, 0),
        NpcActionKey::EatMeal => (0, 30),
        NpcActionKey::RestockMealService => (0, 45),
        NpcActionKey::TreatPatients => (0, 45),
        NpcActionKey::TravelToLeisure => (15, 0),
        NpcActionKey::Relax => (0, 60),
        NpcActionKey::TravelHome => (15, 0),
        NpcActionKey::ReserveBed => (0, 0),
        NpcActionKey::Sleep => (0, 480),
        NpcActionKey::RaiseAlarm => (5, 0),
        NpcActionKey::RespondAlarm => (10, 45),
        NpcActionKey::IdleSafely => (0, 30),
    }
}

fn fact_key(fact: NpcFact) -> &'static str {
    match fact {
        NpcFact::Hungry => "is_hungry",
        NpcFact::VeryHungry => "is_very_hungry",
        NpcFact::Sleepy => "sleepy",
        NpcFact::Exhausted => "exhausted",
        NpcFact::NeedMorale => "need_morale",
        NpcFact::OnShift => "on_shift",
        NpcFact::ShiftStartingSoon => "shift_starting_soon",
        NpcFact::ThreatDetected => "threat_detected",
        NpcFact::MealWindowOpen => "meal_window_open",
        NpcFact::AtHome => "at_home",
        NpcFact::AtDutyArea => "at_duty_area",
        NpcFact::HasReservedBed => "has_reserved_bed",
        NpcFact::HasReservedMealSeat => "has_reserved_meal_seat",
        NpcFact::GuardCoverageInsufficient => "guard_coverage_insufficient",
    }
}

fn common_life_actions(context: &NpcPlanningContext) -> Vec<Action> {
    let request = &context.request;
    let mut actions = Vec::new();

    if request.canteen_anchor.is_some()
        && context.is_anchor_reachable(request.canteen_anchor.as_deref())
    {
        let mut travel_to_canteen = Action::new(action_name(NpcActionKey::TravelToCanteen))
            .with_mutator(Mutator::set("at_canteen", true))
            .with_mutator(Mutator::set("at_home", false))
            .with_mutator(Mutator::set("at_duty_area", false))
            .with_mutator(Mutator::set("has_reserved_meal_seat", true))
            .set_cost(1);
        if request.role != NpcRole::Cook {
            travel_to_canteen =
                travel_to_canteen.with_precondition(("meal_window_open", Compare::equals(true)));
        } else {
            travel_to_canteen =
                travel_to_canteen.with_precondition(("on_shift", Compare::equals(true)));
        }
        actions.push(travel_to_canteen);

        actions.push(
            Action::new(action_name(NpcActionKey::EatMeal))
                .with_precondition(("at_canteen", Compare::equals(true)))
                .with_precondition(("has_reserved_meal_seat", Compare::equals(true)))
                .with_mutator(Mutator::set("is_hungry", false))
                .with_mutator(Mutator::set("is_very_hungry", false))
                .set_cost(2),
        );
    }

    if request.leisure_anchor.is_some()
        && context.is_anchor_reachable(request.leisure_anchor.as_deref())
    {
        actions.push(
            Action::new(action_name(NpcActionKey::TravelToLeisure))
                .with_mutator(Mutator::set("at_leisure", true))
                .with_mutator(Mutator::set("at_home", false))
                .set_cost(1),
        );
        actions.push(
            Action::new(action_name(NpcActionKey::Relax))
                .with_precondition(("at_leisure", Compare::equals(true)))
                .with_mutator(Mutator::set("need_morale", false))
                .with_mutator(Mutator::set("morale_recovered", true))
                .set_cost(2),
        );
    }

    if request.home_anchor.is_some() && context.is_anchor_reachable(request.home_anchor.as_deref())
    {
        actions.push(
            Action::new(action_name(NpcActionKey::TravelHome))
                .with_precondition(("at_home", Compare::not_equals(true)))
                .with_mutator(Mutator::set("at_home", true))
                .with_mutator(Mutator::set("at_duty_area", false))
                .with_mutator(Mutator::set("at_canteen", false))
                .with_mutator(Mutator::set("at_leisure", false))
                .set_cost(1),
        );
    }

    if request.bed_id.is_some() {
        actions.push(
            Action::new(action_name(NpcActionKey::ReserveBed))
                .with_precondition(("at_home", Compare::equals(true)))
                .with_mutator(Mutator::set("has_reserved_bed", true))
                .set_cost(1),
        );
        actions.push(
            Action::new(action_name(NpcActionKey::Sleep))
                .with_precondition(("at_home", Compare::equals(true)))
                .with_precondition(("has_reserved_bed", Compare::equals(true)))
                .with_mutator(Mutator::set("sleepy", false))
                .with_mutator(Mutator::set("exhausted", false))
                .with_mutator(Mutator::set("is_rested", true))
                .set_cost(2),
        );
    }

    if request.alarm_anchor.is_some()
        && context.is_anchor_reachable(request.alarm_anchor.as_deref())
    {
        actions.push(
            Action::new(action_name(NpcActionKey::RaiseAlarm))
                .with_precondition(("threat_detected", Compare::equals(true)))
                .with_mutator(Mutator::set("alarm_raised", true))
                .set_cost(1),
        );
        actions.push(
            Action::new(action_name(NpcActionKey::RespondAlarm))
                .with_precondition(("threat_detected", Compare::equals(true)))
                .with_mutator(Mutator::set("threat_detected", false))
                .with_mutator(Mutator::set("threat_resolved", true))
                .with_mutator(Mutator::set("at_duty_area", true))
                .set_cost(1),
        );
    }

    actions.push(
        Action::new(action_name(NpcActionKey::IdleSafely))
            .with_precondition(("at_home", Compare::equals(true)))
            .with_mutator(Mutator::set("is_idle_safe", true))
            .set_cost(3),
    );

    actions
}

fn guard_actions(request: &NpcPlanRequest) -> Vec<Action> {
    let mut actions = Vec::new();

    if request.guard_post_id.is_some() {
        actions.push(
            Action::new(action_name(NpcActionKey::ReserveGuardPost))
                .with_precondition(("at_duty_area", Compare::equals(true)))
                .with_mutator(Mutator::set("has_reserved_guard_post", true))
                .set_cost(1),
        );
        actions.push(
            Action::new(action_name(NpcActionKey::StandGuard))
                .with_precondition(("on_shift", Compare::equals(true)))
                .with_precondition(("at_duty_area", Compare::equals(true)))
                .with_precondition(("has_reserved_guard_post", Compare::equals(true)))
                .with_mutator(Mutator::set("guard_duty_satisfied", true))
                .with_mutator(Mutator::set("guard_coverage_secured", true))
                .set_cost(2),
        );
    }

    if request.patrol_route_id.is_some() {
        actions.push(
            Action::new(action_name(NpcActionKey::PatrolRoute))
                .with_precondition(("on_shift", Compare::equals(true)))
                .with_precondition(("at_duty_area", Compare::equals(true)))
                .with_mutator(Mutator::set("patrol_completed", true))
                .with_mutator(Mutator::set("guard_duty_satisfied", true))
                .set_cost(2),
        );
    }

    actions
}

fn cook_actions(context: &NpcPlanningContext) -> Vec<Action> {
    let request = &context.request;
    let mut actions = Vec::new();

    if request.role == NpcRole::Cook
        && request.canteen_anchor.is_some()
        && context.is_anchor_reachable(request.canteen_anchor.as_deref())
    {
        actions.push(
            Action::new(action_name(NpcActionKey::RestockMealService))
                .with_precondition(("on_shift", Compare::equals(true)))
                .with_precondition(("at_canteen", Compare::equals(true)))
                .with_mutator(Mutator::set("meal_service_restocked", true))
                .set_cost(2),
        );
    }

    actions
}

fn doctor_actions(request: &NpcPlanRequest) -> Vec<Action> {
    let mut actions = Vec::new();
    if request.role == NpcRole::Doctor && request.medical_station_id.is_some() {
        actions.push(
            Action::new(action_name(NpcActionKey::TreatPatients))
                .with_precondition(("on_shift", Compare::equals(true)))
                .with_precondition(("at_duty_area", Compare::equals(true)))
                .with_mutator(Mutator::set("patients_treated", true))
                .set_cost(2),
        );
    }
    actions
}
