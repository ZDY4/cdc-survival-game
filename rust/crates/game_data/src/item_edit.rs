use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    load_effect_library, validate_item_definition, EffectLoadError, ItemDefinition,
    ItemDefinitionValidationError, ItemEditDiagnosticSeverity::Error as DiagnosticError,
    ItemValidationCatalog,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ItemEditDiagnosticSeverity {
    Error,
    Warning,
    Info,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemEditDiagnostic {
    pub severity: ItemEditDiagnosticSeverity,
    pub code: String,
    pub message: String,
}

impl ItemEditDiagnostic {
    pub fn error(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            severity: DiagnosticError,
            code: code.into(),
            message: message.into(),
        }
    }
}

impl From<&ItemDefinitionValidationError> for ItemEditDiagnostic {
    fn from(value: &ItemDefinitionValidationError) -> Self {
        Self::error("validation_error", value.to_string())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct ItemEditOperationSummary {
    pub operation: String,
    pub item_id: Option<u32>,
    pub path: Option<PathBuf>,
    pub changed: bool,
    pub details: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ItemEditResult {
    pub changed: bool,
    pub diagnostics: Vec<ItemEditDiagnostic>,
    pub summary: ItemEditOperationSummary,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ItemEditDocument {
    pub file_name: String,
    pub relative_path: String,
    pub definition: ItemDefinition,
    pub diagnostics: Vec<ItemEditDiagnostic>,
}

#[derive(Debug, Error)]
pub enum ItemEditError {
    #[error("item id must be a positive integer")]
    InvalidItemId,
    #[error("failed to read item directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read item file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse item file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("failed to load effect catalog from {path}: {source}")]
    LoadEffectCatalog {
        path: PathBuf,
        #[source]
        source: EffectLoadError,
    },
    #[error("item {item_id} failed validation: {source}")]
    InvalidItemDefinition {
        item_id: u32,
        #[source]
        source: ItemDefinitionValidationError,
    },
    #[error("failed to serialize item {item_id}: {source}")]
    SerializeItem {
        item_id: u32,
        #[source]
        source: serde_json::Error,
    },
    #[error("failed to create directory {path}: {source}")]
    CreateDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to write temporary item file {path}: {source}")]
    WriteTempFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to replace item file {path}: {source}")]
    ReplaceFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to delete item file {path}: {source}")]
    DeleteFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
}

#[derive(Debug, Clone)]
pub struct ItemEditorService {
    items_dir: PathBuf,
    data_root: Option<PathBuf>,
}

impl ItemEditorService {
    pub fn new(items_dir: impl Into<PathBuf>) -> Self {
        let items_dir = items_dir.into();
        let data_root = infer_data_root(&items_dir);
        Self {
            items_dir,
            data_root,
        }
    }

    pub fn with_data_root(items_dir: impl Into<PathBuf>, data_root: impl Into<PathBuf>) -> Self {
        Self {
            items_dir: items_dir.into(),
            data_root: Some(data_root.into()),
        }
    }

    pub fn items_dir(&self) -> &Path {
        &self.items_dir
    }

    pub fn data_root(&self) -> Option<&Path> {
        self.data_root.as_deref()
    }

    pub fn load_documents(&self) -> Result<Vec<ItemEditDocument>, ItemEditError> {
        if !self.items_dir.exists() {
            return Ok(Vec::new());
        }

        let effect_ids = self.effect_ids()?;
        let mut entries = fs::read_dir(&self.items_dir)
            .map_err(|source| ItemEditError::ReadDir {
                path: self.items_dir.clone(),
                source,
            })?
            .collect::<Result<Vec<_>, _>>()
            .map_err(|source| ItemEditError::ReadDir {
                path: self.items_dir.clone(),
                source,
            })?;
        entries.sort_by_key(|entry| entry.file_name());

        let mut definitions = Vec::new();
        for entry in entries {
            let path = entry.path();
            if path.extension().and_then(|value| value.to_str()) != Some("json") {
                continue;
            }
            let raw = fs::read_to_string(&path).map_err(|source| ItemEditError::ReadFile {
                path: path.clone(),
                source,
            })?;
            let definition: ItemDefinition =
                serde_json::from_str(&raw).map_err(|source| ItemEditError::ParseFile {
                    path: path.clone(),
                    source,
                })?;
            let file_name = path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .to_string();
            definitions.push((path, file_name, definition));
        }

        let item_ids = definitions
            .iter()
            .map(|(_, _, definition)| definition.id)
            .collect::<BTreeSet<_>>();

        let mut documents = definitions
            .into_iter()
            .map(|(path, file_name, definition)| {
                let diagnostics = self.validate_definition_with_item_ids_inner(
                    &definition,
                    &item_ids,
                    &effect_ids,
                )?;
                let relative_path = relative_to_root(&path, self.data_root.as_deref())
                    .unwrap_or_else(|| path.to_string_lossy().replace('\\', "/"));
                Ok(ItemEditDocument {
                    file_name,
                    relative_path,
                    definition,
                    diagnostics,
                })
            })
            .collect::<Result<Vec<_>, ItemEditError>>()?;

        let duplicate_ids = duplicate_ids(documents.iter().map(|document| document.definition.id));
        for document in &mut documents {
            if duplicate_ids.contains(&document.definition.id) {
                document.diagnostics.push(ItemEditDiagnostic::error(
                    "duplicate_item_id",
                    format!(
                        "item {} appears more than once in data/items",
                        document.definition.id
                    ),
                ));
            }
        }

        documents.sort_by(|left, right| {
            left.definition
                .id
                .cmp(&right.definition.id)
                .then_with(|| left.file_name.cmp(&right.file_name))
        });
        Ok(documents)
    }

    pub fn validate_definition_result(
        &self,
        definition: &ItemDefinition,
    ) -> Result<ItemEditResult, ItemEditError> {
        let item_ids = self.load_item_ids_from_disk()?;
        self.validate_definition_with_item_ids(definition, item_ids)
    }

    pub fn validate_definition_with_item_ids(
        &self,
        definition: &ItemDefinition,
        item_ids: BTreeSet<u32>,
    ) -> Result<ItemEditResult, ItemEditError> {
        let effect_ids = self.effect_ids()?;
        let diagnostics =
            self.validate_definition_with_item_ids_inner(definition, &item_ids, &effect_ids)?;
        let detail = if diagnostics.is_empty() {
            "item definition is valid".to_string()
        } else {
            "item definition is invalid".to_string()
        };

        Ok(ItemEditResult {
            changed: false,
            diagnostics,
            summary: ItemEditOperationSummary {
                operation: "validate_item_definition".to_string(),
                item_id: Some(definition.id),
                path: None,
                changed: false,
                details: vec![detail],
            },
        })
    }

    pub fn save_item_definition(
        &self,
        original_id: Option<u32>,
        definition: &ItemDefinition,
        item_ids: BTreeSet<u32>,
    ) -> Result<ItemEditResult, ItemEditError> {
        if definition.id == 0 {
            return Err(ItemEditError::InvalidItemId);
        }

        self.validate_definition_with_item_ids(definition, item_ids)?;
        let target_path = self.path_for_item_id(definition.id);
        let mut details = Vec::new();
        let mut changed = self.write_item(definition, &target_path)?;
        details.push(format!("saved item {}", definition.id));

        if let Some(original_id) = original_id.filter(|original_id| *original_id != definition.id) {
            let old_path = self.path_for_item_id(original_id);
            if old_path.exists() {
                fs::remove_file(&old_path).map_err(|source| ItemEditError::DeleteFile {
                    path: old_path.clone(),
                    source,
                })?;
                changed = true;
                details.push(format!("removed renamed item {}", original_id));
            }
        }

        Ok(ItemEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: ItemEditOperationSummary {
                operation: "save_item_definition".to_string(),
                item_id: Some(definition.id),
                path: Some(target_path),
                changed,
                details,
            },
        })
    }

    pub fn delete_item_definition(&self, item_id: u32) -> Result<ItemEditResult, ItemEditError> {
        if item_id == 0 {
            return Err(ItemEditError::InvalidItemId);
        }

        let path = self.path_for_item_id(item_id);
        let changed = if path.exists() {
            fs::remove_file(&path).map_err(|source| ItemEditError::DeleteFile {
                path: path.clone(),
                source,
            })?;
            true
        } else {
            false
        };

        Ok(ItemEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: ItemEditOperationSummary {
                operation: "delete_item_definition".to_string(),
                item_id: Some(item_id),
                path: Some(path),
                changed,
                details: vec![format!("deleted item {}", item_id)],
            },
        })
    }

    fn load_item_ids_from_disk(&self) -> Result<BTreeSet<u32>, ItemEditError> {
        Ok(self
            .load_documents()?
            .into_iter()
            .map(|document| document.definition.id)
            .collect())
    }

    fn validate_definition_with_item_ids_inner(
        &self,
        definition: &ItemDefinition,
        item_ids: &BTreeSet<u32>,
        effect_ids: &BTreeSet<String>,
    ) -> Result<Vec<ItemEditDiagnostic>, ItemEditError> {
        let catalog = ItemValidationCatalog {
            item_ids: item_ids.clone(),
            effect_ids: effect_ids.clone(),
        };
        match validate_item_definition(definition, Some(&catalog)) {
            Ok(()) => Ok(Vec::new()),
            Err(source) => Ok(vec![ItemEditDiagnostic::from(&source)]),
        }
    }

    fn effect_ids(&self) -> Result<BTreeSet<String>, ItemEditError> {
        let Some(data_root) = self.data_root.as_ref() else {
            return Ok(BTreeSet::new());
        };
        let effects_dir = data_root.join("json").join("effects");
        if !effects_dir.exists() {
            return Ok(BTreeSet::new());
        }
        load_effect_library(&effects_dir)
            .map(|library| library.ids())
            .map_err(|source| ItemEditError::LoadEffectCatalog {
                path: effects_dir,
                source,
            })
    }

    fn path_for_item_id(&self, item_id: u32) -> PathBuf {
        self.items_dir.join(format!("{item_id}.json"))
    }

    fn write_item(&self, definition: &ItemDefinition, path: &Path) -> Result<bool, ItemEditError> {
        let raw = serde_json::to_string_pretty(definition).map_err(|source| {
            ItemEditError::SerializeItem {
                item_id: definition.id,
                source,
            }
        })?;

        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|source| ItemEditError::CreateDir {
                path: parent.to_path_buf(),
                source,
            })?;
        }

        if let Ok(existing_raw) = fs::read_to_string(path) {
            if existing_raw == raw {
                return Ok(false);
            }
        }

        let temp_path = temporary_path_for(path);
        fs::write(&temp_path, raw).map_err(|source| ItemEditError::WriteTempFile {
            path: temp_path.clone(),
            source,
        })?;
        if path.exists() {
            fs::remove_file(path).map_err(|source| ItemEditError::ReplaceFile {
                path: path.to_path_buf(),
                source,
            })?;
        }
        fs::rename(&temp_path, path).map_err(|source| ItemEditError::ReplaceFile {
            path: path.to_path_buf(),
            source,
        })?;
        Ok(true)
    }
}

fn infer_data_root(items_dir: &Path) -> Option<PathBuf> {
    let parent = items_dir.parent()?;
    let items_name = items_dir.file_name()?.to_str()?;
    if items_name != "items" {
        return None;
    }
    Some(parent.to_path_buf())
}

fn relative_to_root(path: &Path, data_root: Option<&Path>) -> Option<String> {
    let data_root = data_root?;
    path.strip_prefix(data_root)
        .ok()
        .map(|relative| relative.to_string_lossy().replace('\\', "/"))
}

fn duplicate_ids(ids: impl IntoIterator<Item = u32>) -> BTreeSet<u32> {
    let mut seen = BTreeSet::new();
    let mut duplicates = BTreeSet::new();
    for id in ids {
        if !seen.insert(id) {
            duplicates.insert(id);
        }
    }
    duplicates
}

fn temporary_path_for(path: &Path) -> PathBuf {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("item.json");
    path.with_file_name(format!("{file_name}.tmp"))
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::*;
    use crate::ItemFragment;

    #[test]
    fn load_documents_marks_duplicate_ids() {
        let fixture = TestFixture::new();
        fixture.write_item_json(
            "100.json",
            serde_json::json!({
                "id": 100,
                "name": "alpha",
                "fragments": [{ "kind": "stacking", "stackable": true, "max_stack": 1 }]
            }),
        );
        fixture.write_item_json(
            "100-copy.json",
            serde_json::json!({
                "id": 100,
                "name": "beta",
                "fragments": [{ "kind": "stacking", "stackable": true, "max_stack": 1 }]
            }),
        );

        let documents = fixture
            .service()
            .load_documents()
            .expect("documents should load");
        assert_eq!(documents.len(), 2);
        assert!(documents.iter().all(|document| {
            document
                .diagnostics
                .iter()
                .any(|diagnostic| diagnostic.code == "duplicate_item_id")
        }));
    }

    #[test]
    fn save_item_definition_removes_old_file_when_id_changes() {
        let fixture = TestFixture::new();
        fixture.write_item_json(
            "100.json",
            serde_json::json!({
                "id": 100,
                "name": "alpha",
                "fragments": [{ "kind": "stacking", "stackable": true, "max_stack": 1 }]
            }),
        );

        let definition = ItemDefinition {
            id: 101,
            name: "renamed".to_string(),
            description: String::new(),
            icon_path: String::new(),
            value: 0,
            weight: 0.0,
            fragments: vec![ItemFragment::Stacking {
                stackable: true,
                max_stack: 1,
            }],
            extra: Default::default(),
        };

        fixture
            .service()
            .save_item_definition(Some(100), &definition, [101_u32].into_iter().collect())
            .expect("save should succeed");

        assert!(!fixture.items_dir.join("100.json").exists());
        assert!(fixture.items_dir.join("101.json").exists());
    }

    struct TestFixture {
        root: PathBuf,
        items_dir: PathBuf,
    }

    impl TestFixture {
        fn new() -> Self {
            static COUNTER: AtomicU64 = AtomicU64::new(0);
            let unique = COUNTER.fetch_add(1, Ordering::Relaxed);
            let timestamp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("time should be valid")
                .as_nanos();
            let root =
                std::env::temp_dir().join(format!("cdc_item_edit_test_{}_{}", timestamp, unique));
            let items_dir = root.join("items");
            fs::create_dir_all(root.join("json").join("effects"))
                .expect("effects dir should exist");
            fs::create_dir_all(&items_dir).expect("items dir should exist");
            Self { root, items_dir }
        }

        fn service(&self) -> ItemEditorService {
            ItemEditorService::with_data_root(&self.items_dir, &self.root)
        }

        fn write_item_json(&self, name: &str, value: serde_json::Value) {
            fs::write(
                self.items_dir.join(name),
                serde_json::to_string_pretty(&value).expect("json should serialize"),
            )
            .expect("item should be written");
        }
    }

    impl Drop for TestFixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.root);
        }
    }
}
