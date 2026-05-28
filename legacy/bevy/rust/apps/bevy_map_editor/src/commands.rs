use bevy::prelude::*;

use crate::state::{EditorState, LibraryView, OrbitCameraState};
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
}

pub(crate) fn handle_map_editor_commands(
    mut requests: MessageReader<MapEditorCommand>,
    mut editor: ResMut<EditorState>,
    mut orbit_camera: ResMut<OrbitCameraState>,
) {
    for request in requests.read() {
        match request {
            MapEditorCommand::Reload => {
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
        }
    }
}
