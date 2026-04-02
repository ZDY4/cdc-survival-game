use std::collections::BTreeSet;

use game_data::AiBehaviorProfile;

use super::behavior::{evaluate_condition, AiBlackboard};
use super::NpcFact;

pub fn rebuild_facts(
    behavior: &AiBehaviorProfile,
    blackboard: &AiBlackboard,
    role: game_data::NpcRole,
) -> Vec<NpcFact> {
    let mut active_facts = BTreeSet::new();
    for fact in &behavior.facts {
        if evaluate_condition(&fact.condition, behavior, &active_facts, blackboard, role) {
            active_facts.insert(NpcFact::from(fact.id.as_str().to_string()));
        }
    }
    active_facts.into_iter().collect()
}
