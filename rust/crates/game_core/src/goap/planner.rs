use dogoap::prelude::{format_plan, get_effects_from_plan, make_plan};

use super::actions::{
    build_action_set_for_context, build_start_state, parse_action_key, step_for_action_with_context,
};
use super::goals::goal_requirements;
use super::{NpcGoalKey, NpcPlanRequest, NpcPlanResult, NpcPlanningContext};
use crate::utility::{select_goal_for_context, NpcUtilityContext};

pub fn build_plan(request: &NpcPlanRequest) -> NpcPlanResult {
    let utility_context = NpcUtilityContext::from_plan_request(request);
    let selected_goal = select_goal_for_context(&utility_context);
    let planning_context = NpcPlanningContext::from_plan_request(request);
    build_plan_for_goal_with_context(&planning_context, selected_goal)
}

pub fn build_plan_for_context(context: &NpcPlanningContext) -> NpcPlanResult {
    let utility_context = NpcUtilityContext::from_plan_request(&context.request);
    let selected_goal = select_goal_for_context(&utility_context);
    build_plan_for_goal_with_context(context, selected_goal)
}

pub fn build_plan_for_goal(request: &NpcPlanRequest, selected_goal: NpcGoalKey) -> NpcPlanResult {
    let context = NpcPlanningContext::from_plan_request(request);
    build_plan_for_goal_with_context(&context, selected_goal)
}

pub fn build_plan_for_goal_with_context(
    context: &NpcPlanningContext,
    selected_goal: NpcGoalKey,
) -> NpcPlanResult {
    let start = build_start_state(&context.request);
    let goal = goal_requirements(&context.request, &selected_goal);
    let actions = build_action_set_for_context(context);

    if let Some(plan) = make_plan(&start, &actions, &goal) {
        let total_cost = plan.1;
        let debug_plan = format_plan(plan.clone());
        let mut steps = Vec::new();
        for effect in get_effects_from_plan(plan.0) {
            let action = parse_action_key(&effect.action);
            steps.push(step_for_action_with_context(&action, context));
        }

        NpcPlanResult {
            selected_goal,
            steps,
            total_cost,
            facts: context.request.facts.clone(),
            debug_plan,
            planned: true,
        }
    } else {
        NpcPlanResult {
            selected_goal,
            steps: Vec::new(),
            total_cost: 0,
            facts: context.request.facts.clone(),
            debug_plan: "no_plan".to_string(),
            planned: false,
        }
    }
}
