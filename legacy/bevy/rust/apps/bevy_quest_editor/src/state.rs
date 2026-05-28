use std::collections::BTreeMap;
use std::path::PathBuf;

use bevy::prelude::*;
use game_data::QuestDefinition;
use game_editor::FlowGraphCanvasState;

#[derive(Debug, Clone)]
pub(crate) struct QuestSearchEntry {
    pub(crate) quest_id: String,
    pub(crate) title: String,
    pub(crate) summary: String,
    pub(crate) search_blob: String,
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct QuestEditorCatalogs {
    pub(crate) definitions: BTreeMap<String, QuestDefinition>,
    pub(crate) ordered_ids: Vec<String>,
    pub(crate) relative_paths: BTreeMap<String, String>,
    pub(crate) search_entries: Vec<QuestSearchEntry>,
}

impl QuestEditorCatalogs {
    pub(crate) fn quest(&self, quest_id: &str) -> Option<&QuestDefinition> {
        self.definitions.get(quest_id)
    }

    pub(crate) fn relative_path(&self, quest_id: &str) -> Option<&str> {
        self.relative_paths.get(quest_id).map(String::as_str)
    }
}

#[derive(Resource)]
pub(crate) struct EditorState {
    pub(crate) repo_root: PathBuf,
    pub(crate) selected_quest_id: Option<String>,
    pub(crate) selected_node_id: Option<String>,
    pub(crate) search_text: String,
    pub(crate) status: String,
    pub(crate) graph_canvas_state: FlowGraphCanvasState,
}

impl EditorState {
    pub(crate) fn select_quest(&mut self, quest_id: &str, catalogs: &QuestEditorCatalogs) -> bool {
        let Some(quest) = catalogs.quest(quest_id) else {
            return false;
        };

        let changed = self.selected_quest_id.as_deref() != Some(quest_id);
        self.selected_quest_id = Some(quest_id.to_string());
        self.sync_node_selection(quest, changed);
        if changed {
            self.graph_canvas_state.request_fit();
        }
        true
    }

    pub(crate) fn select_node(&mut self, node_id: &str, catalogs: &QuestEditorCatalogs) -> bool {
        let Some(quest_id) = self.selected_quest_id.as_deref() else {
            return false;
        };
        let Some(quest) = catalogs.quest(quest_id) else {
            return false;
        };
        if quest.flow.nodes.contains_key(node_id) {
            self.selected_node_id = Some(node_id.to_string());
            true
        } else {
            false
        }
    }

    pub(crate) fn ensure_selection(&mut self, catalogs: &QuestEditorCatalogs) {
        if let Some(quest) = self
            .selected_quest_id
            .as_deref()
            .and_then(|quest_id| catalogs.quest(quest_id))
        {
            self.sync_node_selection(quest, false);
            return;
        }
        if let Some(quest_id) = catalogs.ordered_ids.first() {
            let _ = self.select_quest(quest_id, catalogs);
        } else {
            self.selected_quest_id = None;
            self.selected_node_id = None;
        }
    }

    fn sync_node_selection(&mut self, quest: &QuestDefinition, force_reset: bool) {
        let current_is_valid = self
            .selected_node_id
            .as_deref()
            .is_some_and(|node_id| quest.flow.nodes.contains_key(node_id));
        if force_reset || !current_is_valid {
            self.selected_node_id = preferred_quest_node_id(quest);
        }
    }
}

#[derive(Resource)]
pub(crate) struct ExternalQuestSelectionState {
    pub(crate) repo_root: PathBuf,
    pub(crate) heartbeat_timer: Timer,
    pub(crate) request_poll_timer: Timer,
    pub(crate) last_request_id: Option<String>,
}

impl ExternalQuestSelectionState {
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

pub(crate) fn display_quest_title(quest: &QuestDefinition) -> String {
    if quest.title.trim().is_empty() {
        quest.quest_id.clone()
    } else {
        quest.title.clone()
    }
}

fn preferred_quest_node_id(quest: &QuestDefinition) -> Option<String> {
    if quest
        .flow
        .nodes
        .contains_key(quest.flow.start_node_id.as_str())
    {
        Some(quest.flow.start_node_id.clone())
    } else {
        quest.flow.nodes.keys().next().cloned()
    }
}
