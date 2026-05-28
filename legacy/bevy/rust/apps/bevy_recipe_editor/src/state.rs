use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

use bevy::prelude::*;
use game_data::{
    RecipeDefinition, RecipeEditDiagnostic, RecipeEditDiagnosticSeverity, RecipeEditorService,
};
use game_editor::{WorkingDocumentStore, WorkspaceDocument};

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

impl WorkspaceDocument for WorkingRecipeDocument {
    type Id = String;

    fn document_id(&self) -> Self::Id {
        self.definition.id.clone()
    }

    fn is_dirty(&self) -> bool {
        self.dirty
    }
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct RecipeEditorCatalogs {
    pub(crate) item_name_lookup: BTreeMap<u32, String>,
    pub(crate) skill_name_lookup: BTreeMap<String, String>,
    pub(crate) item_ids: Vec<u32>,
    pub(crate) skill_ids: Vec<String>,
}

impl RecipeEditorCatalogs {
    pub(crate) fn item_name(&self, item_id: u32) -> Option<&str> {
        self.item_name_lookup.get(&item_id).map(String::as_str)
    }

    pub(crate) fn skill_name(&self, skill_id: &str) -> Option<&str> {
        self.skill_name_lookup.get(skill_id).map(String::as_str)
    }
}

#[derive(Resource)]
pub(crate) struct EditorState {
    pub(crate) repo_root: PathBuf,
    pub(crate) service: RecipeEditorService,
    pub(crate) workspace: WorkingDocumentStore<WorkingRecipeDocument>,
    pub(crate) search_text: String,
    pub(crate) status: String,
}

impl EditorState {
    pub(crate) fn select_recipe_id(&mut self, recipe_id: &str) -> bool {
        let selected_key = self
            .workspace
            .iter()
            .find_map(|(key, document)| (document.definition.id == recipe_id).then(|| key.clone()));
        if let Some(key) = selected_key {
            self.workspace.set_selected_document_key(Some(key));
            true
        } else {
            false
        }
    }

    pub(crate) fn ensure_selection(&mut self) {
        self.workspace.ensure_selection();
    }

    pub(crate) fn selected_document(&self) -> Option<&WorkingRecipeDocument> {
        self.workspace.selected_document()
    }

    pub(crate) fn current_recipe_ids(&self) -> BTreeSet<String> {
        self.workspace.current_ids()
    }

    pub(crate) fn has_duplicate_ids(&self) -> bool {
        self.workspace.has_duplicate_ids()
    }

    pub(crate) fn has_dirty_documents(&self) -> bool {
        self.workspace.has_dirty_documents()
    }

    pub(crate) fn dirty_document_keys(&self) -> Vec<String> {
        self.workspace.dirty_document_keys()
    }

    pub(crate) fn recipe_error_count(&self) -> usize {
        self.workspace
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

#[derive(Resource)]
pub(crate) struct ExternalRecipeSelectionState {
    pub(crate) repo_root: PathBuf,
    pub(crate) heartbeat_timer: Timer,
    pub(crate) request_poll_timer: Timer,
    pub(crate) last_request_id: Option<String>,
}

impl ExternalRecipeSelectionState {
    pub(crate) fn new(repo_root: PathBuf) -> Self {
        let mut heartbeat_timer = Timer::from_seconds(1.0, TimerMode::Repeating);
        heartbeat_timer.set_elapsed(heartbeat_timer.duration());

        let mut request_poll_timer = Timer::from_seconds(0.25, TimerMode::Repeating);
        request_poll_timer.set_elapsed(request_poll_timer.duration());

        Self {
            repo_root,
            heartbeat_timer,
            request_poll_timer,
            last_request_id: None,
        }
    }
}
