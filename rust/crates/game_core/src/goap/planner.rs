use dogoap::prelude::{format_plan, get_effects_from_plan, make_plan};

use super::actions::{build_action_set, build_start_state, parse_action_key, step_for_action};
use super::goals::goal_requirements;
use super::{NpcGoalKey, NpcPlanRequest, NpcPlanResult};
use crate::utility::select_goal;

pub fn build_plan(request: &NpcPlanRequest) -> NpcPlanResult {
    let selected_goal = select_goal(request);
    build_plan_for_goal(request, selected_goal)
}

pub fn build_plan_for_goal(request: &NpcPlanRequest, selected_goal: NpcGoalKey) -> NpcPlanResult {
    let start = build_start_state(request);
    let goal = goal_requirements(request, selected_goal);
    let actions = build_action_set(request);

    if let Some(plan) = make_plan(&start, &actions, &goal) {
        let total_cost = plan.1;
        let debug_plan = format_plan(plan.clone());
        let mut steps = Vec::new();
        for effect in get_effects_from_plan(plan.0) {
            if let Some(action) = parse_action_key(&effect.action) {
                steps.push(step_for_action(action, request));
            }
        }

        NpcPlanResult {
            selected_goal,
            steps,
            total_cost,
            facts: request.facts.clone(),
            debug_plan,
            planned: true,
        }
    } else {
        NpcPlanResult {
            selected_goal,
            steps: Vec::new(),
            total_cost: 0,
            facts: request.facts.clone(),
            debug_plan: "no_plan".to_string(),
            planned: false,
        }
    }
}
