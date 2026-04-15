mod ai_context;
mod ai_provider;
mod ai_review;
mod ai_settings;
mod editor_menu;
mod quest_workspace;

use std::{
    collections::{BTreeMap, BTreeSet, HashSet},
    fs,
    path::{Path, PathBuf},
};

use game_data::{
    load_shared_content_registry, DialogueConnection, DialogueData, SharedContentRegistry,
};
use serde::{Deserialize, Serialize};
use tauri::Manager;

use crate::ai_provider::{generate_dialogue_draft, generate_quest_draft, test_ai_provider};
use crate::ai_settings::{load_ai_settings, save_ai_settings};
use crate::quest_workspace::{
    delete_quest_document, load_quest_workspace, save_quest_documents, validate_quest_document,
};

const DEFAULT_DIALOG_NODE_TYPES: &[&str] = &["dialog", "choice", "condition", "action", "end"];
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

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct EditorRuntimeFlags {
    menu_self_test_scenario: Option<String>,
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

#[tauri::command]
fn get_editor_bootstrap() -> Result<EditorBootstrap, String> {
    Ok(editor_bootstrap()?)
}

#[tauri::command]
fn get_editor_runtime_flags() -> Result<EditorRuntimeFlags, String> {
    let menu_self_test_scenario = std::env::var("CDC_EDITOR_SELF_TEST")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty());

    if let Some(scenario) = &menu_self_test_scenario {
        eprintln!(
            "[editor-self-test] runtime self-test scenario requested: {}",
            scenario
        );
    }

    Ok(EditorRuntimeFlags {
        menu_self_test_scenario,
    })
}

#[tauri::command]
fn log_editor_frontend_debug(
    level: String,
    message: String,
    payload: Option<String>,
) -> Result<(), String> {
    match payload {
        Some(payload) if !payload.is_empty() => {
            eprintln!("[editor-menu][frontend][{}] {} {}", level, message, payload);
        }
        _ => {
            eprintln!("[editor-menu][frontend][{}] {}", level, message);
        }
    }
    Ok(())
}

#[tauri::command]
fn load_shared_registry() -> Result<SharedContentRegistry, String> {
    load_shared_content_registry(repo_root()?)
        .map_err(|error| format!("failed to load shared content registry: {error}"))
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

    Ok(DeleteDialogueResult {
        deleted_id: dialog_id,
    })
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
                    "Consolidate content workflows into this standalone editor incrementally.",
            },
        ],
        editor_domains: vec![
            "Dialogue and quest flows",
            "Multi-layer map authoring",
            "Import, export, and validation tools",
        ],
    })
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

pub(crate) fn validate_dialogue(dialog: &DialogueData) -> Vec<ValidationIssue> {
    let mut issues = Vec::new();

    if dialog.dialog_id.trim().is_empty() {
        issues.push(document_error("dialogId", "Dialog id cannot be empty."));
    }
    if dialog.nodes.is_empty() {
        issues.push(document_error(
            "nodes",
            "Dialog must contain at least one node.",
        ));
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
        issues.push(document_error(
            "nodes",
            "Dialog can only have one start node.",
        ));
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
                format!(
                    "Connection references missing source node {}.",
                    connection.from
                ),
            ));
        }
        if !node_ids.contains(&connection.to) {
            issues.push(edge_error(
                connection_edge_key(connection),
                "connections",
                format!(
                    "Connection references missing target node {}.",
                    connection.to
                ),
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

pub(crate) fn repo_root() -> Result<PathBuf, String> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("..");
    root.canonicalize()
        .map_err(|error| format!("failed to resolve repo root: {error}"))
}

fn dialogue_data_dir() -> Result<PathBuf, String> {
    Ok(repo_root()?.join("data").join("dialogues"))
}

fn dialogue_file_path(dialog_id: &str) -> Result<PathBuf, String> {
    Ok(dialogue_data_dir()?.join(format!("{dialog_id}.json")))
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
        .setup(|app| {
            eprintln!("[editor-menu] setup start");
            app.manage(editor_menu::EditorMenuState::default());
            editor_menu::apply_window_menu(&app.handle(), "main")?;
            if let Some(window) = app.get_webview_window("main") {
                editor_menu::attach_window_menu_listener(window);
                editor_menu::remember_focused_editor_window(&app.handle(), "main", true);
            } else {
                eprintln!("[editor-menu] main window not available during setup");
            }
            eprintln!("[editor-menu] setup complete");
            Ok(())
        })
        .on_page_load(|webview, _payload| {
            eprintln!(
                "[editor-menu] page load window={} url={:?}",
                webview.label(),
                webview.url()
            );
            let _ = editor_menu::apply_window_menu(&webview.app_handle(), webview.label());
            if let Some(window) = webview.app_handle().get_webview_window(webview.label()) {
                editor_menu::attach_window_menu_listener(window);
            } else {
                eprintln!(
                    "[editor-menu] page load could not resolve window handle for {}",
                    webview.label()
                );
            }
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::Focused(focused) = event {
                eprintln!(
                    "[editor-menu] window focus event window={} focused={}",
                    window.label(),
                    focused
                );
                editor_menu::remember_focused_editor_window(
                    &window.app_handle(),
                    window.label(),
                    *focused,
                );
            }
        })
        .invoke_handler(tauri::generate_handler![
            get_editor_bootstrap,
            get_editor_runtime_flags,
            log_editor_frontend_debug,
            load_shared_registry,
            load_dialogue_workspace,
            validate_dialogue_document,
            save_dialogue_documents,
            delete_dialogue_document,
            load_quest_workspace,
            validate_quest_document,
            save_quest_documents,
            delete_quest_document,
            load_ai_settings,
            save_ai_settings,
            test_ai_provider,
            generate_dialogue_draft,
            generate_quest_draft
        ])
        .run(tauri::generate_context!())
        .expect("error while running CDC content editor");
}
