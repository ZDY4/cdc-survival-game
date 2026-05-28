use bevy::log::{info, warn};
use game_data::{load_map_library, load_overworld_library, OverworldId};

use crate::scene::{map_focus_target, overworld_focus_target};
use crate::state::{
    build_working_maps, map_display_name, project_data_dir, validate_document, EditorState,
    OrbitCameraState,
};

pub(crate) fn reload_editor_content(editor: &mut EditorState) -> String {
    if editor.maps.values().any(|document| document.dirty) {
        warn!("map editor reload blocked: dirty drafts exist");
        return "Save or discard dirty map drafts before reloading content.".to_string();
    }

    let maps_dir = project_data_dir("maps");
    let overworld_dir = project_data_dir("overworld");
    match (
        load_map_library(&maps_dir),
        load_overworld_library(&overworld_dir),
    ) {
        (Ok(map_library), Ok(overworld_library)) => {
            let previous_selected_map = editor.selected_map_id.clone();
            let previous_selected_overworld = editor.selected_overworld_id.clone();
            editor.maps = build_working_maps(&editor.map_service, &map_library);
            editor.overworld_library = overworld_library;
            editor
                .restore_selection_after_reload(previous_selected_map, previous_selected_overworld);
            info!(
                "map editor reloaded content: maps={}, overworlds={}",
                editor.maps.len(),
                editor.overworld_library.len()
            );
            format!(
                "Reloaded {} maps and {} overworld documents.",
                editor.maps.len(),
                editor.overworld_library.len()
            )
        }
        (Err(map_error), Ok(_)) => {
            warn!("map editor reload failed for maps: {map_error}");
            format!("Failed to reload maps: {map_error}")
        }
        (Ok(_), Err(overworld_error)) => {
            warn!("map editor reload failed for overworlds: {overworld_error}");
            format!("Failed to reload overworlds: {overworld_error}")
        }
        (Err(map_error), Err(overworld_error)) => {
            warn!(
                "map editor reload failed: maps={}, overworlds={}",
                map_error, overworld_error
            );
            format!("Failed to reload content. maps={map_error}; overworld={overworld_error}")
        }
    }
}

pub(crate) fn refresh_current_map_diagnostics(editor: &mut EditorState) -> Result<String, String> {
    let selected_map_id = editor
        .selected_map_id
        .clone()
        .ok_or_else(|| "No map selected.".to_string())?;
    let document = editor
        .maps
        .get_mut(&selected_map_id)
        .ok_or_else(|| "Selected map is no longer loaded.".to_string())?;
    document.diagnostics = validate_document(&editor.map_service, &document.definition);
    info!(
        "map editor validated map: map_id={}, diagnostics={}",
        selected_map_id,
        document.diagnostics.len()
    );
    Ok(format!(
        "Validated map {} ({} diagnostic entries).",
        selected_map_id,
        document.diagnostics.len()
    ))
}

pub(crate) fn save_current_map(editor: &mut EditorState) -> Result<String, String> {
    let preserved_level = editor.current_map_level;
    let selected_map_id = editor
        .selected_map_id
        .clone()
        .ok_or_else(|| "No map selected.".to_string())?;
    let document = editor
        .maps
        .get(&selected_map_id)
        .cloned()
        .ok_or_else(|| "Selected map is no longer loaded.".to_string())?;

    let result = editor
        .map_service
        .save_map_definition(document.original_id.as_ref(), &document.definition)
        .map_err(|error| error.to_string())?;

    let next_map_id = document.definition.id.as_str().to_string();
    let mut next_document = document.clone();
    next_document.original_id = Some(document.definition.id.clone());
    next_document.dirty = false;
    next_document.last_save_message = Some(result.summary.details.join("; "));
    next_document.diagnostics = validate_document(&editor.map_service, &next_document.definition);

    if next_map_id != selected_map_id {
        editor.maps.remove(&selected_map_id);
    }
    editor.maps.insert(next_map_id.clone(), next_document);
    editor.update_map_selection(next_map_id.clone(), preserved_level);
    info!("map editor saved map: map_id={next_map_id}");
    Ok(format!("Saved map {}.", map_display_name(&next_map_id)))
}

pub(crate) fn sync_camera_target_to_selected_view(
    editor: &EditorState,
    orbit_camera: &mut OrbitCameraState,
) {
    match editor.selected_view {
        crate::state::LibraryView::Maps => {
            let Some(selected_map_id) = editor.selected_map_id.as_ref() else {
                return;
            };
            let Some(document) = editor.maps.get(selected_map_id) else {
                return;
            };
            orbit_camera.target = map_focus_target(&document.definition);
        }
        crate::state::LibraryView::Overworlds => {
            let Some(selected_overworld_id) = editor.selected_overworld_id.as_ref() else {
                return;
            };
            let Some(definition) = editor
                .overworld_library
                .get(&OverworldId(selected_overworld_id.clone()))
            else {
                return;
            };
            orbit_camera.target = overworld_focus_target(definition);
        }
    }
}
