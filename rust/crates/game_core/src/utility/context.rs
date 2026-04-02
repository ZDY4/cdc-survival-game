use std::collections::BTreeSet;

use game_data::{AiBehaviorProfile, NpcRole};

use crate::goap::{AiBlackboard, NpcFact, NpcPlanRequest};

#[derive(Debug, Clone, PartialEq, Default)]
pub struct NpcUtilityContext {
    pub role: NpcRole,
    pub behavior: AiBehaviorProfile,
    pub blackboard: AiBlackboard,
    facts: BTreeSet<NpcFact>,
}

impl NpcUtilityContext {
    pub fn from_plan_request(request: &NpcPlanRequest) -> Self {
        Self {
            role: request.role,
            behavior: request.behavior.clone(),
            blackboard: request.blackboard.clone(),
            facts: request.facts.iter().cloned().collect(),
        }
    }

    pub fn facts(&self) -> &BTreeSet<NpcFact> {
        &self.facts
    }

    pub fn has_fact(&self, fact: &NpcFact) -> bool {
        self.facts.contains(fact)
    }
}
