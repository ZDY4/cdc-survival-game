use bevy::prelude::*;

use crate::actions::{
    delete_current_document, reload_editor_content, save_all_dirty_documents,
    save_current_document, validate_current_document,
};
use crate::state::EditorState;

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub(crate) enum ItemEditorCommand {
    Reload,
    ValidateCurrent,
    SaveCurrent,
    SaveAllDirty,
    DeleteCurrent,
    SelectDocument { key: String },
}

pub(crate) fn handle_item_editor_commands(
    mut requests: MessageReader<ItemEditorCommand>,
    mut editor: ResMut<EditorState>,
) {
    for request in requests.read() {
        match request {
            ItemEditorCommand::Reload => {
                editor.status = reload_editor_content(&mut editor).unwrap_or_else(|error| error);
            }
            ItemEditorCommand::ValidateCurrent => {
                editor.status =
                    validate_current_document(&mut editor).unwrap_or_else(|error| error);
            }
            ItemEditorCommand::SaveCurrent => {
                editor.status = save_current_document(&mut editor).unwrap_or_else(|error| error);
            }
            ItemEditorCommand::SaveAllDirty => {
                editor.status = save_all_dirty_documents(&mut editor).unwrap_or_else(|error| error);
            }
            ItemEditorCommand::DeleteCurrent => {
                editor.status = delete_current_document(&mut editor).unwrap_or_else(|error| error);
            }
            ItemEditorCommand::SelectDocument { key } => {
                editor
                    .workspace
                    .set_selected_document_key(Some(key.clone()));
                editor.ensure_selection();
            }
        }
    }
}
