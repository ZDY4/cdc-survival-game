use std::collections::BTreeSet;

use game_data::NpcRole;

use crate::goap::{NpcFact, NpcPlanRequest};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NpcUtilityContext {
    pub role: NpcRole,
    facts: BTreeSet<NpcFact>,
}

impl NpcUtilityContext {
    pub fn from_plan_request(request: &NpcPlanRequest) -> Self {
        Self {
            role: request.role,
            facts: request.facts.iter().copied().collect(),
        }
    }

    pub fn has_fact(&self, fact: NpcFact) -> bool {
        self.facts.contains(&fact)
    }
}
