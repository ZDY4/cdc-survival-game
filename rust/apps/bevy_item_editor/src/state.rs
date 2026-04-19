use std::collections::BTreeSet;
use std::path::PathBuf;

use bevy::prelude::*;
use game_data::{EffectLibrary, ItemDefinition, ItemEditDiagnostic, ItemEditorService};
use game_editor::{WorkingDocumentStore, WorkspaceDocument};

pub(crate) const DEFAULT_EQUIPMENT_SLOTS: &[&str] = &[
    "head",
    "body",
    "hands",
    "legs",
    "feet",
    "back",
    "main_hand",
    "off_hand",
    "accessory",
    "accessory_1",
    "accessory_2",
];

pub(crate) const DEFAULT_KNOWN_SUBTYPES: &[&str] = &[
    "unarmed", "dagger", "sword", "blunt", "axe", "spear", "polearm", "bow", "gun", "pistol",
    "rifle", "shotgun", "tool", "tools", "watch", "backpack", "healing", "food", "drink", "water",
    "metal", "wood", "fabric", "medical", "chemical", "key", "device", "misc",
];

#[derive(Debug, Clone)]
pub(crate) struct WorkingItemDocument {
    pub(crate) document_key: String,
    pub(crate) original_id: Option<u32>,
    pub(crate) file_name: String,
    pub(crate) relative_path: String,
    pub(crate) definition: ItemDefinition,
    pub(crate) dirty: bool,
    pub(crate) diagnostics: Vec<ItemEditDiagnostic>,
    pub(crate) last_save_message: Option<String>,
}

impl WorkspaceDocument for WorkingItemDocument {
    type Id = u32;

    fn document_id(&self) -> Self::Id {
        self.definition.id
    }

    fn is_dirty(&self) -> bool {
        self.dirty
    }
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct ItemEditorCatalogs {
    pub(crate) effect_ids: Vec<String>,
    pub(crate) equipment_slots: Vec<String>,
    pub(crate) known_subtypes: Vec<String>,
}

#[derive(Resource)]
pub(crate) struct EditorState {
    pub(crate) repo_root: PathBuf,
    pub(crate) service: ItemEditorService,
    pub(crate) effects: EffectLibrary,
    pub(crate) workspace: WorkingDocumentStore<WorkingItemDocument>,
    pub(crate) search_text: String,
    pub(crate) status: String,
}

impl EditorState {
    pub(crate) fn ensure_selection(&mut self) {
        self.workspace.ensure_selection();
    }

    pub(crate) fn selected_document(&self) -> Option<&WorkingItemDocument> {
        self.workspace.selected_document()
    }

    pub(crate) fn select_item_id(&mut self, item_id: u32) -> bool {
        let next_key = self
            .workspace
            .iter()
            .find(|(_, document)| document.definition.id == item_id)
            .map(|(key, _)| key.clone());
        if let Some(next_key) = next_key {
            self.workspace.set_selected_document_key(Some(next_key));
            true
        } else {
            false
        }
    }

    pub(crate) fn current_item_ids(&self) -> BTreeSet<u32> {
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

    pub(crate) fn suggested_next_item_id(&self) -> u32 {
        self.workspace
            .values()
            .map(|document| document.definition.id)
            .max()
            .unwrap_or(1000)
            .saturating_add(1)
    }
}

#[derive(Resource)]
pub(crate) struct ExternalItemSelectionState {
    pub(crate) repo_root: PathBuf,
    pub(crate) heartbeat_timer: Timer,
    pub(crate) request_poll_timer: Timer,
    pub(crate) last_request_id: Option<String>,
}

impl ExternalItemSelectionState {
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
