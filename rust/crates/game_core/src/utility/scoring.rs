use crate::goap::behavior::evaluate_condition;
use crate::goap::{NpcGoalKey, NpcGoalScore, NpcPlanRequest};

use super::context::NpcUtilityContext;

pub fn score_goals(request: &NpcPlanRequest) -> Vec<NpcGoalScore> {
    let context = NpcUtilityContext::from_plan_request(request);
    score_goals_for_context(&context)
}

pub fn score_goals_for_context(context: &NpcUtilityContext) -> Vec<NpcGoalScore> {
    context
        .behavior
        .goals
        .iter()
        .map(|goal| {
            let mut matched_rule_ids = Vec::new();
            let mut score = 0;
            for score_rule_id in &goal.score_rule_ids {
                let Some(score_rule) = context.behavior.score_rules.get(score_rule_id) else {
                    continue;
                };
                let matched = score_rule
                    .when
                    .as_ref()
                    .map(|condition| {
                        evaluate_condition(
                            condition,
                            &context.behavior,
                            context.facts(),
                            &context.blackboard,
                            context.role,
                        )
                    })
                    .unwrap_or(true);
                if matched {
                    score += score_rule.score_delta;
                    matched_rule_ids.push(score_rule.id.as_str().to_string());
                }
            }
            NpcGoalScore {
                goal: NpcGoalKey::from(goal.id.as_str().to_string()),
                score,
                matched_rule_ids,
            }
        })
        .collect()
}

pub fn score_goal(request: &NpcPlanRequest, goal: &NpcGoalKey) -> i32 {
    let context = NpcUtilityContext::from_plan_request(request);
    score_goal_for_context(&context, goal)
}

pub fn score_goal_for_context(context: &NpcUtilityContext, goal: &NpcGoalKey) -> i32 {
    score_goals_for_context(context)
        .into_iter()
        .find(|entry| entry.goal == *goal)
        .map(|entry| entry.score)
        .unwrap_or_default()
}
