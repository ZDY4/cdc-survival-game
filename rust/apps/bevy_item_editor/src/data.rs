use std::collections::{BTreeMap, BTreeSet};
use std::path::PathBuf;

use bevy::log::{info, warn};
use bevy::prelude::*;
use game_data::{load_effect_library, ItemEditDiagnostic, ItemEditorService};
use game_editor::{
    clear_item_editor_selection_request, read_item_editor_selection_request,
    write_item_editor_session,
};

use crate::state::{
    EditorState, ExternalItemSelectionState, ItemEditorCatalogs, WorkingItemDocument,
    DEFAULT_EQUIPMENT_SLOTS, DEFAULT_KNOWN_SUBTYPES,
};

pub(crate) fn load_editor_resources(
    initial_selection: Option<u32>,
) -> Result<(EditorState, ItemEditorCatalogs), String> {
    let repo_root = repo_root();
    let data_root = repo_root.join("data");
    let items_dir = data_root.join("items");
    let effects_dir = data_root.join("json").join("effects");
    let service = ItemEditorService::with_data_root(&items_dir, &data_root);
    let effects = load_effect_library(&effects_dir)
        .map_err(|error| format!("failed to load effect catalog: {error}"))?;
    let documents = service
        .load_documents()
        .map_err(|error| format!("failed to load item workspace: {error}"))?;

    let mut working_documents = BTreeMap::new();
    let mut equipment_slots = DEFAULT_EQUIPMENT_SLOTS
        .iter()
        .map(|value| (*value).to_string())
        .collect::<BTreeSet<_>>();
    let mut known_subtypes = DEFAULT_KNOWN_SUBTYPES
        .iter()
        .map(|value| (*value).to_string())
        .collect::<BTreeSet<_>>();
    let mut diagnostics = 0usize;

    for document in documents {
        diagnostics += document.diagnostics.len();
        for slot in document.definition.equip_slots() {
            if !slot.trim().is_empty() {
                equipment_slots.insert(slot);
            }
        }
        for fragment in &document.definition.fragments {
            match fragment {
                game_data::ItemFragment::Weapon { subtype, .. }
                | game_data::ItemFragment::Usable { subtype, .. } => {
                    let subtype = subtype.trim();
                    if !subtype.is_empty() {
                        known_subtypes.insert(subtype.to_string());
                    }
                }
                _ => {}
            }
        }
        working_documents.insert(
            document.file_name.clone(),
            WorkingItemDocument {
                document_key: document.file_name.clone(),
                original_id: Some(document.definition.id),
                file_name: document.file_name,
                relative_path: document.relative_path,
                definition: document.definition,
                dirty: false,
                diagnostics: document.diagnostics,
                last_save_message: None,
            },
        );
    }

    let mut editor = EditorState {
        repo_root,
        service,
        effects,
        documents: working_documents,
        selected_document_key: None,
        search_text: String::new(),
        status: "Loaded item workspace.".to_string(),
    };
    if let Some(item_id) = initial_selection {
        if editor.select_item_id(item_id) {
            editor.status = format!("Loaded item workspace and selected item {item_id}.");
        } else {
            editor.status =
                format!("Loaded item workspace. Requested item {item_id} was not found.");
            warn!("item editor startup selection not found: item_id={item_id}");
            editor.ensure_selection();
        }
    } else {
        editor.ensure_selection();
    }
    let catalogs = ItemEditorCatalogs {
        effect_ids: editor.effects.ids().into_iter().collect(),
        equipment_slots: equipment_slots.into_iter().collect(),
        known_subtypes: known_subtypes.into_iter().collect(),
    };

    info!(
        "item editor data loaded: items={}, effects={}, diagnostics={}",
        editor.documents.len(),
        catalogs.effect_ids.len(),
        diagnostics
    );
    if diagnostics > 0 {
        warn!("item editor loaded workspace with {diagnostics} diagnostic entries");
    }

    Ok((editor, catalogs))
}

pub(crate) fn poll_external_selection_system(
    time: Res<Time>,
    mut editor: ResMut<EditorState>,
    mut external: ResMut<ExternalItemSelectionState>,
) {
    if external.heartbeat_timer.tick(time.delta()).just_finished() {
        if let Err(error) = write_item_editor_session(&external.repo_root, std::process::id()) {
            warn!("item editor failed to refresh handoff session: {error}");
        }
    }

    if !external
        .request_poll_timer
        .tick(time.delta())
        .just_finished()
    {
        return;
    }

    let request = match read_item_editor_selection_request(&external.repo_root) {
        Ok(request) => request,
        Err(error) => {
            warn!("item editor failed to read selection request: {error}");
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

    editor.status = if editor.select_item_id(request.item_id) {
        info!(
            "item editor applied external selection request: item_id={}, request_id={}",
            request.item_id, request.request_id
        );
        format!("Selected item {} from external request.", request.item_id)
    } else {
        warn!(
            "item editor received external selection for unknown item: item_id={}, request_id={}",
            request.item_id, request.request_id
        );
        format!(
            "External request targeted missing item {}.",
            request.item_id
        )
    };

    if let Err(error) = clear_item_editor_selection_request(&external.repo_root) {
        warn!("item editor failed to clear selection request: {error}");
    }
}

pub(crate) fn validate_all_documents(editor: &mut EditorState) -> Result<(), String> {
    let duplicate_ids = duplicate_ids(
        editor
            .documents
            .values()
            .map(|document| document.definition.id),
    );
    let item_ids = editor.current_item_ids();
    let keys = editor.documents.keys().cloned().collect::<Vec<_>>();

    for key in keys {
        let definition = editor
            .documents
            .get(&key)
            .map(|document| document.definition.clone())
            .ok_or_else(|| format!("missing document {key}"))?;
        let mut diagnostics = editor
            .service
            .validate_definition_with_item_ids(&definition, item_ids.clone())
            .map_err(|error| error.to_string())?
            .diagnostics;
        if duplicate_ids.contains(&definition.id) {
            diagnostics.push(ItemEditDiagnostic::error(
                "duplicate_item_id",
                format!(
                    "item {} appears more than once in the working set",
                    definition.id
                ),
            ));
        }
        if let Some(document) = editor.documents.get_mut(&key) {
            document.diagnostics = diagnostics;
        }
    }

    Ok(())
}

pub(crate) fn duplicate_ids(ids: impl IntoIterator<Item = u32>) -> BTreeSet<u32> {
    let mut seen = BTreeSet::new();
    let mut duplicates = BTreeSet::new();
    for id in ids {
        if !seen.insert(id) {
            duplicates.insert(id);
        }
    }
    duplicates
}

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}
