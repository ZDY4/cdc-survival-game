use bevy::prelude::*;
use game_data::CharacterAiPreviewContext;
use game_editor::PreviewCameraController;

use crate::camera_mode::{
    reset_active_preview_camera, sync_preview_camera_mode, PreviewCameraMode,
    PreviewCameraModeState,
};
use crate::preview::{
    ensure_selected_character, refresh_preview_state, select_character, PreviewCamera,
};
use crate::state::{EditorData, EditorUiState, PreviewState};

#[derive(Message, Debug, Clone)]
pub(crate) enum CharacterEditorCommand {
    SelectCharacter(String),
    SetTryOnItem { slot: String, item_id: Option<u32> },
    UpdatePreviewContext(CharacterAiPreviewContext),
    SetCameraMode(PreviewCameraMode),
    ResetCamera,
    ClearTryOn,
}

pub(crate) fn ensure_selected_character_system(
    data: Res<EditorData>,
    ui_state: Res<EditorUiState>,
    mut requests: MessageWriter<CharacterEditorCommand>,
) {
    if ui_state.selected_character_id.is_none() && !data.character_summaries.is_empty() {
        requests.write(CharacterEditorCommand::SelectCharacter(
            data.character_summaries[0].id.clone(),
        ));
    }
}

pub(crate) fn handle_character_editor_commands(
    mut requests: MessageReader<CharacterEditorCommand>,
    data: Res<EditorData>,
    mut ui_state: ResMut<EditorUiState>,
    mut preview_state: ResMut<PreviewState>,
    mut camera_mode: ResMut<PreviewCameraModeState>,
    mut preview_camera_query: Query<
        (&mut PreviewCameraController, &mut Projection),
        With<PreviewCamera>,
    >,
) {
    let Ok((mut preview_camera, mut preview_projection)) = preview_camera_query.single_mut() else {
        return;
    };

    ensure_selected_character(
        &data,
        &mut ui_state,
        &mut preview_state,
        &mut camera_mode,
        &mut preview_camera,
        &mut preview_projection,
    );

    for request in requests.read() {
        match request {
            CharacterEditorCommand::SelectCharacter(character_id) => select_character(
                character_id.clone(),
                &data,
                &mut ui_state,
                &mut preview_state,
                &mut camera_mode,
                &mut preview_camera,
                &mut preview_projection,
            ),
            CharacterEditorCommand::SetTryOnItem { slot, item_id } => {
                match item_id {
                    Some(item_id) => {
                        ui_state.try_on.insert(slot.clone(), *item_id);
                    }
                    None => {
                        ui_state.try_on.remove(slot);
                    }
                }
                refresh_preview_state(
                    &data,
                    &mut ui_state,
                    &mut preview_state,
                    &mut camera_mode,
                    &mut preview_camera,
                    &mut preview_projection,
                    false,
                );
            }
            CharacterEditorCommand::UpdatePreviewContext(context) => {
                ui_state.preview_context = context.clone();
                refresh_preview_state(
                    &data,
                    &mut ui_state,
                    &mut preview_state,
                    &mut camera_mode,
                    &mut preview_camera,
                    &mut preview_projection,
                    false,
                );
            }
            CharacterEditorCommand::SetCameraMode(mode) => {
                camera_mode.mode = *mode;
                reset_active_preview_camera(
                    &camera_mode,
                    preview_state.resolved_preview.as_ref(),
                    &mut preview_camera,
                    &mut preview_projection,
                );
            }
            CharacterEditorCommand::ResetCamera => {
                reset_active_preview_camera(
                    &camera_mode,
                    preview_state.resolved_preview.as_ref(),
                    &mut preview_camera,
                    &mut preview_projection,
                );
            }
            CharacterEditorCommand::ClearTryOn => {
                ui_state.try_on.clear();
                refresh_preview_state(
                    &data,
                    &mut ui_state,
                    &mut preview_state,
                    &mut camera_mode,
                    &mut preview_camera,
                    &mut preview_projection,
                    false,
                );
            }
        }
    }

    sync_preview_camera_mode(&camera_mode, &mut preview_camera, &mut preview_projection);
}
