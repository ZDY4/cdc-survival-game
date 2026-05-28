use bevy::prelude::*;

use crate::data::reload_editor_content;
use crate::navigation::open_dialogue_in_editor;
use crate::state::{EditorState, QuestEditorCatalogs};

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub(crate) enum QuestEditorCommand {
    Reload,
    OpenDialogue(String),
}

pub(crate) fn handle_quest_editor_commands(
    mut requests: MessageReader<QuestEditorCommand>,
    mut editor: ResMut<EditorState>,
    mut catalogs: ResMut<QuestEditorCatalogs>,
) {
    for request in requests.read() {
        match request {
            QuestEditorCommand::Reload => {
                editor.status =
                    reload_editor_content(&mut editor, &mut catalogs).unwrap_or_else(|error| error);
            }
            QuestEditorCommand::OpenDialogue(dialogue_id) => {
                editor.status = open_dialogue_in_editor(&editor.repo_root, dialogue_id)
                    .unwrap_or_else(|error| error);
            }
        }
    }
}
