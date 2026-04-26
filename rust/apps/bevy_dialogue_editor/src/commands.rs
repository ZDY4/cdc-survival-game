use bevy::prelude::*;

use crate::data::reload_editor_content;
use crate::state::{DialogueEditorCatalogs, EditorState};

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub(crate) enum DialogueEditorCommand {
    Reload,
}

pub(crate) fn handle_dialogue_editor_commands(
    mut requests: MessageReader<DialogueEditorCommand>,
    mut editor: ResMut<EditorState>,
    mut catalogs: ResMut<DialogueEditorCatalogs>,
) {
    for request in requests.read() {
        match request {
            DialogueEditorCommand::Reload => {
                editor.status =
                    reload_editor_content(&mut editor, &mut catalogs).unwrap_or_else(|error| error);
            }
        }
    }
}
