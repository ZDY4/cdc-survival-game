use std::borrow::Cow;
use std::collections::{BTreeMap, BTreeSet};
use std::fmt;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::NpcRole;

macro_rules! ai_id_type {
    ($name:ident) => {
        #[derive(Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize, Default)]
        #[serde(transparent)]
        pub struct $name(pub Cow<'static, str>);

        impl $name {
            pub fn as_str(&self) -> &str {
                self.0.as_ref()
            }
        }

        impl fmt::Debug for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(self.as_str())
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(self.as_str())
            }
        }

        impl From<&str> for $name {
            fn from(value: &str) -> Self {
                Self(Cow::Owned(value.to_string()))
            }
        }

        impl From<String> for $name {
            fn from(value: String) -> Self {
                Self(Cow::Owned(value))
            }
        }
    };
}

ai_id_type!(AiConditionId);
ai_id_type!(AiFactId);
ai_id_type!(AiScoreRuleId);
ai_id_type!(AiGoalId);
ai_id_type!(AiActionId);
ai_id_type!(AiExecutorBindingId);
ai_id_type!(AiBehaviorProfileRef);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AiComparisonOperator {
    LessThan,
    LessThanOrEqual,
    Equal,
    GreaterThanOrEqual,
    GreaterThan,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "snake_case")]
pub enum AiConditionDefinition {
    ConditionRef {
        condition_id: AiConditionId,
    },
    FactTrue {
        fact_id: AiFactId,
    },
    BoolEquals {
        key: String,
        value: bool,
    },
    NumberCompare {
        key: String,
        op: AiComparisonOperator,
        value: f32,
    },
    TextEquals {
        key: String,
        value: String,
    },
    TextKeyEquals {
        left_key: String,
        right_key: String,
    },
    RoleIs {
        role: NpcRole,
    },
    AllOf {
        conditions: Vec<AiConditionDefinition>,
    },
    AnyOf {
        conditions: Vec<AiConditionDefinition>,
    },
    Not {
        condition: Box<AiConditionDefinition>,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiConditionModuleDefinition {
    pub id: AiConditionId,
    pub condition: AiConditionDefinition,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiFactModuleDefinition {
    pub id: AiFactId,
    pub condition: AiConditionDefinition,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiScoreRuleDefinition {
    pub id: AiScoreRuleId,
    #[serde(default)]
    pub when: Option<AiConditionDefinition>,
    pub score_delta: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AiPlannerDatumAssignment {
    pub key: String,
    pub value: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiConditionalPlannerRequirements {
    #[serde(default)]
    pub when: Option<AiConditionDefinition>,
    #[serde(default)]
    pub requirements: Vec<AiPlannerDatumAssignment>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AiAnchorBinding {
    Home,
    Duty,
    Canteen,
    Leisure,
    Alarm,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AiReservationBinding {
    GuardPost,
    Bed,
    MealObject,
    LeisureObject,
    MedicalStation,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum BuiltinAiExecutorKind {
    TravelToAnchor,
    UseSmartObject,
    FollowPatrolRoute,
    IdleAtAnchor,
    ResolveAlarm,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiExecutorBindingDefinition {
    pub id: AiExecutorBindingId,
    pub kind: BuiltinAiExecutorKind,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct AiNeedEffectDefinition {
    #[serde(default)]
    pub hunger_delta: f32,
    #[serde(default)]
    pub energy_delta: f32,
    #[serde(default)]
    pub morale_delta: f32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct AiWorldStateEffectDefinition {
    #[serde(default)]
    pub set_world_alert_active: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiActionDefinition {
    pub id: AiActionId,
    #[serde(default)]
    pub preconditions: Vec<AiPlannerDatumAssignment>,
    #[serde(default)]
    pub effects: Vec<AiPlannerDatumAssignment>,
    pub planner_cost: usize,
    #[serde(default)]
    pub target_anchor: Option<AiAnchorBinding>,
    #[serde(default)]
    pub reservation_target: Option<AiReservationBinding>,
    pub executor_binding_id: AiExecutorBindingId,
    #[serde(default)]
    pub default_travel_minutes: u32,
    #[serde(default)]
    pub perform_minutes: u32,
    #[serde(default)]
    pub expected_fact_ids: Vec<AiFactId>,
    #[serde(default)]
    pub need_effects: AiNeedEffectDefinition,
    #[serde(default)]
    pub world_state_effects: AiWorldStateEffectDefinition,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiGoalDefinition {
    pub id: AiGoalId,
    #[serde(default)]
    pub score_rule_ids: Vec<AiScoreRuleId>,
    #[serde(default)]
    pub planner_requirements: Vec<AiPlannerDatumAssignment>,
    #[serde(default)]
    pub conditional_requirements: Vec<AiConditionalPlannerRequirements>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AiBehaviorDefinition {
    pub id: AiBehaviorProfileRef,
    #[serde(default)]
    pub fact_ids: Vec<AiFactId>,
    #[serde(default)]
    pub goal_ids: Vec<AiGoalId>,
    #[serde(default)]
    pub action_ids: Vec<AiActionId>,
    #[serde(default)]
    pub default_goal_id: Option<AiGoalId>,
    #[serde(default)]
    pub alert_goal_id: Option<AiGoalId>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct AiModulePack {
    #[serde(default)]
    pub conditions: Vec<AiConditionModuleDefinition>,
    #[serde(default)]
    pub facts: Vec<AiFactModuleDefinition>,
    #[serde(default)]
    pub score_rules: Vec<AiScoreRuleDefinition>,
    #[serde(default)]
    pub goals: Vec<AiGoalDefinition>,
    #[serde(default)]
    pub actions: Vec<AiActionDefinition>,
    #[serde(default)]
    pub executors: Vec<AiExecutorBindingDefinition>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct AiModuleLibrary {
    pub conditions: BTreeMap<AiConditionId, AiConditionModuleDefinition>,
    pub facts: BTreeMap<AiFactId, AiFactModuleDefinition>,
    pub score_rules: BTreeMap<AiScoreRuleId, AiScoreRuleDefinition>,
    pub goals: BTreeMap<AiGoalId, AiGoalDefinition>,
    pub actions: BTreeMap<AiActionId, AiActionDefinition>,
    pub executors: BTreeMap<AiExecutorBindingId, AiExecutorBindingDefinition>,
    pub behaviors: BTreeMap<AiBehaviorProfileRef, AiBehaviorDefinition>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct AiBehaviorProfile {
    pub id: AiBehaviorProfileRef,
    pub facts: Vec<AiFactModuleDefinition>,
    pub goals: Vec<AiGoalDefinition>,
    pub actions: Vec<AiActionDefinition>,
    pub score_rules: BTreeMap<AiScoreRuleId, AiScoreRuleDefinition>,
    pub executors: BTreeMap<AiExecutorBindingId, AiExecutorBindingDefinition>,
    pub conditions: BTreeMap<AiConditionId, AiConditionModuleDefinition>,
    pub default_goal_id: Option<AiGoalId>,
    pub alert_goal_id: Option<AiGoalId>,
}

#[derive(Debug, Error)]
pub enum AiModuleLoadError {
    #[error("failed to read AI directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read AI file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse AI file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("invalid AI module library: {source}")]
    InvalidDefinition {
        #[from]
        source: AiModuleValidationError,
    },
}

#[derive(Debug, Clone, Error, PartialEq, Eq)]
pub enum AiModuleValidationError {
    #[error("duplicate AI module id {id} found in {domain}")]
    DuplicateId { domain: &'static str, id: String },
    #[error("AI behavior {behavior_id} references missing {domain} {id}")]
    MissingReference {
        behavior_id: String,
        domain: &'static str,
        id: String,
    },
    #[error("AI goal {goal_id} references missing score rule {rule_id}")]
    MissingGoalScoreRule { goal_id: String, rule_id: String },
    #[error("AI action {action_id} references missing executor binding {executor_id}")]
    MissingActionExecutor {
        action_id: String,
        executor_id: String,
    },
    #[error("AI condition reference {condition_id} is missing")]
    MissingConditionReference { condition_id: String },
    #[error("AI condition reference cycle detected at {condition_id}")]
    ConditionCycle { condition_id: String },
}

pub fn load_ai_module_library(
    path: impl AsRef<Path>,
) -> Result<AiModuleLibrary, AiModuleLoadError> {
    let root = path.as_ref();
    let mut library = AiModuleLibrary::default();
    load_module_dir(root.join("modules"), &mut library)?;
    load_behavior_dir(root.join("behaviors"), &mut library)?;
    validate_ai_module_library(&library)?;
    Ok(library)
}

pub fn validate_ai_module_library(
    library: &AiModuleLibrary,
) -> Result<(), AiModuleValidationError> {
    for fact in library.facts.values() {
        validate_condition_tree(library, &fact.condition, &mut BTreeSet::new())?;
    }

    for condition in library.conditions.values() {
        validate_condition_tree(library, &condition.condition, &mut BTreeSet::new())?;
    }

    for score_rule in library.score_rules.values() {
        if let Some(condition) = &score_rule.when {
            validate_condition_tree(library, condition, &mut BTreeSet::new())?;
        }
    }

    for goal in library.goals.values() {
        for rule_id in &goal.score_rule_ids {
            if !library.score_rules.contains_key(rule_id) {
                return Err(AiModuleValidationError::MissingGoalScoreRule {
                    goal_id: goal.id.as_str().to_string(),
                    rule_id: rule_id.as_str().to_string(),
                });
            }
        }
    }

    for action in library.actions.values() {
        if !library.executors.contains_key(&action.executor_binding_id) {
            return Err(AiModuleValidationError::MissingActionExecutor {
                action_id: action.id.as_str().to_string(),
                executor_id: action.executor_binding_id.as_str().to_string(),
            });
        }
    }

    for behavior in library.behaviors.values() {
        for fact_id in &behavior.fact_ids {
            if !library.facts.contains_key(fact_id) {
                return Err(AiModuleValidationError::MissingReference {
                    behavior_id: behavior.id.as_str().to_string(),
                    domain: "fact",
                    id: fact_id.as_str().to_string(),
                });
            }
        }
        for goal_id in &behavior.goal_ids {
            if !library.goals.contains_key(goal_id) {
                return Err(AiModuleValidationError::MissingReference {
                    behavior_id: behavior.id.as_str().to_string(),
                    domain: "goal",
                    id: goal_id.as_str().to_string(),
                });
            }
        }
        for action_id in &behavior.action_ids {
            if !library.actions.contains_key(action_id) {
                return Err(AiModuleValidationError::MissingReference {
                    behavior_id: behavior.id.as_str().to_string(),
                    domain: "action",
                    id: action_id.as_str().to_string(),
                });
            }
        }
        if let Some(default_goal_id) = &behavior.default_goal_id {
            if !library.goals.contains_key(default_goal_id) {
                return Err(AiModuleValidationError::MissingReference {
                    behavior_id: behavior.id.as_str().to_string(),
                    domain: "default_goal",
                    id: default_goal_id.as_str().to_string(),
                });
            }
        }
        if let Some(alert_goal_id) = &behavior.alert_goal_id {
            if !library.goals.contains_key(alert_goal_id) {
                return Err(AiModuleValidationError::MissingReference {
                    behavior_id: behavior.id.as_str().to_string(),
                    domain: "alert_goal",
                    id: alert_goal_id.as_str().to_string(),
                });
            }
        }
    }

    Ok(())
}

pub fn resolve_ai_behavior_profile(
    library: &AiModuleLibrary,
    profile_ref: &AiBehaviorProfileRef,
) -> Result<AiBehaviorProfile, AiModuleValidationError> {
    let behavior = library.behaviors.get(profile_ref).ok_or_else(|| {
        AiModuleValidationError::MissingReference {
            behavior_id: profile_ref.as_str().to_string(),
            domain: "behavior",
            id: profile_ref.as_str().to_string(),
        }
    })?;

    let mut condition_ids = BTreeSet::new();
    let mut score_rules = BTreeMap::new();
    let mut executors = BTreeMap::new();

    let facts = behavior
        .fact_ids
        .iter()
        .filter_map(|fact_id| library.facts.get(fact_id))
        .cloned()
        .collect::<Vec<_>>();

    let goals = behavior
        .goal_ids
        .iter()
        .filter_map(|goal_id| library.goals.get(goal_id))
        .cloned()
        .collect::<Vec<_>>();

    let actions = behavior
        .action_ids
        .iter()
        .filter_map(|action_id| library.actions.get(action_id))
        .cloned()
        .collect::<Vec<_>>();

    for fact in &facts {
        collect_condition_refs(library, &fact.condition, &mut condition_ids)?;
    }

    for goal in &goals {
        for score_rule_id in &goal.score_rule_ids {
            if let Some(score_rule) = library.score_rules.get(score_rule_id) {
                if let Some(condition) = &score_rule.when {
                    collect_condition_refs(library, condition, &mut condition_ids)?;
                }
                score_rules.insert(score_rule.id.clone(), score_rule.clone());
            }
        }
    }

    for action in &actions {
        if let Some(executor) = library.executors.get(&action.executor_binding_id) {
            executors.insert(executor.id.clone(), executor.clone());
        }
    }

    let conditions = condition_ids
        .into_iter()
        .filter_map(|condition_id| {
            library
                .conditions
                .get(&condition_id)
                .cloned()
                .map(|definition| (condition_id, definition))
        })
        .collect();

    Ok(AiBehaviorProfile {
        id: behavior.id.clone(),
        facts,
        goals,
        actions,
        score_rules,
        executors,
        conditions,
        default_goal_id: behavior.default_goal_id.clone(),
        alert_goal_id: behavior.alert_goal_id.clone(),
    })
}

fn load_module_dir(dir: PathBuf, library: &mut AiModuleLibrary) -> Result<(), AiModuleLoadError> {
    if !dir.exists() {
        return Ok(());
    }
    let mut file_paths = read_json_files(&dir)?;
    file_paths.sort();
    for path in file_paths {
        let raw = fs::read_to_string(&path).map_err(|source| AiModuleLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let pack: AiModulePack =
            serde_json::from_str(&raw).map_err(|source| AiModuleLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;
        merge_module_pack(library, pack)?;
    }
    Ok(())
}

fn load_behavior_dir(dir: PathBuf, library: &mut AiModuleLibrary) -> Result<(), AiModuleLoadError> {
    if !dir.exists() {
        return Ok(());
    }
    let mut file_paths = read_json_files(&dir)?;
    file_paths.sort();
    for path in file_paths {
        let raw = fs::read_to_string(&path).map_err(|source| AiModuleLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let definition: AiBehaviorDefinition =
            serde_json::from_str(&raw).map_err(|source| AiModuleLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;
        if library
            .behaviors
            .insert(definition.id.clone(), definition.clone())
            .is_some()
        {
            return Err(AiModuleLoadError::InvalidDefinition {
                source: AiModuleValidationError::DuplicateId {
                    domain: "behavior",
                    id: definition.id.as_str().to_string(),
                },
            });
        }
    }
    Ok(())
}

fn merge_module_pack(
    library: &mut AiModuleLibrary,
    pack: AiModulePack,
) -> Result<(), AiModuleLoadError> {
    insert_unique(
        "condition",
        &mut library.conditions,
        pack.conditions
            .into_iter()
            .map(|item| (item.id.clone(), item)),
    )?;
    insert_unique(
        "fact",
        &mut library.facts,
        pack.facts.into_iter().map(|item| (item.id.clone(), item)),
    )?;
    insert_unique(
        "score_rule",
        &mut library.score_rules,
        pack.score_rules
            .into_iter()
            .map(|item| (item.id.clone(), item)),
    )?;
    insert_unique(
        "goal",
        &mut library.goals,
        pack.goals.into_iter().map(|item| (item.id.clone(), item)),
    )?;
    insert_unique(
        "action",
        &mut library.actions,
        pack.actions.into_iter().map(|item| (item.id.clone(), item)),
    )?;
    insert_unique(
        "executor",
        &mut library.executors,
        pack.executors
            .into_iter()
            .map(|item| (item.id.clone(), item)),
    )?;
    Ok(())
}

fn insert_unique<K, V, I>(
    domain: &'static str,
    target: &mut BTreeMap<K, V>,
    entries: I,
) -> Result<(), AiModuleLoadError>
where
    K: Ord + Clone + fmt::Display,
    I: IntoIterator<Item = (K, V)>,
{
    for (id, value) in entries {
        if target.insert(id.clone(), value).is_some() {
            return Err(AiModuleLoadError::InvalidDefinition {
                source: AiModuleValidationError::DuplicateId {
                    domain,
                    id: id.to_string(),
                },
            });
        }
    }
    Ok(())
}

fn read_json_files(dir: &Path) -> Result<Vec<PathBuf>, AiModuleLoadError> {
    let mut file_paths = Vec::new();
    let entries = fs::read_dir(dir).map_err(|source| AiModuleLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;
    for entry in entries {
        let entry = entry.map_err(|source| AiModuleLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if path.is_file() && path.extension().is_some_and(|ext| ext == "json") {
            file_paths.push(path);
        }
    }
    Ok(file_paths)
}

fn validate_condition_tree(
    library: &AiModuleLibrary,
    condition: &AiConditionDefinition,
    stack: &mut BTreeSet<AiConditionId>,
) -> Result<(), AiModuleValidationError> {
    match condition {
        AiConditionDefinition::ConditionRef { condition_id } => {
            if !stack.insert(condition_id.clone()) {
                return Err(AiModuleValidationError::ConditionCycle {
                    condition_id: condition_id.as_str().to_string(),
                });
            }
            let referenced = library.conditions.get(condition_id).ok_or_else(|| {
                AiModuleValidationError::MissingConditionReference {
                    condition_id: condition_id.as_str().to_string(),
                }
            })?;
            validate_condition_tree(library, &referenced.condition, stack)?;
            stack.remove(condition_id);
        }
        AiConditionDefinition::AllOf { conditions }
        | AiConditionDefinition::AnyOf { conditions } => {
            for child in conditions {
                validate_condition_tree(library, child, stack)?;
            }
        }
        AiConditionDefinition::Not { condition } => {
            validate_condition_tree(library, condition, stack)?;
        }
        AiConditionDefinition::FactTrue { .. }
        | AiConditionDefinition::BoolEquals { .. }
        | AiConditionDefinition::NumberCompare { .. }
        | AiConditionDefinition::TextEquals { .. }
        | AiConditionDefinition::TextKeyEquals { .. }
        | AiConditionDefinition::RoleIs { .. } => {}
    }
    Ok(())
}

fn collect_condition_refs(
    library: &AiModuleLibrary,
    condition: &AiConditionDefinition,
    ids: &mut BTreeSet<AiConditionId>,
) -> Result<(), AiModuleValidationError> {
    match condition {
        AiConditionDefinition::ConditionRef { condition_id } => {
            let definition = library.conditions.get(condition_id).ok_or_else(|| {
                AiModuleValidationError::MissingConditionReference {
                    condition_id: condition_id.as_str().to_string(),
                }
            })?;
            ids.insert(condition_id.clone());
            collect_condition_refs(library, &definition.condition, ids)?;
        }
        AiConditionDefinition::AllOf { conditions }
        | AiConditionDefinition::AnyOf { conditions } => {
            for child in conditions {
                collect_condition_refs(library, child, ids)?;
            }
        }
        AiConditionDefinition::Not { condition } => {
            collect_condition_refs(library, condition, ids)?;
        }
        AiConditionDefinition::FactTrue { .. }
        | AiConditionDefinition::BoolEquals { .. }
        | AiConditionDefinition::NumberCompare { .. }
        | AiConditionDefinition::TextEquals { .. }
        | AiConditionDefinition::TextKeyEquals { .. }
        | AiConditionDefinition::RoleIs { .. } => {}
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{
        validate_ai_module_library, AiActionDefinition, AiActionId, AiBehaviorDefinition,
        AiBehaviorProfileRef, AiComparisonOperator, AiConditionDefinition,
        AiExecutorBindingDefinition, AiExecutorBindingId, AiFactId, AiFactModuleDefinition,
        AiGoalDefinition, AiGoalId, AiModuleLibrary, AiPlannerDatumAssignment,
        AiScoreRuleDefinition, AiScoreRuleId, BuiltinAiExecutorKind,
    };
    use crate::NpcRole;

    #[test]
    fn ai_library_validation_accepts_simple_resident_behavior() {
        let mut library = AiModuleLibrary::default();
        library.facts.insert(
            AiFactId::from("sleepy"),
            AiFactModuleDefinition {
                id: AiFactId::from("sleepy"),
                condition: AiConditionDefinition::NumberCompare {
                    key: "need.energy".into(),
                    op: AiComparisonOperator::LessThanOrEqual,
                    value: 50.0,
                },
            },
        );
        library.score_rules.insert(
            AiScoreRuleId::from("sleep_if_sleepy"),
            AiScoreRuleDefinition {
                id: AiScoreRuleId::from("sleep_if_sleepy"),
                when: Some(AiConditionDefinition::FactTrue {
                    fact_id: AiFactId::from("sleepy"),
                }),
                score_delta: 600,
            },
        );
        library.goals.insert(
            AiGoalId::from("sleep"),
            AiGoalDefinition {
                id: AiGoalId::from("sleep"),
                score_rule_ids: vec![AiScoreRuleId::from("sleep_if_sleepy")],
                planner_requirements: vec![AiPlannerDatumAssignment {
                    key: "is_rested".into(),
                    value: true,
                }],
                conditional_requirements: Vec::new(),
            },
        );
        library.executors.insert(
            AiExecutorBindingId::from("use_smart_object"),
            AiExecutorBindingDefinition {
                id: AiExecutorBindingId::from("use_smart_object"),
                kind: BuiltinAiExecutorKind::UseSmartObject,
            },
        );
        library.actions.insert(
            AiActionId::from("sleep"),
            AiActionDefinition {
                id: AiActionId::from("sleep"),
                preconditions: vec![AiPlannerDatumAssignment {
                    key: "at_home".into(),
                    value: true,
                }],
                effects: vec![AiPlannerDatumAssignment {
                    key: "is_rested".into(),
                    value: true,
                }],
                planner_cost: 2,
                target_anchor: None,
                reservation_target: None,
                executor_binding_id: AiExecutorBindingId::from("use_smart_object"),
                default_travel_minutes: 0,
                perform_minutes: 60,
                expected_fact_ids: Vec::new(),
                need_effects: Default::default(),
                world_state_effects: Default::default(),
            },
        );
        library.behaviors.insert(
            AiBehaviorProfileRef::from("resident_settlement"),
            AiBehaviorDefinition {
                id: AiBehaviorProfileRef::from("resident_settlement"),
                fact_ids: vec![AiFactId::from("sleepy")],
                goal_ids: vec![AiGoalId::from("sleep")],
                action_ids: vec![AiActionId::from("sleep")],
                default_goal_id: Some(AiGoalId::from("sleep")),
                alert_goal_id: None,
            },
        );

        assert!(validate_ai_module_library(&library).is_ok());
    }

    #[test]
    fn ai_library_validation_rejects_missing_condition_reference() {
        let mut library = AiModuleLibrary::default();
        library.facts.insert(
            AiFactId::from("guard_shift"),
            AiFactModuleDefinition {
                id: AiFactId::from("guard_shift"),
                condition: AiConditionDefinition::ConditionRef {
                    condition_id: "missing".into(),
                },
            },
        );
        let error =
            validate_ai_module_library(&library).expect_err("missing condition should fail");
        assert!(matches!(
            error,
            super::AiModuleValidationError::MissingConditionReference { .. }
        ));

        let _ = NpcRole::Guard;
    }
}
