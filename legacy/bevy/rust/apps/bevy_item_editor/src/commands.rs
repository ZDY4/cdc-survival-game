use bevy::prelude::*;
use game_bevy::rust_asset_dir;
use game_editor::{open_model_directory, open_model_in_blockbench, open_model_in_gltf_viewer};

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
    OpenPreviewModelInBlockbench(String),
    OpenPreviewModelInGltfViewer(String),
    OpenPreviewModelDirectory(String),
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
            ItemEditorCommand::OpenPreviewModelInBlockbench(asset_path) => {
                editor.status = open_model_in_blockbench(&rust_asset_dir(), asset_path)
                    .unwrap_or_else(|error| error);
            }
            ItemEditorCommand::OpenPreviewModelInGltfViewer(asset_path) => {
                editor.status =
                    open_model_in_gltf_viewer(&editor.repo_root, &rust_asset_dir(), asset_path)
                        .unwrap_or_else(|error| error);
            }
            ItemEditorCommand::OpenPreviewModelDirectory(asset_path) => {
                editor.status = open_model_directory(&rust_asset_dir(), asset_path)
                    .map(|directory| format!("已打开模型目录: {}", directory.display()))
                    .unwrap_or_else(|error| error);
            }
        }
    }
}
