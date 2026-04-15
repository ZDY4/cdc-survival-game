use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

use bevy::prelude::*;
use game_data::{
    RecipeDefinition, RecipeEditDiagnostic, RecipeEditDiagnosticSeverity, RecipeEditorService,
};
use game_editor::ai_chat::{AiChatState, AiChatWorkerState};

use crate::ai::AiRecipeProposalView;

pub(crate) type RecipeAiState = AiChatState<AiRecipeProposalView>;
pub(crate) type RecipeAiWorkerState = AiChatWorkerState<AiRecipeProposalView>;

#[derive(Debug, Clone)]
pub(crate) struct WorkingRecipeDocument {
    pub(crate) document_key: String,
    pub(crate) original_id: Option<String>,
    pub(crate) file_name: String,
    pub(crate) relative_path: String,
    pub(crate) definition: RecipeDefinition,
    pub(crate) dirty: bool,
    pub(crate) diagnostics: Vec<RecipeEditDiagnostic>,
    pub(crate) last_save_message: Option<String>,
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct RecipeEditorCatalogs {
    pub(crate) item_name_lookup: BTreeMap<u32, String>,
    pub(crate) item_ids: Vec<u32>,
    pub(crate) skill_ids: Vec<String>,
}

impl RecipeEditorCatalogs {
    pub(crate) fn item_name(&self, item_id: u32) -> Option<&str> {
        self.item_name_lookup.get(&item_id).map(String::as_str)
    }
}

#[derive(Resource)]
pub(crate) struct EditorState {
    pub(crate) repo_root: PathBuf,
    pub(crate) service: RecipeEditorService,
    pub(crate) documents: BTreeMap<String, WorkingRecipeDocument>,
    pub(crate) selected_document_key: Option<String>,
    pub(crate) search_text: String,
    pub(crate) status: String,
}

impl EditorState {
    pub(crate) fn ensure_selection(&mut self) {
        if self
            .selected_document_key
            .as_ref()
            .is_some_and(|key| self.documents.contains_key(key))
        {
            return;
        }
        self.selected_document_key = self.documents.keys().next().cloned();
    }

    pub(crate) fn selected_document(&self) -> Option<&WorkingRecipeDocument> {
        let key = self.selected_document_key.as_ref()?;
        self.documents.get(key)
    }

    pub(crate) fn current_recipe_ids(&self) -> BTreeSet<String> {
        self.documents
            .values()
            .map(|document| document.definition.id.clone())
            .collect()
    }

    pub(crate) fn has_duplicate_ids(&self) -> bool {
        let mut ids = BTreeSet::new();
        self.documents
            .values()
            .any(|document| !ids.insert(document.definition.id.clone()))
    }

    pub(crate) fn has_dirty_documents(&self) -> bool {
        self.documents.values().any(|document| document.dirty)
    }

    pub(crate) fn dirty_document_keys(&self) -> Vec<String> {
        self.documents
            .iter()
            .filter_map(|(key, document)| document.dirty.then_some(key.clone()))
            .collect()
    }

    pub(crate) fn suggested_next_recipe_id(&self) -> String {
        let used_ids = self.current_recipe_ids();
        for index in 1.. {
            let candidate = format!("recipe_new_{index}");
            if !used_ids.contains(candidate.as_str()) {
                return candidate;
            }
        }
        "recipe_new".to_string()
    }

    pub(crate) fn recipe_error_count(&self) -> usize {
        self.documents
            .values()
            .map(|document| {
                document
                    .diagnostics
                    .iter()
                    .filter(|diagnostic| {
                        matches!(diagnostic.severity, RecipeEditDiagnosticSeverity::Error)
                    })
                    .count()
            })
            .sum()
    }
}

#[derive(Resource, Default)]
pub(crate) struct EditorEguiFontState {
    pub(crate) initialized: bool,
}
