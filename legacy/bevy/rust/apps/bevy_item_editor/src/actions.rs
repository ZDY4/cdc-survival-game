use bevy::log::{info, warn};

use crate::data::{load_editor_resources, validate_all_documents};
use crate::state::EditorState;

pub(crate) fn reload_editor_content(editor: &mut EditorState) -> Result<String, String> {
    if editor.has_dirty_documents() {
        warn!("item editor reload blocked: dirty drafts exist");
        return Err("Save or delete dirty item drafts before reloading content.".to_string());
    }

    let selected_id = editor
        .selected_document()
        .map(|document| document.definition.id);
    let (mut next_editor, _) = load_editor_resources(None)?;
    next_editor
        .workspace
        .set_selected_document_key(selected_id.and_then(|item_id| {
            next_editor
                .workspace
                .iter()
                .find(|(_, document)| document.definition.id == item_id)
                .map(|(key, _)| key.clone())
        }));
    next_editor.ensure_selection();

    let message = format!("Reloaded {} item documents.", next_editor.workspace.len());
    *editor = next_editor;
    info!(
        "item editor reloaded content: items={}",
        editor.workspace.len()
    );
    Ok(message)
}

pub(crate) fn validate_current_document(editor: &mut EditorState) -> Result<String, String> {
    validate_all_documents(editor)?;
    let Some(document) = editor.selected_document() else {
        return Err("No item selected.".to_string());
    };
    Ok(format!(
        "Validated item {} ({} diagnostics).",
        document.definition.id,
        document.diagnostics.len()
    ))
}

pub(crate) fn save_current_document(editor: &mut EditorState) -> Result<String, String> {
    let key = editor
        .workspace
        .selected_document_key()
        .cloned()
        .ok_or_else(|| "No item selected.".to_string())?;
    save_document_by_key(editor, &key)
}

pub(crate) fn save_all_dirty_documents(editor: &mut EditorState) -> Result<String, String> {
    let keys = editor.dirty_document_keys();
    if keys.is_empty() {
        return Ok("No unsaved item changes.".to_string());
    }

    for key in keys.clone() {
        if editor.workspace.contains_key(&key) {
            save_document_by_key(editor, &key)?;
        }
    }
    Ok(format!("Saved {} dirty item documents.", keys.len()))
}

pub(crate) fn delete_current_document(editor: &mut EditorState) -> Result<String, String> {
    let key = editor
        .workspace
        .selected_document_key()
        .cloned()
        .ok_or_else(|| "No item selected.".to_string())?;
    let document = editor
        .workspace
        .get(&key)
        .cloned()
        .ok_or_else(|| "Selected item is no longer loaded.".to_string())?;

    if let Some(original_id) = document.original_id {
        let delete_id = if document.dirty && document.definition.id != original_id {
            original_id
        } else {
            document.definition.id
        };
        editor
            .service
            .delete_item_definition(delete_id)
            .map_err(|error| error.to_string())?;
    }

    editor.workspace.remove(&key);
    editor.ensure_selection();
    validate_all_documents(editor)?;
    Ok(format!("Deleted item draft {}.", document.definition.id))
}

fn save_document_by_key(editor: &mut EditorState, key: &str) -> Result<String, String> {
    validate_all_documents(editor)?;
    if editor.has_duplicate_ids() {
        return Err("Resolve duplicate item ids before saving.".to_string());
    }

    let item_ids = editor.current_item_ids();
    let document = editor
        .workspace
        .get(key)
        .cloned()
        .ok_or_else(|| format!("item draft {key} is no longer loaded"))?;
    if document.diagnostics.iter().any(|diagnostic| {
        matches!(
            diagnostic.severity,
            game_data::ItemEditDiagnosticSeverity::Error
        )
    }) {
        return Err(format!(
            "item {} has validation errors and cannot be saved",
            document.definition.id
        ));
    }

    let result = editor
        .service
        .save_item_definition(document.original_id, &document.definition, item_ids)
        .map_err(|error| error.to_string())?;

    let next_key = format!("{}.json", document.definition.id);
    let mut next_document = document.clone();
    next_document.document_key = next_key.clone();
    next_document.original_id = Some(document.definition.id);
    next_document.file_name = next_key.clone();
    next_document.relative_path = format!("items/{}.json", document.definition.id);
    next_document.dirty = false;
    next_document.last_save_message = Some(result.summary.details.join("; "));
    editor.workspace.remove(key);
    editor.workspace.insert(next_key.clone(), next_document);
    editor.workspace.set_selected_document_key(Some(next_key));
    validate_all_documents(editor)?;
    info!("item editor saved item: item_id={}", document.definition.id);
    Ok(format!("Saved item {}.", document.definition.id))
}
