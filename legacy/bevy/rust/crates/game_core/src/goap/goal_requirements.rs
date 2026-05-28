//! GOAP 目标需求展开模块。
//! 负责把选中 goal 展开为规划要求，不负责条件定义本身或规划执行。

use std::collections::BTreeSet;

use game_data::{
    AiBehaviorProfile, AiConditionalPlannerRequirements, AiGoalDefinition,
    AiPlannerDatumAssignment, NpcRole,
};

use super::{evaluate_condition, AiBlackboard, NpcFact, NpcPlanRequest};

pub fn selected_goal_requirements(
    goal: &AiGoalDefinition,
    request: &NpcPlanRequest,
) -> Vec<AiPlannerDatumAssignment> {
    let facts = request.facts.iter().cloned().collect::<BTreeSet<_>>();
    let mut requirements = goal.planner_requirements.clone();

    if let Some(matched) = first_matching_requirement_set(
        &goal.conditional_requirements,
        &request.behavior,
        &facts,
        &request.blackboard,
        request.role,
    ) {
        requirements.extend(matched.requirements.clone());
    }

    requirements
}

fn first_matching_requirement_set<'a>(
    sets: &'a [AiConditionalPlannerRequirements],
    behavior: &AiBehaviorProfile,
    facts: &BTreeSet<NpcFact>,
    blackboard: &AiBlackboard,
    role: NpcRole,
) -> Option<&'a AiConditionalPlannerRequirements> {
    sets.iter().find(|entry| {
        entry
            .when
            .as_ref()
            .map(|condition| evaluate_condition(condition, behavior, facts, blackboard, role))
            .unwrap_or(true)
    })
}
