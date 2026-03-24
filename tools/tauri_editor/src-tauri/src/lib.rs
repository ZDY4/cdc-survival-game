mod ai_context;
mod ai_provider;
mod ai_review;
mod ai_settings;
mod narrative_app_settings;
mod narrative_context;
mod narrative_provider;
mod narrative_review;
mod narrative_sync;
mod narrative_templates;
mod narrative_workspace;
mod quest_workspace;

use std::{
    collections::{BTreeMap, BTreeSet, HashSet},
    fs,
    path::{Path, PathBuf},
};

use game_data::{
    load_character_library, load_effect_library, load_shared_content_registry,
    validate_item_definition, validate_map_definition, DialogueConnection, DialogueData,
    ItemDefinition, ItemDefinitionValidationError, ItemFragment, ItemValidationCatalog,
    MapDefinition, MapValidationCatalog, SharedContentRegistry,
};
use serde::{Deserialize, Serialize};

use crate::ai_provider::{
    generate_dialogue_draft, generate_quest_draft, test_ai_provider,
};
use crate::ai_settings::{load_ai_settings, save_ai_settings};
use crate::narrative_app_settings::{
    load_narrative_app_settings, save_narrative_app_settings,
};
use crate::narrative_provider::{
    generate_narrative_draft, revise_narrative_draft,
};
use crate::narrative_sync::{
    create_cloud_workspace, export_project_context_snapshot, list_cloud_workspaces,
    load_narrative_sync_settings, save_narrative_sync_settings, sync_narrative_workspace,
    upload_project_context_snapshot,
};
use crate::narrative_workspace::{
    create_narrative_document, delete_narrative_document, load_narrative_document,
    load_narrative_workspace, prepare_structuring_bundle, save_narrative_document,
    summarize_narrative_document,
};
use crate::quest_workspace::{
    delete_quest_document, load_quest_workspace, save_quest_documents, validate_quest_document,
};

const DEFAULT_FRAGMENT_KINDS: &[&str] = &[
    "economy",
    "stacking",
    "equip",
    "durability",
    "attribute_modifiers",
    "weapon",
    "usable",
    "crafting",
    "passive_effects",
];
const DEFAULT_EQUIPMENT_SLOTS: &[&str] = &[
    "head",
    "body",
    "hands",
    "legs",
    "feet",
    "back",
    "main_hand",
    "off_hand",
    "accessory",
    "accessory_1",
    "accessory_2",
];
const DEFAULT_KNOWN_SUBTYPES: &[&str] = &[
    "unarmed",
    "dagger",
    "sword",
    "blunt",
    "axe",
    "spear",
    "polearm",
    "bow",
    "gun",
    "pistol",
    "rifle",
    "shotgun",
    "tool",
    "tools",
    "watch",
    "backpack",
    "healing",
    "food",
    "drink",
    "water",
    "metal",
    "wood",
    "fabric",
    "medical",
    "chemical",
    "key",
    "device",
    "misc",
];
const DEFAULT_DIALOG_NODE_TYPES: &[&str] = &["dialog", "choice", "condition", "action", "end"];
const DEFAULT_BUILDING_PREFABS: &[&str] = &[
    "safehouse_house",
    "safehouse_upper_room",
    "street_block",
    "warehouse_shell",
];
const DEFAULT_INTERACTION_KINDS: &[&str] = &[
    "enter_outdoor_location",
    "enter_subscene",
    "pickup",
    "dialogue",
    "trade",
];

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct MigrationStage {
    pub(crate) id: &'static str,
    pub(crate) title: &'static str,
    pub(crate) description: &'static str,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct EditorBootstrap {
    pub(crate) app_name: &'static str,
    pub(crate) workspace_root: String,
    pub(crate) shared_rust_path: String,
    pub(crate) active_stage: &'static str,
    pub(crate) stages: Vec<MigrationStage>,
    pub(crate) editor_domains: Vec<&'static str>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ValidationIssue {
    pub(crate) severity: String,
    pub(crate) field: String,
    pub(crate) message: String,
    pub(crate) scope: Option<String>,
    pub(crate) node_id: Option<String>,
    pub(crate) edge_key: Option<String>,
    pub(crate) path: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct CatalogEntry {
    value: String,
    label: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ItemReferencePreview {
    id: String,
    name: String,
    value: i32,
    weight: f32,
    derived_tags: Vec<String>,
    key_fragments: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct EffectReferencePreview {
    id: String,
    name: String,
    description: String,
    category: String,
    duration: f32,
    stack_mode: String,
    resource_deltas: BTreeMap<String, f32>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ReferenceUsageEntry {
    source_item_id: u32,
    source_item_name: String,
    fragment_kind: String,
    path: String,
    note: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ItemCatalogs {
    fragment_kinds: Vec<String>,
    effect_ids: Vec<String>,
    effect_entries: Vec<CatalogEntry>,
    effect_previews: Vec<EffectReferencePreview>,
    item_previews: Vec<ItemReferencePreview>,
    effect_used_by: BTreeMap<String, Vec<ReferenceUsageEntry>>,
    item_used_by: BTreeMap<String, Vec<ReferenceUsageEntry>>,
    equipment_slots: Vec<String>,
    known_subtypes: Vec<String>,
    item_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ItemDocumentPayload {
    document_key: String,
    original_id: u32,
    file_name: String,
    relative_path: String,
    item: ItemDefinition,
    validation: Vec<ValidationIssue>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct ItemWorkspacePayload {
    bootstrap: EditorBootstrap,
    data_directory: String,
    item_count: usize,
    catalogs: ItemCatalogs,
    documents: Vec<ItemDocumentPayload>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SaveItemDocumentInput {
    original_id: Option<u32>,
    item: ItemDefinition,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct SaveItemsResult {
    saved_ids: Vec<u32>,
    deleted_ids: Vec<u32>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct DeleteItemResult {
    deleted_id: u32,
}

#[derive(Debug, Clone)]
struct ParsedItemDocument {
    file_name: String,
    relative_path: String,
    item: ItemDefinition,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct DialogueCatalogs {
    node_types: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct DialogueDocumentPayload {
    document_key: String,
    original_id: String,
    file_name: String,
    relative_path: String,
    dialog: DialogueData,
    validation: Vec<ValidationIssue>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct DialogueWorkspacePayload {
    bootstrap: EditorBootstrap,
    data_directory: String,
    dialog_count: usize,
    catalogs: DialogueCatalogs,
    documents: Vec<DialogueDocumentPayload>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SaveDialogueDocumentInput {
    original_id: Option<String>,
    dialog: DialogueData,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct SaveDialoguesResult {
    saved_ids: Vec<String>,
    deleted_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct DeleteDialogueResult {
    deleted_id: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct MapCatalogs {
    item_ids: Vec<String>,
    character_ids: Vec<String>,
    building_prefabs: Vec<String>,
    interactive_kinds: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct MapDocumentPayload {
    document_key: String,
    original_id: String,
    file_name: String,
    relative_path: String,
    map: MapDefinition,
    validation: Vec<ValidationIssue>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct MapWorkspacePayload {
    bootstrap: EditorBootstrap,
    data_directory: String,
    map_count: usize,
    catalogs: MapCatalogs,
    documents: Vec<MapDocumentPayload>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SaveMapDocumentInput {
    original_id: Option<String>,
    map: MapDefinition,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct SaveMapsResult {
    saved_ids: Vec<String>,
    deleted_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct DeleteMapResult {
    deleted_id: String,
}

#[tauri::command]
fn get_editor_bootstrap() -> Result<EditorBootstrap, String> {
    Ok(editor_bootstrap()?)
}

#[tauri::command]
fn load_shared_registry() -> Result<SharedContentRegistry, String> {
    load_shared_content_registry(repo_root()?)
        .map_err(|error| format!("failed to load shared content registry: {error}"))
}

#[tauri::command]
fn load_item_workspace() -> Result<ItemWorkspacePayload, String> {
    let effect_library = load_effect_catalog()?;
    let effect_ids = effect_library.ids();
    let documents = load_item_documents_with_effects(&effect_ids)?;
    let catalogs = collect_catalogs(&documents, &effect_library);
    let bootstrap = editor_bootstrap()?;
    let data_directory = to_forward_slashes(&item_data_dir()?);
    let item_count = documents.len();

    Ok(ItemWorkspacePayload {
        bootstrap,
        data_directory,
        item_count,
        catalogs,
        documents,
    })
}

#[tauri::command]
fn validate_item_document(item: ItemDefinition) -> Result<Vec<ValidationIssue>, String> {
    let effect_ids = load_effect_catalog()?.ids();
    let mut item_ids = BTreeSet::new();
    for document in load_item_document_sources()? {
        item_ids.insert(document.item.id);
    }
    item_ids.insert(item.id);

    let catalog = ItemValidationCatalog { item_ids, effect_ids };
    Ok(validate_item(&item, &catalog, false))
}

#[tauri::command]
fn save_item_documents(documents: Vec<SaveItemDocumentInput>) -> Result<SaveItemsResult, String> {
    if documents.is_empty() {
        return Ok(SaveItemsResult {
            saved_ids: Vec::new(),
            deleted_ids: Vec::new(),
        });
    }

    let mut seen_ids = HashSet::new();
    let mut seen_original_ids = HashSet::new();
    for document in &documents {
        if !seen_ids.insert(document.item.id) {
            return Err(format!("duplicate item id in save batch: {}", document.item.id));
        }

        if let Some(original_id) = document.original_id {
            if !seen_original_ids.insert(original_id) {
                return Err(format!(
                    "duplicate original item id in save batch: {}",
                    original_id
                ));
            }
        }
    }

    let effect_ids = load_effect_catalog()?.ids();
    let existing_documents = load_item_document_sources()?;
    let skipped_original_ids: HashSet<u32> = documents
        .iter()
        .filter_map(|document| document.original_id)
        .collect();
    let mut final_items = BTreeMap::new();

    for document in existing_documents {
        if skipped_original_ids.contains(&document.item.id) {
            continue;
        }

        if final_items.insert(document.item.id, document.item).is_some() {
            return Err("existing item data contains duplicate ids".to_string());
        }
    }

    for document in &documents {
        if final_items
            .insert(document.item.id, document.item.clone())
            .is_some()
        {
            return Err(format!(
                "item id {} conflicts with another item document",
                document.item.id
            ));
        }
    }

    let catalog = ItemValidationCatalog {
        item_ids: final_items.keys().copied().collect(),
        effect_ids,
    };

    for document in &documents {
        let issues = validate_item(&document.item, &catalog, false);

        if issues.iter().any(|issue| issue.severity == "error") {
            return Err(format!(
                "item {} has validation errors and cannot be saved",
                document.item.id
            ));
        }
    }

    let data_dir = item_data_dir()?;
    fs::create_dir_all(&data_dir)
        .map_err(|error| format!("failed to create item directory: {error}"))?;

    let mut saved_ids = Vec::new();
    let mut deleted_ids = Vec::new();

    for document in documents {
        let item = document.item;
        let target_path = item_file_path(item.id)?;
        let json = serde_json::to_string_pretty(&item)
            .map_err(|error| format!("failed to serialize item {}: {error}", item.id))?;
        fs::write(&target_path, json)
            .map_err(|error| format!("failed to write {}: {error}", target_path.display()))?;

        if let Some(original_id) = document.original_id {
            if original_id != item.id {
                let old_path = item_file_path(original_id)?;
                if old_path.exists() {
                    fs::remove_file(&old_path).map_err(|error| {
                        format!("failed to remove renamed item {}: {error}", original_id)
                    })?;
                    deleted_ids.push(original_id);
                }
            }
        }

        saved_ids.push(item.id);
    }

    Ok(SaveItemsResult {
        saved_ids,
        deleted_ids,
    })
}

#[tauri::command]
fn delete_item_document(item_id: u32) -> Result<DeleteItemResult, String> {
    let path = item_file_path(item_id)?;
    if path.exists() {
        fs::remove_file(&path)
            .map_err(|error| format!("failed to delete {}: {error}", path.display()))?;
    }

    Ok(DeleteItemResult { deleted_id: item_id })
}

#[tauri::command]
fn load_dialogue_workspace() -> Result<DialogueWorkspacePayload, String> {
    let documents = load_dialogue_documents()?;
    let bootstrap = editor_bootstrap()?;
    let data_directory = to_forward_slashes(&dialogue_data_dir()?);
    let dialog_count = documents.len();
    let catalogs = collect_dialogue_catalogs(&documents);

    Ok(DialogueWorkspacePayload {
        bootstrap,
        data_directory,
        dialog_count,
        catalogs,
        documents,
    })
}

#[tauri::command]
fn validate_dialogue_document(dialog: DialogueData) -> Vec<ValidationIssue> {
    validate_dialogue(&dialog)
}

#[tauri::command]
fn save_dialogue_documents(
    documents: Vec<SaveDialogueDocumentInput>,
) -> Result<SaveDialoguesResult, String> {
    if documents.is_empty() {
        return Ok(SaveDialoguesResult {
            saved_ids: Vec::new(),
            deleted_ids: Vec::new(),
        });
    }

    let mut seen_ids = HashSet::new();
    for document in &documents {
        let dialog_id = document.dialog.dialog_id.trim();
        if dialog_id.is_empty() {
            return Err("dialog_id cannot be empty".to_string());
        }
        if !seen_ids.insert(dialog_id.to_string()) {
            return Err(format!("duplicate dialog id in save batch: {dialog_id}"));
        }

        let issues = validate_dialogue(&document.dialog);
        if issues.iter().any(|issue| issue.severity == "error") {
            return Err(format!(
                "dialog {} has validation errors and cannot be saved",
                document.dialog.dialog_id
            ));
        }
    }

    let data_dir = dialogue_data_dir()?;
    fs::create_dir_all(&data_dir)
        .map_err(|error| format!("failed to create dialogue directory: {error}"))?;

    let mut saved_ids = Vec::new();
    let mut deleted_ids = Vec::new();

    for document in documents {
        let dialog = document.dialog;
        let target_path = dialogue_file_path(&dialog.dialog_id)?;
        let json = serde_json::to_string_pretty(&dialog)
            .map_err(|error| format!("failed to serialize dialog {}: {error}", dialog.dialog_id))?;
        fs::write(&target_path, json)
            .map_err(|error| format!("failed to write {}: {error}", target_path.display()))?;

        if let Some(original_id) = document.original_id {
            if original_id != dialog.dialog_id {
                let old_path = dialogue_file_path(&original_id)?;
                if old_path.exists() {
                    fs::remove_file(&old_path).map_err(|error| {
                        format!("failed to remove renamed dialog {}: {error}", original_id)
                    })?;
                    deleted_ids.push(original_id);
                }
            }
        }

        saved_ids.push(dialog.dialog_id);
    }

    Ok(SaveDialoguesResult {
        saved_ids,
        deleted_ids,
    })
}

#[tauri::command]
fn delete_dialogue_document(dialog_id: String) -> Result<DeleteDialogueResult, String> {
    let path = dialogue_file_path(&dialog_id)?;
    if path.exists() {
        fs::remove_file(&path)
            .map_err(|error| format!("failed to delete {}: {error}", path.display()))?;
    }

    Ok(DeleteDialogueResult { deleted_id: dialog_id })
}

#[tauri::command]
fn load_map_workspace() -> Result<MapWorkspacePayload, String> {
    let item_documents = load_item_documents()?;
    let character_ids = load_character_ids()?;
    let validation_catalog = map_validation_catalog(&item_documents, &character_ids);
    let documents = load_map_documents(&validation_catalog)?;
    let bootstrap = editor_bootstrap()?;
    let data_directory = to_forward_slashes(&map_data_dir()?);
    let map_count = documents.len();
    let catalogs = collect_map_catalogs(&documents, &validation_catalog);

    Ok(MapWorkspacePayload {
        bootstrap,
        data_directory,
        map_count,
        catalogs,
        documents,
    })
}

#[tauri::command]
fn validate_map_document(map: MapDefinition) -> Result<Vec<ValidationIssue>, String> {
    let item_documents = load_item_documents()?;
    let character_ids = load_character_ids()?;
    let validation_catalog = map_validation_catalog(&item_documents, &character_ids);
    Ok(validate_map(&map, &validation_catalog))
}

#[tauri::command]
fn save_map_documents(documents: Vec<SaveMapDocumentInput>) -> Result<SaveMapsResult, String> {
    if documents.is_empty() {
        return Ok(SaveMapsResult {
            saved_ids: Vec::new(),
            deleted_ids: Vec::new(),
        });
    }

    let item_documents = load_item_documents()?;
    let character_ids = load_character_ids()?;
    let validation_catalog = map_validation_catalog(&item_documents, &character_ids);
    let mut seen_ids = HashSet::new();

    for document in &documents {
        let map_id = document.map.id.as_str().trim();
        if map_id.is_empty() {
            return Err("map id cannot be empty".to_string());
        }
        if !seen_ids.insert(map_id.to_string()) {
            return Err(format!("duplicate map id in save batch: {map_id}"));
        }

        let issues = validate_map(&document.map, &validation_catalog);
        if issues.iter().any(|issue| issue.severity == "error") {
            return Err(format!("map {} has validation errors and cannot be saved", map_id));
        }
    }

    let data_dir = map_data_dir()?;
    fs::create_dir_all(&data_dir)
        .map_err(|error| format!("failed to create map directory: {error}"))?;

    let mut saved_ids = Vec::new();
    let mut deleted_ids = Vec::new();

    for document in documents {
        let map = document.map;
        let target_path = map_file_path(map.id.as_str())?;
        let json = serde_json::to_string_pretty(&map)
            .map_err(|error| format!("failed to serialize map {}: {error}", map.id))?;
        fs::write(&target_path, json)
            .map_err(|error| format!("failed to write {}: {error}", target_path.display()))?;

        if let Some(original_id) = document.original_id {
            if original_id != map.id.as_str() {
                let old_path = map_file_path(&original_id)?;
                if old_path.exists() {
                    fs::remove_file(&old_path).map_err(|error| {
                        format!("failed to remove renamed map {}: {error}", original_id)
                    })?;
                    deleted_ids.push(original_id);
                }
            }
        }

        saved_ids.push(map.id.0);
    }

    Ok(SaveMapsResult {
        saved_ids,
        deleted_ids,
    })
}

#[tauri::command]
fn delete_map_document(map_id: String) -> Result<DeleteMapResult, String> {
    let path = map_file_path(&map_id)?;
    if path.exists() {
        fs::remove_file(&path)
            .map_err(|error| format!("failed to delete {}: {error}", path.display()))?;
    }

    Ok(DeleteMapResult { deleted_id: map_id })
}

pub(crate) fn editor_bootstrap() -> Result<EditorBootstrap, String> {
    let workspace_root = repo_root()?;
    let shared_rust_path = workspace_root.join("rust");

    Ok(EditorBootstrap {
        app_name: "CDC Content Editor",
        workspace_root: to_forward_slashes(&workspace_root),
        shared_rust_path: to_forward_slashes(&shared_rust_path),
        active_stage: "Phase 1: Rust Foundation",
        stages: vec![
            MigrationStage {
                id: "phase-1",
                title: "Phase 1: Rust Foundation",
                description:
                    "Build shared data models, protocol definitions, and validation before large-scale runtime rewrites.",
            },
            MigrationStage {
                id: "phase-2",
                title: "Phase 2: Bevy Logic Service",
                description:
                    "Introduce the Bevy logic service and move suitable gameplay systems behind IPC or TCP.",
            },
            MigrationStage {
                id: "phase-3",
                title: "Phase 3: Editor Independence",
                description:
                    "Migrate content workflows from the Godot plugin into this standalone editor incrementally.",
            },
        ],
        editor_domains: vec![
            "Items and recipes",
            "Dialogue and quest flows",
            "Multi-layer map authoring",
            "Import, export, and validation tools",
        ],
    })
}

fn load_item_documents() -> Result<Vec<ItemDocumentPayload>, String> {
    let effect_ids = load_effect_catalog()?.ids();
    load_item_documents_with_effects(&effect_ids)
}

fn load_item_documents_with_effects(
    effect_ids: &BTreeSet<String>,
) -> Result<Vec<ItemDocumentPayload>, String> {
    let parsed_documents = load_item_document_sources()?;
    let catalog = item_validation_catalog_from_documents(&parsed_documents, effect_ids);
    let mut id_counts: BTreeMap<u32, usize> = BTreeMap::new();
    for document in &parsed_documents {
        *id_counts.entry(document.item.id).or_default() += 1;
    }

    let mut documents = parsed_documents
        .into_iter()
        .map(|document| {
            let duplicate_id = id_counts.get(&document.item.id).copied().unwrap_or_default() > 1;
            let validation = validate_item(&document.item, &catalog, duplicate_id);

            ItemDocumentPayload {
                document_key: document.file_name.clone(),
                original_id: document.item.id,
                file_name: document.file_name,
                relative_path: document.relative_path,
                item: document.item,
                validation,
            }
        })
        .collect::<Vec<_>>();

    documents.sort_by(|left, right| {
        left.item
            .id
            .cmp(&right.item.id)
            .then_with(|| left.file_name.cmp(&right.file_name))
    });
    Ok(documents)
}

fn load_item_document_sources() -> Result<Vec<ParsedItemDocument>, String> {
    let data_dir = item_data_dir()?;
    if !data_dir.exists() {
        return Ok(Vec::new());
    }

    let mut entries = fs::read_dir(&data_dir)
        .map_err(|error| format!("failed to read {}: {error}", data_dir.display()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("failed to enumerate item directory: {error}"))?;

    entries.sort_by_key(|entry| entry.file_name());

    let mut documents = Vec::new();
    for entry in entries {
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
        let item: ItemDefinition = serde_json::from_str(&raw)
            .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
        let file_name = path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string();
        let relative_path = relative_to_repo(&path)?;

        documents.push(ParsedItemDocument {
            file_name,
            relative_path,
            item,
        });
    }

    Ok(documents)
}

fn load_dialogue_documents() -> Result<Vec<DialogueDocumentPayload>, String> {
    let data_dir = dialogue_data_dir()?;
    if !data_dir.exists() {
        return Ok(Vec::new());
    }

    let mut entries = fs::read_dir(&data_dir)
        .map_err(|error| format!("failed to read {}: {error}", data_dir.display()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("failed to enumerate dialogue directory: {error}"))?;

    entries.sort_by_key(|entry| entry.file_name());

    let mut documents = Vec::new();
    for entry in entries {
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
        let dialog: DialogueData = serde_json::from_str(&raw)
            .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
        let validation = validate_dialogue(&dialog);
        let file_name = path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string();
        let relative_path = relative_to_repo(&path)?;
        let document_key = if dialog.dialog_id.is_empty() {
            file_name.clone()
        } else {
            dialog.dialog_id.clone()
        };

        documents.push(DialogueDocumentPayload {
            document_key,
            original_id: dialog.dialog_id.clone(),
            file_name,
            relative_path,
            dialog,
            validation,
        });
    }

    documents.sort_by(|left, right| left.document_key.cmp(&right.document_key));
    Ok(documents)
}

fn load_map_documents(
    validation_catalog: &MapValidationCatalog,
) -> Result<Vec<MapDocumentPayload>, String> {
    let data_dir = map_data_dir()?;
    if !data_dir.exists() {
        return Ok(Vec::new());
    }

    let mut entries = fs::read_dir(&data_dir)
        .map_err(|error| format!("failed to read {}: {error}", data_dir.display()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("failed to enumerate map directory: {error}"))?;

    entries.sort_by_key(|entry| entry.file_name());

    let mut documents = Vec::new();
    for entry in entries {
        let path = entry.path();
        if path.extension().and_then(|ext| ext.to_str()) != Some("json") {
            continue;
        }

        let raw = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
        let map: MapDefinition = serde_json::from_str(&raw)
            .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
        let validation = validate_map(&map, validation_catalog);
        let file_name = path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or_default()
            .to_string();
        let relative_path = relative_to_repo(&path)?;
        let document_key = if map.id.as_str().trim().is_empty() {
            file_name.clone()
        } else {
            map.id.as_str().to_string()
        };

        documents.push(MapDocumentPayload {
            document_key,
            original_id: map.id.as_str().to_string(),
            file_name,
            relative_path,
            map,
            validation,
        });
    }

    documents.sort_by(|left, right| left.document_key.cmp(&right.document_key));
    Ok(documents)
}

fn collect_catalogs(
    documents: &[ItemDocumentPayload],
    effect_library: &game_data::EffectLibrary,
) -> ItemCatalogs {
    let mut fragment_kinds = seeded_set(DEFAULT_FRAGMENT_KINDS);
    let mut equipment_slots = seeded_set(DEFAULT_EQUIPMENT_SLOTS);
    let mut known_subtypes = seeded_set(DEFAULT_KNOWN_SUBTYPES);

    for document in documents {
        for fragment in &document.item.fragments {
            fragment_kinds.insert(fragment.kind().to_string());

            match fragment {
                ItemFragment::Equip { slots, .. } => {
                    for slot in slots {
                        if !slot.trim().is_empty() {
                            equipment_slots.insert(slot.clone());
                        }
                    }
                }
                ItemFragment::Weapon { subtype, .. } | ItemFragment::Usable { subtype, .. } => {
                    if !subtype.trim().is_empty() {
                        known_subtypes.insert(subtype.clone());
                    }
                }
                ItemFragment::Economy { .. }
                | ItemFragment::Stacking { .. }
                | ItemFragment::Durability { .. }
                | ItemFragment::AttributeModifiers { .. }
                | ItemFragment::Crafting { .. }
                | ItemFragment::PassiveEffects { .. } => {}
            }
        }
    }

    let effect_ids = effect_library.ids();
    let effect_previews = build_effect_previews(effect_library);
    let item_previews = build_item_previews(documents);
    let (mut effect_used_by, mut item_used_by) = build_reference_indexes(documents);
    sort_usage_map(&mut effect_used_by);
    sort_usage_map(&mut item_used_by);

    ItemCatalogs {
        fragment_kinds: fragment_kinds.into_iter().collect(),
        effect_ids: effect_ids.into_iter().collect(),
        effect_entries: effect_library
            .iter()
            .map(|(id, definition)| CatalogEntry {
                value: id.clone(),
                label: if definition.name.trim().is_empty() {
                    id.clone()
                } else {
                    format!("{id} · {}", definition.name)
                },
            })
            .collect(),
        effect_previews,
        item_previews,
        effect_used_by,
        item_used_by,
        equipment_slots: equipment_slots.into_iter().collect(),
        known_subtypes: known_subtypes.into_iter().collect(),
        item_ids: documents
            .iter()
            .map(|document| document.item.id.to_string())
            .collect(),
    }
}

fn build_effect_previews(effect_library: &game_data::EffectLibrary) -> Vec<EffectReferencePreview> {
    effect_library
        .iter()
        .map(|(id, effect)| EffectReferencePreview {
            id: id.clone(),
            name: effect.name.clone(),
            description: effect.description.clone(),
            category: effect.category.clone(),
            duration: effect.duration,
            stack_mode: effect.stack_mode.clone(),
            resource_deltas: effect
                .gameplay_effect
                .as_ref()
                .map(|value| value.resource_deltas.clone())
                .unwrap_or_default(),
        })
        .collect()
}

fn build_item_previews(documents: &[ItemDocumentPayload]) -> Vec<ItemReferencePreview> {
    let mut previews = documents
        .iter()
        .map(|document| {
            let item = &document.item;
            ItemReferencePreview {
                id: item.id.to_string(),
                name: item.name.clone(),
                value: item.value,
                weight: item.weight,
                derived_tags: derive_item_tags(item),
                key_fragments: summarize_item_fragments(item),
            }
        })
        .collect::<Vec<_>>();

    previews.sort_by(|left, right| {
        left.id
            .parse::<u32>()
            .unwrap_or_default()
            .cmp(&right.id.parse::<u32>().unwrap_or_default())
    });
    previews
}

fn derive_item_tags(item: &ItemDefinition) -> Vec<String> {
    let has_weapon = item.fragments.iter().any(|fragment| matches!(fragment, ItemFragment::Weapon { .. }));
    let equip_slots = item.fragments.iter().find_map(|fragment| {
        if let ItemFragment::Equip { slots, .. } = fragment {
            Some(slots)
        } else {
            None
        }
    });
    let has_usable = item.fragments.iter().any(|fragment| matches!(fragment, ItemFragment::Usable { .. }));
    let has_crafting = item.fragments.iter().any(|fragment| matches!(fragment, ItemFragment::Crafting { .. }));
    let has_stacking = item.fragments.iter().any(|fragment| matches!(fragment, ItemFragment::Stacking { .. }));

    let mut tags = Vec::new();
    if has_weapon {
        tags.push("weapon".to_string());
    }

    if let Some(slots) = equip_slots {
        if !has_weapon
            && slots
                .iter()
                .any(|slot| matches!(slot.as_str(), "head" | "body" | "hands" | "legs" | "feet" | "back"))
        {
            tags.push("armor".to_string());
        }
        if slots
            .iter()
            .any(|slot| matches!(slot.as_str(), "accessory" | "accessory_1" | "accessory_2"))
        {
            tags.push("accessory".to_string());
        }
    }

    if has_usable {
        tags.push("usable".to_string());
    }
    if !has_weapon && !has_usable && equip_slots.is_none() && (has_crafting || has_stacking) {
        tags.push("material_or_misc".to_string());
    }
    if tags.is_empty() {
        tags.push("material_or_misc".to_string());
    }
    tags
}

fn summarize_item_fragments(item: &ItemDefinition) -> Vec<String> {
    let mut summaries = Vec::new();
    for fragment in &item.fragments {
        let summary = match fragment {
            ItemFragment::Economy { rarity } => format!("economy: {rarity}"),
            ItemFragment::Stacking {
                stackable,
                max_stack,
            } => {
                if *stackable {
                    format!("stacking: x{max_stack}")
                } else {
                    "stacking: single".to_string()
                }
            }
            ItemFragment::Equip {
                slots,
                level_requirement,
                ..
            } => format!("equip: {} slots, lvl {}", slots.len(), level_requirement),
            ItemFragment::Durability {
                durability,
                max_durability,
                ..
            } => format!("durability: {durability}/{max_durability}"),
            ItemFragment::AttributeModifiers { attributes } => {
                format!("attributes: {} entries", attributes.len())
            }
            ItemFragment::Weapon {
                subtype,
                damage,
                on_hit_effect_ids,
                ..
            } => format!("weapon: {subtype}, dmg {damage}, {} hit fx", on_hit_effect_ids.len()),
            ItemFragment::Usable {
                subtype,
                effect_ids,
                ..
            } => format!("usable: {subtype}, {} effects", effect_ids.len()),
            ItemFragment::Crafting {
                crafting_recipe,
                deconstruct_yield,
            } => format!(
                "crafting: {} mats, {} yields",
                crafting_recipe
                    .as_ref()
                    .map(|recipe| recipe.materials.len())
                    .unwrap_or_default(),
                deconstruct_yield.len()
            ),
            ItemFragment::PassiveEffects { effect_ids } => {
                format!("passive_effects: {} effects", effect_ids.len())
            }
        };
        summaries.push(summary);
    }
    summaries
}

fn build_reference_indexes(
    documents: &[ItemDocumentPayload],
) -> (
    BTreeMap<String, Vec<ReferenceUsageEntry>>,
    BTreeMap<String, Vec<ReferenceUsageEntry>>,
) {
    let mut effect_used_by: BTreeMap<String, Vec<ReferenceUsageEntry>> = BTreeMap::new();
    let mut item_used_by: BTreeMap<String, Vec<ReferenceUsageEntry>> = BTreeMap::new();

    for document in documents {
        let item = &document.item;
        let source_name = if item.name.trim().is_empty() {
            format!("Item {}", item.id)
        } else {
            item.name.clone()
        };

        for fragment in &item.fragments {
            match fragment {
                ItemFragment::Equip {
                    equip_effect_ids,
                    unequip_effect_ids,
                    ..
                } => {
                    for effect_id in equip_effect_ids {
                        if effect_id.trim().is_empty() {
                            continue;
                        }
                        push_usage(
                            &mut effect_used_by,
                            effect_id,
                            ReferenceUsageEntry {
                                source_item_id: item.id,
                                source_item_name: source_name.clone(),
                                fragment_kind: "equip".to_string(),
                                path: "fragments.equip.equip_effect_ids".to_string(),
                                note: "equip effect".to_string(),
                            },
                        );
                    }
                    for effect_id in unequip_effect_ids {
                        if effect_id.trim().is_empty() {
                            continue;
                        }
                        push_usage(
                            &mut effect_used_by,
                            effect_id,
                            ReferenceUsageEntry {
                                source_item_id: item.id,
                                source_item_name: source_name.clone(),
                                fragment_kind: "equip".to_string(),
                                path: "fragments.equip.unequip_effect_ids".to_string(),
                                note: "unequip effect".to_string(),
                            },
                        );
                    }
                }
                ItemFragment::Durability {
                    repair_materials, ..
                } => {
                    for entry in repair_materials {
                        push_usage(
                            &mut item_used_by,
                            &entry.item_id.to_string(),
                            ReferenceUsageEntry {
                                source_item_id: item.id,
                                source_item_name: source_name.clone(),
                                fragment_kind: "durability".to_string(),
                                path: "fragments.durability.repair_materials".to_string(),
                                note: format!("repair material x{}", entry.count),
                            },
                        );
                    }
                }
                ItemFragment::Weapon {
                    ammo_type,
                    on_hit_effect_ids,
                    ..
                } => {
                    if let Some(ammo_type) = ammo_type {
                        push_usage(
                            &mut item_used_by,
                            &ammo_type.to_string(),
                            ReferenceUsageEntry {
                                source_item_id: item.id,
                                source_item_name: source_name.clone(),
                                fragment_kind: "weapon".to_string(),
                                path: "fragments.weapon.ammo_type".to_string(),
                                note: "weapon ammo type".to_string(),
                            },
                        );
                    }
                    for effect_id in on_hit_effect_ids {
                        if effect_id.trim().is_empty() {
                            continue;
                        }
                        push_usage(
                            &mut effect_used_by,
                            effect_id,
                            ReferenceUsageEntry {
                                source_item_id: item.id,
                                source_item_name: source_name.clone(),
                                fragment_kind: "weapon".to_string(),
                                path: "fragments.weapon.on_hit_effect_ids".to_string(),
                                note: "on-hit effect".to_string(),
                            },
                        );
                    }
                }
                ItemFragment::Usable { effect_ids, .. } => {
                    for effect_id in effect_ids {
                        if effect_id.trim().is_empty() {
                            continue;
                        }
                        push_usage(
                            &mut effect_used_by,
                            effect_id,
                            ReferenceUsageEntry {
                                source_item_id: item.id,
                                source_item_name: source_name.clone(),
                                fragment_kind: "usable".to_string(),
                                path: "fragments.usable.effect_ids".to_string(),
                                note: "usable effect".to_string(),
                            },
                        );
                    }
                }
                ItemFragment::Crafting {
                    crafting_recipe,
                    deconstruct_yield,
                } => {
                    if let Some(recipe) = crafting_recipe {
                        for entry in &recipe.materials {
                            push_usage(
                                &mut item_used_by,
                                &entry.item_id.to_string(),
                                ReferenceUsageEntry {
                                    source_item_id: item.id,
                                    source_item_name: source_name.clone(),
                                    fragment_kind: "crafting".to_string(),
                                    path: "fragments.crafting.crafting_recipe.materials".to_string(),
                                    note: format!("crafting material x{}", entry.count),
                                },
                            );
                        }
                    }
                    for entry in deconstruct_yield {
                        push_usage(
                            &mut item_used_by,
                            &entry.item_id.to_string(),
                            ReferenceUsageEntry {
                                source_item_id: item.id,
                                source_item_name: source_name.clone(),
                                fragment_kind: "crafting".to_string(),
                                path: "fragments.crafting.deconstruct_yield".to_string(),
                                note: format!("deconstruct yield x{}", entry.count),
                            },
                        );
                    }
                }
                ItemFragment::PassiveEffects { effect_ids } => {
                    for effect_id in effect_ids {
                        if effect_id.trim().is_empty() {
                            continue;
                        }
                        push_usage(
                            &mut effect_used_by,
                            effect_id,
                            ReferenceUsageEntry {
                                source_item_id: item.id,
                                source_item_name: source_name.clone(),
                                fragment_kind: "passive_effects".to_string(),
                                path: "fragments.passive_effects.effect_ids".to_string(),
                                note: "passive effect".to_string(),
                            },
                        );
                    }
                }
                ItemFragment::Economy { .. }
                | ItemFragment::Stacking { .. }
                | ItemFragment::AttributeModifiers { .. } => {}
            }
        }
    }

    (effect_used_by, item_used_by)
}

fn push_usage(
    map: &mut BTreeMap<String, Vec<ReferenceUsageEntry>>,
    key: &str,
    entry: ReferenceUsageEntry,
) {
    map.entry(key.to_string()).or_default().push(entry);
}

fn sort_usage_map(map: &mut BTreeMap<String, Vec<ReferenceUsageEntry>>) {
    for entries in map.values_mut() {
        entries.sort_by(|left, right| {
            left.source_item_id
                .cmp(&right.source_item_id)
                .then_with(|| left.fragment_kind.cmp(&right.fragment_kind))
                .then_with(|| left.path.cmp(&right.path))
                .then_with(|| left.note.cmp(&right.note))
        });
    }
}

fn collect_dialogue_catalogs(documents: &[DialogueDocumentPayload]) -> DialogueCatalogs {
    let mut node_types = seeded_set(DEFAULT_DIALOG_NODE_TYPES);

    for document in documents {
        for node in &document.dialog.nodes {
            if !node.node_type.trim().is_empty() {
                node_types.insert(node.node_type.clone());
            }
        }
    }

    DialogueCatalogs {
        node_types: node_types.into_iter().collect(),
    }
}

fn collect_map_catalogs(
    documents: &[MapDocumentPayload],
    validation_catalog: &MapValidationCatalog,
) -> MapCatalogs {
    let mut building_prefabs = seeded_set(DEFAULT_BUILDING_PREFABS);
    let mut interactive_kinds = seeded_set(DEFAULT_INTERACTION_KINDS);

    for document in documents {
        for object in &document.map.objects {
            if let Some(building) = object.props.building.as_ref() {
                if !building.prefab_id.trim().is_empty() {
                    building_prefabs.insert(building.prefab_id.clone());
                }
            }
            if let Some(interactive) = object.props.interactive.as_ref() {
                if !interactive.interaction_kind.trim().is_empty() {
                    interactive_kinds.insert(interactive.interaction_kind.clone());
                }
            }
        }
    }

    MapCatalogs {
        item_ids: validation_catalog.item_ids.iter().cloned().collect(),
        character_ids: validation_catalog.character_ids.iter().cloned().collect(),
        building_prefabs: building_prefabs.into_iter().collect(),
        interactive_kinds: interactive_kinds.into_iter().collect(),
    }
}

fn item_validation_catalog_from_documents(
    documents: &[ParsedItemDocument],
    effect_ids: &BTreeSet<String>,
) -> ItemValidationCatalog {
    ItemValidationCatalog {
        item_ids: documents.iter().map(|document| document.item.id).collect(),
        effect_ids: effect_ids.clone(),
    }
}

fn validate_item(
    item: &ItemDefinition,
    catalog: &ItemValidationCatalog,
    duplicate_id: bool,
) -> Vec<ValidationIssue> {
    let mut issues = Vec::new();

    if duplicate_id {
        issues.push(item_error(
            "id",
            "Item id duplicates another item file.",
            "id",
        ));
    }

    if let Err(error) = validate_item_definition(item, Some(catalog)) {
        issues.push(item_validation_issue(item, error));
    }

    issues
}

fn item_validation_issue(
    item: &ItemDefinition,
    validation_error: ItemDefinitionValidationError,
) -> ValidationIssue {
    match validation_error {
        ItemDefinitionValidationError::InvalidId => item_error("id", "Item id must be a positive integer.", "id"),
        ItemDefinitionValidationError::MissingName { .. } => item_error("name", "Item name cannot be empty.", "name"),
        ItemDefinitionValidationError::MissingFragments { .. } => {
            item_error("fragments", "Item must define at least one fragment.", "fragments")
        }
        ItemDefinitionValidationError::NegativeWeight { .. } => {
            item_error("weight", "Item weight cannot be negative.", "weight")
        }
        ItemDefinitionValidationError::NegativeValue { .. } => {
            item_error("value", "Item value cannot be negative.", "value")
        }
        ItemDefinitionValidationError::DuplicateFragmentKind { kind, .. } => item_error(
            "fragments",
            format!("Fragment kind {kind} cannot appear more than once."),
            &format!("fragments.{kind}"),
        ),
        ItemDefinitionValidationError::EquipWithoutSlots { .. } => {
            item_error(
                "equip.slots",
                "Equip fragment must define at least one slot.",
                "fragments.equip.slots",
            )
        }
        ItemDefinitionValidationError::WeaponWithoutEquip { .. } => item_error(
            "weapon",
            "Weapon fragment requires an equip fragment on the same item.",
            "fragments.weapon",
        ),
        ItemDefinitionValidationError::InvalidMaxStack { .. } => {
            item_error(
                "stacking.max_stack",
                "Stacking fragment must use max_stack >= 1.",
                "fragments.stacking.max_stack",
            )
        }
        ItemDefinitionValidationError::InvalidNonStackableMaxStack { .. } => item_error(
            "stacking.max_stack",
            "Non-stackable items must use a max_stack of 1.",
            "fragments.stacking.max_stack",
        ),
        ItemDefinitionValidationError::DurabilityExceedsMax { .. } => item_error(
            "durability",
            "Durability cannot exceed max durability unless both use -1.",
            "fragments.durability",
        ),
        ItemDefinitionValidationError::UnknownEffectId {
            fragment,
            effect_id,
            ..
        } => {
            let path = resolve_effect_path(item, &fragment, &effect_id);
            item_error(
                format!("{fragment}.effect_ids"),
                format!("Unknown effect id: {effect_id}."),
                path.as_str(),
            )
        }
        ItemDefinitionValidationError::UnknownItemId {
            fragment,
            referenced_item_id,
            ..
        } => {
            let path = resolve_item_reference_path(item, &fragment, referenced_item_id);
            item_error(
                format!("{fragment}.item_ids"),
                format!("Unknown item id reference: {referenced_item_id}."),
                path.as_str(),
            )
        }
        ItemDefinitionValidationError::EmptyEquipSlot { .. } => {
            item_error(
                "equip.slots",
                "Equip slots cannot contain blank values.",
                "fragments.equip.slots",
            )
        }
        ItemDefinitionValidationError::EmptyEffectId { fragment, .. } => {
            let path = resolve_effect_path(item, &fragment, "");
            item_error(
                format!("{fragment}.effect_ids"),
                "Effect id lists cannot contain blank values.",
                path.as_str(),
            )
        }
        ItemDefinitionValidationError::InvalidAmountEntry { fragment, .. } => {
            let path = resolve_invalid_amount_path(item, &fragment);
            item_error(
                format!("{fragment}.amounts"),
                "Item amount entries must reference a valid item id and a positive count.",
                path.as_str(),
            )
        }
    }
}

fn resolve_effect_path(item: &ItemDefinition, fragment: &str, effect_id: &str) -> String {
    let normalized = effect_id.trim();
    for item_fragment in &item.fragments {
        match item_fragment {
            ItemFragment::Equip {
                equip_effect_ids,
                unequip_effect_ids,
                ..
            } if fragment == "equip" => {
                if normalized.is_empty()
                    || equip_effect_ids.iter().any(|value| value.trim() == normalized)
                {
                    return "fragments.equip.equip_effect_ids".to_string();
                }
                if unequip_effect_ids.iter().any(|value| value.trim() == normalized) {
                    return "fragments.equip.unequip_effect_ids".to_string();
                }
                return "fragments.equip.equip_effect_ids".to_string();
            }
            ItemFragment::Weapon {
                on_hit_effect_ids, ..
            } if fragment == "weapon" => {
                if normalized.is_empty()
                    || on_hit_effect_ids
                        .iter()
                        .any(|value| value.trim() == normalized)
                {
                    return "fragments.weapon.on_hit_effect_ids".to_string();
                }
            }
            ItemFragment::Usable { effect_ids, .. } if fragment == "usable" => {
                if normalized.is_empty()
                    || effect_ids.iter().any(|value| value.trim() == normalized)
                {
                    return "fragments.usable.effect_ids".to_string();
                }
            }
            ItemFragment::PassiveEffects { effect_ids } if fragment == "passive_effects" => {
                if normalized.is_empty()
                    || effect_ids.iter().any(|value| value.trim() == normalized)
                {
                    return "fragments.passive_effects.effect_ids".to_string();
                }
            }
            _ => {}
        }
    }

    format!("fragments.{fragment}.effect_ids")
}

fn resolve_item_reference_path(
    item: &ItemDefinition,
    fragment: &str,
    referenced_item_id: u32,
) -> String {
    for item_fragment in &item.fragments {
        match item_fragment {
            ItemFragment::Weapon { ammo_type, .. } if fragment == "weapon" => {
                if ammo_type == &Some(referenced_item_id) {
                    return "fragments.weapon.ammo_type".to_string();
                }
            }
            ItemFragment::Durability {
                repair_materials, ..
            } if fragment == "durability" => {
                if repair_materials
                    .iter()
                    .any(|entry| entry.item_id == referenced_item_id)
                {
                    return "fragments.durability.repair_materials".to_string();
                }
            }
            ItemFragment::Crafting {
                crafting_recipe,
                deconstruct_yield,
            } if fragment == "crafting" => {
                if crafting_recipe
                    .as_ref()
                    .map(|recipe| {
                        recipe
                            .materials
                            .iter()
                            .any(|entry| entry.item_id == referenced_item_id)
                    })
                    .unwrap_or(false)
                {
                    return "fragments.crafting.crafting_recipe.materials".to_string();
                }
                if deconstruct_yield
                    .iter()
                    .any(|entry| entry.item_id == referenced_item_id)
                {
                    return "fragments.crafting.deconstruct_yield".to_string();
                }
            }
            _ => {}
        }
    }

    format!("fragments.{fragment}.item_ids")
}

fn resolve_invalid_amount_path(item: &ItemDefinition, fragment: &str) -> String {
    for item_fragment in &item.fragments {
        match item_fragment {
            ItemFragment::Durability {
                repair_materials, ..
            } if fragment == "durability" => {
                if repair_materials
                    .iter()
                    .any(|entry| entry.item_id == 0 || entry.count < 1)
                {
                    return "fragments.durability.repair_materials".to_string();
                }
            }
            ItemFragment::Crafting {
                crafting_recipe,
                deconstruct_yield,
            } if fragment == "crafting" => {
                if crafting_recipe
                    .as_ref()
                    .map(|recipe| {
                        recipe
                            .materials
                            .iter()
                            .any(|entry| entry.item_id == 0 || entry.count < 1)
                    })
                    .unwrap_or(false)
                {
                    return "fragments.crafting.crafting_recipe.materials".to_string();
                }
                if deconstruct_yield
                    .iter()
                    .any(|entry| entry.item_id == 0 || entry.count < 1)
                {
                    return "fragments.crafting.deconstruct_yield".to_string();
                }
            }
            _ => {}
        }
    }
    format!("fragments.{fragment}.amounts")
}

pub(crate) fn validate_dialogue(dialog: &DialogueData) -> Vec<ValidationIssue> {
    let mut issues = Vec::new();

    if dialog.dialog_id.trim().is_empty() {
        issues.push(document_error("dialogId", "Dialog id cannot be empty."));
    }
    if dialog.nodes.is_empty() {
        issues.push(document_error("nodes", "Dialog must contain at least one node."));
        return issues;
    }

    let normalized_connections = merge_dialogue_connections(dialog);
    let mut node_ids = HashSet::new();
    let mut node_types = BTreeMap::new();
    let mut start_count = 0;
    for node in &dialog.nodes {
        if node.id.trim().is_empty() {
            issues.push(document_error("nodes", "Every node must have an id."));
            continue;
        }
        if !node_ids.insert(node.id.clone()) {
            issues.push(document_error(
                "nodes",
                format!("Duplicate node id detected: {}", node.id),
            ));
        }
        node_types.insert(node.id.clone(), node.node_type.clone());
        if node.is_start || node.id == "start" {
            start_count += 1;
        }
        if node.node_type.trim().is_empty() {
            issues.push(node_error(
                &node.id,
                "type",
                format!("Node {} is missing a type.", node.id),
            ));
        }
        if node.node_type == "dialog" && node.text.trim().is_empty() {
            issues.push(node_error(
                &node.id,
                "text",
                "Dialog nodes must include text.".to_string(),
            ));
        }
        if node.node_type == "choice" && node.options.is_empty() {
            issues.push(node_error(
                &node.id,
                "options",
                "Choice nodes must define at least one option.".to_string(),
            ));
        }
        if node.node_type == "end" {
            let outgoing = outgoing_connections_for(&normalized_connections, &node.id);
            if !outgoing.is_empty() {
                issues.push(node_error(
                    &node.id,
                    "connections",
                    "End nodes cannot have outgoing edges.".to_string(),
                ));
            }
        }
    }

    if start_count == 0 {
        issues.push(document_error("nodes", "Dialog requires one start node."));
    } else if start_count > 1 {
        issues.push(document_error("nodes", "Dialog can only have one start node."));
    }

    for connection in &normalized_connections {
        if connection.from.trim().is_empty() || connection.to.trim().is_empty() {
            issues.push(edge_error(
                connection_edge_key(connection),
                "connections",
                "Every connection must define both from and to node ids.",
            ));
            continue;
        }
        if !node_ids.contains(&connection.from) {
            issues.push(edge_error(
                connection_edge_key(connection),
                "connections",
                format!("Connection references missing source node {}.", connection.from),
            ));
        }
        if !node_ids.contains(&connection.to) {
            issues.push(edge_error(
                connection_edge_key(connection),
                "connections",
                format!("Connection references missing target node {}.", connection.to),
            ));
        }
    }

    for node in &dialog.nodes {
        match node.node_type.as_str() {
            "dialog" | "action" => {
                if !node.next.trim().is_empty()
                    && !has_connection(
                        &normalized_connections,
                        &node_types,
                        &node.id,
                        "next",
                        &node.next,
                    )
                {
                    issues.push(node_error(
                        &node.id,
                        "next",
                        "The next field does not match the graph connections.".to_string(),
                    ));
                }
            }
            "choice" => {
                for (index, option) in node.options.iter().enumerate() {
                    if !option.next.trim().is_empty()
                        && !has_connection(
                            &normalized_connections,
                            &node_types,
                            &node.id,
                            &format!("option-{index}"),
                            &option.next,
                        )
                    {
                        issues.push(node_error(
                            &node.id,
                            &format!("options[{index}].next"),
                            format!(
                                "Choice option {} does not match the graph connection.",
                                index + 1
                            ),
                        ));
                    }
                }
            }
            "condition" => {
                for (handle, target) in [("true", &node.true_next), ("false", &node.false_next)] {
                    if !target.trim().is_empty()
                        && !has_connection(
                            &normalized_connections,
                            &node_types,
                            &node.id,
                            handle,
                            target,
                        )
                    {
                        issues.push(node_error(
                            &node.id,
                            handle,
                            format!("{handle} branch does not match the graph connection."),
                        ));
                    }
                }
            }
            _ => {}
        }
    }

    issues
}

fn validate_map(
    map: &MapDefinition,
    validation_catalog: &MapValidationCatalog,
) -> Vec<ValidationIssue> {
    match validate_map_definition(map, Some(validation_catalog)) {
        Ok(()) => Vec::new(),
        Err(error) => vec![document_error("map", error.to_string())],
    }
}

fn item_error(
    field: impl Into<String>,
    message: impl Into<String>,
    path: impl Into<String>,
) -> ValidationIssue {
    error_with_path(field, message, Some(path.into()))
}

fn error_with_path(
    field: impl Into<String>,
    message: impl Into<String>,
    path: Option<String>,
) -> ValidationIssue {
    ValidationIssue {
        severity: "error".to_string(),
        field: field.into(),
        message: message.into(),
        scope: None,
        node_id: None,
        edge_key: None,
        path,
    }
}

pub(crate) fn document_error(
    field: impl Into<String>,
    message: impl Into<String>,
) -> ValidationIssue {
    ValidationIssue {
        severity: "error".to_string(),
        field: field.into(),
        message: message.into(),
        scope: Some("document".to_string()),
        node_id: None,
        edge_key: None,
        path: None,
    }
}

pub(crate) fn node_error(
    node_id: &str,
    field: impl Into<String>,
    message: impl Into<String>,
) -> ValidationIssue {
    ValidationIssue {
        severity: "error".to_string(),
        field: field.into(),
        message: message.into(),
        scope: Some("node".to_string()),
        node_id: Some(node_id.to_string()),
        edge_key: None,
        path: None,
    }
}

pub(crate) fn edge_error(
    edge_key: String,
    field: impl Into<String>,
    message: impl Into<String>,
) -> ValidationIssue {
    ValidationIssue {
        severity: "error".to_string(),
        field: field.into(),
        message: message.into(),
        scope: Some("edge".to_string()),
        node_id: None,
        edge_key: Some(edge_key),
        path: None,
    }
}

fn outgoing_connections_for<'a>(
    connections: &'a [DialogueConnection],
    node_id: &str,
) -> Vec<&'a DialogueConnection> {
    connections
        .iter()
        .filter(|connection| connection.from == node_id)
        .collect()
}

fn merge_dialogue_connections(dialog: &DialogueData) -> Vec<DialogueConnection> {
    let mut keyed_connections: BTreeMap<String, DialogueConnection> = BTreeMap::new();

    for connection in &dialog.connections {
        keyed_connections.insert(connection_edge_key(connection), connection.clone());
    }

    for connection in derive_connections_from_nodes(dialog) {
        keyed_connections
            .entry(connection_edge_key(&connection))
            .or_insert(connection);
    }

    keyed_connections.into_values().collect()
}

fn derive_connections_from_nodes(dialog: &DialogueData) -> Vec<DialogueConnection> {
    let mut derived = Vec::new();

    for node in &dialog.nodes {
        match node.node_type.as_str() {
            "dialog" | "action" => {
                if !node.next.trim().is_empty() {
                    derived.push(DialogueConnection {
                        from: node.id.clone(),
                        from_port: 0,
                        to: node.next.clone(),
                        to_port: 0,
                        extra: BTreeMap::new(),
                    });
                }
            }
            "choice" => {
                for (index, option) in node.options.iter().enumerate() {
                    if option.next.trim().is_empty() {
                        continue;
                    }
                    derived.push(DialogueConnection {
                        from: node.id.clone(),
                        from_port: index as i32,
                        to: option.next.clone(),
                        to_port: 0,
                        extra: BTreeMap::new(),
                    });
                }
            }
            "condition" => {
                for (index, target) in [node.true_next.clone(), node.false_next.clone()]
                    .into_iter()
                    .enumerate()
                {
                    if target.trim().is_empty() {
                        continue;
                    }
                    derived.push(DialogueConnection {
                        from: node.id.clone(),
                        from_port: index as i32,
                        to: target,
                        to_port: 0,
                        extra: BTreeMap::new(),
                    });
                }
            }
            _ => {}
        }
    }

    derived
}

fn has_connection(
    connections: &[DialogueConnection],
    node_types: &BTreeMap<String, String>,
    source_id: &str,
    source_handle: &str,
    target_id: &str,
) -> bool {
    connections.iter().any(|connection| {
        let source_type = node_types
            .get(source_id)
            .map(|value| value.as_str())
            .unwrap_or("");
        connection.from == source_id
            && connection.to == target_id
            && port_to_handle(source_type, connection.from_port) == source_handle
    })
}

fn port_to_handle(node_type: &str, port: i32) -> String {
    match node_type {
        "choice" => format!("option-{port}"),
        "condition" => {
            if port == 0 {
                "true".to_string()
            } else {
                "false".to_string()
            }
        }
        _ => "next".to_string(),
    }
}

fn connection_edge_key(connection: &DialogueConnection) -> String {
    format!(
        "{}:{}->{}:{}",
        connection.from, connection.from_port, connection.to, connection.to_port
    )
}

fn seeded_set(values: &[&str]) -> BTreeSet<String> {
    values.iter().map(|value| (*value).to_string()).collect()
}

fn repo_root() -> Result<PathBuf, String> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("..");
    root.canonicalize()
        .map_err(|error| format!("failed to resolve repo root: {error}"))
}

fn item_data_dir() -> Result<PathBuf, String> {
    Ok(repo_root()?.join("data").join("items"))
}

fn effect_data_dir() -> Result<PathBuf, String> {
    Ok(repo_root()?.join("data").join("json").join("effects"))
}

fn character_data_dir() -> Result<PathBuf, String> {
    Ok(repo_root()?.join("data").join("characters"))
}

fn dialogue_data_dir() -> Result<PathBuf, String> {
    Ok(repo_root()?.join("data").join("dialogues"))
}

fn map_data_dir() -> Result<PathBuf, String> {
    Ok(repo_root()?.join("data").join("maps"))
}

fn item_file_path(item_id: u32) -> Result<PathBuf, String> {
    Ok(item_data_dir()?.join(format!("{item_id}.json")))
}

fn dialogue_file_path(dialog_id: &str) -> Result<PathBuf, String> {
    Ok(dialogue_data_dir()?.join(format!("{dialog_id}.json")))
}

fn map_file_path(map_id: &str) -> Result<PathBuf, String> {
    Ok(map_data_dir()?.join(format!("{map_id}.json")))
}

fn load_effect_catalog() -> Result<game_data::EffectLibrary, String> {
    let data_dir = effect_data_dir()?;
    if !data_dir.exists() {
        return Ok(game_data::EffectLibrary::default());
    }

    load_effect_library(&data_dir).map_err(|error| format!("failed to load effect catalog: {error}"))
}

fn load_character_ids() -> Result<BTreeSet<String>, String> {
    let library = load_character_library(character_data_dir()?)
        .map_err(|error| format!("failed to load character catalog: {error}"))?;
    Ok(library
        .iter()
        .map(|(id, _)| id.as_str().to_string())
        .collect())
}

fn map_validation_catalog(
    item_documents: &[ItemDocumentPayload],
    character_ids: &BTreeSet<String>,
) -> MapValidationCatalog {
    MapValidationCatalog {
        item_ids: item_documents
            .iter()
            .map(|document| document.item.id.to_string())
            .collect(),
        character_ids: character_ids.clone(),
    }
}

pub(crate) fn relative_to_repo(path: &Path) -> Result<String, String> {
    let repo = repo_root()?;
    let relative = path
        .strip_prefix(&repo)
        .map_err(|error| format!("failed to relativize {}: {error}", path.display()))?;
    Ok(to_forward_slashes(relative))
}

pub(crate) fn to_forward_slashes(path: impl AsRef<Path>) -> String {
    path.as_ref().to_string_lossy().replace('\\', "/")
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            get_editor_bootstrap,
            load_shared_registry,
            load_item_workspace,
            validate_item_document,
            save_item_documents,
            delete_item_document,
            load_dialogue_workspace,
            validate_dialogue_document,
            save_dialogue_documents,
            delete_dialogue_document,
            load_quest_workspace,
            validate_quest_document,
            save_quest_documents,
            delete_quest_document,
            load_narrative_workspace,
            load_narrative_document,
            save_narrative_document,
            create_narrative_document,
            delete_narrative_document,
            summarize_narrative_document,
            prepare_structuring_bundle,
            load_narrative_sync_settings,
            save_narrative_sync_settings,
            list_cloud_workspaces,
            create_cloud_workspace,
            sync_narrative_workspace,
            export_project_context_snapshot,
            upload_project_context_snapshot,
            load_map_workspace,
            validate_map_document,
            save_map_documents,
            delete_map_document,
            load_ai_settings,
            save_ai_settings,
            load_narrative_app_settings,
            save_narrative_app_settings,
            test_ai_provider,
            generate_dialogue_draft,
            generate_quest_draft,
            generate_narrative_draft,
            revise_narrative_draft
        ])
        .run(tauri::generate_context!())
        .expect("error while running CDC content editor");
}
