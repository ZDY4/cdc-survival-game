use bevy::log::{info, warn};
use bevy::prelude::*;
use game_editor::{
    clear_editor_navigation_request, read_editor_navigation_request, write_editor_session,
    EditorKind, EditorNavigationAction,
};

use crate::commands::CharacterEditorCommand;
use crate::state::{EditorData, EditorUiState, ExternalCharacterSelectionState};

pub(crate) fn poll_external_selection_system(
    time: Res<Time>,
    data: Res<EditorData>,
    mut ui_state: ResMut<EditorUiState>,
    mut external: ResMut<ExternalCharacterSelectionState>,
    mut requests: MessageWriter<CharacterEditorCommand>,
) {
    if external.heartbeat_timer.tick(time.delta()).just_finished() {
        if let Err(error) = write_editor_session(
            &external.repo_root,
            EditorKind::Character,
            std::process::id(),
        ) {
            warn!("character editor failed to refresh handoff session: {error}");
        }
    }

    if !external
        .request_poll_timer
        .tick(time.delta())
        .just_finished()
    {
        return;
    }

    let request = match read_editor_navigation_request(&external.repo_root, EditorKind::Character) {
        Ok(request) => request,
        Err(error) => {
            warn!("character editor failed to read selection request: {error}");
            return;
        }
    };
    let Some(request) = request else {
        return;
    };

    if external.last_request_id.as_deref() == Some(request.request_id.as_str()) {
        return;
    }
    external.last_request_id = Some(request.request_id.clone());

    if !matches!(request.action, EditorNavigationAction::SelectRecord)
        || request.target_kind != "character"
    {
        warn!(
            "character editor ignored unsupported navigation request: request_id={}, target_kind={}",
            request.request_id, request.target_kind
        );
        if let Err(error) =
            clear_editor_navigation_request(&external.repo_root, EditorKind::Character)
        {
            warn!("character editor failed to clear selection request: {error}");
        }
        return;
    }

    if data
        .character_summaries
        .iter()
        .any(|summary| summary.id == request.target_id)
    {
        requests.write(CharacterEditorCommand::SelectCharacter(
            request.target_id.clone(),
        ));
        ui_state.status = format!(
            "Selected character {} from external request.",
            request.target_id
        );
        info!(
            "character editor applied external selection request: character_id={}, request_id={}",
            request.target_id, request.request_id
        );
    } else {
        ui_state.status = format!(
            "External request targeted missing character {}.",
            request.target_id
        );
        warn!(
            "character editor received external selection for unknown character: character_id={}, request_id={}",
            request.target_id, request.request_id
        );
    }

    if let Err(error) = clear_editor_navigation_request(&external.repo_root, EditorKind::Character)
    {
        warn!("character editor failed to clear selection request: {error}");
    }
}
