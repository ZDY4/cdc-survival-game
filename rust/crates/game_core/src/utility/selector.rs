use crate::goap::{NpcGoalKey, NpcPlanRequest};

use super::context::NpcUtilityContext;
use super::scoring::score_goals_for_context;

pub fn select_goal(request: &NpcPlanRequest) -> NpcGoalKey {
    let context = NpcUtilityContext::from_plan_request(request);
    select_goal_for_context(&context)
}

pub fn select_goal_for_context(context: &NpcUtilityContext) -> NpcGoalKey {
    score_goals_for_context(context)
        .into_iter()
        .max_by(|left, right| {
            left.score
                .cmp(&right.score)
                .then_with(|| right.goal.as_str().cmp(left.goal.as_str()))
        })
        .map(|entry| entry.goal)
        .or_else(|| {
            context
                .behavior
                .default_goal_id
                .clone()
                .map(|goal| NpcGoalKey::from(goal.as_str().to_string()))
        })
        .unwrap_or_else(|| NpcGoalKey::from("idle_safely"))
}
