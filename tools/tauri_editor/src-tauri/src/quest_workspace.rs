use std::collections::{BTreeSet, HashSet};
use std::fs;
use std::path::{Path, PathBuf};

use game_data::{
    QuestDefinition, QuestDefinitionValidationError, QuestLibrary, QuestLoadError,
    QuestValidationCatalog,
};
use serde::{Deserialize, Serialize};

use crate::{EditorBootstrap, ValidationIssue};

const DEFAULT_QUEST_NODE_TYPES: &[&str] =
    &["start", "objective", "dialog", "choice", "reward", "end"];
const DEFAULT_OBJECTIVE_TYPES: &[&str] = &[
    "travel",
    "search",
    "collect",
    "kill",
    "sleep",
    "survive",
    "craft",
    "build",
];

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuestCatalogs {
    pub node_types: Vec<String>,
    pub objective_types: Vec<String>,
    pub item_ids: Vec<String>,
    pub dialog_ids: Vec<String>,
    pub quest_ids: Vec<String>,
    pub location_ids: Vec<String>,
    pub recipe_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuestDocumentPayload {
    pub document_key: String,
    pub original_id: String,
    pub file_name: String,
    pub relative_path: String,
    pub quest: QuestDefinition,
    pub validation: Vec<ValidationIssue>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuestWorkspacePayload {
    pub bootstrap: EditorBootstrap,
    pub data_directory: String,
    pub quest_count: usize,
    pub catalogs: QuestCatalogs,
    pub documents: Vec<QuestDocumentPayload>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveQuestDocumentInput {
    pub original_id: Option<String>,
    pub quest: QuestDefinition,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveQuestsResult {
    pub saved_ids: Vec<String>,
    pub deleted_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteQuestResult {
    pub deleted_id: String,
}

#[tauri::command]
pub fn load_quest_workspace() -> Result<QuestWorkspacePayload, String> {
    let documents = load_quest_documents()?;
    let bootstrap = crate::editor_bootstrap()?;
    let validation_catalog = quest_validation_catalog(Some(&documents))?;
    let catalogs = collect_quest_catalogs(&documents, &validation_catalog);

    Ok(QuestWorkspacePayload {
        bootstrap,
        data_directory: crate::to_forward_slashes(quest_data_dir()?),
        quest_count: documents.len(),
        catalogs,
        documents,
    })
}

#[tauri::command]
pub fn validate_quest_document(quest: QuestDefinition) -> Result<Vec<ValidationIssue>, String> {
    let catalog = quest_validation_catalog(None)?;
    Ok(validate_quest_record(&quest, &catalog))
}

#[tauri::command]
pub fn save_quest_documents(
    documents: Vec<SaveQuestDocumentInput>,
) -> Result<SaveQuestsResult, String> {
    if documents.is_empty() {
        return Ok(SaveQuestsResult {
            saved_ids: Vec::new(),
            deleted_ids: Vec::new(),
        });
    }

    let mut seen_ids = HashSet::new();
    let mut catalog = quest_validation_catalog(None)?;
    for document in &documents {
        let quest_id = document.quest.quest_id.trim();
        if quest_id.is_empty() {
            return Err("quest_id cannot be empty".to_string());
        }
        if !seen_ids.insert(quest_id.to_string()) {
            return Err(format!("duplicate quest id in save batch: {quest_id}"));
        }
        catalog.quest_ids.insert(quest_id.to_string());
    }

    for document in &documents {
        let issues = validate_quest_record(&document.quest, &catalog);
        if issues.iter().any(|issue| issue.severity == "error") {
            return Err(format!(
                "quest {} has validation errors and cannot be saved",
                document.quest.quest_id
            ));
        }
    }

    let data_dir = quest_data_dir()?;
    fs::create_dir_all(&data_dir)
        .map_err(|error| format!("failed to create {}: {error}", data_dir.display()))?;

    let mut saved_ids = Vec::new();
    let mut deleted_ids = Vec::new();
    for document in documents {
        let quest = document.quest;
        let target_path = quest_file_path(&quest.quest_id)?;
        let json = serde_json::to_string_pretty(&quest)
            .map_err(|error| format!("failed to serialize quest {}: {error}", quest.quest_id))?;
        fs::write(&target_path, json)
            .map_err(|error| format!("failed to write {}: {error}", target_path.display()))?;

        if let Some(original_id) = document.original_id {
            if original_id != quest.quest_id {
                let old_path = quest_file_path(&original_id)?;
                if old_path.exists() {
                    fs::remove_file(&old_path).map_err(|error| {
                        format!("failed to remove renamed quest {}: {error}", original_id)
                    })?;
                    deleted_ids.push(original_id);
                }
            }
        }

        saved_ids.push(quest.quest_id);
    }

    Ok(SaveQuestsResult {
        saved_ids,
        deleted_ids,
    })
}

#[tauri::command]
pub fn delete_quest_document(quest_id: String) -> Result<DeleteQuestResult, String> {
    let path = quest_file_path(&quest_id)?;
    if path.exists() {
        fs::remove_file(&path)
            .map_err(|error| format!("failed to delete {}: {error}", path.display()))?;
    }
    Ok(DeleteQuestResult { deleted_id: quest_id })
}

pub fn validate_quest_record(
    quest: &QuestDefinition,
    validation_catalog: &QuestValidationCatalog,
) -> Vec<ValidationIssue> {
    match game_data::validate_quest_definition(quest, Some(validation_catalog)) {
        Ok(()) => Vec::new(),
        Err(error) => vec![map_quest_validation_error(error)],
    }
}

pub fn quest_validation_catalog(
    loaded_documents: Option<&[QuestDocumentPayload]>,
) -> Result<QuestValidationCatalog, String> {
    let repo_root = quest_repo_root()?;
    let mut catalog = QuestValidationCatalog {
        quest_ids: quest_ids_from_fs()?,
        item_ids: load_numeric_ids(&repo_root.join("data").join("items"))?,
        dialog_ids: stem_ids(&repo_root.join("data").join("dialogues"))?,
        map_location_ids: object_ids_from_file(
            &repo_root.join("data").join("json").join("map_locations.json"),
        )?,
        recipe_ids: stem_ids(&repo_root.join("data").join("recipes"))?,
    };

    if let Some(documents) = loaded_documents {
        for document in documents {
            catalog.quest_ids.insert(document.quest.quest_id.clone());
        }
    }

    Ok(catalog)
}

fn load_quest_documents() -> Result<Vec<QuestDocumentPayload>, String> {
    let data_dir = quest_data_dir()?;
    if !data_dir.exists() {
        return Ok(Vec::new());
    }

    let validation_catalog = quest_validation_catalog(None)?;
    let library: QuestLibrary = game_data::load_quest_library(&data_dir, None)
        .map_err(|error| format_quest_load_error(&data_dir, error))?;

    let mut documents = Vec::new();
    for (quest_id, quest) in library.iter() {
        let path = quest_file_path(quest_id)?;
        let file_name = path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string();
        let relative_path = crate::relative_to_repo(&path)?;
        let validation = validate_quest_record(quest, &validation_catalog);

        documents.push(QuestDocumentPayload {
            document_key: quest_id.clone(),
            original_id: quest_id.clone(),
            file_name,
            relative_path,
            quest: quest.clone(),
            validation,
        });
    }

    documents.sort_by(|left, right| left.document_key.cmp(&right.document_key));
    Ok(documents)
}

fn collect_quest_catalogs(
    documents: &[QuestDocumentPayload],
    validation_catalog: &QuestValidationCatalog,
) -> QuestCatalogs {
    let mut node_types = seeded_set(DEFAULT_QUEST_NODE_TYPES);
    let mut objective_types = seeded_set(DEFAULT_OBJECTIVE_TYPES);

    for document in documents {
        for node in document.quest.flow.nodes.values() {
            if !node.node_type.trim().is_empty() {
                node_types.insert(node.node_type.clone());
            }
            if !node.objective_type.trim().is_empty() {
                objective_types.insert(node.objective_type.clone());
            }
        }
    }

    QuestCatalogs {
        node_types: node_types.into_iter().collect(),
        objective_types: objective_types.into_iter().collect(),
        item_ids: validation_catalog
            .item_ids
            .iter()
            .map(ToString::to_string)
            .collect(),
        dialog_ids: validation_catalog.dialog_ids.iter().cloned().collect(),
        quest_ids: validation_catalog.quest_ids.iter().cloned().collect(),
        location_ids: validation_catalog.map_location_ids.iter().cloned().collect(),
        recipe_ids: validation_catalog.recipe_ids.iter().cloned().collect(),
    }
}

fn map_quest_validation_error(error: QuestDefinitionValidationError) -> ValidationIssue {
    match error {
        QuestDefinitionValidationError::MissingQuestId => crate::document_error("questId", "quest_id cannot be empty"),
        QuestDefinitionValidationError::MissingTitle { quest_id } => {
            crate::document_error("title", format!("Quest {quest_id} title cannot be empty."))
        }
        QuestDefinitionValidationError::UnknownPrerequisite {
            prerequisite_id, ..
        } => crate::document_error(
            "prerequisites",
            format!("Unknown prerequisite quest: {prerequisite_id}."),
        ),
        QuestDefinitionValidationError::MissingStartNodeId { .. } => {
            crate::document_error("flow.startNodeId", "flow.start_node_id cannot be empty.")
        }
        QuestDefinitionValidationError::InvalidStartNodeCount { count, .. } => crate::document_error(
            "flow.nodes",
            format!("Quest must contain exactly one start node, found {count}."),
        ),
        QuestDefinitionValidationError::MissingEndNode { .. } => {
            crate::document_error("flow.nodes", "Quest must contain at least one end node.")
        }
        QuestDefinitionValidationError::UnknownStartNode { node_id, .. } => crate::document_error(
            "flow.startNodeId",
            format!("flow.start_node_id points to missing node {node_id}."),
        ),
        QuestDefinitionValidationError::StartNodeTypeMismatch { node_id, .. } => crate::node_error(
            &node_id,
            "type",
            "flow.start_node_id must point to a start node.".to_string(),
        ),
        QuestDefinitionValidationError::MissingNodeId { node_key, .. } => crate::document_error(
            "flow.nodes",
            format!("Node {node_key} is missing its id."),
        ),
        QuestDefinitionValidationError::NodeIdMismatch {
            node_key, node_id, ..
        } => crate::document_error(
            "flow.nodes",
            format!("Node key {node_key} does not match node id {node_id}."),
        ),
        QuestDefinitionValidationError::MissingObjectiveType { node_id, .. } => crate::node_error(
            &node_id,
            "objectiveType",
            "Objective nodes must define objective_type.".to_string(),
        ),
        QuestDefinitionValidationError::UnknownObjectiveItem {
            node_id, item_id, ..
        } => crate::node_error(
            &node_id,
            "itemId",
            if item_id == 0 {
                "Collect objectives must define item_id.".to_string()
            } else {
                format!("Collect objective references unknown item id {item_id}.")
            },
        ),
        QuestDefinitionValidationError::MissingDialogId { node_id, .. } => crate::node_error(
            &node_id,
            "dialogId",
            "Dialog nodes must define dialog_id.".to_string(),
        ),
        QuestDefinitionValidationError::UnknownDialogId {
            node_id, dialog_id, ..
        } => crate::node_error(
            &node_id,
            "dialogId",
            format!("Dialog node references unknown dialog id {dialog_id}."),
        ),
        QuestDefinitionValidationError::EmptyChoiceOptions { node_id, .. } => crate::node_error(
            &node_id,
            "options",
            "Choice nodes must define at least one option.".to_string(),
        ),
        QuestDefinitionValidationError::UnknownRewardItem {
            node_id, item_id, ..
        } => crate::node_error(
            &node_id,
            "rewards.items",
            format!("Reward node references unknown item id {item_id}."),
        ),
        QuestDefinitionValidationError::UnknownUnlockLocation {
            node_id,
            location_id,
            ..
        } => crate::node_error(
            &node_id,
            "rewards.unlockLocation",
            format!("Reward node references unknown location id {location_id}."),
        ),
        QuestDefinitionValidationError::UnknownUnlockRecipe {
            node_id,
            recipe_id,
            ..
        } => crate::node_error(
            &node_id,
            "rewards.unlockRecipes",
            format!("Reward node references unknown recipe id {recipe_id}."),
        ),
        QuestDefinitionValidationError::UnknownConnectionNode {
            from,
            from_port,
            to,
            to_port,
            ..
        } => crate::edge_error(
            format!("{from}:{from_port}->{to}:{to_port}"),
            "flow.connections",
            "Connection references missing quest flow nodes.",
        ),
    }
}

fn format_quest_load_error(data_dir: &Path, error: QuestLoadError) -> String {
    match error {
        QuestLoadError::ReadDir { source, .. } => {
            format!("failed to read {}: {source}", data_dir.display())
        }
        other => other.to_string(),
    }
}

fn seeded_set(values: &[&str]) -> BTreeSet<String> {
    values.iter().map(|value| (*value).to_string()).collect()
}

fn quest_ids_from_fs() -> Result<BTreeSet<String>, String> {
    stem_ids(&quest_data_dir()?)
}

fn load_numeric_ids(directory: &Path) -> Result<BTreeSet<u32>, String> {
    let mut ids = BTreeSet::new();
    for id in stem_ids(directory)? {
        if let Ok(value) = id.parse::<u32>() {
            ids.insert(value);
        }
    }
    Ok(ids)
}

fn stem_ids(directory: &Path) -> Result<BTreeSet<String>, String> {
    if !directory.exists() {
        return Ok(BTreeSet::new());
    }

    let mut entries = fs::read_dir(directory)
        .map_err(|error| format!("failed to read {}: {error}", directory.display()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("failed to enumerate {}: {error}", directory.display()))?;
    entries.sort_by_key(|entry| entry.file_name());

    let mut ids = BTreeSet::new();
    for entry in entries {
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let id = path
            .file_stem()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .trim()
            .to_string();
        if !id.is_empty() {
            ids.insert(id);
        }
    }
    Ok(ids)
}

fn object_ids_from_file(path: &Path) -> Result<BTreeSet<String>, String> {
    if !path.exists() {
        return Ok(BTreeSet::new());
    }

    let raw = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let parsed: serde_json::Value = serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;

    let mut ids = BTreeSet::new();
    if let serde_json::Value::Object(map) = parsed {
        for key in map.keys() {
            ids.insert(key.clone());
        }
    }
    Ok(ids)
}

pub fn quest_data_dir() -> Result<PathBuf, String> {
    Ok(quest_repo_root()?.join("data").join("quests"))
}

pub fn quest_file_path(quest_id: &str) -> Result<PathBuf, String> {
    Ok(quest_data_dir()?.join(format!("{quest_id}.json")))
}

fn quest_repo_root() -> Result<PathBuf, String> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("..");
    root.canonicalize()
        .map_err(|error| format!("failed to resolve repo root: {error}"))
}

#[cfg(test)]
mod tests {
    use super::{quest_validation_catalog, validate_quest_record};

    #[test]
    fn validation_catalog_loads_project_ids() {
        let catalog = quest_validation_catalog(None).expect("catalog should load");
        assert!(!catalog.quest_ids.is_empty());
        assert!(!catalog.item_ids.is_empty());
    }

    #[test]
    fn validate_real_quest_data_is_clean() {
        let documents = super::load_quest_documents().expect("quest documents should load");
        let catalog = quest_validation_catalog(Some(&documents)).expect("catalog should load");
        for document in &documents {
            let issues = validate_quest_record(&document.quest, &catalog);
            assert!(
                issues.is_empty(),
                "quest {} should validate cleanly, got {:?}",
                document.quest.quest_id,
                issues
            );
        }
    }
}
