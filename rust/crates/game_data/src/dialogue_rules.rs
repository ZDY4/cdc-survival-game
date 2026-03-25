use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use thiserror::Error;

use crate::{DialogueData, NpcRole, WorldMode};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueRuleConditions {
    #[serde(default)]
    pub world_mode_in: Vec<WorldMode>,
    #[serde(default)]
    pub map_id_in: Vec<String>,
    #[serde(default)]
    pub outdoor_location_in: Vec<String>,
    #[serde(default)]
    pub subscene_location_in: Vec<String>,
    #[serde(default)]
    pub player_level_min: Option<i32>,
    #[serde(default)]
    pub player_level_max: Option<i32>,
    #[serde(default)]
    pub player_hp_ratio_min: Option<f32>,
    #[serde(default)]
    pub player_hp_ratio_max: Option<f32>,
    #[serde(default)]
    pub player_active_quests_any: Vec<String>,
    #[serde(default)]
    pub player_completed_quests_any: Vec<String>,
    #[serde(default)]
    pub relation_score_min: Option<i32>,
    #[serde(default)]
    pub relation_score_max: Option<i32>,
    #[serde(default)]
    pub npc_role_in: Vec<NpcRole>,
    #[serde(default)]
    pub npc_on_shift: Option<bool>,
    #[serde(default)]
    pub npc_schedule_labels_in: Vec<String>,
    #[serde(default)]
    pub npc_action_in: Vec<String>,
    #[serde(default)]
    pub npc_morale_min: Option<f32>,
    #[serde(default)]
    pub npc_morale_max: Option<f32>,
}

impl DialogueRuleConditions {
    pub fn matches(&self, context: &DialogueResolutionContext) -> bool {
        if !self.world_mode_in.is_empty() && !self.world_mode_in.contains(&context.world_mode) {
            return false;
        }
        if !matches_optional_string(&self.map_id_in, context.map_id.as_deref()) {
            return false;
        }
        if !matches_optional_string(
            &self.outdoor_location_in,
            context.outdoor_location_id.as_deref(),
        ) {
            return false;
        }
        if !matches_optional_string(
            &self.subscene_location_in,
            context.subscene_location_id.as_deref(),
        ) {
            return false;
        }
        if !matches_min_max_i32(
            context.player_level,
            self.player_level_min,
            self.player_level_max,
        ) {
            return false;
        }
        if !matches_min_max_f32(
            context.player_hp_ratio,
            self.player_hp_ratio_min,
            self.player_hp_ratio_max,
        ) {
            return false;
        }
        if !matches_any_set(
            &self.player_active_quests_any,
            &context.player_active_quests,
        ) {
            return false;
        }
        if !matches_any_set(
            &self.player_completed_quests_any,
            &context.player_completed_quests,
        ) {
            return false;
        }
        if !matches_optional_min_max_i32(
            context.relation_score,
            self.relation_score_min,
            self.relation_score_max,
        ) {
            return false;
        }
        if !self.npc_role_in.is_empty() {
            let Some(role) = context.npc_role else {
                return false;
            };
            if !self.npc_role_in.contains(&role) {
                return false;
            }
        }
        if let Some(expected_on_shift) = self.npc_on_shift {
            if context.npc_on_shift != Some(expected_on_shift) {
                return false;
            }
        }
        if !matches_any_strings(&self.npc_schedule_labels_in, &context.npc_schedule_labels) {
            return false;
        }
        if !matches_optional_string(&self.npc_action_in, context.npc_action.as_deref()) {
            return false;
        }
        matches_optional_min_max_f32(context.npc_morale, self.npc_morale_min, self.npc_morale_max)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueRuleVariant {
    #[serde(default)]
    pub dialogue_id: String,
    #[serde(default)]
    pub when: DialogueRuleConditions,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueRuleDefinition {
    #[serde(default)]
    pub dialogue_key: String,
    #[serde(default)]
    pub default_dialogue_id: String,
    #[serde(default)]
    pub variants: Vec<DialogueRuleVariant>,
    #[serde(flatten)]
    pub extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueResolutionContext {
    #[serde(default)]
    pub world_mode: WorldMode,
    #[serde(default)]
    pub map_id: Option<String>,
    #[serde(default)]
    pub outdoor_location_id: Option<String>,
    #[serde(default)]
    pub subscene_location_id: Option<String>,
    #[serde(default)]
    pub player_level: i32,
    #[serde(default)]
    pub player_hp_ratio: f32,
    #[serde(default)]
    pub player_active_quests: BTreeSet<String>,
    #[serde(default)]
    pub player_completed_quests: BTreeSet<String>,
    #[serde(default)]
    pub relation_score: Option<i32>,
    #[serde(default)]
    pub npc_definition_id: Option<String>,
    #[serde(default)]
    pub npc_role: Option<NpcRole>,
    #[serde(default)]
    pub npc_on_shift: Option<bool>,
    #[serde(default)]
    pub npc_schedule_labels: Vec<String>,
    #[serde(default)]
    pub npc_action: Option<String>,
    #[serde(default)]
    pub npc_morale: Option<f32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum DialogueResolutionSource {
    Variant,
    Default,
    #[default]
    Unresolved,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueResolutionPreview {
    #[serde(default)]
    pub dialogue_key: String,
    #[serde(default)]
    pub resolved_dialogue_id: Option<String>,
    #[serde(default)]
    pub source: DialogueResolutionSource,
    #[serde(default)]
    pub matched_variant_index: Option<usize>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct DialogueResolutionResult {
    #[serde(default)]
    pub dialogue_key: String,
    #[serde(default)]
    pub resolved_dialogue_id: Option<String>,
    #[serde(default)]
    pub source: DialogueResolutionSource,
    #[serde(default)]
    pub used_fallback_dialogue: bool,
    #[serde(default)]
    pub fallback_reason: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct DialogueLibrary {
    definitions: BTreeMap<String, DialogueData>,
}

impl From<BTreeMap<String, DialogueData>> for DialogueLibrary {
    fn from(definitions: BTreeMap<String, DialogueData>) -> Self {
        Self { definitions }
    }
}

impl DialogueLibrary {
    pub fn get(&self, id: &str) -> Option<&DialogueData> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &DialogueData)> {
        self.definitions.iter()
    }

    pub fn ids(&self) -> BTreeSet<String> {
        self.definitions.keys().cloned().collect()
    }

    pub fn is_empty(&self) -> bool {
        self.definitions.is_empty()
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct DialogueRuleLibrary {
    definitions: BTreeMap<String, DialogueRuleDefinition>,
}

impl From<BTreeMap<String, DialogueRuleDefinition>> for DialogueRuleLibrary {
    fn from(definitions: BTreeMap<String, DialogueRuleDefinition>) -> Self {
        Self { definitions }
    }
}

impl DialogueRuleLibrary {
    pub fn get(&self, id: &str) -> Option<&DialogueRuleDefinition> {
        self.definitions.get(id)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&String, &DialogueRuleDefinition)> {
        self.definitions.iter()
    }

    pub fn ids(&self) -> BTreeSet<String> {
        self.definitions.keys().cloned().collect()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct DialogueRuleValidationCatalog {
    pub dialogue_ids: BTreeSet<String>,
}

#[derive(Debug, Error)]
pub enum DialogueValidationError {
    #[error("dialog_id cannot be empty")]
    MissingDialogId,
}

#[derive(Debug, Error)]
pub enum DialogueLoadError {
    #[error("failed to read dialogue directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read dialogue file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse dialogue file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("duplicate dialogue id {dialog_id} in {first_path} and {second_path}")]
    DuplicateId {
        dialog_id: String,
        first_path: PathBuf,
        second_path: PathBuf,
    },
    #[error("dialogue definition in {path} is invalid: {source}")]
    Validation {
        path: PathBuf,
        #[source]
        source: DialogueValidationError,
    },
}

#[derive(Debug, Error)]
pub enum DialogueRuleValidationError {
    #[error("dialogue_key cannot be empty")]
    MissingDialogueKey,
    #[error("dialogue rule {dialogue_key} variant {variant_index} dialogue_id cannot be empty")]
    MissingVariantDialogueId {
        dialogue_key: String,
        variant_index: usize,
    },
    #[error(
        "dialogue rule {dialogue_key} references unknown dialogue id {dialogue_id} in {field}"
    )]
    UnknownDialogueId {
        dialogue_key: String,
        dialogue_id: String,
        field: String,
    },
}

#[derive(Debug, Error)]
pub enum DialogueRuleLoadError {
    #[error("failed to read dialogue rule directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read dialogue rule file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse dialogue rule file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("duplicate dialogue rule {dialogue_key} in {first_path} and {second_path}")]
    DuplicateId {
        dialogue_key: String,
        first_path: PathBuf,
        second_path: PathBuf,
    },
    #[error("dialogue rule definition in {path} is invalid: {source}")]
    Validation {
        path: PathBuf,
        #[source]
        source: DialogueRuleValidationError,
    },
}

pub fn resolve_dialogue_preview(
    definition: &DialogueRuleDefinition,
    context: &DialogueResolutionContext,
) -> DialogueResolutionPreview {
    for (index, variant) in definition.variants.iter().enumerate() {
        if variant.when.matches(context) {
            return DialogueResolutionPreview {
                dialogue_key: definition.dialogue_key.clone(),
                resolved_dialogue_id: Some(variant.dialogue_id.clone()),
                source: DialogueResolutionSource::Variant,
                matched_variant_index: Some(index),
            };
        }
    }

    if !definition.default_dialogue_id.trim().is_empty() {
        return DialogueResolutionPreview {
            dialogue_key: definition.dialogue_key.clone(),
            resolved_dialogue_id: Some(definition.default_dialogue_id.clone()),
            source: DialogueResolutionSource::Default,
            matched_variant_index: None,
        };
    }

    DialogueResolutionPreview {
        dialogue_key: definition.dialogue_key.clone(),
        resolved_dialogue_id: None,
        source: DialogueResolutionSource::Unresolved,
        matched_variant_index: None,
    }
}

pub fn validate_dialogue_definition(
    definition: &DialogueData,
) -> Result<(), DialogueValidationError> {
    if definition.dialog_id.trim().is_empty() {
        return Err(DialogueValidationError::MissingDialogId);
    }
    Ok(())
}

pub fn load_dialogue_library(dir: impl AsRef<Path>) -> Result<DialogueLibrary, DialogueLoadError> {
    let dir = dir.as_ref();
    let entries = fs::read_dir(dir).map_err(|source| DialogueLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    let mut definitions = BTreeMap::new();
    let mut origins = BTreeMap::new();
    for entry in entries {
        let entry = entry.map_err(|source| DialogueLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path).map_err(|source| DialogueLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let mut definition: DialogueData =
            serde_json::from_str(&raw).map_err(|source| DialogueLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;
        if definition.dialog_id.trim().is_empty() {
            definition.dialog_id = file_stem_id(&path);
        }
        validate_dialogue_definition(&definition).map_err(|source| {
            DialogueLoadError::Validation {
                path: path.clone(),
                source,
            }
        })?;

        if let Some(first_path) = origins.insert(definition.dialog_id.clone(), path.clone()) {
            return Err(DialogueLoadError::DuplicateId {
                dialog_id: definition.dialog_id.clone(),
                first_path,
                second_path: path,
            });
        }

        definitions.insert(definition.dialog_id.clone(), definition);
    }

    Ok(DialogueLibrary::from(definitions))
}

pub fn validate_dialogue_rule_definition(
    definition: &DialogueRuleDefinition,
    catalog: Option<&DialogueRuleValidationCatalog>,
) -> Result<(), DialogueRuleValidationError> {
    let dialogue_key = definition.dialogue_key.trim();
    if dialogue_key.is_empty() {
        return Err(DialogueRuleValidationError::MissingDialogueKey);
    }

    if !definition.default_dialogue_id.trim().is_empty() {
        validate_dialogue_reference(
            dialogue_key,
            definition.default_dialogue_id.as_str(),
            "default_dialogue_id",
            catalog,
        )?;
    }

    for (index, variant) in definition.variants.iter().enumerate() {
        if variant.dialogue_id.trim().is_empty() {
            return Err(DialogueRuleValidationError::MissingVariantDialogueId {
                dialogue_key: dialogue_key.to_string(),
                variant_index: index,
            });
        }
        validate_dialogue_reference(
            dialogue_key,
            variant.dialogue_id.as_str(),
            &format!("variants[{index}].dialogue_id"),
            catalog,
        )?;
    }

    Ok(())
}

pub fn load_dialogue_rule_library(
    dir: impl AsRef<Path>,
    catalog: Option<&DialogueRuleValidationCatalog>,
) -> Result<DialogueRuleLibrary, DialogueRuleLoadError> {
    let dir = dir.as_ref();
    let entries = fs::read_dir(dir).map_err(|source| DialogueRuleLoadError::ReadDir {
        path: dir.to_path_buf(),
        source,
    })?;

    let mut definitions = BTreeMap::new();
    let mut origins = BTreeMap::new();
    for entry in entries {
        let entry = entry.map_err(|source| DialogueRuleLoadError::ReadDir {
            path: dir.to_path_buf(),
            source,
        })?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path).map_err(|source| DialogueRuleLoadError::ReadFile {
            path: path.clone(),
            source,
        })?;
        let mut definition: DialogueRuleDefinition =
            serde_json::from_str(&raw).map_err(|source| DialogueRuleLoadError::ParseFile {
                path: path.clone(),
                source,
            })?;
        if definition.dialogue_key.trim().is_empty() {
            definition.dialogue_key = file_stem_id(&path);
        }
        validate_dialogue_rule_definition(&definition, catalog).map_err(|source| {
            DialogueRuleLoadError::Validation {
                path: path.clone(),
                source,
            }
        })?;

        if let Some(first_path) = origins.insert(definition.dialogue_key.clone(), path.clone()) {
            return Err(DialogueRuleLoadError::DuplicateId {
                dialogue_key: definition.dialogue_key.clone(),
                first_path,
                second_path: path,
            });
        }

        definitions.insert(definition.dialogue_key.clone(), definition);
    }

    Ok(DialogueRuleLibrary::from(definitions))
}

fn validate_dialogue_reference(
    dialogue_key: &str,
    dialogue_id: &str,
    field: &str,
    catalog: Option<&DialogueRuleValidationCatalog>,
) -> Result<(), DialogueRuleValidationError> {
    let normalized = dialogue_id.trim();
    if normalized.is_empty() {
        return Ok(());
    }
    if let Some(catalog) = catalog {
        if !catalog.dialogue_ids.is_empty() && !catalog.dialogue_ids.contains(normalized) {
            return Err(DialogueRuleValidationError::UnknownDialogueId {
                dialogue_key: dialogue_key.to_string(),
                dialogue_id: normalized.to_string(),
                field: field.to_string(),
            });
        }
    }
    Ok(())
}

fn matches_optional_string(expected: &[String], actual: Option<&str>) -> bool {
    if expected.is_empty() {
        return true;
    }
    let Some(actual) = actual else {
        return false;
    };
    expected.iter().any(|value| value == actual)
}

fn matches_any_strings(expected: &[String], actual: &[String]) -> bool {
    if expected.is_empty() {
        return true;
    }
    actual
        .iter()
        .any(|label| expected.iter().any(|value| value == label))
}

fn matches_any_set(expected: &[String], actual: &BTreeSet<String>) -> bool {
    if expected.is_empty() {
        return true;
    }
    expected.iter().any(|value| actual.contains(value))
}

fn matches_min_max_i32(value: i32, min: Option<i32>, max: Option<i32>) -> bool {
    min.is_none_or(|min| value >= min) && max.is_none_or(|max| value <= max)
}

fn matches_optional_min_max_i32(value: Option<i32>, min: Option<i32>, max: Option<i32>) -> bool {
    match value {
        Some(value) => matches_min_max_i32(value, min, max),
        None => min.is_none() && max.is_none(),
    }
}

fn matches_min_max_f32(value: f32, min: Option<f32>, max: Option<f32>) -> bool {
    min.is_none_or(|min| value >= min) && max.is_none_or(|max| value <= max)
}

fn matches_optional_min_max_f32(value: Option<f32>, min: Option<f32>, max: Option<f32>) -> bool {
    match value {
        Some(value) => matches_min_max_f32(value, min, max),
        None => min.is_none() && max.is_none(),
    }
}

fn file_stem_id(path: &Path) -> String {
    path.file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_string()
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::time::{SystemTime, UNIX_EPOCH};

    use serde_json::json;

    use super::{
        load_dialogue_library, load_dialogue_rule_library, resolve_dialogue_preview,
        DialogueResolutionContext, DialogueResolutionSource, DialogueRuleConditions,
        DialogueRuleDefinition, DialogueRuleValidationCatalog, DialogueRuleVariant,
    };
    use crate::{DialogueData, DialogueNode, NpcRole, WorldMode};

    #[test]
    fn dialogue_rule_loader_validates_unknown_dialogue_ids() {
        let temp_dir = create_temp_dir("dialogue_rule_loader_validates_unknown_ids");
        write_json(
            &temp_dir.join("trader.json"),
            &json!({
                "dialogue_key": "trader_lao_wang",
                "default_dialogue_id": "missing_dialogue"
            }),
        );

        let error = load_dialogue_rule_library(
            &temp_dir,
            Some(&DialogueRuleValidationCatalog {
                dialogue_ids: ["trader_lao_wang".to_string()].into_iter().collect(),
            }),
        )
        .expect_err("missing dialogue id should fail validation");
        assert!(error.to_string().contains("missing_dialogue"));
    }

    #[test]
    fn dialogue_rule_resolution_prefers_first_matching_variant() {
        let definition = DialogueRuleDefinition {
            dialogue_key: "doctor_chen".to_string(),
            default_dialogue_id: "doctor_chen_default".to_string(),
            variants: vec![
                DialogueRuleVariant {
                    dialogue_id: "doctor_chen_emergency".to_string(),
                    when: DialogueRuleConditions {
                        npc_on_shift: Some(true),
                        player_hp_ratio_max: Some(0.5),
                        ..DialogueRuleConditions::default()
                    },
                    ..DialogueRuleVariant::default()
                },
                DialogueRuleVariant {
                    dialogue_id: "doctor_chen_shift".to_string(),
                    when: DialogueRuleConditions {
                        npc_on_shift: Some(true),
                        ..DialogueRuleConditions::default()
                    },
                    ..DialogueRuleVariant::default()
                },
            ],
            ..DialogueRuleDefinition::default()
        };

        let preview = resolve_dialogue_preview(
            &definition,
            &DialogueResolutionContext {
                world_mode: WorldMode::Interior,
                player_level: 3,
                player_hp_ratio: 0.4,
                npc_role: Some(NpcRole::Doctor),
                npc_on_shift: Some(true),
                ..DialogueResolutionContext::default()
            },
        );

        assert_eq!(
            preview.resolved_dialogue_id.as_deref(),
            Some("doctor_chen_emergency")
        );
        assert_eq!(preview.source, DialogueResolutionSource::Variant);
        assert_eq!(preview.matched_variant_index, Some(0));
    }

    #[test]
    fn dialogue_loader_backfills_missing_file_id() {
        let temp_dir = create_temp_dir("dialogue_loader_backfills_missing_file_id");
        write_json(
            &temp_dir.join("fallback.json"),
            &json!({
                "nodes": [{
                    "id": "start",
                    "type": "dialog",
                    "text": "hi",
                    "is_start": true
                }]
            }),
        );

        let library = load_dialogue_library(&temp_dir).expect("dialogue library should load");
        let dialogue = library
            .get("fallback")
            .expect("dialogue id should be backfilled from file name");
        assert_eq!(dialogue.dialog_id, "fallback");
    }

    #[test]
    fn dialogue_rule_conditions_match_quests_and_npc_state() {
        let conditions = DialogueRuleConditions {
            player_completed_quests_any: vec!["clinic_intro".to_string()],
            npc_role_in: vec![NpcRole::Doctor],
            npc_action_in: vec!["treat_patients".to_string()],
            npc_schedule_labels_in: vec!["诊所轮值".to_string()],
            relation_score_min: Some(20),
            ..DialogueRuleConditions::default()
        };

        assert!(conditions.matches(&DialogueResolutionContext {
            player_completed_quests: ["clinic_intro".to_string()].into_iter().collect(),
            relation_score: Some(40),
            npc_role: Some(NpcRole::Doctor),
            npc_schedule_labels: vec!["诊所轮值".to_string()],
            npc_action: Some("treat_patients".to_string()),
            ..DialogueResolutionContext::default()
        }));
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

    fn write_json(path: &Path, value: &serde_json::Value) {
        let raw = serde_json::to_string_pretty(value).expect("json should serialize");
        fs::write(path, raw).expect("json file should be written");
    }

    #[allow(dead_code)]
    fn sample_dialogue(dialog_id: &str) -> DialogueData {
        DialogueData {
            dialog_id: dialog_id.to_string(),
            nodes: vec![DialogueNode {
                id: "start".to_string(),
                node_type: "dialog".to_string(),
                text: "hello".to_string(),
                is_start: true,
                ..DialogueNode::default()
            }],
            ..DialogueData::default()
        }
    }
}
