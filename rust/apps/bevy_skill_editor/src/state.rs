use std::collections::BTreeMap;
use std::path::PathBuf;

use bevy::prelude::*;
use game_data::{SkillDefinition, SkillTreeDefinition};

#[derive(Debug, Clone)]
pub(crate) struct SkillSearchEntry {
    pub(crate) skill_id: String,
    pub(crate) tree_id: String,
    pub(crate) skill_name: String,
    pub(crate) tree_name: String,
    pub(crate) search_blob: String,
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct SkillEditorCatalogs {
    pub(crate) skills: BTreeMap<String, SkillDefinition>,
    pub(crate) trees: BTreeMap<String, SkillTreeDefinition>,
    pub(crate) sorted_tree_ids: Vec<String>,
    pub(crate) skills_by_tree: BTreeMap<String, Vec<String>>,
    pub(crate) reverse_prerequisites: BTreeMap<String, Vec<String>>,
    pub(crate) search_entries: Vec<SkillSearchEntry>,
}

impl SkillEditorCatalogs {
    pub(crate) fn skill(&self, skill_id: &str) -> Option<&SkillDefinition> {
        self.skills.get(skill_id)
    }

    pub(crate) fn tree(&self, tree_id: &str) -> Option<&SkillTreeDefinition> {
        self.trees.get(tree_id)
    }

    pub(crate) fn tree_skill_ids(&self, tree_id: &str) -> &[String] {
        self.skills_by_tree
            .get(tree_id)
            .map(Vec::as_slice)
            .unwrap_or(&[])
    }

    pub(crate) fn display_skill_name(&self, skill_id: &str) -> String {
        self.skill(skill_id)
            .map(display_skill_name)
            .unwrap_or_else(|| skill_id.to_string())
    }

    pub(crate) fn display_tree_name(&self, tree_id: &str) -> String {
        self.tree(tree_id)
            .map(display_tree_name)
            .unwrap_or_else(|| tree_id.to_string())
    }
}

#[derive(Resource)]
pub(crate) struct EditorState {
    pub(crate) repo_root: PathBuf,
    pub(crate) selected_tree_id: Option<String>,
    pub(crate) selected_skill_id: Option<String>,
    pub(crate) search_text: String,
    pub(crate) status: String,
}

impl EditorState {
    pub(crate) fn select_tree(&mut self, tree_id: &str, catalogs: &SkillEditorCatalogs) -> bool {
        if !catalogs.trees.contains_key(tree_id) {
            return false;
        }
        self.selected_tree_id = Some(tree_id.to_string());
        self.selected_skill_id = None;
        true
    }

    pub(crate) fn select_skill(&mut self, skill_id: &str, catalogs: &SkillEditorCatalogs) -> bool {
        let Some(skill) = catalogs.skill(skill_id) else {
            return false;
        };
        self.selected_tree_id = Some(skill.tree_id.clone());
        self.selected_skill_id = Some(skill_id.to_string());
        true
    }

    pub(crate) fn ensure_selection(&mut self, catalogs: &SkillEditorCatalogs) {
        if let Some(skill_id) = self.selected_skill_id.clone() {
            if let Some(skill) = catalogs.skill(&skill_id) {
                self.selected_tree_id = Some(skill.tree_id.clone());
            } else {
                self.selected_skill_id = None;
            }
        }

        if self
            .selected_tree_id
            .as_deref()
            .is_some_and(|tree_id| !catalogs.trees.contains_key(tree_id))
        {
            self.selected_tree_id = None;
            self.selected_skill_id = None;
        }

        if self.selected_tree_id.is_none() {
            self.selected_tree_id = catalogs.sorted_tree_ids.first().cloned();
        }

        if let (Some(tree_id), Some(skill_id)) = (
            self.selected_tree_id.as_deref(),
            self.selected_skill_id.as_deref(),
        ) {
            if catalogs
                .skill(skill_id)
                .map(|skill| skill.tree_id.as_str() != tree_id)
                .unwrap_or(true)
            {
                self.selected_skill_id = None;
            }
        }
    }
}

#[derive(Resource)]
pub(crate) struct ExternalSkillSelectionState {
    pub(crate) repo_root: PathBuf,
    pub(crate) heartbeat_timer: Timer,
    pub(crate) request_poll_timer: Timer,
    pub(crate) last_request_id: Option<String>,
}

impl ExternalSkillSelectionState {
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

pub(crate) fn display_skill_name(skill: &SkillDefinition) -> String {
    if skill.name.trim().is_empty() {
        skill.id.clone()
    } else {
        skill.name.clone()
    }
}

pub(crate) fn display_tree_name(tree: &SkillTreeDefinition) -> String {
    if tree.name.trim().is_empty() {
        tree.id.clone()
    } else {
        tree.name.clone()
    }
}

pub(crate) fn skill_activation_mode(skill: &SkillDefinition) -> &str {
    skill
        .activation
        .as_ref()
        .map(|activation| activation.mode.trim())
        .filter(|mode| !mode.is_empty())
        .unwrap_or("passive")
}
