use std::collections::{BTreeMap, BTreeSet};

use game_data::{
    AiBehaviorProfile, AiComparisonOperator, AiConditionDefinition,
    AiConditionalPlannerRequirements, AiGoalDefinition, AiPlannerDatumAssignment, NpcRole,
};

use super::{NpcFact, NpcPlanRequest};

#[derive(Debug, Clone, PartialEq, Default)]
pub struct AiBlackboard {
    numbers: BTreeMap<String, f32>,
    booleans: BTreeMap<String, bool>,
    texts: BTreeMap<String, String>,
}

impl AiBlackboard {
    pub fn set_number(&mut self, key: impl Into<String>, value: f32) {
        self.numbers.insert(key.into(), value);
    }

    pub fn set_bool(&mut self, key: impl Into<String>, value: bool) {
        self.booleans.insert(key.into(), value);
    }

    pub fn set_text(&mut self, key: impl Into<String>, value: impl Into<String>) {
        self.texts.insert(key.into(), value.into());
    }

    pub fn set_optional_text(&mut self, key: impl Into<String>, value: Option<String>) {
        if let Some(value) = value {
            self.set_text(key, value);
        }
    }

    pub fn number(&self, key: &str) -> Option<f32> {
        self.numbers.get(key).copied()
    }

    pub fn boolean(&self, key: &str) -> Option<bool> {
        self.booleans.get(key).copied()
    }

    pub fn text(&self, key: &str) -> Option<&str> {
        self.texts.get(key).map(String::as_str)
    }
}

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

pub fn selected_goal_requirements(
    goal: &AiGoalDefinition,
    request: &NpcPlanRequest,
) -> Vec<AiPlannerDatumAssignment> {
    let facts = request.facts.iter().cloned().collect::<BTreeSet<_>>();
    let mut requirements = goal.planner_requirements.clone();

    if let Some(matched) = first_matching_requirement_set(
        &goal.conditional_requirements,
        &request.behavior,
        &facts,
        &request.blackboard,
        request.role,
    ) {
        requirements.extend(matched.requirements.clone());
    }

    requirements
}

fn first_matching_requirement_set<'a>(
    sets: &'a [AiConditionalPlannerRequirements],
    behavior: &AiBehaviorProfile,
    facts: &BTreeSet<NpcFact>,
    blackboard: &AiBlackboard,
    role: NpcRole,
) -> Option<&'a AiConditionalPlannerRequirements> {
    sets.iter().find(|entry| {
        entry
            .when
            .as_ref()
            .map(|condition| evaluate_condition(condition, behavior, facts, blackboard, role))
            .unwrap_or(true)
    })
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
