use std::collections::BTreeSet;

use bevy::log::{info, warn};
use game_data::RecipeEditDiagnosticSeverity;

use crate::data::{load_editor_resources, validate_all_documents};
use crate::state::{EditorState, RecipeEditorCatalogs};

pub(crate) fn reload_editor_content(editor: &mut EditorState) -> Result<String, String> {
    if editor.has_dirty_documents() {
        warn!("recipe editor reload blocked: dirty drafts exist");
        return Err("Save or delete dirty recipe drafts before reloading content.".to_string());
    }

    let selected_id = editor
        .selected_document()
        .map(|document| document.definition.id.clone());
    let (next_editor, _) = load_editor_resources(selected_id)?;

    let message = format!("Reloaded {} recipe documents.", next_editor.workspace.len());
    *editor = next_editor;
    info!(
        "recipe editor reloaded content: recipes={}",
        editor.workspace.len()
    );
    Ok(message)
}

pub(crate) fn validate_current_document(
    editor: &mut EditorState,
    catalogs: &RecipeEditorCatalogs,
) -> Result<String, String> {
    validate_all_documents(editor, catalogs)?;
    let Some(document) = editor.selected_document() else {
        return Err("No recipe selected.".to_string());
    };
    Ok(format!(
        "Validated recipe {} ({} diagnostics).",
        document.definition.id,
        document.diagnostics.len()
    ))
}

pub(crate) fn save_current_document(
    editor: &mut EditorState,
    catalogs: &RecipeEditorCatalogs,
) -> Result<String, String> {
    let key = editor
        .workspace
        .selected_document_key()
        .cloned()
        .ok_or_else(|| "No recipe selected.".to_string())?;
    save_document_by_key(editor, catalogs, &key)
}

pub(crate) fn save_all_dirty_documents(
    editor: &mut EditorState,
    catalogs: &RecipeEditorCatalogs,
) -> Result<String, String> {
    let keys = editor.dirty_document_keys();
    if keys.is_empty() {
        return Ok("No unsaved recipe changes.".to_string());
    }

    for key in keys.clone() {
        if editor.workspace.contains_key(&key) {
            save_document_by_key(editor, catalogs, &key)?;
        }
    }
    Ok(format!("Saved {} dirty recipe documents.", keys.len()))
}

pub(crate) fn delete_current_document(
    editor: &mut EditorState,
    catalogs: &RecipeEditorCatalogs,
) -> Result<String, String> {
    let key = editor
        .workspace
        .selected_document_key()
        .cloned()
        .ok_or_else(|| "No recipe selected.".to_string())?;
    let document = editor
        .workspace
        .get(&key)
        .cloned()
        .ok_or_else(|| "Selected recipe is no longer loaded.".to_string())?;

    if let Some(original_id) = document.original_id.clone() {
        let delete_id = if document.dirty && document.definition.id != original_id {
            original_id
        } else {
            document.definition.id.clone()
        };
        editor
            .service
            .delete_recipe_definition(&delete_id)
            .map_err(|error| error.to_string())?;
    }

    editor.workspace.remove(&key);
    editor.ensure_selection();
    validate_all_documents(editor, catalogs)?;
    Ok(format!("Deleted recipe draft {}.", document.definition.id))
}

fn save_document_by_key(
    editor: &mut EditorState,
    catalogs: &RecipeEditorCatalogs,
    key: &str,
) -> Result<String, String> {
    validate_all_documents(editor, catalogs)?;
    if editor.has_duplicate_ids() {
        return Err("Resolve duplicate recipe ids before saving.".to_string());
    }

    let document = editor
        .workspace
        .get(key)
        .cloned()
        .ok_or_else(|| format!("recipe draft {key} is no longer loaded"))?;
    if document
        .diagnostics
        .iter()
        .any(|diagnostic| matches!(diagnostic.severity, RecipeEditDiagnosticSeverity::Error))
    {
        return Err(format!(
            "recipe {} has validation errors and cannot be saved",
            document.definition.id
        ));
    }

    let result = editor
        .service
        .save_recipe_definition(
            document.original_id.as_deref(),
            &document.definition,
            catalogs.item_ids.iter().copied().collect::<BTreeSet<_>>(),
            catalogs.skill_ids.iter().cloned().collect::<BTreeSet<_>>(),
            editor.current_recipe_ids(),
        )
        .map_err(|error| error.to_string())?;

    let next_key = format!("{}.json", document.definition.id);
    let mut next_document = document.clone();
    next_document.document_key = next_key.clone();
    next_document.original_id = Some(document.definition.id.clone());
    next_document.file_name = next_key.clone();
    next_document.relative_path = format!("recipes/{}.json", document.definition.id);
    next_document.dirty = false;
    next_document.last_save_message = Some(result.summary.details.join("; "));
    editor.workspace.remove(key);
    editor.workspace.insert(next_key.clone(), next_document);
    editor.workspace.set_selected_document_key(Some(next_key));
    validate_all_documents(editor, catalogs)?;
    info!(
        "recipe editor saved recipe: recipe_id={}",
        document.definition.id
    );
    Ok(format!("Saved recipe {}.", document.definition.id))
}
