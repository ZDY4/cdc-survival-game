use std::collections::BTreeMap;
use std::path::PathBuf;

use bevy::prelude::*;
use game_data::{resolve_dialogue_start_node_id, DialogueData};
use game_editor::FlowGraphCanvasState;

#[derive(Debug, Clone)]
pub(crate) struct DialogueSearchEntry {
    pub(crate) dialogue_id: String,
    pub(crate) summary: String,
    pub(crate) search_blob: String,
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct DialogueEditorCatalogs {
    pub(crate) definitions: BTreeMap<String, DialogueData>,
    pub(crate) ordered_ids: Vec<String>,
    pub(crate) relative_paths: BTreeMap<String, String>,
    pub(crate) search_entries: Vec<DialogueSearchEntry>,
}

impl DialogueEditorCatalogs {
    pub(crate) fn dialogue(&self, dialogue_id: &str) -> Option<&DialogueData> {
        self.definitions.get(dialogue_id)
    }

    pub(crate) fn relative_path(&self, dialogue_id: &str) -> Option<&str> {
        self.relative_paths.get(dialogue_id).map(String::as_str)
    }
}

#[derive(Resource)]
pub(crate) struct EditorState {
    pub(crate) repo_root: PathBuf,
    pub(crate) selected_dialogue_id: Option<String>,
    pub(crate) selected_node_id: Option<String>,
    pub(crate) search_text: String,
    pub(crate) status: String,
    pub(crate) graph_canvas_state: FlowGraphCanvasState,
}

impl EditorState {
    pub(crate) fn select_dialogue(
        &mut self,
        dialogue_id: &str,
        catalogs: &DialogueEditorCatalogs,
    ) -> bool {
        let Some(dialogue) = catalogs.dialogue(dialogue_id) else {
            return false;
        };

        let changed = self.selected_dialogue_id.as_deref() != Some(dialogue_id);
        self.selected_dialogue_id = Some(dialogue_id.to_string());
        self.sync_node_selection(dialogue, changed);
        if changed {
            self.graph_canvas_state.request_fit();
        }
        true
    }

    pub(crate) fn select_node(&mut self, node_id: &str, catalogs: &DialogueEditorCatalogs) -> bool {
        let Some(dialogue_id) = self.selected_dialogue_id.as_deref() else {
            return false;
        };
        let Some(dialogue) = catalogs.dialogue(dialogue_id) else {
            return false;
        };
        if dialogue.nodes.iter().any(|node| node.id == node_id) {
            self.selected_node_id = Some(node_id.to_string());
            true
        } else {
            false
        }
    }

    pub(crate) fn ensure_selection(&mut self, catalogs: &DialogueEditorCatalogs) {
        if let Some(dialogue) = self
            .selected_dialogue_id
            .as_deref()
            .and_then(|dialogue_id| catalogs.dialogue(dialogue_id))
        {
            self.sync_node_selection(dialogue, false);
            return;
        }
        if let Some(dialogue_id) = catalogs.ordered_ids.first() {
            let _ = self.select_dialogue(dialogue_id, catalogs);
        } else {
            self.selected_dialogue_id = None;
            self.selected_node_id = None;
        }
    }

    fn sync_node_selection(&mut self, dialogue: &DialogueData, force_reset: bool) {
        let current_is_valid = self
            .selected_node_id
            .as_deref()
            .is_some_and(|node_id| dialogue.nodes.iter().any(|node| node.id == node_id));
        if force_reset || !current_is_valid {
            self.selected_node_id = preferred_dialogue_node_id(dialogue);
        }
    }
}

fn preferred_dialogue_node_id(dialogue: &DialogueData) -> Option<String> {
    resolve_dialogue_start_node_id(dialogue)
        .or_else(|| dialogue.nodes.first().map(|node| node.id.clone()))
}

#[derive(Resource)]
pub(crate) struct ExternalDialogueSelectionState {
    pub(crate) repo_root: PathBuf,
    pub(crate) heartbeat_timer: Timer,
    pub(crate) request_poll_timer: Timer,
    pub(crate) last_request_id: Option<String>,
}

impl ExternalDialogueSelectionState {
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
