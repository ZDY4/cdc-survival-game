use bevy::log::{info, warn};
use bevy::prelude::*;
use game_editor::{
    clear_editor_navigation_request, read_editor_navigation_request, write_editor_session,
    EditorKind, EditorNavigationAction,
};

use crate::state::{EditorState, ExternalSkillSelectionState, SkillEditorCatalogs};

pub(crate) fn poll_external_selection_system(
    time: Res<Time>,
    mut editor: ResMut<EditorState>,
    catalogs: Res<SkillEditorCatalogs>,
    mut external: ResMut<ExternalSkillSelectionState>,
) {
    if external.heartbeat_timer.tick(time.delta()).just_finished() {
        if let Err(error) =
            write_editor_session(&external.repo_root, EditorKind::Skill, std::process::id())
        {
            warn!("skill editor failed to refresh handoff session: {error}");
        }
    }

    if !external
        .request_poll_timer
        .tick(time.delta())
        .just_finished()
    {
        return;
    }

    let request = match read_editor_navigation_request(&external.repo_root, EditorKind::Skill) {
        Ok(request) => request,
        Err(error) => {
            warn!("skill editor failed to read selection request: {error}");
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

    if !matches!(request.action, EditorNavigationAction::SelectRecord) {
        warn!(
            "skill editor ignored unsupported navigation request: request_id={}, target_kind={}",
            request.request_id, request.target_kind
        );
        if let Err(error) = clear_editor_navigation_request(&external.repo_root, EditorKind::Skill)
        {
            warn!("skill editor failed to clear selection request: {error}");
        }
        return;
    }

    editor.status = match request.target_kind.as_str() {
        "skill" => {
            if editor.select_skill(&request.target_id, &catalogs) {
                info!(
                    "skill editor applied external skill selection: skill_id={}, request_id={}",
                    request.target_id, request.request_id
                );
                format!(
                    "Selected skill {} from external request.",
                    request.target_id
                )
            } else {
                warn!(
                    "skill editor received external selection for unknown skill: skill_id={}, request_id={}",
                    request.target_id, request.request_id
                );
                format!(
                    "External request targeted missing skill {}.",
                    request.target_id
                )
            }
        }
        "skill_tree" => {
            if editor.select_tree(&request.target_id, &catalogs) {
                info!(
                    "skill editor applied external tree selection: tree_id={}, request_id={}",
                    request.target_id, request.request_id
                );
                format!(
                    "Selected skill tree {} from external request.",
                    request.target_id
                )
            } else {
                warn!(
                    "skill editor received external selection for unknown tree: tree_id={}, request_id={}",
                    request.target_id, request.request_id
                );
                format!(
                    "External request targeted missing skill tree {}.",
                    request.target_id
                )
            }
        }
        other => {
            warn!(
                "skill editor ignored unsupported navigation target kind: request_id={}, target_kind={}",
                request.request_id, other
            );
            format!("Ignored unsupported navigation target kind {other}.")
        }
    };

    if let Err(error) = clear_editor_navigation_request(&external.repo_root, EditorKind::Skill) {
        warn!("skill editor failed to clear selection request: {error}");
    }
}
