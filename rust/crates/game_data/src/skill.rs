use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum SkillExecutionKind {
    #[default]
    None,
    DamageSingle,
    DamageAoe,
    ToggleStatus,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum SkillTargetSideRule {
    #[default]
    Any,
    HostileOnly,
    FriendlyOnly,
    PlayerOnly,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct SkillModifierDefinition {
    #[serde(default)]
    pub base: f32,
    #[serde(default)]
    pub per_level: f32,
    #[serde(default)]
    pub max_value: f32,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct SkillGameplayEffect {
    #[serde(default)]
    pub modifiers: BTreeMap<String, SkillModifierDefinition>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SkillTargetingDefinition {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub range_cells: i32,
    #[serde(default = "default_target_shape")]
    pub shape: String,
    #[serde(default)]
    pub radius: i32,
    #[serde(default)]
    pub execution_kind: SkillExecutionKind,
    #[serde(default)]
    pub target_side_rule: SkillTargetSideRule,
    #[serde(default = "default_target_requires_los")]
    pub require_los: bool,
    #[serde(default = "default_target_allow_self")]
    pub allow_self: bool,
    #[serde(default = "default_target_allow_friendly_fire")]
    pub allow_friendly_fire: bool,
    #[serde(default)]
    pub handler_script: String,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

impl Default for SkillTargetingDefinition {
    fn default() -> Self {
        Self {
            enabled: false,
            range_cells: 0,
            shape: default_target_shape(),
            radius: 0,
            execution_kind: SkillExecutionKind::None,
            target_side_rule: SkillTargetSideRule::Any,
            require_los: default_target_requires_los(),
            allow_self: default_target_allow_self(),
            allow_friendly_fire: default_target_allow_friendly_fire(),
            handler_script: String::new(),
            extra: BTreeMap::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct SkillActivationEffect {
    #[serde(default)]
    pub duration: f32,
    #[serde(default)]
    pub is_infinite: bool,
    #[serde(default)]
    pub category: String,
    #[serde(default)]
    pub modifiers: BTreeMap<String, SkillModifierDefinition>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct SkillActivationDefinition {
    #[serde(default = "default_activation_mode")]
    pub mode: String,
    #[serde(default)]
    pub cooldown: f32,
    #[serde(default)]
    pub effect: Option<SkillActivationEffect>,
    #[serde(default)]
    pub targeting: Option<SkillTargetingDefinition>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct SkillDefinition {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub icon: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub tree_id: String,
    #[serde(default = "default_max_level")]
    pub max_level: i32,
    #[serde(default)]
    pub prerequisites: Vec<String>,
    #[serde(default)]
    pub attribute_requirements: BTreeMap<String, i32>,
    #[serde(default)]
    pub gameplay_effect: Option<SkillGameplayEffect>,
    #[serde(default)]
    pub activation: Option<SkillActivationDefinition>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Default)]
pub struct SkillTreePosition {
    #[serde(default)]
    pub x: f32,
    #[serde(default)]
    pub y: f32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct SkillTreeLink {
    #[serde(default)]
    pub from: String,
    #[serde(default)]
    pub to: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct SkillTreeDefinition {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub skills: Vec<String>,
    #[serde(default)]
    pub links: Vec<SkillTreeLink>,
    #[serde(default)]
    pub layout: BTreeMap<String, SkillTreePosition>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct SkillLibrary {
    definitions: BTreeMap<String, SkillDefinition>,
}

impl From<BTreeMap<String, SkillDefinition>> for SkillLibrary {
    fn from(definitions: BTreeMap<String, SkillDefinition>) -> Self {
        Self { definitions }
    }
}

impl SkillLibrary {
    pub fn get(&self, id: &str) -> Option<&SkillDefinition> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &SkillDefinition)> {
        self.definitions.iter()
    }

    pub fn len(&self) -> usize {
        self.definitions.len()
    }

    pub fn is_empty(&self) -> bool {
        self.definitions.is_empty()
    }

    pub fn ids(&self) -> BTreeSet<String> {
        self.definitions.keys().cloned().collect()
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct SkillTreeLibrary {
    definitions: BTreeMap<String, SkillTreeDefinition>,
}

impl From<BTreeMap<String, SkillTreeDefinition>> for SkillTreeLibrary {
    fn from(definitions: BTreeMap<String, SkillTreeDefinition>) -> Self {
        Self { definitions }
    }
}

impl SkillTreeLibrary {
    pub fn get(&self, id: &str) -> Option<&SkillTreeDefinition> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &SkillTreeDefinition)> {
        self.definitions.iter()
    }

    pub fn len(&self) -> usize {
        self.definitions.len()
    }

    pub fn is_empty(&self) -> bool {
        self.definitions.is_empty()
    }

    pub fn ids(&self) -> BTreeSet<String> {
        self.definitions.keys().cloned().collect()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct SkillValidationCatalog {
    pub skill_ids: BTreeSet<String>,
    pub tree_ids: BTreeSet<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct SkillTreeValidationCatalog {
    pub skill_ids: BTreeSet<String>,
}

#[derive(Debug, Error, Clone, PartialEq)]
pub enum SkillDefinitionValidationError {
    #[error("skill id cannot be empty")]
    MissingId,
    #[error("skill {skill_id} name cannot be empty")]
    MissingName { skill_id: String },
    #[error("skill {skill_id} tree_id cannot be empty")]
    MissingTreeId { skill_id: String },
    #[error("skill {skill_id} max_level must be at least 1")]
    InvalidMaxLevel { skill_id: String },
    #[error("skill {skill_id} references unknown tree id {tree_id}")]
    UnknownTreeId { skill_id: String, tree_id: String },
    #[error("skill {skill_id} references unknown prerequisite {prerequisite_id}")]
    UnknownPrerequisite {
        skill_id: String,
        prerequisite_id: String,
    },
    #[error("skill {skill_id} cannot list itself as a prerequisite")]
    SelfPrerequisite { skill_id: String },
    #[error("skill {skill_id} activation mode {mode} is invalid")]
    InvalidActivationMode { skill_id: String, mode: String },
    #[error("skill {skill_id} activation cooldown cannot be negative")]
    NegativeCooldown { skill_id: String },
    #[error("skill {skill_id} targeting shape {shape} is invalid")]
    InvalidTargetShape { skill_id: String, shape: String },
    #[error("skill {skill_id} target_side_rule is invalid for self-targeting policy")]
    InvalidTargetSideRule { skill_id: String },
}

#[derive(Debug, Error, Clone, PartialEq)]
pub enum SkillTreeDefinitionValidationError {
    #[error("skill tree id cannot be empty")]
    MissingId,
    #[error("skill tree {tree_id} name cannot be empty")]
    MissingName { tree_id: String },
    #[error("skill tree {tree_id} contains duplicate skill id {skill_id}")]
    DuplicateSkill { tree_id: String, skill_id: String },
    #[error("skill tree {tree_id} references unknown skill id {skill_id}")]
    UnknownSkillId { tree_id: String, skill_id: String },
    #[error("skill tree {tree_id} contains invalid link {from}->{to}")]
    InvalidLink {
        tree_id: String,
        from: String,
        to: String,
    },
    #[error("skill tree {tree_id} layout references unknown skill id {skill_id}")]
    UnknownLayoutSkill { tree_id: String, skill_id: String },
}

#[derive(Debug, Error)]
pub enum SkillLoadError {
    #[error("failed to read skill definition directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read skill definition file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse skill definition file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("skill definition file {path} is invalid: {source}")]
    Validation {
        path: PathBuf,
        #[source]
        source: SkillDefinitionValidationError,
    },
    #[error(
        "duplicate skill id {skill_id} found in {duplicate_path} (first declared in {first_path})"
    )]
    DuplicateId {
        skill_id: String,
        first_path: PathBuf,
        duplicate_path: PathBuf,
    },
}

#[derive(Debug, Error)]
pub enum SkillTreeLoadError {
    #[error("failed to read skill tree definition directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read skill tree definition file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse skill tree definition file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("skill tree definition file {path} is invalid: {source}")]
    Validation {
        path: PathBuf,
        #[source]
        source: SkillTreeDefinitionValidationError,
    },
    #[error("duplicate skill tree id {tree_id} found in {duplicate_path} (first declared in {first_path})")]
    DuplicateId {
        tree_id: String,
        first_path: PathBuf,
        duplicate_path: PathBuf,
    },
}

pub fn validate_skill_definition(
    definition: &SkillDefinition,
    catalog: Option<&SkillValidationCatalog>,
) -> Result<(), SkillDefinitionValidationError> {
    let skill_id = definition.id.trim();
    if skill_id.is_empty() {
        return Err(SkillDefinitionValidationError::MissingId);
    }
    if definition.name.trim().is_empty() {
        return Err(SkillDefinitionValidationError::MissingName {
            skill_id: skill_id.to_string(),
        });
    }
    if definition.tree_id.trim().is_empty() {
        return Err(SkillDefinitionValidationError::MissingTreeId {
            skill_id: skill_id.to_string(),
        });
    }
    if definition.max_level < 1 {
        return Err(SkillDefinitionValidationError::InvalidMaxLevel {
            skill_id: skill_id.to_string(),
        });
    }

    if let Some(catalog) = catalog {
        if !catalog.tree_ids.is_empty() && !catalog.tree_ids.contains(definition.tree_id.trim()) {
            return Err(SkillDefinitionValidationError::UnknownTreeId {
                skill_id: skill_id.to_string(),
                tree_id: definition.tree_id.trim().to_string(),
            });
        }
        for prerequisite_id in &definition.prerequisites {
            let prerequisite_id = prerequisite_id.trim();
            if prerequisite_id.is_empty() {
                continue;
            }
            if prerequisite_id == skill_id {
                return Err(SkillDefinitionValidationError::SelfPrerequisite {
                    skill_id: skill_id.to_string(),
                });
            }
            if !catalog.skill_ids.is_empty() && !catalog.skill_ids.contains(prerequisite_id) {
                return Err(SkillDefinitionValidationError::UnknownPrerequisite {
                    skill_id: skill_id.to_string(),
                    prerequisite_id: prerequisite_id.to_string(),
                });
            }
        }
    }

    if let Some(activation) = definition.activation.as_ref() {
        let mode = activation.mode.trim();
        if !mode.is_empty() && mode != "passive" && mode != "active" && mode != "toggle" {
            return Err(SkillDefinitionValidationError::InvalidActivationMode {
                skill_id: skill_id.to_string(),
                mode: mode.to_string(),
            });
        }
        if activation.cooldown < 0.0 {
            return Err(SkillDefinitionValidationError::NegativeCooldown {
                skill_id: skill_id.to_string(),
            });
        }
        if let Some(targeting) = activation.targeting.as_ref() {
            let shape = targeting.shape.trim();
            if !shape.is_empty() && shape != "single" && shape != "diamond" && shape != "square" {
                return Err(SkillDefinitionValidationError::InvalidTargetShape {
                    skill_id: skill_id.to_string(),
                    shape: shape.to_string(),
                });
            }
            if matches!(targeting.target_side_rule, SkillTargetSideRule::PlayerOnly)
                && !targeting.allow_self
            {
                return Err(SkillDefinitionValidationError::InvalidTargetSideRule {
                    skill_id: skill_id.to_string(),
                });
            }
        }
    }

    Ok(())
}

pub fn validate_skill_tree_definition(
    definition: &SkillTreeDefinition,
    catalog: Option<&SkillTreeValidationCatalog>,
) -> Result<(), SkillTreeDefinitionValidationError> {
    let tree_id = definition.id.trim();
    if tree_id.is_empty() {
        return Err(SkillTreeDefinitionValidationError::MissingId);
    }
    if definition.name.trim().is_empty() {
        return Err(SkillTreeDefinitionValidationError::MissingName {
            tree_id: tree_id.to_string(),
        });
    }

    let mut seen_skills = BTreeSet::new();
    for skill_id in &definition.skills {
        let skill_id = skill_id.trim();
        if skill_id.is_empty() {
            continue;
        }
        if !seen_skills.insert(skill_id.to_string()) {
            return Err(SkillTreeDefinitionValidationError::DuplicateSkill {
                tree_id: tree_id.to_string(),
                skill_id: skill_id.to_string(),
            });
        }
        if let Some(catalog) = catalog {
            if !catalog.skill_ids.is_empty() && !catalog.skill_ids.contains(skill_id) {
                return Err(SkillTreeDefinitionValidationError::UnknownSkillId {
                    tree_id: tree_id.to_string(),
                    skill_id: skill_id.to_string(),
                });
            }
        }
    }

    for link in &definition.links {
        let from = link.from.trim();
        let to = link.to.trim();
        if from.is_empty()
            || to.is_empty()
            || !seen_skills.contains(from)
            || !seen_skills.contains(to)
        {
            return Err(SkillTreeDefinitionValidationError::InvalidLink {
                tree_id: tree_id.to_string(),
                from: from.to_string(),
                to: to.to_string(),
            });
        }
    }

    for skill_id in definition.layout.keys() {
        let skill_id = skill_id.trim();
        if skill_id.is_empty() || !seen_skills.contains(skill_id) {
            return Err(SkillTreeDefinitionValidationError::UnknownLayoutSkill {
                tree_id: tree_id.to_string(),
                skill_id: skill_id.to_string(),
            });
        }
    }

    Ok(())
}

pub fn load_skill_library(
    dir: impl AsRef<Path>,
    catalog: Option<&SkillValidationCatalog>,
) -> Result<SkillLibrary, SkillLoadError> {
    let dir = dir.as_ref();
    let entries = fs::read_dir(dir).map_err(|source| SkillLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    let mut definitions = BTreeMap::new();
    let mut origins = BTreeMap::<String, PathBuf>::new();

    for entry in entries {
        let entry = entry.map_err(|source| SkillLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if !path.is_file() || path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path).map_err(|source| SkillLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let mut definition: SkillDefinition =
            serde_json::from_str(&raw).map_err(|source| SkillLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;
        if definition.id.trim().is_empty() {
            definition.id = path
                .file_stem()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .to_string();
        }

        validate_skill_definition(&definition, catalog).map_err(|source| {
            SkillLoadError::Validation {
                path: path.clone(),
                source,
            }
        })?;

        if let Some(first_path) = origins.insert(definition.id.clone(), path.clone()) {
            return Err(SkillLoadError::DuplicateId {
                skill_id: definition.id.clone(),
                first_path,
                duplicate_path: path,
            });
        }

        definitions.insert(definition.id.clone(), definition);
    }

    Ok(SkillLibrary { definitions })
}

pub fn load_skill_tree_library(
    dir: impl AsRef<Path>,
    catalog: Option<&SkillTreeValidationCatalog>,
) -> Result<SkillTreeLibrary, SkillTreeLoadError> {
    let dir = dir.as_ref();
    let entries = fs::read_dir(dir).map_err(|source| SkillTreeLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    let mut definitions = BTreeMap::new();
    let mut origins = BTreeMap::<String, PathBuf>::new();

    for entry in entries {
        let entry = entry.map_err(|source| SkillTreeLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if !path.is_file() || path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path).map_err(|source| SkillTreeLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let mut definition: SkillTreeDefinition =
            serde_json::from_str(&raw).map_err(|source| SkillTreeLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;
        if definition.id.trim().is_empty() {
            definition.id = path
                .file_stem()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .to_string();
        }

        validate_skill_tree_definition(&definition, catalog).map_err(|source| {
            SkillTreeLoadError::Validation {
                path: path.clone(),
                source,
            }
        })?;

        if let Some(first_path) = origins.insert(definition.id.clone(), path.clone()) {
            return Err(SkillTreeLoadError::DuplicateId {
                tree_id: definition.id.clone(),
                first_path,
                duplicate_path: path,
            });
        }

        definitions.insert(definition.id.clone(), definition);
    }

    Ok(SkillTreeLibrary { definitions })
}

const fn default_max_level() -> i32 {
    1
}

fn default_activation_mode() -> String {
    "passive".to_string()
}

fn default_target_shape() -> String {
    "single".to_string()
}

const fn default_target_requires_los() -> bool {
    true
}

const fn default_target_allow_self() -> bool {
    true
}

const fn default_target_allow_friendly_fire() -> bool {
    true
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::{
        load_skill_library, load_skill_tree_library, SkillTreeValidationCatalog,
        SkillValidationCatalog,
    };

    #[test]
    fn load_skill_library_accepts_real_data() {
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("..");
        let tree_library = load_skill_tree_library(
            repo_root.join("data").join("skill_trees"),
            Some(&SkillTreeValidationCatalog::default()),
        )
        .expect("skill trees should load");
        let catalog = SkillValidationCatalog {
            skill_ids: Default::default(),
            tree_ids: tree_library.ids(),
        };
        let skill_library =
            load_skill_library(repo_root.join("data").join("skills"), Some(&catalog))
                .expect("skills should load");
        assert!(!skill_library.is_empty());
    }
}
