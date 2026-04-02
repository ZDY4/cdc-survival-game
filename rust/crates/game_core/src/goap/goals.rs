use dogoap::prelude::{Compare, Goal};
use game_data::AiGoalDefinition;

use super::behavior::selected_goal_requirements;
use super::{NpcGoalKey, NpcPlanRequest};

pub fn goal_requirements(request: &NpcPlanRequest, goal: &NpcGoalKey) -> Goal {
    let Some(goal_definition) = find_goal_definition(request, goal) else {
        return Goal::new();
    };

    let mut goal_state = Goal::new();
    for requirement in selected_goal_requirements(goal_definition, request) {
        goal_state = goal_state.with_req(requirement.key, Compare::equals(requirement.value));
    }
    goal_state
}

fn find_goal_definition<'a>(
    request: &'a NpcPlanRequest,
    goal: &NpcGoalKey,
) -> Option<&'a AiGoalDefinition> {
    request
        .behavior
        .goals
        .iter()
        .find(|entry| entry.id.as_str() == goal.as_str())
}
