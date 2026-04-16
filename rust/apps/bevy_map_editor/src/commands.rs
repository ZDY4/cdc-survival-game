use bevy::prelude::*;

use crate::map_ai::{apply_prepared_proposal, start_map_ai_generation};
use crate::state::{EditorState, LibraryView, MapAiState, MapAiWorkerState, OrbitCameraState};
use crate::ui::actions::{
    refresh_current_map_diagnostics, reload_editor_content, save_current_map,
    sync_camera_target_to_selected_view,
};

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub(crate) enum MapEditorCommand {
    Reload,
    SaveCurrent,
    ValidateCurrent,
    SelectMap { map_id: String, level: i32 },
    SelectOverworld { overworld_id: String },
    SetSelectedView(LibraryView),
    StartAiGeneration,
    ApplyAiProposal,
}

pub(crate) fn handle_map_editor_commands(
    mut requests: MessageReader<MapEditorCommand>,
    mut editor: ResMut<EditorState>,
    mut orbit_camera: ResMut<OrbitCameraState>,
    mut ai: ResMut<MapAiState>,
    mut worker: ResMut<MapAiWorkerState>,
) {
    for request in requests.read() {
        match request {
            MapEditorCommand::Reload => {
                ai.clear_result();
                editor.status = reload_editor_content(&mut editor);
                sync_camera_target_to_selected_view(&editor, &mut orbit_camera);
            }
            MapEditorCommand::SaveCurrent => {
                editor.status = save_current_map(&mut editor).unwrap_or_else(|error| error);
                sync_camera_target_to_selected_view(&editor, &mut orbit_camera);
            }
            MapEditorCommand::ValidateCurrent => {
                editor.status =
                    refresh_current_map_diagnostics(&mut editor).unwrap_or_else(|error| error);
            }
            MapEditorCommand::SelectMap { map_id, level } => {
                editor.update_map_selection(map_id.clone(), *level);
                sync_camera_target_to_selected_view(&editor, &mut orbit_camera);
            }
            MapEditorCommand::SelectOverworld { overworld_id } => {
                editor.update_overworld_selection(overworld_id.clone());
                sync_camera_target_to_selected_view(&editor, &mut orbit_camera);
            }
            MapEditorCommand::SetSelectedView(view) => {
                editor.set_selected_view(*view);
                sync_camera_target_to_selected_view(&editor, &mut orbit_camera);
            }
            MapEditorCommand::StartAiGeneration => {
                start_map_ai_generation(&editor, &mut ai, &mut worker);
            }
            MapEditorCommand::ApplyAiProposal => {
                if let Some(proposal) = ai.result.as_ref() {
                    match apply_prepared_proposal(&mut editor, proposal) {
                        Ok(status) => {
                            editor.status = status;
                            sync_camera_target_to_selected_view(&editor, &mut orbit_camera);
                        }
                        Err(error) => {
                            editor.status = error;
                        }
                    }
                }
            }
        }
    }
}
