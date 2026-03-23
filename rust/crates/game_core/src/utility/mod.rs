use crate::goap::{NpcFact, NpcGoalKey, NpcPlanRequest};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct NpcGoalScore {
    pub goal: NpcGoalKey,
    pub score: i32,
}

pub fn select_goal(request: &NpcPlanRequest) -> NpcGoalKey {
    score_goals(request)
        .into_iter()
        .max_by_key(|entry| entry.score)
        .map(|entry| entry.goal)
        .unwrap_or(NpcGoalKey::IdleSafely)
}

pub fn score_goals(request: &NpcPlanRequest) -> Vec<NpcGoalScore> {
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
        score: score_goal(request, goal),
    })
    .collect()
}

pub fn score_goal(request: &NpcPlanRequest, goal: NpcGoalKey) -> i32 {
    match goal {
        NpcGoalKey::RespondThreat => {
            if has_fact(request, NpcFact::ThreatDetected) {
                1000
            } else {
                0
            }
        }
        NpcGoalKey::PreserveLife => {
            if has_fact(request, NpcFact::VeryHungry) || has_fact(request, NpcFact::Exhausted) {
                900
            } else {
                0
            }
        }
        NpcGoalKey::SatisfyShift => {
            if has_fact(request, NpcFact::OnShift) || has_fact(request, NpcFact::ShiftStartingSoon)
            {
                800
            } else {
                0
            }
        }
        NpcGoalKey::EatMeal => {
            if has_fact(request, NpcFact::Hungry) && has_fact(request, NpcFact::MealWindowOpen) {
                700
            } else {
                0
            }
        }
        NpcGoalKey::Sleep => {
            if has_fact(request, NpcFact::Sleepy) {
                600
            } else {
                0
            }
        }
        NpcGoalKey::RecoverMorale => {
            if has_fact(request, NpcFact::NeedMorale) {
                500
            } else {
                0
            }
        }
        NpcGoalKey::ReturnHome => {
            if !has_fact(request, NpcFact::AtHome) {
                400
            } else {
                0
            }
        }
        NpcGoalKey::IdleSafely => 100,
    }
}

fn has_fact(request: &NpcPlanRequest, fact: NpcFact) -> bool {
    request.facts.contains(&fact)
}

#[cfg(test)]
mod tests {
    use game_data::NpcRole;

    use super::{score_goals, select_goal};
    use crate::goap::{NpcFact, NpcGoalKey, NpcPlanRequest};

    #[test]
    fn select_goal_prioritizes_threats_over_needs() {
        let goal = select_goal(&NpcPlanRequest {
            role: NpcRole::Guard,
            facts: vec![NpcFact::ThreatDetected, NpcFact::Hungry, NpcFact::MealWindowOpen],
            ..NpcPlanRequest::default()
        });

        assert_eq!(goal, NpcGoalKey::RespondThreat);
    }

    #[test]
    fn select_goal_prefers_shift_over_meal() {
        let goal = select_goal(&NpcPlanRequest {
            role: NpcRole::Guard,
            facts: vec![NpcFact::OnShift, NpcFact::Hungry, NpcFact::MealWindowOpen],
            ..NpcPlanRequest::default()
        });

        assert_eq!(goal, NpcGoalKey::SatisfyShift);
    }

    #[test]
    fn score_goals_always_includes_idle_fallback() {
        let scores = score_goals(&NpcPlanRequest {
            role: NpcRole::Resident,
            ..NpcPlanRequest::default()
        });

        assert!(scores.iter().any(|entry| entry.goal == NpcGoalKey::IdleSafely));
    }
}
