use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct RecipeOutput {
    #[serde(default, deserialize_with = "deserialize_u32ish")]
    pub item_id: u32,
    #[serde(default = "default_count")]
    pub count: i32,
    #[serde(default)]
    pub quality_bonus: i32,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct RecipeMaterial {
    #[serde(default, deserialize_with = "deserialize_u32ish")]
    pub item_id: u32,
    #[serde(default = "default_count")]
    pub count: i32,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct RecipeUnlockCondition {
    #[serde(default, rename = "type")]
    pub condition_type: String,
    #[serde(default)]
    pub id: String,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct RecipeDefinition {
    #[serde(default)]
    pub id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub category: String,
    #[serde(default)]
    pub output: RecipeOutput,
    #[serde(default)]
    pub materials: Vec<RecipeMaterial>,
    #[serde(default, deserialize_with = "deserialize_stringish_vec")]
    pub required_tools: Vec<String>,
    #[serde(default, deserialize_with = "deserialize_stringish_vec")]
    pub optional_tools: Vec<String>,
    #[serde(default = "default_required_station")]
    pub required_station: String,
    #[serde(default)]
    pub skill_requirements: BTreeMap<String, i32>,
    #[serde(default)]
    pub craft_time: f32,
    #[serde(default)]
    pub experience_reward: i32,
    #[serde(default)]
    pub unlock_conditions: Vec<RecipeUnlockCondition>,
    #[serde(default)]
    pub is_default_unlocked: bool,
    #[serde(default = "default_durability_influence")]
    pub durability_influence: f32,
    #[serde(default)]
    pub is_repair: bool,
    #[serde(default = "default_target_type")]
    pub target_type: String,
    #[serde(default = "default_repair_amount")]
    pub repair_amount: i32,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct RecipeLibrary {
    definitions: BTreeMap<String, RecipeDefinition>,
}

impl From<BTreeMap<String, RecipeDefinition>> for RecipeLibrary {
    fn from(definitions: BTreeMap<String, RecipeDefinition>) -> Self {
        Self { definitions }
    }
}

impl RecipeLibrary {
    pub fn get(&self, id: &str) -> Option<&RecipeDefinition> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &RecipeDefinition)> {
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
pub struct RecipeValidationCatalog {
    pub item_ids: BTreeSet<u32>,
    pub skill_ids: BTreeSet<String>,
    pub recipe_ids: BTreeSet<String>,
}

#[derive(Debug, Error, Clone, PartialEq)]
pub enum RecipeDefinitionValidationError {
    #[error("recipe id cannot be empty")]
    MissingId,
    #[error("recipe {recipe_id} name cannot be empty")]
    MissingName { recipe_id: String },
    #[error("recipe {recipe_id} output item_id must be > 0")]
    MissingOutputItem { recipe_id: String },
    #[error("recipe {recipe_id} output count must be > 0")]
    InvalidOutputCount { recipe_id: String },
    #[error("recipe {recipe_id} craft_time cannot be negative")]
    NegativeCraftTime { recipe_id: String },
    #[error("recipe {recipe_id} durability_influence must be >= 0")]
    NegativeDurabilityInfluence { recipe_id: String },
    #[error("recipe {recipe_id} repair_amount must be > 0 when is_repair is true")]
    InvalidRepairAmount { recipe_id: String },
    #[error("recipe {recipe_id} material {index} item_id must be > 0")]
    MissingMaterialItem { recipe_id: String, index: usize },
    #[error("recipe {recipe_id} material {index} count must be > 0")]
    InvalidMaterialCount { recipe_id: String, index: usize },
    #[error("recipe {recipe_id} references unknown item id {item_id} at {path}")]
    UnknownItemReference {
        recipe_id: String,
        item_id: u32,
        path: String,
    },
    #[error("recipe {recipe_id} references unknown skill id {skill_id}")]
    UnknownSkillReference { recipe_id: String, skill_id: String },
    #[error("recipe {recipe_id} references unknown unlock recipe id {unlock_id}")]
    UnknownUnlockRecipe {
        recipe_id: String,
        unlock_id: String,
    },
}

#[derive(Debug, Error)]
pub enum RecipeLoadError {
    #[error("failed to read recipe definition directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read recipe definition file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse recipe definition file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("recipe definition file {path} is invalid: {source}")]
    Validation {
        path: PathBuf,
        #[source]
        source: RecipeDefinitionValidationError,
    },
    #[error("duplicate recipe id {recipe_id} found in {duplicate_path} (first declared in {first_path})")]
    DuplicateId {
        recipe_id: String,
        first_path: PathBuf,
        duplicate_path: PathBuf,
    },
}

pub fn validate_recipe_definition(
    definition: &RecipeDefinition,
    catalog: Option<&RecipeValidationCatalog>,
) -> Result<(), RecipeDefinitionValidationError> {
    let recipe_id = definition.id.trim();
    if recipe_id.is_empty() {
        return Err(RecipeDefinitionValidationError::MissingId);
    }
    if definition.name.trim().is_empty() {
        return Err(RecipeDefinitionValidationError::MissingName {
            recipe_id: recipe_id.to_string(),
        });
    }
    if definition.output.item_id == 0 {
        return Err(RecipeDefinitionValidationError::MissingOutputItem {
            recipe_id: recipe_id.to_string(),
        });
    }
    if definition.output.count < 1 {
        return Err(RecipeDefinitionValidationError::InvalidOutputCount {
            recipe_id: recipe_id.to_string(),
        });
    }
    if definition.craft_time < 0.0 {
        return Err(RecipeDefinitionValidationError::NegativeCraftTime {
            recipe_id: recipe_id.to_string(),
        });
    }
    if definition.durability_influence < 0.0 {
        return Err(
            RecipeDefinitionValidationError::NegativeDurabilityInfluence {
                recipe_id: recipe_id.to_string(),
            },
        );
    }
    if definition.is_repair && definition.repair_amount < 1 {
        return Err(RecipeDefinitionValidationError::InvalidRepairAmount {
            recipe_id: recipe_id.to_string(),
        });
    }

    for (index, material) in definition.materials.iter().enumerate() {
        if material.item_id == 0 {
            return Err(RecipeDefinitionValidationError::MissingMaterialItem {
                recipe_id: recipe_id.to_string(),
                index,
            });
        }
        if material.count < 1 {
            return Err(RecipeDefinitionValidationError::InvalidMaterialCount {
                recipe_id: recipe_id.to_string(),
                index,
            });
        }
    }

    if let Some(catalog) = catalog {
        if !catalog.item_ids.is_empty() {
            if !catalog.item_ids.contains(&definition.output.item_id) {
                return Err(RecipeDefinitionValidationError::UnknownItemReference {
                    recipe_id: recipe_id.to_string(),
                    item_id: definition.output.item_id,
                    path: "output.item_id".to_string(),
                });
            }
            for (index, material) in definition.materials.iter().enumerate() {
                if !catalog.item_ids.contains(&material.item_id) {
                    return Err(RecipeDefinitionValidationError::UnknownItemReference {
                        recipe_id: recipe_id.to_string(),
                        item_id: material.item_id,
                        path: format!("materials[{index}].item_id"),
                    });
                }
            }
            for tool in definition
                .required_tools
                .iter()
                .chain(definition.optional_tools.iter())
            {
                if let Ok(item_id) = tool.parse::<u32>() {
                    if !catalog.item_ids.contains(&item_id) {
                        return Err(RecipeDefinitionValidationError::UnknownItemReference {
                            recipe_id: recipe_id.to_string(),
                            item_id,
                            path: "tools".to_string(),
                        });
                    }
                }
            }
        }

        if !catalog.skill_ids.is_empty() {
            for skill_id in definition.skill_requirements.keys() {
                if !catalog.skill_ids.contains(skill_id) {
                    return Err(RecipeDefinitionValidationError::UnknownSkillReference {
                        recipe_id: recipe_id.to_string(),
                        skill_id: skill_id.clone(),
                    });
                }
            }
        }

        if !catalog.recipe_ids.is_empty() {
            for condition in &definition.unlock_conditions {
                if condition.condition_type == "recipe"
                    && !condition.id.trim().is_empty()
                    && !catalog.recipe_ids.contains(condition.id.trim())
                {
                    return Err(RecipeDefinitionValidationError::UnknownUnlockRecipe {
                        recipe_id: recipe_id.to_string(),
                        unlock_id: condition.id.trim().to_string(),
                    });
                }
            }
        }
    }

    Ok(())
}

pub fn load_recipe_library(
    dir: impl AsRef<Path>,
    catalog: Option<&RecipeValidationCatalog>,
) -> Result<RecipeLibrary, RecipeLoadError> {
    let dir = dir.as_ref();
    let entries = fs::read_dir(dir).map_err(|source| RecipeLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    let mut definitions = BTreeMap::new();
    let mut origins = BTreeMap::<String, PathBuf>::new();

    for entry in entries {
        let entry = entry.map_err(|source| RecipeLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if !path.is_file() || path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path).map_err(|source| RecipeLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let mut definition: RecipeDefinition =
            serde_json::from_str(&raw).map_err(|source| RecipeLoadError::ParseFile {
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

        validate_recipe_definition(&definition, catalog).map_err(|source| {
            RecipeLoadError::Validation {
                path: path.clone(),
                source,
            }
        })?;

        if let Some(first_path) = origins.insert(definition.id.clone(), path.clone()) {
            return Err(RecipeLoadError::DuplicateId {
                recipe_id: definition.id.clone(),
                first_path,
                duplicate_path: path,
            });
        }

        definitions.insert(definition.id.clone(), definition);
    }

    Ok(RecipeLibrary { definitions })
}

const fn default_count() -> i32 {
    1
}

fn default_required_station() -> String {
    "none".to_string()
}

const fn default_durability_influence() -> f32 {
    1.0
}

fn default_target_type() -> String {
    "any".to_string()
}

const fn default_repair_amount() -> i32 {
    30
}

fn parse_u32ish(value: &Value) -> Result<u32, String> {
    match value {
        Value::Number(number) => number
            .as_u64()
            .and_then(|value| u32::try_from(value).ok())
            .ok_or_else(|| format!("invalid u32 number {number}")),
        Value::String(text) => text
            .trim()
            .parse::<u32>()
            .map_err(|error| format!("invalid u32 string {text}: {error}")),
        Value::Null => Ok(0),
        other => Err(format!("unsupported u32ish value: {other}")),
    }
}

fn deserialize_u32ish<'de, D>(deserializer: D) -> Result<u32, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    parse_u32ish(&value).map_err(serde::de::Error::custom)
}

fn deserialize_stringish_vec<'de, D>(deserializer: D) -> Result<Vec<String>, D::Error>
where
    D: Deserializer<'de>,
{
    let values = Option::<Vec<Value>>::deserialize(deserializer)?.unwrap_or_default();
    Ok(values
        .into_iter()
        .filter_map(|value| match value {
            Value::String(text) => {
                let normalized = text.trim().to_string();
                (!normalized.is_empty()).then_some(normalized)
            }
            Value::Number(number) => Some(number.to_string()),
            _ => None,
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use std::path::PathBuf;

    use super::{load_recipe_library, RecipeValidationCatalog};
    use crate::{load_item_library, load_skill_library, SkillValidationCatalog};

    #[test]
    fn load_recipe_library_accepts_real_data() {
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("..");
        let items = load_item_library(repo_root.join("data").join("items"), None)
            .expect("items should load");
        let skills = load_skill_library(
            repo_root.join("data").join("skills"),
            Some(&SkillValidationCatalog::default()),
        )
        .expect("skills should load");
        let catalog = RecipeValidationCatalog {
            item_ids: items.ids(),
            skill_ids: skills.ids(),
            recipe_ids: Default::default(),
        };
        let recipes = load_recipe_library(repo_root.join("data").join("recipes"), Some(&catalog))
            .expect("recipes should load");
        assert!(!recipes.is_empty());
    }
}
