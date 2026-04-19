use bevy::prelude::*;

use crate::actions::{
    delete_current_document, reload_editor_content, save_all_dirty_documents,
    save_current_document, validate_current_document,
};
use crate::state::{EditorState, RecipeEditorCatalogs};

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub(crate) enum RecipeEditorCommand {
    Reload,
    ValidateCurrent,
    SaveCurrent,
    SaveAllDirty,
    DeleteCurrent,
    SelectDocument { key: String },
}

pub(crate) fn handle_recipe_editor_commands(
    mut requests: MessageReader<RecipeEditorCommand>,
    mut editor: ResMut<EditorState>,
    catalogs: Res<RecipeEditorCatalogs>,
) {
    for request in requests.read() {
        match request {
            RecipeEditorCommand::Reload => {
                editor.status = reload_editor_content(&mut editor).unwrap_or_else(|error| error);
            }
            RecipeEditorCommand::ValidateCurrent => {
                editor.status =
                    validate_current_document(&mut editor, &catalogs).unwrap_or_else(|error| error);
            }
            RecipeEditorCommand::SaveCurrent => {
                editor.status =
                    save_current_document(&mut editor, &catalogs).unwrap_or_else(|error| error);
            }
            RecipeEditorCommand::SaveAllDirty => {
                editor.status =
                    save_all_dirty_documents(&mut editor, &catalogs).unwrap_or_else(|error| error);
            }
            RecipeEditorCommand::DeleteCurrent => {
                editor.status =
                    delete_current_document(&mut editor, &catalogs).unwrap_or_else(|error| error);
            }
            RecipeEditorCommand::SelectDocument { key } => {
                editor
                    .workspace
                    .set_selected_document_key(Some(key.clone()));
                editor.ensure_selection();
            }
        }
    }
}
