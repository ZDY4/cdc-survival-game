use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Deserializer, Serialize};
use serde_json::Value;
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Default)]
pub struct QuestPosition {
    #[serde(default)]
    pub x: f32,
    #[serde(default)]
    pub y: f32,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct QuestChoiceOption {
    #[serde(default)]
    pub text: String,
    #[serde(default)]
    pub next: String,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct QuestRewardItem {
    #[serde(default, deserialize_with = "deserialize_u32ish")]
    pub id: u32,
    #[serde(default = "default_count")]
    pub count: i32,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct QuestRewards {
    #[serde(default)]
    pub items: Vec<QuestRewardItem>,
    #[serde(default)]
    pub experience: i32,
    #[serde(default)]
    pub skill_points: i32,
    #[serde(default)]
    pub unlock_location: String,
    #[serde(default)]
    pub unlock_recipes: Vec<String>,
    #[serde(default)]
    pub title: String,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct QuestNode {
    #[serde(default)]
    pub id: String,
    #[serde(default, rename = "type")]
    pub node_type: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub objective_type: String,
    #[serde(default)]
    pub target: String,
    #[serde(default, deserialize_with = "deserialize_option_u32ish")]
    pub item_id: Option<u32>,
    #[serde(default)]
    pub count: i32,
    #[serde(default)]
    pub dialog_id: String,
    #[serde(default)]
    pub options: Vec<QuestChoiceOption>,
    #[serde(default)]
    pub rewards: QuestRewards,
    #[serde(default)]
    pub position: Option<QuestPosition>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct QuestConnection {
    #[serde(default)]
    pub from: String,
    #[serde(default)]
    pub from_port: i32,
    #[serde(default)]
    pub to: String,
    #[serde(default)]
    pub to_port: i32,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct QuestFlow {
    #[serde(default = "default_start_node_id")]
    pub start_node_id: String,
    #[serde(default)]
    pub nodes: BTreeMap<String, QuestNode>,
    #[serde(default)]
    pub connections: Vec<QuestConnection>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

impl Default for QuestFlow {
    fn default() -> Self {
        Self {
            start_node_id: default_start_node_id(),
            nodes: BTreeMap::new(),
            connections: Vec::new(),
            extra: BTreeMap::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct QuestEditorMeta {
    #[serde(default)]
    pub relationship_position: Option<QuestPosition>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct QuestDefinition {
    #[serde(default)]
    pub quest_id: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub description: String,
    #[serde(default)]
    pub prerequisites: Vec<String>,
    #[serde(default = "default_time_limit")]
    pub time_limit: i32,
    #[serde(default)]
    pub flow: QuestFlow,
    #[serde(default, rename = "_editor")]
    pub editor: QuestEditorMeta,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct QuestLibrary {
    definitions: BTreeMap<String, QuestDefinition>,
}

impl From<BTreeMap<String, QuestDefinition>> for QuestLibrary {
    fn from(definitions: BTreeMap<String, QuestDefinition>) -> Self {
        Self { definitions }
    }
}

impl QuestLibrary {
    pub fn get(&self, id: &str) -> Option<&QuestDefinition> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &QuestDefinition)> {
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
pub struct QuestValidationCatalog {
    pub quest_ids: BTreeSet<String>,
    pub item_ids: BTreeSet<u32>,
    pub dialog_ids: BTreeSet<String>,
    pub map_location_ids: BTreeSet<String>,
    pub recipe_ids: BTreeSet<String>,
}

#[derive(Debug, Error)]
pub enum QuestDefinitionValidationError {
    #[error("quest id cannot be empty")]
    MissingQuestId,
    #[error("quest {quest_id} title cannot be empty")]
    MissingTitle { quest_id: String },
    #[error("quest {quest_id} references missing prerequisite {prerequisite_id}")]
    UnknownPrerequisite {
        quest_id: String,
        prerequisite_id: String,
    },
    #[error("quest {quest_id} flow.start_node_id cannot be empty")]
    MissingStartNodeId { quest_id: String },
    #[error("quest {quest_id} must contain exactly one start node, found {count}")]
    InvalidStartNodeCount { quest_id: String, count: usize },
    #[error("quest {quest_id} must contain at least one end node")]
    MissingEndNode { quest_id: String },
    #[error("quest {quest_id} flow.start_node_id points to missing node {node_id}")]
    UnknownStartNode { quest_id: String, node_id: String },
    #[error("quest {quest_id} flow.start_node_id {node_id} must point to a start node")]
    StartNodeTypeMismatch { quest_id: String, node_id: String },
    #[error("quest {quest_id} contains node {node_key} with empty id")]
    MissingNodeId { quest_id: String, node_key: String },
    #[error(
        "quest {quest_id} contains node {node_key} whose id {node_id} does not match its map key"
    )]
    NodeIdMismatch {
        quest_id: String,
        node_key: String,
        node_id: String,
    },
    #[error("quest {quest_id} objective node {node_id} requires objective_type")]
    MissingObjectiveType { quest_id: String, node_id: String },
    #[error(
        "quest {quest_id} objective node {node_id} uses unsupported objective_type {objective_type}"
    )]
    UnsupportedObjectiveType {
        quest_id: String,
        node_id: String,
        objective_type: String,
    },
    #[error("quest {quest_id} objective node {node_id} references unknown item id {item_id}")]
    UnknownObjectiveItem {
        quest_id: String,
        node_id: String,
        item_id: u32,
    },
    #[error("quest {quest_id} dialog node {node_id} requires dialog_id")]
    MissingDialogId { quest_id: String, node_id: String },
    #[error("quest {quest_id} dialog node {node_id} references unknown dialog id {dialog_id}")]
    UnknownDialogId {
        quest_id: String,
        node_id: String,
        dialog_id: String,
    },
    #[error("quest {quest_id} choice node {node_id} must define at least one option")]
    EmptyChoiceOptions { quest_id: String, node_id: String },
    #[error("quest {quest_id} reward node {node_id} references unknown item id {item_id}")]
    UnknownRewardItem {
        quest_id: String,
        node_id: String,
        item_id: u32,
    },
    #[error(
        "quest {quest_id} reward node {node_id} references unknown map location id {location_id}"
    )]
    UnknownUnlockLocation {
        quest_id: String,
        node_id: String,
        location_id: String,
    },
    #[error("quest {quest_id} reward node {node_id} references unknown recipe id {recipe_id}")]
    UnknownUnlockRecipe {
        quest_id: String,
        node_id: String,
        recipe_id: String,
    },
    #[error("quest {quest_id} contains connection {from}:{from_port}->{to}:{to_port} that references missing nodes")]
    UnknownConnectionNode {
        quest_id: String,
        from: String,
        from_port: i32,
        to: String,
        to_port: i32,
    },
}

#[derive(Debug, Error)]
pub enum QuestLoadError {
    #[error("failed to read quest definition directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read quest definition file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse quest definition file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("duplicate quest id {quest_id} in {first_path} and {second_path}")]
    DuplicateId {
        quest_id: String,
        first_path: PathBuf,
        second_path: PathBuf,
    },
    #[error("quest definition in {path} is invalid: {source}")]
    Validation {
        path: PathBuf,
        #[source]
        source: QuestDefinitionValidationError,
    },
}

pub fn validate_quest_definition(
    definition: &QuestDefinition,
    catalog: Option<&QuestValidationCatalog>,
) -> Result<(), QuestDefinitionValidationError> {
    let quest_id = definition.quest_id.trim();
    if quest_id.is_empty() {
        return Err(QuestDefinitionValidationError::MissingQuestId);
    }
    if definition.title.trim().is_empty() {
        return Err(QuestDefinitionValidationError::MissingTitle {
            quest_id: quest_id.to_string(),
        });
    }

    for prerequisite_id in &definition.prerequisites {
        let normalized = prerequisite_id.trim();
        if normalized.is_empty() {
            continue;
        }
        if let Some(catalog) = catalog {
            if !catalog.quest_ids.is_empty()
                && normalized != quest_id
                && !catalog.quest_ids.contains(normalized)
            {
                return Err(QuestDefinitionValidationError::UnknownPrerequisite {
                    quest_id: quest_id.to_string(),
                    prerequisite_id: normalized.to_string(),
                });
            }
        }
    }

    if definition.flow.start_node_id.trim().is_empty() {
        return Err(QuestDefinitionValidationError::MissingStartNodeId {
            quest_id: quest_id.to_string(),
        });
    }

    let mut start_count = 0usize;
    let mut end_count = 0usize;
    for (node_key, node) in &definition.flow.nodes {
        if node.id.trim().is_empty() {
            return Err(QuestDefinitionValidationError::MissingNodeId {
                quest_id: quest_id.to_string(),
                node_key: node_key.clone(),
            });
        }
        if node.id != *node_key {
            return Err(QuestDefinitionValidationError::NodeIdMismatch {
                quest_id: quest_id.to_string(),
                node_key: node_key.clone(),
                node_id: node.id.clone(),
            });
        }

        match node.node_type.as_str() {
            "start" => start_count += 1,
            "end" => end_count += 1,
            "objective" => {
                let objective_type = node.objective_type.trim();
                if objective_type.is_empty() {
                    return Err(QuestDefinitionValidationError::MissingObjectiveType {
                        quest_id: quest_id.to_string(),
                        node_id: node.id.clone(),
                    });
                }
                if !is_supported_objective_type(objective_type) {
                    return Err(QuestDefinitionValidationError::UnsupportedObjectiveType {
                        quest_id: quest_id.to_string(),
                        node_id: node.id.clone(),
                        objective_type: objective_type.to_string(),
                    });
                }
                if objective_type == "collect" {
                    if let Some(item_id) = node.item_id {
                        if let Some(catalog) = catalog {
                            if !catalog.item_ids.is_empty() && !catalog.item_ids.contains(&item_id)
                            {
                                return Err(QuestDefinitionValidationError::UnknownObjectiveItem {
                                    quest_id: quest_id.to_string(),
                                    node_id: node.id.clone(),
                                    item_id,
                                });
                            }
                        }
                    } else {
                        return Err(QuestDefinitionValidationError::UnknownObjectiveItem {
                            quest_id: quest_id.to_string(),
                            node_id: node.id.clone(),
                            item_id: 0,
                        });
                    }
                }
            }
            "dialog" => {
                let dialog_id = node.dialog_id.trim();
                if dialog_id.is_empty() {
                    return Err(QuestDefinitionValidationError::MissingDialogId {
                        quest_id: quest_id.to_string(),
                        node_id: node.id.clone(),
                    });
                }
                if let Some(catalog) = catalog {
                    if !catalog.dialog_ids.is_empty() && !catalog.dialog_ids.contains(dialog_id) {
                        return Err(QuestDefinitionValidationError::UnknownDialogId {
                            quest_id: quest_id.to_string(),
                            node_id: node.id.clone(),
                            dialog_id: dialog_id.to_string(),
                        });
                    }
                }
            }
            "choice" => {
                if node.options.is_empty() {
                    return Err(QuestDefinitionValidationError::EmptyChoiceOptions {
                        quest_id: quest_id.to_string(),
                        node_id: node.id.clone(),
                    });
                }
            }
            "reward" => {
                for reward_item in &node.rewards.items {
                    if reward_item.id == 0 {
                        return Err(QuestDefinitionValidationError::UnknownRewardItem {
                            quest_id: quest_id.to_string(),
                            node_id: node.id.clone(),
                            item_id: reward_item.id,
                        });
                    }
                    if let Some(catalog) = catalog {
                        if !catalog.item_ids.is_empty()
                            && !catalog.item_ids.contains(&reward_item.id)
                        {
                            return Err(QuestDefinitionValidationError::UnknownRewardItem {
                                quest_id: quest_id.to_string(),
                                node_id: node.id.clone(),
                                item_id: reward_item.id,
                            });
                        }
                    }
                }

                let unlock_location = node.rewards.unlock_location.trim();
                if !unlock_location.is_empty() {
                    if let Some(catalog) = catalog {
                        if !catalog.map_location_ids.is_empty()
                            && !catalog.map_location_ids.contains(unlock_location)
                        {
                            return Err(QuestDefinitionValidationError::UnknownUnlockLocation {
                                quest_id: quest_id.to_string(),
                                node_id: node.id.clone(),
                                location_id: unlock_location.to_string(),
                            });
                        }
                    }
                }

                for recipe_id in &node.rewards.unlock_recipes {
                    let normalized = recipe_id.trim();
                    if normalized.is_empty() {
                        continue;
                    }
                    if let Some(catalog) = catalog {
                        if !catalog.recipe_ids.is_empty()
                            && !catalog.recipe_ids.contains(normalized)
                        {
                            return Err(QuestDefinitionValidationError::UnknownUnlockRecipe {
                                quest_id: quest_id.to_string(),
                                node_id: node.id.clone(),
                                recipe_id: normalized.to_string(),
                            });
                        }
                    }
                }
            }
            _ => {}
        }
    }

    if start_count != 1 {
        return Err(QuestDefinitionValidationError::InvalidStartNodeCount {
            quest_id: quest_id.to_string(),
            count: start_count,
        });
    }
    if end_count < 1 {
        return Err(QuestDefinitionValidationError::MissingEndNode {
            quest_id: quest_id.to_string(),
        });
    }

    let start_node_id = definition.flow.start_node_id.trim();
    let Some(start_node) = definition.flow.nodes.get(start_node_id) else {
        return Err(QuestDefinitionValidationError::UnknownStartNode {
            quest_id: quest_id.to_string(),
            node_id: start_node_id.to_string(),
        });
    };
    if start_node.node_type != "start" {
        return Err(QuestDefinitionValidationError::StartNodeTypeMismatch {
            quest_id: quest_id.to_string(),
            node_id: start_node.id.clone(),
        });
    }

    for connection in &definition.flow.connections {
        if !definition.flow.nodes.contains_key(connection.from.trim())
            || !definition.flow.nodes.contains_key(connection.to.trim())
        {
            return Err(QuestDefinitionValidationError::UnknownConnectionNode {
                quest_id: quest_id.to_string(),
                from: connection.from.clone(),
                from_port: connection.from_port,
                to: connection.to.clone(),
                to_port: connection.to_port,
            });
        }
    }

    Ok(())
}

pub fn load_quest_library(
    dir: impl AsRef<Path>,
    catalog: Option<&QuestValidationCatalog>,
) -> Result<QuestLibrary, QuestLoadError> {
    let dir = dir.as_ref();
    let entries = fs::read_dir(dir).map_err(|source| QuestLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    let mut definitions = BTreeMap::new();
    let mut origins: BTreeMap<String, PathBuf> = BTreeMap::new();

    for entry in entries {
        let entry = entry.map_err(|source| QuestLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if !path.is_file() || path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path).map_err(|source| QuestLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let mut definition: QuestDefinition =
            serde_json::from_str(&raw).map_err(|source| QuestLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;

        if definition.quest_id.trim().is_empty() {
            definition.quest_id = path
                .file_stem()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .to_string();
        }

        for (node_key, node) in &mut definition.flow.nodes {
            if node.id.trim().is_empty() {
                node.id = node_key.clone();
            }
        }

        validate_quest_definition(&definition, catalog).map_err(|source| {
            QuestLoadError::Validation {
                path: path.clone(),
                source,
            }
        })?;

        if let Some(first_path) = origins.insert(definition.quest_id.clone(), path.clone()) {
            return Err(QuestLoadError::DuplicateId {
                quest_id: definition.quest_id.clone(),
                first_path,
                second_path: path,
            });
        }

        definitions.insert(definition.quest_id.clone(), definition);
    }

    Ok(QuestLibrary::from(definitions))
}

fn deserialize_u32ish<'de, D>(deserializer: D) -> Result<u32, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Value::deserialize(deserializer)?;
    parse_u32ish(value).map_err(serde::de::Error::custom)
}

fn deserialize_option_u32ish<'de, D>(deserializer: D) -> Result<Option<u32>, D::Error>
where
    D: Deserializer<'de>,
{
    let value = Option::<Value>::deserialize(deserializer)?;
    value
        .map(parse_u32ish)
        .transpose()
        .map_err(serde::de::Error::custom)
}

fn parse_u32ish(value: Value) -> Result<u32, String> {
    match value {
        Value::Number(number) => number
            .as_u64()
            .and_then(|parsed| u32::try_from(parsed).ok())
            .ok_or_else(|| format!("invalid u32 value: {number}")),
        Value::String(text) => text
            .trim()
            .parse::<u32>()
            .map_err(|error| format!("invalid u32 string {text}: {error}")),
        other => Err(format!("unsupported u32 value: {other}")),
    }
}

fn default_start_node_id() -> String {
    "start".to_string()
}

fn default_time_limit() -> i32 {
    -1
}

fn default_count() -> i32 {
    1
}

fn is_supported_objective_type(objective_type: &str) -> bool {
    matches!(objective_type, "collect" | "kill")
}

#[cfg(test)]
mod tests {
    use super::{
        load_quest_library, validate_quest_definition, QuestConnection, QuestDefinition,
        QuestDefinitionValidationError, QuestFlow, QuestNode, QuestRewardItem, QuestRewards,
        QuestValidationCatalog,
    };
    use std::collections::{BTreeMap, BTreeSet};
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn validate_quest_accepts_realistic_flow() {
        let definition = QuestDefinition {
            quest_id: "find_food".to_string(),
            title: "Find Food".to_string(),
            description: String::new(),
            prerequisites: vec!["first_explore".to_string()],
            time_limit: -1,
            flow: QuestFlow {
                start_node_id: "start".to_string(),
                nodes: BTreeMap::from([
                    (
                        "start".to_string(),
                        QuestNode {
                            id: "start".to_string(),
                            node_type: "start".to_string(),
                            ..QuestNode::default()
                        },
                    ),
                    (
                        "collect_food".to_string(),
                        QuestNode {
                            id: "collect_food".to_string(),
                            node_type: "objective".to_string(),
                            objective_type: "collect".to_string(),
                            item_id: Some(1007),
                            count: 3,
                            ..QuestNode::default()
                        },
                    ),
                    (
                        "reward".to_string(),
                        QuestNode {
                            id: "reward".to_string(),
                            node_type: "reward".to_string(),
                            rewards: QuestRewards {
                                items: vec![QuestRewardItem {
                                    id: 1008,
                                    count: 1,
                                    ..QuestRewardItem::default()
                                }],
                                ..QuestRewards::default()
                            },
                            ..QuestNode::default()
                        },
                    ),
                    (
                        "end".to_string(),
                        QuestNode {
                            id: "end".to_string(),
                            node_type: "end".to_string(),
                            ..QuestNode::default()
                        },
                    ),
                ]),
                connections: vec![
                    QuestConnection {
                        from: "start".to_string(),
                        to: "collect_food".to_string(),
                        ..QuestConnection::default()
                    },
                    QuestConnection {
                        from: "collect_food".to_string(),
                        to: "reward".to_string(),
                        ..QuestConnection::default()
                    },
                    QuestConnection {
                        from: "reward".to_string(),
                        to: "end".to_string(),
                        ..QuestConnection::default()
                    },
                ],
                ..QuestFlow::default()
            },
            ..QuestDefinition::default()
        };

        let catalog = QuestValidationCatalog {
            quest_ids: ["find_food".to_string(), "first_explore".to_string()]
                .into_iter()
                .collect(),
            item_ids: [1007_u32, 1008_u32].into_iter().collect(),
            dialog_ids: BTreeSet::new(),
            map_location_ids: BTreeSet::new(),
            recipe_ids: BTreeSet::new(),
        };

        validate_quest_definition(&definition, Some(&catalog)).expect("quest should validate");
    }

    #[test]
    fn validate_quest_rejects_missing_start_node() {
        let definition = QuestDefinition {
            quest_id: "broken".to_string(),
            title: "Broken".to_string(),
            flow: QuestFlow {
                start_node_id: "start".to_string(),
                nodes: BTreeMap::from([(
                    "end".to_string(),
                    QuestNode {
                        id: "end".to_string(),
                        node_type: "end".to_string(),
                        ..QuestNode::default()
                    },
                )]),
                ..QuestFlow::default()
            },
            ..QuestDefinition::default()
        };

        let error = validate_quest_definition(&definition, None)
            .expect_err("missing start node should fail");
        assert!(matches!(
            error,
            QuestDefinitionValidationError::InvalidStartNodeCount { .. }
                | QuestDefinitionValidationError::UnknownStartNode { .. }
        ));
    }

    #[test]
    fn validate_quest_rejects_unsupported_objective_type() {
        let definition = QuestDefinition {
            quest_id: "broken".to_string(),
            title: "Broken".to_string(),
            flow: QuestFlow {
                start_node_id: "start".to_string(),
                nodes: BTreeMap::from([
                    (
                        "start".to_string(),
                        QuestNode {
                            id: "start".to_string(),
                            node_type: "start".to_string(),
                            ..QuestNode::default()
                        },
                    ),
                    (
                        "travel".to_string(),
                        QuestNode {
                            id: "travel".to_string(),
                            node_type: "objective".to_string(),
                            objective_type: "travel".to_string(),
                            ..QuestNode::default()
                        },
                    ),
                    (
                        "end".to_string(),
                        QuestNode {
                            id: "end".to_string(),
                            node_type: "end".to_string(),
                            ..QuestNode::default()
                        },
                    ),
                ]),
                connections: vec![
                    QuestConnection {
                        from: "start".to_string(),
                        to: "travel".to_string(),
                        ..QuestConnection::default()
                    },
                    QuestConnection {
                        from: "travel".to_string(),
                        to: "end".to_string(),
                        ..QuestConnection::default()
                    },
                ],
                ..QuestFlow::default()
            },
            ..QuestDefinition::default()
        };

        let error = validate_quest_definition(&definition, None)
            .expect_err("unsupported objective should fail");
        assert!(matches!(
            error,
            QuestDefinitionValidationError::UnsupportedObjectiveType { .. }
        ));
    }

    #[test]
    fn load_quest_library_accepts_real_data() {
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("..")
            .join("..")
            .join("..");
        let quest_dir = repo_root.join("data").join("quests");
        if !quest_dir.exists() {
            return;
        }

        let library = load_quest_library(&quest_dir, None).expect("quest library should load");
        assert!(!library.is_empty());
    }

    #[test]
    fn load_quest_library_backfills_missing_file_id() {
        let temp_dir = create_temp_dir("quest_library_backfills_missing_file_id");
        let quest_path = temp_dir.join("draft_quest.json");
        fs::write(
            &quest_path,
            r#"{
  "title": "Draft",
  "flow": {
    "start_node_id": "start",
    "nodes": {
      "start": { "type": "start" },
      "end": { "type": "end" }
    },
    "connections": [
      { "from": "start", "from_port": 0, "to": "end", "to_port": 0 }
    ]
  }
}"#,
        )
        .expect("quest file should be written");

        let library = load_quest_library(&temp_dir, None).expect("library should load");
        assert!(library.get("draft_quest").is_some());
    }

    fn create_temp_dir(label: &str) -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time should be after epoch")
            .as_nanos();
        let dir = std::env::temp_dir().join(format!("game_data_{label}_{unique}"));
        fs::create_dir_all(&dir).expect("temp dir should be created");
        dir
    }

    fn _write_json(path: &Path, raw: &str) {
        fs::write(path, raw).expect("json file should be written");
    }
}
