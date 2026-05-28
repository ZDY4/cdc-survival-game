//! GOAP 条件求值模块。
//! 负责 blackboard、facts 和 role 条件解释，不负责目标打分或规划执行。

use std::collections::BTreeSet;

use game_data::{AiBehaviorProfile, AiComparisonOperator, AiConditionDefinition, NpcRole};

use super::{AiBlackboard, NpcFact};

pub fn evaluate_condition(
    condition: &AiConditionDefinition,
    behavior: &AiBehaviorProfile,
    facts: &BTreeSet<NpcFact>,
    blackboard: &AiBlackboard,
    role: NpcRole,
) -> bool {
    match condition {
        AiConditionDefinition::ConditionRef { condition_id } => behavior
            .conditions
            .get(condition_id)
            .map(|definition| {
                evaluate_condition(&definition.condition, behavior, facts, blackboard, role)
            })
            .unwrap_or(false),
        AiConditionDefinition::FactTrue { fact_id } => {
            facts.contains(&NpcFact::from(fact_id.as_str().to_string()))
        }
        AiConditionDefinition::BoolEquals { key, value } => {
            blackboard.boolean(key).unwrap_or(false) == *value
        }
        AiConditionDefinition::NumberCompare { key, op, value } => {
            let Some(number) = blackboard.number(key) else {
                return false;
            };
            compare_number(number, *op, *value)
        }
        AiConditionDefinition::TextEquals { key, value } => {
            blackboard.text(key).is_some_and(|current| current == value)
        }
        AiConditionDefinition::TextKeyEquals {
            left_key,
            right_key,
        } => match (blackboard.text(left_key), blackboard.text(right_key)) {
            (Some(left), Some(right)) => left == right,
            _ => false,
        },
        AiConditionDefinition::RoleIs {
            role: expected_role,
        } => role == *expected_role,
        AiConditionDefinition::AllOf { conditions } => conditions
            .iter()
            .all(|child| evaluate_condition(child, behavior, facts, blackboard, role)),
        AiConditionDefinition::AnyOf { conditions } => conditions
            .iter()
            .any(|child| evaluate_condition(child, behavior, facts, blackboard, role)),
        AiConditionDefinition::Not { condition } => {
            !evaluate_condition(condition, behavior, facts, blackboard, role)
        }
    }
}

fn compare_number(left: f32, op: AiComparisonOperator, right: f32) -> bool {
    match op {
        AiComparisonOperator::LessThan => left < right,
        AiComparisonOperator::LessThanOrEqual => left <= right,
        AiComparisonOperator::Equal => (left - right).abs() <= f32::EPSILON,
        AiComparisonOperator::GreaterThanOrEqual => left >= right,
        AiComparisonOperator::GreaterThan => left > right,
    }
}
