//! GOAP 事实重建模块。
//! 负责根据 blackboard 和条件集重建活动 facts，不负责目标打分或动作规划。

use std::collections::BTreeSet;

use game_data::AiBehaviorProfile;

use super::{evaluate_condition, AiBlackboard, NpcFact};

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
