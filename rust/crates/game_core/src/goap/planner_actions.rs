//! GOAP 规划动作映射模块。
//! 负责 dogoap action 集合和计划步骤映射，不负责目标选择或执行阶段推进。

use std::borrow::Cow;

use dogoap::prelude::{Action, Compare, LocalState, Mutator};
use game_data::{
    AiActionDefinition, AiAnchorBinding, AiGoalDefinition, AiReservationBinding,
    BuiltinAiExecutorKind,
};

use super::{NpcActionKey, NpcFact, NpcPlanRequest, NpcPlanStep, NpcPlanningContext};

pub fn build_action_set(request: &NpcPlanRequest) -> Vec<Action> {
    let context = NpcPlanningContext::from_plan_request(request);
    build_action_set_for_context(&context)
}

pub fn build_action_set_for_context(context: &NpcPlanningContext) -> Vec<Action> {
    let request = &context.request;
    request
        .behavior
        .actions
        .iter()
        .filter(|action| {
            context.is_anchor_reachable(
                resolve_target_anchor(request, action.target_anchor.as_ref()).as_deref(),
            )
        })
        .map(build_action)
        .collect()
}

pub fn build_start_state(request: &NpcPlanRequest) -> LocalState {
    let mut state = LocalState::new();

    for key in planner_keys(request) {
        state = state.with_datum(key, false);
    }

    for fact in &request.facts {
        state = state.with_datum(planner_state_key_for_fact(fact), true);
    }

    state
}

pub fn step_for_action(action: &NpcActionKey, request: &NpcPlanRequest) -> NpcPlanStep {
    let context = NpcPlanningContext::from_plan_request(request);
    step_for_action_with_context(action, &context)
}

pub fn step_for_action_with_context(
    action: &NpcActionKey,
    context: &NpcPlanningContext,
) -> NpcPlanStep {
    let request = &context.request;
    let definition = request
        .behavior
        .actions
        .iter()
        .find(|entry| entry.id.as_str() == action.as_str())
        .expect("action definition should exist for planned action");

    let target_anchor = resolve_target_anchor(request, definition.target_anchor.as_ref());
    let reservation_target =
        resolve_reservation_target(request, definition.reservation_target.as_ref());
    let travel_minutes =
        context.travel_minutes_to(target_anchor.as_deref(), definition.default_travel_minutes);
    let executor_kind = request
        .behavior
        .executors
        .get(&definition.executor_binding_id)
        .map(|entry| entry.kind.clone())
        .unwrap_or(BuiltinAiExecutorKind::IdleAtAnchor);

    NpcPlanStep {
        action: action.clone(),
        target_anchor,
        reservation_target,
        travel_minutes,
        perform_minutes: definition.perform_minutes,
        expected_facts: definition
            .expected_fact_ids
            .iter()
            .map(|fact_id| NpcFact::from(fact_id.as_str().to_string()))
            .collect(),
        executor_kind,
        need_effects: definition.need_effects.clone(),
        world_state_effects: definition.world_state_effects.clone(),
    }
}

pub fn action_name(action: &NpcActionKey) -> &str {
    action.as_str()
}

pub fn parse_action_key(name: &str) -> NpcActionKey {
    NpcActionKey::from(name)
}

fn build_action(definition: &AiActionDefinition) -> Action {
    let mut action = Action::new(definition.id.as_str());
    for precondition in &definition.preconditions {
        action = action.with_precondition((
            precondition.key.as_str(),
            Compare::equals(precondition.value),
        ));
    }
    for effect in &definition.effects {
        action = action.with_mutator(Mutator::set(effect.key.as_str(), effect.value));
    }
    action.set_cost(definition.planner_cost)
}

fn planner_keys(request: &NpcPlanRequest) -> Vec<&str> {
    let mut keys = Vec::new();

    for goal in &request.behavior.goals {
        collect_goal_keys(goal, &mut keys);
    }

    for action in &request.behavior.actions {
        for precondition in &action.preconditions {
            keys.push(precondition.key.as_str());
        }
        for effect in &action.effects {
            keys.push(effect.key.as_str());
        }
    }

    keys.sort_unstable();
    keys.dedup();
    keys
}

fn collect_goal_keys<'a>(goal: &'a AiGoalDefinition, keys: &mut Vec<&'a str>) {
    for requirement in &goal.planner_requirements {
        keys.push(requirement.key.as_str());
    }
    for conditional in &goal.conditional_requirements {
        for requirement in &conditional.requirements {
            keys.push(requirement.key.as_str());
        }
    }
}

fn planner_state_key_for_fact(fact: &NpcFact) -> Cow<'static, str> {
    match fact.as_str() {
        "hungry" => Cow::Borrowed("is_hungry"),
        "very_hungry" => Cow::Borrowed("is_very_hungry"),
        other => Cow::Owned(other.to_string()),
    }
}

fn resolve_target_anchor(
    request: &NpcPlanRequest,
    binding: Option<&AiAnchorBinding>,
) -> Option<String> {
    match binding {
        Some(AiAnchorBinding::Home) => request.home_anchor.clone(),
        Some(AiAnchorBinding::Duty) => request.duty_anchor.clone(),
        Some(AiAnchorBinding::Canteen) => request.canteen_anchor.clone(),
        Some(AiAnchorBinding::Leisure) => request.leisure_anchor.clone(),
        Some(AiAnchorBinding::Alarm) => request.alarm_anchor.clone(),
        None => None,
    }
}

fn resolve_reservation_target(
    request: &NpcPlanRequest,
    binding: Option<&AiReservationBinding>,
) -> Option<String> {
    match binding {
        Some(AiReservationBinding::GuardPost) => request.guard_post_id.clone(),
        Some(AiReservationBinding::Bed) => request.bed_id.clone(),
        Some(AiReservationBinding::MealObject) => request.meal_object_id.clone(),
        Some(AiReservationBinding::LeisureObject) => request.leisure_object_id.clone(),
        Some(AiReservationBinding::MedicalStation) => request.medical_station_id.clone(),
        None => None,
    }
}
