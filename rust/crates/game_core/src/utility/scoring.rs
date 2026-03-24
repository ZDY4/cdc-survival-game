use game_data::NpcRole;

use crate::goap::{NpcFact, NpcGoalKey, NpcPlanRequest};

use super::context::NpcUtilityContext;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NpcGoalScore {
    pub goal: NpcGoalKey,
    pub score: i32,
}

pub fn score_goals(request: &NpcPlanRequest) -> Vec<NpcGoalScore> {
    let context = NpcUtilityContext::from_plan_request(request);
    score_goals_for_context(&context)
}

pub fn score_goals_for_context(context: &NpcUtilityContext) -> Vec<NpcGoalScore> {
    [
        NpcGoalKey::RespondThreat,
        NpcGoalKey::PreserveLife,
        NpcGoalKey::SatisfyShift,
        NpcGoalKey::EatMeal,
        NpcGoalKey::Sleep,
        NpcGoalKey::RecoverMorale,
        NpcGoalKey::ReturnHome,
        NpcGoalKey::IdleSafely,
    ]
    .into_iter()
    .map(|goal| NpcGoalScore {
        goal,
        score: score_goal_for_context(context, goal),
    })
    .collect()
}

pub fn score_goal(request: &NpcPlanRequest, goal: NpcGoalKey) -> i32 {
    let context = NpcUtilityContext::from_plan_request(request);
    score_goal_for_context(&context, goal)
}

pub fn score_goal_for_context(context: &NpcUtilityContext, goal: NpcGoalKey) -> i32 {
    base_score(context, goal) + role_goal_modifier(context.role, goal)
}

fn base_score(context: &NpcUtilityContext, goal: NpcGoalKey) -> i32 {
    match goal {
        NpcGoalKey::RespondThreat => {
            if context.has_fact(NpcFact::ThreatDetected) {
                1000
            } else {
                0
            }
        }
        NpcGoalKey::PreserveLife => {
            if context.has_fact(NpcFact::VeryHungry) || context.has_fact(NpcFact::Exhausted) {
                900
            } else {
                0
            }
        }
        NpcGoalKey::SatisfyShift => {
            if context.has_fact(NpcFact::OnShift) || context.has_fact(NpcFact::ShiftStartingSoon) {
                800
            } else {
                0
            }
        }
        NpcGoalKey::EatMeal => {
            if context.has_fact(NpcFact::Hungry) && context.has_fact(NpcFact::MealWindowOpen) {
                700
            } else {
                0
            }
        }
        NpcGoalKey::Sleep => {
            if context.has_fact(NpcFact::Sleepy) {
                600
            } else {
                0
            }
        }
        NpcGoalKey::RecoverMorale => {
            if context.has_fact(NpcFact::NeedMorale) {
                500
            } else {
                0
            }
        }
        NpcGoalKey::ReturnHome => {
            if !context.has_fact(NpcFact::AtHome) {
                400
            } else {
                0
            }
        }
        NpcGoalKey::IdleSafely => 100,
    }
}

fn role_goal_modifier(role: NpcRole, goal: NpcGoalKey) -> i32 {
    match role {
        NpcRole::Guard => match goal {
            NpcGoalKey::RespondThreat => 50,
            NpcGoalKey::SatisfyShift => 40,
            _ => 0,
        },
        NpcRole::Cook => match goal {
            NpcGoalKey::SatisfyShift => 60,
            NpcGoalKey::EatMeal => -20,
            NpcGoalKey::RecoverMorale => -20,
            _ => 0,
        },
        NpcRole::Doctor => match goal {
            NpcGoalKey::SatisfyShift => 30,
            _ => 0,
        },
        NpcRole::Resident => 0,
    }
}
