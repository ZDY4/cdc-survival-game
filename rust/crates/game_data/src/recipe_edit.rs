use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::{
    file_backed::{
        collect_sorted_dir_entries, duplicate_values, read_json_file, relative_path_from_root,
        write_json_atomically,
    },
    load_item_library, load_recipe_library, load_skill_library, validate_recipe_definition,
    ItemLoadError, RecipeDefinition, RecipeDefinitionValidationError, RecipeLoadError,
    RecipeValidationCatalog, SkillLoadError, SkillValidationCatalog,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RecipeEditDiagnosticSeverity {
    Error,
    Warning,
    Info,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecipeEditDiagnostic {
    pub severity: RecipeEditDiagnosticSeverity,
    pub code: String,
    pub message: String,
}

impl RecipeEditDiagnostic {
    pub fn error(code: impl Into<String>, message: impl Into<String>) -> Self {
        Self {
            severity: RecipeEditDiagnosticSeverity::Error,
            code: code.into(),
            message: message.into(),
        }
    }
}

impl From<&RecipeDefinitionValidationError> for RecipeEditDiagnostic {
    fn from(value: &RecipeDefinitionValidationError) -> Self {
        Self::error("validation_error", value.to_string())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct RecipeEditOperationSummary {
    pub operation: String,
    pub recipe_id: Option<String>,
    pub path: Option<PathBuf>,
    pub changed: bool,
    pub details: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RecipeEditResult {
    pub changed: bool,
    pub diagnostics: Vec<RecipeEditDiagnostic>,
    pub summary: RecipeEditOperationSummary,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct RecipeEditDocument {
    pub file_name: String,
    pub relative_path: String,
    pub definition: RecipeDefinition,
    pub diagnostics: Vec<RecipeEditDiagnostic>,
}

#[derive(Debug, Error)]
pub enum RecipeEditError {
    #[error("recipe id cannot be empty")]
    InvalidRecipeId,
    #[error("failed to read recipe directory {path}: {source}")]
    ReadDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to read recipe file {path}: {source}")]
    ReadFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to parse recipe file {path}: {source}")]
    ParseFile {
        path: PathBuf,
        #[source]
        source: serde_json::Error,
    },
    #[error("failed to load item catalog from {path}: {source}")]
    LoadItemCatalog {
        path: PathBuf,
        #[source]
        source: ItemLoadError,
    },
    #[error("failed to load skill catalog from {path}: {source}")]
    LoadSkillCatalog {
        path: PathBuf,
        #[source]
        source: SkillLoadError,
    },
    #[error("failed to load recipe catalog from {path}: {source}")]
    LoadRecipeCatalog {
        path: PathBuf,
        #[source]
        source: RecipeLoadError,
    },
    #[error("failed to serialize recipe {recipe_id}: {source}")]
    SerializeRecipe {
        recipe_id: String,
        #[source]
        source: serde_json::Error,
    },
    #[error("failed to create directory {path}: {source}")]
    CreateDir {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to write temporary recipe file {path}: {source}")]
    WriteTempFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to replace recipe file {path}: {source}")]
    ReplaceFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("failed to delete recipe file {path}: {source}")]
    DeleteFile {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
}

#[derive(Debug, Clone)]
pub struct RecipeEditorService {
    recipes_dir: PathBuf,
    data_root: Option<PathBuf>,
}

impl RecipeEditorService {
    pub fn new(recipes_dir: impl Into<PathBuf>) -> Self {
        let recipes_dir = recipes_dir.into();
        let data_root = infer_data_root(&recipes_dir);
        Self {
            recipes_dir,
            data_root,
        }
    }

    pub fn with_data_root(recipes_dir: impl Into<PathBuf>, data_root: impl Into<PathBuf>) -> Self {
        Self {
            recipes_dir: recipes_dir.into(),
            data_root: Some(data_root.into()),
        }
    }

    pub fn recipes_dir(&self) -> &Path {
        &self.recipes_dir
    }

    pub fn data_root(&self) -> Option<&Path> {
        self.data_root.as_deref()
    }

    pub fn load_documents(&self) -> Result<Vec<RecipeEditDocument>, RecipeEditError> {
        if !self.recipes_dir.exists() {
            return Ok(Vec::new());
        }

        let item_ids = self.item_ids()?;
        let skill_ids = self.skill_ids()?;
        let entries = collect_sorted_dir_entries(&self.recipes_dir, |path, source| {
            RecipeEditError::ReadDir {
                path: path.to_path_buf(),
                source,
            }
        })?;

        let mut definitions = Vec::new();
        for entry in entries {
            let path = entry.path();
            if path.extension().and_then(|value| value.to_str()) != Some("json") {
                continue;
            }
            let mut definition: RecipeDefinition = read_json_file(
                &path,
                |path, source| RecipeEditError::ReadFile {
                    path: path.to_path_buf(),
                    source,
                },
                |path, source| RecipeEditError::ParseFile {
                    path: path.to_path_buf(),
                    source,
                },
            )?;
            if definition.id.trim().is_empty() {
                definition.id = path
                    .file_stem()
                    .and_then(|value| value.to_str())
                    .unwrap_or_default()
                    .to_string();
            }
            let file_name = path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .to_string();
            definitions.push((path, file_name, definition));
        }

        let recipe_ids = definitions
            .iter()
            .map(|(_, _, definition)| definition.id.clone())
            .collect::<BTreeSet<_>>();

        let mut documents = definitions
            .into_iter()
            .map(|(path, file_name, definition)| {
                let diagnostics = self.validate_definition_with_catalog_inner(
                    &definition,
                    &item_ids,
                    &skill_ids,
                    &recipe_ids,
                )?;
                let relative_path = relative_path_from_root(&path, self.data_root.as_deref())
                    .unwrap_or_else(|| path.to_string_lossy().replace('\\', "/"));
                Ok(RecipeEditDocument {
                    file_name,
                    relative_path,
                    definition,
                    diagnostics,
                })
            })
            .collect::<Result<Vec<_>, RecipeEditError>>()?;

        let duplicate_ids = duplicate_values(
            documents
                .iter()
                .map(|document| document.definition.id.clone()),
        );
        for document in &mut documents {
            if duplicate_ids.contains(document.definition.id.as_str()) {
                document.diagnostics.push(RecipeEditDiagnostic::error(
                    "duplicate_recipe_id",
                    format!(
                        "recipe {} appears more than once in data/recipes",
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
        definition: &RecipeDefinition,
    ) -> Result<RecipeEditResult, RecipeEditError> {
        let item_ids = self.item_ids()?;
        let skill_ids = self.skill_ids()?;
        let recipe_ids = self.load_recipe_ids_from_disk()?;
        self.validate_definition_with_catalog(definition, item_ids, skill_ids, recipe_ids)
    }

    pub fn validate_definition_with_catalog(
        &self,
        definition: &RecipeDefinition,
        item_ids: BTreeSet<u32>,
        skill_ids: BTreeSet<String>,
        recipe_ids: BTreeSet<String>,
    ) -> Result<RecipeEditResult, RecipeEditError> {
        let diagnostics = self.validate_definition_with_catalog_inner(
            definition,
            &item_ids,
            &skill_ids,
            &recipe_ids,
        )?;
        let detail = if diagnostics.is_empty() {
            "recipe definition is valid".to_string()
        } else {
            "recipe definition is invalid".to_string()
        };

        Ok(RecipeEditResult {
            changed: false,
            diagnostics,
            summary: RecipeEditOperationSummary {
                operation: "validate_recipe_definition".to_string(),
                recipe_id: Some(definition.id.clone()),
                path: None,
                changed: false,
                details: vec![detail],
            },
        })
    }

    pub fn save_recipe_definition(
        &self,
        original_id: Option<&str>,
        definition: &RecipeDefinition,
        item_ids: BTreeSet<u32>,
        skill_ids: BTreeSet<String>,
        recipe_ids: BTreeSet<String>,
    ) -> Result<RecipeEditResult, RecipeEditError> {
        let normalized_id = definition.id.trim();
        if normalized_id.is_empty() {
            return Err(RecipeEditError::InvalidRecipeId);
        }

        self.validate_definition_with_catalog(definition, item_ids, skill_ids, recipe_ids)?;
        let target_path = self.path_for_recipe_id(normalized_id);
        let mut details = Vec::new();
        let mut changed = self.write_recipe(definition, &target_path)?;
        details.push(format!("saved recipe {}", normalized_id));

        if let Some(original_id) = original_id
            .map(str::trim)
            .filter(|original_id| !original_id.is_empty() && *original_id != normalized_id)
        {
            let old_path = self.path_for_recipe_id(original_id);
            if old_path.exists() {
                fs::remove_file(&old_path).map_err(|source| RecipeEditError::DeleteFile {
                    path: old_path.clone(),
                    source,
                })?;
                changed = true;
                details.push(format!("removed renamed recipe {}", original_id));
            }
        }

        Ok(RecipeEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: RecipeEditOperationSummary {
                operation: "save_recipe_definition".to_string(),
                recipe_id: Some(normalized_id.to_string()),
                path: Some(target_path),
                changed,
                details,
            },
        })
    }

    pub fn delete_recipe_definition(
        &self,
        recipe_id: &str,
    ) -> Result<RecipeEditResult, RecipeEditError> {
        let recipe_id = recipe_id.trim();
        if recipe_id.is_empty() {
            return Err(RecipeEditError::InvalidRecipeId);
        }

        let path = self.path_for_recipe_id(recipe_id);
        let changed = if path.exists() {
            fs::remove_file(&path).map_err(|source| RecipeEditError::DeleteFile {
                path: path.clone(),
                source,
            })?;
            true
        } else {
            false
        };

        Ok(RecipeEditResult {
            changed,
            diagnostics: Vec::new(),
            summary: RecipeEditOperationSummary {
                operation: "delete_recipe_definition".to_string(),
                recipe_id: Some(recipe_id.to_string()),
                path: Some(path),
                changed,
                details: vec![format!("deleted recipe {}", recipe_id)],
            },
        })
    }

    fn load_recipe_ids_from_disk(&self) -> Result<BTreeSet<String>, RecipeEditError> {
        Ok(self
            .load_documents()?
            .into_iter()
            .map(|document| document.definition.id)
            .collect())
    }

    fn validate_definition_with_catalog_inner(
        &self,
        definition: &RecipeDefinition,
        item_ids: &BTreeSet<u32>,
        skill_ids: &BTreeSet<String>,
        recipe_ids: &BTreeSet<String>,
    ) -> Result<Vec<RecipeEditDiagnostic>, RecipeEditError> {
        let catalog = RecipeValidationCatalog {
            item_ids: item_ids.clone(),
            skill_ids: skill_ids.clone(),
            recipe_ids: recipe_ids.clone(),
        };
        match validate_recipe_definition(definition, Some(&catalog)) {
            Ok(()) => Ok(Vec::new()),
            Err(source) => Ok(vec![RecipeEditDiagnostic::from(&source)]),
        }
    }

    fn item_ids(&self) -> Result<BTreeSet<u32>, RecipeEditError> {
        let Some(data_root) = self.data_root.as_ref() else {
            return Ok(BTreeSet::new());
        };
        let items_dir = data_root.join("items");
        if !items_dir.exists() {
            return Ok(BTreeSet::new());
        }
        load_item_library(&items_dir, None)
            .map(|library| library.ids())
            .map_err(|source| RecipeEditError::LoadItemCatalog {
                path: items_dir,
                source,
            })
    }

    fn skill_ids(&self) -> Result<BTreeSet<String>, RecipeEditError> {
        let Some(data_root) = self.data_root.as_ref() else {
            return Ok(BTreeSet::new());
        };
        let skills_dir = data_root.join("skills");
        if !skills_dir.exists() {
            return Ok(BTreeSet::new());
        }
        load_skill_library(&skills_dir, Some(&SkillValidationCatalog::default()))
            .map(|library| library.ids())
            .map_err(|source| RecipeEditError::LoadSkillCatalog {
                path: skills_dir,
                source,
            })
    }

    pub fn recipe_ids(&self) -> Result<BTreeSet<String>, RecipeEditError> {
        if !self.recipes_dir.exists() {
            return Ok(BTreeSet::new());
        }
        load_recipe_library(&self.recipes_dir, None)
            .map(|library| library.ids())
            .map_err(|source| RecipeEditError::LoadRecipeCatalog {
                path: self.recipes_dir.clone(),
                source,
            })
    }

    fn path_for_recipe_id(&self, recipe_id: &str) -> PathBuf {
        self.recipes_dir.join(format!("{recipe_id}.json"))
    }

    fn write_recipe(
        &self,
        definition: &RecipeDefinition,
        path: &Path,
    ) -> Result<bool, RecipeEditError> {
        let raw = serde_json::to_string_pretty(definition).map_err(|source| {
            RecipeEditError::SerializeRecipe {
                recipe_id: definition.id.clone(),
                source,
            }
        })?;

        write_json_atomically(
            path,
            &raw,
            |path, source| RecipeEditError::CreateDir {
                path: path.to_path_buf(),
                source,
            },
            |path, source| RecipeEditError::WriteTempFile {
                path: path.to_path_buf(),
                source,
            },
            |path, source| RecipeEditError::ReplaceFile {
                path: path.to_path_buf(),
                source,
            },
        )
    }
}

fn infer_data_root(recipes_dir: &Path) -> Option<PathBuf> {
    let parent = recipes_dir.parent()?;
    let recipes_name = recipes_dir.file_name()?.to_str()?;
    if recipes_name != "recipes" {
        return None;
    }
    Some(parent.to_path_buf())
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::*;

    #[test]
    fn load_documents_marks_duplicate_ids() {
        let fixture = TestFixture::new();
        fixture.write_recipe_json(
            "recipe_a.json",
            serde_json::json!({
                "id": "recipe_shared",
                "name": "alpha",
                "output": { "item_id": 1001, "count": 1 },
                "materials": [{ "item_id": 1002, "count": 1 }]
            }),
        );
        fixture.write_recipe_json(
            "recipe_b.json",
            serde_json::json!({
                "id": "recipe_shared",
                "name": "beta",
                "output": { "item_id": 1001, "count": 1 },
                "materials": [{ "item_id": 1002, "count": 1 }]
            }),
        );

        let documents = fixture
            .service()
            .load_documents()
            .expect("documents should load");
        assert_eq!(documents.len(), 2);
        assert!(documents.iter().all(|document| document
            .diagnostics
            .iter()
            .any(|diagnostic| diagnostic.code == "duplicate_recipe_id")));
    }

    #[test]
    fn save_recipe_definition_removes_renamed_file() {
        let fixture = TestFixture::new();
        fixture.write_recipe_json(
            "recipe_old.json",
            serde_json::json!({
                "id": "recipe_old",
                "name": "old",
                "output": { "item_id": 1001, "count": 1 },
                "materials": [{ "item_id": 1002, "count": 1 }]
            }),
        );

        let mut item_ids = BTreeSet::new();
        item_ids.insert(1001);
        item_ids.insert(1002);
        let definition = RecipeDefinition {
            id: "recipe_new".to_string(),
            name: "new".to_string(),
            output: crate::RecipeOutput {
                item_id: 1001,
                count: 1,
                ..Default::default()
            },
            materials: vec![crate::RecipeMaterial {
                item_id: 1002,
                count: 1,
                ..Default::default()
            }],
            ..Default::default()
        };
        let mut recipe_ids = BTreeSet::new();
        recipe_ids.insert(definition.id.clone());

        fixture
            .service()
            .save_recipe_definition(
                Some("recipe_old"),
                &definition,
                item_ids,
                BTreeSet::new(),
                recipe_ids,
            )
            .expect("save should succeed");

        assert!(!fixture.recipes_dir.join("recipe_old.json").exists());
        assert!(fixture.recipes_dir.join("recipe_new.json").exists());
    }

    struct TestFixture {
        root: PathBuf,
        data_root: PathBuf,
        recipes_dir: PathBuf,
        items_dir: PathBuf,
        skills_dir: PathBuf,
    }

    impl TestFixture {
        fn new() -> Self {
            let root = unique_temp_path("recipe_edit_tests");
            let data_root = root.join("data");
            let recipes_dir = data_root.join("recipes");
            let items_dir = data_root.join("items");
            let skills_dir = data_root.join("skills");
            fs::create_dir_all(&recipes_dir).expect("recipes dir should exist");
            fs::create_dir_all(&items_dir).expect("items dir should exist");
            fs::create_dir_all(&skills_dir).expect("skills dir should exist");
            fs::write(
                items_dir.join("1001.json"),
                serde_json::to_string_pretty(&serde_json::json!({
                    "id": 1001,
                    "name": "output",
                    "fragments": [{ "kind": "stacking", "stackable": false, "max_stack": 1 }]
                }))
                .expect("item json"),
            )
            .expect("write item");
            fs::write(
                items_dir.join("1002.json"),
                serde_json::to_string_pretty(&serde_json::json!({
                    "id": 1002,
                    "name": "material",
                    "fragments": [{ "kind": "stacking", "stackable": true, "max_stack": 10 }]
                }))
                .expect("item json"),
            )
            .expect("write item");
            Self {
                root,
                data_root,
                recipes_dir,
                items_dir,
                skills_dir,
            }
        }

        fn service(&self) -> RecipeEditorService {
            RecipeEditorService::with_data_root(&self.recipes_dir, &self.data_root)
        }

        fn write_recipe_json(&self, file_name: &str, value: serde_json::Value) {
            fs::write(
                self.recipes_dir.join(file_name),
                serde_json::to_string_pretty(&value).expect("recipe json"),
            )
            .expect("recipe file should be written");
        }
    }

    impl Drop for TestFixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.root);
        }
    }

    fn unique_temp_path(prefix: &str) -> PathBuf {
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let counter = COUNTER.fetch_add(1, Ordering::Relaxed);
        let timestamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time should be after unix epoch")
            .as_millis();
        std::env::temp_dir().join(format!("{prefix}_{timestamp}_{counter}"))
    }
}
