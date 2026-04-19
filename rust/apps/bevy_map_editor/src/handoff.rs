use bevy::log::{info, warn};
use bevy::prelude::*;
use game_editor::{
    clear_editor_navigation_request, read_editor_navigation_request, write_editor_session,
    EditorKind, EditorNavigationAction,
};

use crate::commands::MapEditorCommand;
use crate::state::{EditorState, ExternalMapSelectionState};

pub(crate) fn poll_external_selection_system(
    time: Res<Time>,
    mut editor: ResMut<EditorState>,
    mut external: ResMut<ExternalMapSelectionState>,
    mut requests: MessageWriter<MapEditorCommand>,
) {
    if external.heartbeat_timer.tick(time.delta()).just_finished() {
        if let Err(error) =
            write_editor_session(&external.repo_root, EditorKind::Map, std::process::id())
        {
            warn!("map editor failed to refresh handoff session: {error}");
        }
    }

    if !external
        .request_poll_timer
        .tick(time.delta())
        .just_finished()
    {
        return;
    }

    let request = match read_editor_navigation_request(&external.repo_root, EditorKind::Map) {
        Ok(request) => request,
        Err(error) => {
            warn!("map editor failed to read selection request: {error}");
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
        || request.target_kind != "map"
    {
        warn!(
            "map editor ignored unsupported navigation request: request_id={}, target_kind={}",
            request.request_id, request.target_kind
        );
        if let Err(error) = clear_editor_navigation_request(&external.repo_root, EditorKind::Map) {
            warn!("map editor failed to clear selection request: {error}");
        }
        return;
    }

    if let Some(document) = editor.maps.get(&request.target_id) {
        requests.write(MapEditorCommand::SelectMap {
            map_id: request.target_id.clone(),
            level: document.definition.default_level,
        });
        editor.status = format!("Selected map {} from external request.", request.target_id);
        info!(
            "map editor applied external selection request: map_id={}, request_id={}",
            request.target_id, request.request_id
        );
    } else {
        editor.status = format!("External request targeted missing map {}.", request.target_id);
        warn!(
            "map editor received external selection for unknown map: map_id={}, request_id={}",
            request.target_id, request.request_id
        );
    }

    if let Err(error) = clear_editor_navigation_request(&external.repo_root, EditorKind::Map) {
        warn!("map editor failed to clear selection request: {error}");
    }
}
