use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

use bevy::prelude::*;
use game_data::{EffectLibrary, ItemDefinition, ItemEditDiagnostic, ItemEditorService};
use game_editor::ai_chat::{AiChatState, AiChatWorkerState};

use crate::ai::AiItemProposalView;

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

pub(crate) type ItemAiState = AiChatState<AiItemProposalView>;
pub(crate) type ItemAiWorkerState = AiChatWorkerState<AiItemProposalView>;

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
    pub(crate) documents: BTreeMap<String, WorkingItemDocument>,
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

    pub(crate) fn selected_document(&self) -> Option<&WorkingItemDocument> {
        let key = self.selected_document_key.as_ref()?;
        self.documents.get(key)
    }

    pub(crate) fn select_item_id(&mut self, item_id: u32) -> bool {
        let next_key = self
            .documents
            .iter()
            .find(|(_, document)| document.definition.id == item_id)
            .map(|(key, _)| key.clone());
        if let Some(next_key) = next_key {
            self.selected_document_key = Some(next_key);
            true
        } else {
            false
        }
    }

    pub(crate) fn current_item_ids(&self) -> BTreeSet<u32> {
        self.documents
            .values()
            .map(|document| document.definition.id)
            .collect()
    }

    pub(crate) fn has_duplicate_ids(&self) -> bool {
        let mut ids = BTreeSet::new();
        self.documents
            .values()
            .any(|document| !ids.insert(document.definition.id))
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

    pub(crate) fn suggested_next_item_id(&self) -> u32 {
        self.documents
            .values()
            .map(|document| document.definition.id)
            .max()
            .unwrap_or(1000)
            .saturating_add(1)
    }
}

#[derive(Resource, Default)]
pub(crate) struct EditorEguiFontState {
    pub(crate) initialized: bool,
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
