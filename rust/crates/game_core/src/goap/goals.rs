use dogoap::prelude::{Compare, Goal};
use game_data::NpcRole;

use super::{NpcFact, NpcGoalKey, NpcPlanRequest};

pub fn goal_requirements(request: &NpcPlanRequest, goal: NpcGoalKey) -> Goal {
    match goal {
        NpcGoalKey::RespondThreat => Goal::new().with_req("threat_resolved", Compare::equals(true)),
        NpcGoalKey::PreserveLife => {
            if has_fact(request, NpcFact::VeryHungry) || has_fact(request, NpcFact::Hungry) {
                Goal::new().with_req("is_hungry", Compare::equals(false))
            } else {
                Goal::new().with_req("is_rested", Compare::equals(true))
            }
        }
        NpcGoalKey::SatisfyShift => match request.role {
            NpcRole::Guard => {
                if has_fact(request, NpcFact::GuardCoverageInsufficient)
                    || request.patrol_route_id.is_none()
                {
                    Goal::new().with_req("guard_coverage_secured", Compare::equals(true))
                } else {
                    Goal::new().with_req("patrol_completed", Compare::equals(true))
                }
            }
            NpcRole::Cook => Goal::new().with_req("meal_service_restocked", Compare::equals(true)),
            NpcRole::Doctor => Goal::new().with_req("patients_treated", Compare::equals(true)),
            NpcRole::Resident => Goal::new().with_req("at_duty_area", Compare::equals(true)),
        },
        NpcGoalKey::EatMeal => Goal::new().with_req("is_hungry", Compare::equals(false)),
        NpcGoalKey::Sleep => Goal::new().with_req("is_rested", Compare::equals(true)),
        NpcGoalKey::RecoverMorale => {
            Goal::new().with_req("morale_recovered", Compare::equals(true))
        }
        NpcGoalKey::ReturnHome => Goal::new().with_req("at_home", Compare::equals(true)),
        NpcGoalKey::IdleSafely => Goal::new().with_req("is_idle_safe", Compare::equals(true)),
    }
}

fn has_fact(request: &NpcPlanRequest, fact: NpcFact) -> bool {
    request.facts.contains(&fact)
}
