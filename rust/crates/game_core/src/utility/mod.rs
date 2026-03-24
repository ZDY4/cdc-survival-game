pub mod context;
pub mod scoring;
pub mod selector;

pub use context::NpcUtilityContext;
pub use scoring::{
    score_goal, score_goal_for_context, score_goals, score_goals_for_context, NpcGoalScore,
};
pub use selector::{select_goal, select_goal_for_context};

#[cfg(test)]
mod tests {
    use game_data::NpcRole;

    use super::{score_goals, score_goals_for_context, select_goal, NpcUtilityContext};
    use crate::goap::{NpcFact, NpcGoalKey, NpcPlanRequest};

    #[test]
    fn select_goal_prioritizes_threats_over_needs() {
        let goal = select_goal(&NpcPlanRequest {
            role: NpcRole::Guard,
            facts: vec![
                NpcFact::ThreatDetected,
                NpcFact::Hungry,
                NpcFact::MealWindowOpen,
            ],
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

        assert!(scores
            .iter()
            .any(|entry| entry.goal == NpcGoalKey::IdleSafely));
    }

    #[test]
    fn select_goal_prefers_shift_over_meal_for_cook() {
        let goal = select_goal(&NpcPlanRequest {
            role: NpcRole::Cook,
            facts: vec![NpcFact::OnShift, NpcFact::Hungry, NpcFact::MealWindowOpen],
            ..NpcPlanRequest::default()
        });

        assert_eq!(goal, NpcGoalKey::SatisfyShift);
    }

    #[test]
    fn context_scoring_matches_request_scoring() {
        let request = NpcPlanRequest {
            role: NpcRole::Guard,
            facts: vec![NpcFact::OnShift, NpcFact::ThreatDetected],
            ..NpcPlanRequest::default()
        };
        let context = NpcUtilityContext::from_plan_request(&request);
        let request_scores = score_goals(&request);
        let context_scores = score_goals_for_context(&context);

        assert_eq!(request_scores, context_scores);
    }
}
