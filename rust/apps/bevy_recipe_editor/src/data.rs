use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

use bevy::log::{info, warn};
use bevy::prelude::{Res, ResMut, Time};
use game_data::{
    load_item_library, load_skill_library, RecipeEditDiagnostic, RecipeEditorService,
    SkillValidationCatalog,
};
use game_editor::{
    clear_editor_navigation_request, read_editor_navigation_request, write_editor_session,
    EditorKind, EditorNavigationAction, WorkingDocumentStore,
};

use crate::state::{
    EditorState, ExternalRecipeSelectionState, RecipeEditorCatalogs, WorkingRecipeDocument,
};

pub(crate) fn load_editor_resources(
    initial_selection: Option<String>,
) -> Result<(EditorState, RecipeEditorCatalogs), String> {
    let repo_root = repo_root();
    let data_root = repo_root.join("data");
    let recipes_dir = data_root.join("recipes");
    let items_dir = data_root.join("items");
    let skills_dir = data_root.join("skills");

    let service = RecipeEditorService::with_data_root(&recipes_dir, &data_root);
    let item_library = load_item_library(&items_dir, None)
        .map_err(|error| format!("failed to load item catalog: {error}"))?;
    let skill_library = load_skill_library(&skills_dir, Some(&SkillValidationCatalog::default()))
        .map_err(|error| format!("failed to load skill catalog: {error}"))?;
    let documents = service
        .load_documents()
        .map_err(|error| format!("failed to load recipe workspace: {error}"))?;

    let mut working_documents = BTreeMap::new();
    let mut diagnostics = 0usize;
    for document in documents {
        diagnostics += document.diagnostics.len();
        working_documents.insert(
            document.file_name.clone(),
            WorkingRecipeDocument {
                document_key: document.file_name.clone(),
                original_id: Some(document.definition.id.clone()),
                file_name: document.file_name,
                relative_path: document.relative_path,
                definition: document.definition,
                dirty: false,
                diagnostics: document.diagnostics,
                last_save_message: None,
            },
        );
    }

    let catalogs = RecipeEditorCatalogs {
        item_name_lookup: item_library
            .iter()
            .map(|(item_id, definition)| (*item_id, definition.name.clone()))
            .collect::<BTreeMap<_, _>>(),
        skill_name_lookup: skill_library
            .iter()
            .map(|(skill_id, definition)| (skill_id.clone(), definition.name.clone()))
            .collect::<BTreeMap<_, _>>(),
        item_ids: item_library.ids().into_iter().collect(),
        skill_ids: skill_library.ids().into_iter().collect(),
    };

    let mut editor = EditorState {
        repo_root,
        service,
        workspace: WorkingDocumentStore::from_documents(working_documents),
        search_text: String::new(),
        status: "Loaded recipe workspace.".to_string(),
    };
    if let Some(recipe_id) = initial_selection.as_deref() {
        if editor.select_recipe_id(recipe_id) {
            editor.status = format!("Loaded recipe workspace and selected recipe {recipe_id}.");
        } else {
            editor.status =
                format!("Loaded recipe workspace. Requested recipe {recipe_id} was not found.");
            warn!("recipe editor startup selection not found: recipe_id={recipe_id}");
            editor.ensure_selection();
        }
    } else {
        editor.ensure_selection();
    }

    info!(
        "recipe editor data loaded: recipes={}, items={}, skills={}, diagnostics={}",
        editor.workspace.len(),
        catalogs.item_ids.len(),
        catalogs.skill_ids.len(),
        diagnostics
    );
    if diagnostics > 0 {
        warn!("recipe editor loaded workspace with {diagnostics} diagnostic entries");
    }

    Ok((editor, catalogs))
}

pub(crate) fn validate_all_documents(
    editor: &mut EditorState,
    catalogs: &RecipeEditorCatalogs,
) -> Result<(), String> {
    let duplicate_ids = duplicate_ids(
        editor
            .workspace
            .values()
            .map(|document| document.definition.id.clone()),
    );
    let recipe_ids = editor.current_recipe_ids();
    let item_ids = catalogs.item_ids.iter().copied().collect::<BTreeSet<_>>();
    let skill_ids = catalogs.skill_ids.iter().cloned().collect::<BTreeSet<_>>();
    let keys = editor.workspace.keys().cloned().collect::<Vec<_>>();

    for key in keys {
        let definition = editor
            .workspace
            .get(&key)
            .map(|document| document.definition.clone())
            .ok_or_else(|| format!("missing document {key}"))?;
        let mut diagnostics = editor
            .service
            .validate_definition_with_catalog(
                &definition,
                item_ids.clone(),
                skill_ids.clone(),
                recipe_ids.clone(),
            )
            .map_err(|error| error.to_string())?
            .diagnostics;
        if duplicate_ids.contains(definition.id.as_str()) {
            diagnostics.push(RecipeEditDiagnostic::error(
                "duplicate_recipe_id",
                format!(
                    "recipe {} appears more than once in the working set",
                    definition.id
                ),
            ));
        }
        if let Some(document) = editor.workspace.get_mut(&key) {
            document.diagnostics = diagnostics;
        }
    }

    Ok(())
}

fn duplicate_ids(ids: impl IntoIterator<Item = String>) -> BTreeSet<String> {
    let mut seen = BTreeSet::new();
    let mut duplicates = BTreeSet::new();
    for id in ids {
        if !seen.insert(id.clone()) {
            duplicates.insert(id);
        }
    }
    duplicates
}

pub(crate) fn poll_external_selection_system(
    time: Res<Time>,
    mut editor: ResMut<EditorState>,
    mut external: ResMut<ExternalRecipeSelectionState>,
) {
    if external.heartbeat_timer.tick(time.delta()).just_finished() {
        if let Err(error) =
            write_editor_session(&external.repo_root, EditorKind::Recipe, std::process::id())
        {
            warn!("recipe editor failed to refresh handoff session: {error}");
        }
    }

    if !external
        .request_poll_timer
        .tick(time.delta())
        .just_finished()
    {
        return;
    }

    let request = match read_editor_navigation_request(&external.repo_root, EditorKind::Recipe) {
        Ok(request) => request,
        Err(error) => {
            warn!("recipe editor failed to read selection request: {error}");
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
        || request.target_kind != "recipe"
    {
        warn!(
            "recipe editor ignored unsupported navigation request: request_id={}, target_kind={}",
            request.request_id, request.target_kind
        );
        if let Err(error) = clear_editor_navigation_request(&external.repo_root, EditorKind::Recipe)
        {
            warn!("recipe editor failed to clear selection request: {error}");
        }
        return;
    }

    editor.status = if editor.select_recipe_id(&request.target_id) {
        info!(
            "recipe editor applied external selection request: recipe_id={}, request_id={}",
            request.target_id, request.request_id
        );
        format!(
            "Selected recipe {} from external request.",
            request.target_id
        )
    } else {
        warn!(
            "recipe editor received external selection for unknown recipe: recipe_id={}, request_id={}",
            request.target_id, request.request_id
        );
        format!(
            "External request targeted missing recipe {}.",
            request.target_id
        )
    };

    if let Err(error) = clear_editor_navigation_request(&external.repo_root, EditorKind::Recipe) {
        warn!("recipe editor failed to clear selection request: {error}");
    }
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}
