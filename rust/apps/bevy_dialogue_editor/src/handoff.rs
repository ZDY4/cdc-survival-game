use bevy::log::{info, warn};
use bevy::prelude::*;
use game_editor::{
    clear_editor_navigation_request, read_editor_navigation_request, write_editor_session,
    EditorKind, EditorNavigationAction,
};

use crate::state::{DialogueEditorCatalogs, EditorState, ExternalDialogueSelectionState};

pub(crate) fn poll_external_selection_system(
    time: Res<Time>,
    mut editor: ResMut<EditorState>,
    catalogs: Res<DialogueEditorCatalogs>,
    mut external: ResMut<ExternalDialogueSelectionState>,
) {
    if external.heartbeat_timer.tick(time.delta()).just_finished() {
        if let Err(error) = write_editor_session(
            &external.repo_root,
            EditorKind::Dialogue,
            std::process::id(),
        ) {
            warn!("dialogue editor failed to refresh handoff session: {error}");
        }
    }

    if !external
        .request_poll_timer
        .tick(time.delta())
        .just_finished()
    {
        return;
    }

    let request = match read_editor_navigation_request(&external.repo_root, EditorKind::Dialogue) {
        Ok(request) => request,
        Err(error) => {
            warn!("dialogue editor failed to read selection request: {error}");
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
        || request.target_kind != "dialogue"
    {
        warn!(
            "dialogue editor ignored unsupported navigation request: request_id={}, target_kind={}",
            request.request_id, request.target_kind
        );
        if let Err(error) =
            clear_editor_navigation_request(&external.repo_root, EditorKind::Dialogue)
        {
            warn!("dialogue editor failed to clear selection request: {error}");
        }
        return;
    }

    editor.status = if editor.select_dialogue(&request.target_id, &catalogs) {
        info!(
            "dialogue editor applied external selection request: dialogue_id={}, request_id={}",
            request.target_id, request.request_id
        );
        format!(
            "Selected dialogue {} from external request.",
            request.target_id
        )
    } else {
        warn!(
            "dialogue editor received external selection for unknown dialogue: dialogue_id={}, request_id={}",
            request.target_id, request.request_id
        );
        format!(
            "External request targeted missing dialogue {}.",
            request.target_id
        )
    };

    if let Err(error) = clear_editor_navigation_request(&external.repo_root, EditorKind::Dialogue) {
        warn!("dialogue editor failed to clear selection request: {error}");
    }
}
