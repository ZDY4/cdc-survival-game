use bevy::prelude::*;

use crate::data::reload_editor_content;
use crate::state::{EditorState, SkillEditorCatalogs};

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub(crate) enum SkillEditorCommand {
    Reload,
    SelectTree(String),
    SelectSkill(String),
}

pub(crate) fn handle_skill_editor_commands(
    mut requests: MessageReader<SkillEditorCommand>,
    mut editor: ResMut<EditorState>,
    mut catalogs: ResMut<SkillEditorCatalogs>,
) {
    for request in requests.read() {
        match request {
            SkillEditorCommand::Reload => {
                editor.status =
                    reload_editor_content(&mut editor, &mut catalogs).unwrap_or_else(|error| error);
            }
            SkillEditorCommand::SelectTree(tree_id) => {
                editor.status = if editor.select_tree(tree_id, &catalogs) {
                    format!("Selected skill tree {tree_id}.")
                } else {
                    format!("Skill tree {tree_id} was not found.")
                };
            }
            SkillEditorCommand::SelectSkill(skill_id) => {
                editor.status = if editor.select_skill(skill_id, &catalogs) {
                    format!("Selected skill {skill_id}.")
                } else {
                    format!("Skill {skill_id} was not found.")
                };
            }
        }
    }
}
