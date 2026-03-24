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
        .max_by_key(|entry| entry.score)
        .map(|entry| entry.goal)
        .unwrap_or(NpcGoalKey::IdleSafely)
}
