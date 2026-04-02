use std::collections::{hash_map::DefaultHasher, BTreeMap};
use std::fs;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use game_protocol::{
    CloudNarrativeDocument, CloudWorkspaceMeta, NarrativeExecutorMode, NarrativeSyncPushDocument,
    NarrativeSyncRequest, NarrativeSyncResponse, NarrativeSyncSettings, PendingSyncOperation,
    ProjectContextSnapshot, SyncConflictPayload,
};
use reqwest::blocking::{Client, RequestBuilder};
use serde::{Deserialize, Serialize};
use serde_json::json;
use tauri::{AppHandle, Manager};

use crate::narrative_context::build_project_context_snapshot_seed;
use crate::narrative_workspace::{
    load_narrative_documents, resolve_connected_project_root, resolve_workspace_root,
    save_narrative_document, NarrativeDocumentMeta, NarrativeDocumentPayload,
    SaveNarrativeDocumentInput,
};
use crate::to_forward_slashes;

const DEFAULT_SYNC_TIMEOUT_SEC: u64 = 30;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectContextSnapshotExportResult {
    pub snapshot: ProjectContextSnapshot,
    pub export_path: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectContextSnapshotUploadResult {
    pub snapshot: ProjectContextSnapshot,
    pub export_path: String,
    pub server_status: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeWorkspaceSyncResult {
    pub workspace: CloudWorkspaceMeta,
    pub head_revision: u64,
    pub pushed_count: usize,
    pub pulled_count: usize,
    pub conflict_count: usize,
    pub conflicts: Vec<SyncConflictPayload>,
    pub pending_operations: Vec<PendingSyncOperation>,
    pub project_snapshot: Option<ProjectContextSnapshot>,
    pub executor_mode: NarrativeExecutorMode,
    pub sync_status: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateCloudWorkspaceInput {
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct WorkspaceSyncState {
    #[serde(default)]
    head_revision: u64,
    #[serde(default)]
    documents: BTreeMap<String, WorkspaceDocumentSyncState>,
    #[serde(default)]
    last_sync_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct WorkspaceDocumentSyncState {
    #[serde(default)]
    doc_id: String,
    #[serde(default)]
    revision: u64,
    #[serde(default)]
    content_hash: u64,
    #[serde(default)]
    deleted: bool,
    #[serde(default)]
    updated_at: String,
}

#[tauri::command]
pub fn load_narrative_sync_settings(app: AppHandle) -> Result<NarrativeSyncSettings, String> {
    read_narrative_sync_settings(&app)
}

#[tauri::command]
pub fn save_narrative_sync_settings(
    app: AppHandle,
    settings: NarrativeSyncSettings,
) -> Result<NarrativeSyncSettings, String> {
    let normalized = normalize_sync_settings(settings);
    write_narrative_sync_settings(&app, &normalized)?;
    Ok(normalized)
}

#[tauri::command]
pub fn list_cloud_workspaces(app: AppHandle) -> Result<Vec<CloudWorkspaceMeta>, String> {
    let settings = read_narrative_sync_settings(&app)?;
    let client = sync_client()?;
    let url = build_server_url(&settings.server_url, "/workspaces")?;
    let response = authorized_request(client.get(url), &settings)
        .send()
        .map_err(|error| format!("failed to list cloud workspaces: {error}"))?;
    parse_json_response(response)
}

#[tauri::command]
pub fn create_cloud_workspace(
    app: AppHandle,
    input: CreateCloudWorkspaceInput,
) -> Result<CloudWorkspaceMeta, String> {
    if input.name.trim().is_empty() {
        return Err("workspace name cannot be empty".to_string());
    }
    let settings = read_narrative_sync_settings(&app)?;
    let client = sync_client()?;
    let url = build_server_url(&settings.server_url, "/workspaces")?;
    let response = authorized_request(client.post(url), &settings)
        .json(&json!({ "name": input.name.trim() }))
        .send()
        .map_err(|error| format!("failed to create cloud workspace: {error}"))?;
    parse_json_response(response)
}

#[tauri::command]
pub fn sync_narrative_workspace(
    app: AppHandle,
    workspace_root: String,
) -> Result<NarrativeWorkspaceSyncResult, String> {
    let mut settings = read_narrative_sync_settings(&app)?;
    if settings.server_url.trim().is_empty() {
        return Err("请先配置 Narrative Sync server URL。".to_string());
    }
    if settings.workspace_id.trim().is_empty() {
        return Err("请先配置 Narrative Sync workspace ID。".to_string());
    }

    let workspace_root_path = resolve_workspace_root(&workspace_root)?;
    let documents = load_narrative_documents(&workspace_root_path)?;
    let mut sync_state = read_workspace_sync_state(&workspace_root_path)?;
    let pending_operations = collect_pending_operations(&documents, &sync_state);
    let push_documents = pending_operations
        .iter()
        .filter(|operation| operation.kind == "upsert")
        .filter_map(|operation| {
            documents
                .iter()
                .find(|document| document.meta.slug == operation.slug)
                .map(|document| NarrativeSyncPushDocument {
                    document: cloud_document_from_local(
                        document,
                        sync_state.documents.get(&operation.slug).and_then(|state| {
                            if state.doc_id.trim().is_empty() {
                                None
                            } else {
                                Some(state.doc_id.as_str())
                            }
                        }),
                    ),
                    base_revision: operation.base_revision,
                })
        })
        .collect::<Vec<_>>();
    let delete_doc_ids = pending_operations
        .iter()
        .filter(|operation| operation.kind == "delete")
        .map(|operation| operation.doc_id.clone())
        .collect::<Vec<_>>();

    let request = NarrativeSyncRequest {
        device_label: if settings.device_label.trim().is_empty() {
            "desktop-local".to_string()
        } else {
            settings.device_label.clone()
        },
        since_revision: sync_state.head_revision,
        push_documents,
        delete_doc_ids,
    };

    let client = sync_client()?;
    let url = build_server_url(
        &settings.server_url,
        &format!("/workspaces/{}/sync", settings.workspace_id.trim()),
    )?;
    let response = authorized_request(client.post(url), &settings)
        .json(&request)
        .send()
        .map_err(|error| format!("failed to sync workspace: {error}"))?;
    let sync_response: NarrativeSyncResponse = parse_json_response(response)?;

    let workspace_root_string = to_forward_slashes(&workspace_root_path);
    for remote_document in &sync_response.documents {
        apply_remote_document(&workspace_root_string, remote_document)?;
        update_sync_state_for_document(&mut sync_state, remote_document);
    }
    for conflict in &sync_response.conflicts {
        if let Some(entry) = sync_state.documents.get_mut(&conflict.slug) {
            entry.revision = entry.revision.max(conflict.remote_revision);
        }
    }

    sync_state.head_revision = sync_response.head_revision;
    sync_state.last_sync_at = Some(current_timestamp());
    write_workspace_sync_state(&workspace_root_path, &sync_state)?;

    settings.last_sync_at = sync_state.last_sync_at.clone();
    settings.last_sync_status = format!(
        "Synced {} docs, pulled {}, conflicts {}",
        pending_operations.len(),
        sync_response.documents.len(),
        sync_response.conflicts.len()
    );
    write_narrative_sync_settings(&app, &normalize_sync_settings(settings.clone()))?;

    Ok(NarrativeWorkspaceSyncResult {
        workspace: sync_response.workspace,
        head_revision: sync_response.head_revision,
        pushed_count: pending_operations
            .iter()
            .filter(|operation| operation.kind == "upsert")
            .count(),
        pulled_count: sync_response.documents.len(),
        conflict_count: sync_response.conflicts.len(),
        conflicts: sync_response.conflicts,
        pending_operations,
        project_snapshot: sync_response.project_snapshot,
        executor_mode: NarrativeExecutorMode::DesktopLocal,
        sync_status: settings.last_sync_status,
    })
}

#[tauri::command]
pub fn export_project_context_snapshot(
    app: AppHandle,
    workspace_root: String,
    project_root: String,
    max_context_records: Option<usize>,
) -> Result<ProjectContextSnapshotExportResult, String> {
    let workspace_root_path = resolve_workspace_root(&workspace_root)?;
    let project_root_path = resolve_connected_project_root(Some(&project_root))?
        .ok_or_else(|| "项目路径不可用，无法导出上下文快照。".to_string())?;
    let sync_settings = read_narrative_sync_settings(&app).unwrap_or_default();
    let snapshot = build_snapshot(
        &workspace_root_path,
        &project_root_path,
        sync_settings.workspace_id.trim(),
        max_context_records.unwrap_or(24),
    )?;
    let export_path = write_snapshot_export(&workspace_root_path, &snapshot)?;
    Ok(ProjectContextSnapshotExportResult {
        snapshot,
        export_path: to_forward_slashes(export_path),
    })
}

#[tauri::command]
pub fn upload_project_context_snapshot(
    app: AppHandle,
    workspace_root: String,
    project_root: String,
    max_context_records: Option<usize>,
) -> Result<ProjectContextSnapshotUploadResult, String> {
    let export = export_project_context_snapshot(
        app.clone(),
        workspace_root,
        project_root,
        max_context_records,
    )?;
    let settings = read_narrative_sync_settings(&app)?;
    if settings.server_url.trim().is_empty() {
        return Err("请先配置 Narrative Sync server URL。".to_string());
    }
    if settings.workspace_id.trim().is_empty() {
        return Err("请先配置 Narrative Sync workspace ID。".to_string());
    }

    let client = sync_client()?;
    let url = build_server_url(
        &settings.server_url,
        &format!(
            "/workspaces/{}/project-snapshots",
            settings.workspace_id.trim()
        ),
    )?;
    let response = authorized_request(client.post(url), &settings)
        .json(&export.snapshot)
        .send()
        .map_err(|error| format!("failed to upload project context snapshot: {error}"))?;
    let uploaded: ProjectContextSnapshot = parse_json_response(response)?;

    let mut next_settings = settings;
    next_settings.last_sync_status = format!("Uploaded project snapshot {}", uploaded.snapshot_id);
    write_narrative_sync_settings(&app, &normalize_sync_settings(next_settings.clone()))?;

    Ok(ProjectContextSnapshotUploadResult {
        snapshot: uploaded,
        export_path: export.export_path,
        server_status: next_settings.last_sync_status,
    })
}

pub fn read_narrative_sync_settings(app: &AppHandle) -> Result<NarrativeSyncSettings, String> {
    let path = narrative_sync_settings_path(app)?;
    if !path.exists() {
        return Ok(NarrativeSyncSettings::default());
    }

    let raw = fs::read_to_string(&path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let parsed: NarrativeSyncSettings = serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
    Ok(normalize_sync_settings(parsed))
}

fn write_narrative_sync_settings(
    app: &AppHandle,
    settings: &NarrativeSyncSettings,
) -> Result<(), String> {
    let path = narrative_sync_settings_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("failed to create {}: {error}", parent.display()))?;
    }
    let raw = serde_json::to_string_pretty(settings)
        .map_err(|error| format!("failed to serialize narrative sync settings: {error}"))?;
    fs::write(&path, raw).map_err(|error| format!("failed to write {}: {error}", path.display()))
}

fn narrative_sync_settings_path(app: &AppHandle) -> Result<PathBuf, String> {
    let config_dir = app
        .path()
        .app_config_dir()
        .map_err(|error| format!("failed to resolve app config dir: {error}"))?;
    Ok(config_dir.join("narrative_sync_settings.json"))
}

fn normalize_sync_settings(mut settings: NarrativeSyncSettings) -> NarrativeSyncSettings {
    settings.server_url = settings.server_url.trim().trim_end_matches('/').to_string();
    settings.workspace_id = settings.workspace_id.trim().to_string();
    settings.device_label = if settings.device_label.trim().is_empty() {
        "desktop-local".to_string()
    } else {
        settings.device_label.trim().to_string()
    };
    settings.auth_token = settings.auth_token.trim().to_string();
    settings.last_sync_status = settings.last_sync_status.trim().to_string();
    settings
}

fn read_workspace_sync_state(workspace_root: &Path) -> Result<WorkspaceSyncState, String> {
    let path = workspace_sync_state_path(workspace_root);
    if !path.exists() {
        return Ok(WorkspaceSyncState::default());
    }
    let raw = fs::read_to_string(&path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))
}

fn write_workspace_sync_state(
    workspace_root: &Path,
    state: &WorkspaceSyncState,
) -> Result<(), String> {
    let path = workspace_sync_state_path(workspace_root);
    let raw = serde_json::to_string_pretty(state)
        .map_err(|error| format!("failed to serialize workspace sync state: {error}"))?;
    fs::write(&path, raw).map_err(|error| format!("failed to write {}: {error}", path.display()))
}

fn workspace_sync_state_path(workspace_root: &Path) -> PathBuf {
    workspace_root.join(".narrative_sync_state.json")
}

fn collect_pending_operations(
    documents: &[NarrativeDocumentPayload],
    sync_state: &WorkspaceSyncState,
) -> Vec<PendingSyncOperation> {
    let mut pending = Vec::new();
    let now = current_timestamp();

    for document in documents {
        let content_hash = hash_document(document);
        let state = sync_state.documents.get(&document.meta.slug);
        let changed = state
            .map(|entry| entry.content_hash != content_hash || entry.deleted)
            .unwrap_or(true);
        if changed {
            pending.push(PendingSyncOperation {
                operation_id: format!("upsert:{}:{}", document.meta.slug, now),
                kind: "upsert".to_string(),
                doc_id: state
                    .and_then(|entry| {
                        if entry.doc_id.trim().is_empty() {
                            None
                        } else {
                            Some(entry.doc_id.clone())
                        }
                    })
                    .unwrap_or_else(|| document.meta.slug.clone()),
                slug: document.meta.slug.clone(),
                base_revision: state.map(|entry| entry.revision).unwrap_or(0),
                queued_at: now.clone(),
            });
        }
    }

    for (slug, state) in &sync_state.documents {
        if state.deleted || documents.iter().any(|document| document.meta.slug == *slug) {
            continue;
        }
        pending.push(PendingSyncOperation {
            operation_id: format!("delete:{slug}:{now}"),
            kind: "delete".to_string(),
            doc_id: if state.doc_id.trim().is_empty() {
                slug.clone()
            } else {
                state.doc_id.clone()
            },
            slug: slug.clone(),
            base_revision: state.revision,
            queued_at: now.clone(),
        });
    }

    pending
}

fn cloud_document_from_local(
    document: &NarrativeDocumentPayload,
    known_doc_id: Option<&str>,
) -> CloudNarrativeDocument {
    CloudNarrativeDocument {
        doc_id: known_doc_id.unwrap_or(&document.meta.slug).to_string(),
        slug: document.meta.slug.clone(),
        doc_type: document.meta.doc_type.clone(),
        title: document.meta.title.clone(),
        status: document.meta.status.clone(),
        tags: document.meta.tags.clone(),
        related_docs: document.meta.related_docs.clone(),
        source_refs: document.meta.source_refs.clone(),
        markdown: document.markdown.clone(),
        revision: 0,
        updated_at: current_timestamp(),
        deleted_at: None,
    }
}

fn apply_remote_document(
    workspace_root: &str,
    remote_document: &CloudNarrativeDocument,
) -> Result<(), String> {
    if remote_document.deleted_at.is_some() {
        let _ = crate::narrative_workspace::delete_narrative_document(
            workspace_root.to_string(),
            remote_document.slug.clone(),
        )?;
        return Ok(());
    }

    let payload = NarrativeDocumentPayload {
        document_key: remote_document.slug.clone(),
        original_slug: remote_document.slug.clone(),
        file_name: format!("{}.md", remote_document.slug),
        relative_path: format!(
            "narrative/{}/{}.md",
            crate::narrative_templates::doc_type_directory(&remote_document.doc_type),
            remote_document.slug
        ),
        meta: NarrativeDocumentMeta {
            doc_type: remote_document.doc_type.clone(),
            slug: remote_document.slug.clone(),
            title: remote_document.title.clone(),
            status: remote_document.status.clone(),
            tags: remote_document.tags.clone(),
            related_docs: remote_document.related_docs.clone(),
            source_refs: remote_document.source_refs.clone(),
        },
        markdown: remote_document.markdown.clone(),
        validation: Vec::new(),
    };

    save_narrative_document(
        workspace_root.to_string(),
        SaveNarrativeDocumentInput {
            original_slug: Some(remote_document.slug.clone()),
            document: payload,
        },
    )?;
    Ok(())
}

fn update_sync_state_for_document(
    sync_state: &mut WorkspaceSyncState,
    remote_document: &CloudNarrativeDocument,
) {
    sync_state.documents.insert(
        remote_document.slug.clone(),
        WorkspaceDocumentSyncState {
            doc_id: if remote_document.doc_id.trim().is_empty() {
                remote_document.slug.clone()
            } else {
                remote_document.doc_id.clone()
            },
            revision: remote_document.revision,
            content_hash: hash_cloud_document(remote_document),
            deleted: remote_document.deleted_at.is_some(),
            updated_at: remote_document.updated_at.clone(),
        },
    );
}

fn build_snapshot(
    workspace_root: &Path,
    project_root: &Path,
    workspace_id: &str,
    max_context_records: usize,
) -> Result<ProjectContextSnapshot, String> {
    let seed = build_project_context_snapshot_seed(project_root, max_context_records)?;
    let snapshot_id = format!("snapshot-{}", current_timestamp());
    Ok(ProjectContextSnapshot {
        snapshot_id,
        workspace_id: workspace_id.to_string(),
        project_root_fingerprint: hash_path(project_root),
        generated_at: current_timestamp(),
        summary: format!(
            "{} Exported from {}",
            seed.summary,
            to_forward_slashes(workspace_root)
        ),
        source_refs: seed.source_refs,
        runtime_indexes: seed.runtime_indexes,
        story_background: seed.story_background,
    })
}

fn write_snapshot_export(
    workspace_root: &Path,
    snapshot: &ProjectContextSnapshot,
) -> Result<PathBuf, String> {
    let export_dir = workspace_root.join("exports");
    fs::create_dir_all(&export_dir)
        .map_err(|error| format!("failed to create {}: {error}", export_dir.display()))?;
    let export_path = export_dir.join(format!("project_context_{}.json", snapshot.generated_at));
    let raw = serde_json::to_string_pretty(snapshot)
        .map_err(|error| format!("failed to serialize project context snapshot: {error}"))?;
    fs::write(&export_path, raw)
        .map_err(|error| format!("failed to write {}: {error}", export_path.display()))?;
    Ok(export_path)
}

fn hash_document(document: &NarrativeDocumentPayload) -> u64 {
    let mut hasher = DefaultHasher::new();
    document.meta.slug.hash(&mut hasher);
    document.meta.doc_type.hash(&mut hasher);
    document.meta.title.hash(&mut hasher);
    document.meta.status.hash(&mut hasher);
    document.meta.tags.hash(&mut hasher);
    document.meta.related_docs.hash(&mut hasher);
    document.meta.source_refs.hash(&mut hasher);
    document.markdown.hash(&mut hasher);
    hasher.finish()
}

fn hash_cloud_document(document: &CloudNarrativeDocument) -> u64 {
    let mut hasher = DefaultHasher::new();
    document.slug.hash(&mut hasher);
    document.doc_type.hash(&mut hasher);
    document.title.hash(&mut hasher);
    document.status.hash(&mut hasher);
    document.tags.hash(&mut hasher);
    document.related_docs.hash(&mut hasher);
    document.source_refs.hash(&mut hasher);
    document.markdown.hash(&mut hasher);
    document.deleted_at.hash(&mut hasher);
    hasher.finish()
}

fn hash_path(path: &Path) -> String {
    let mut hasher = DefaultHasher::new();
    to_forward_slashes(path).hash(&mut hasher);
    format!("{:x}", hasher.finish())
}

fn current_timestamp() -> String {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs().to_string())
        .unwrap_or_else(|_| "0".to_string())
}

fn sync_client() -> Result<Client, String> {
    Client::builder()
        .timeout(std::time::Duration::from_secs(DEFAULT_SYNC_TIMEOUT_SEC))
        .build()
        .map_err(|error| format!("failed to build sync client: {error}"))
}

fn build_server_url(server_url: &str, suffix: &str) -> Result<String, String> {
    let trimmed = server_url.trim().trim_end_matches('/');
    if trimmed.is_empty() {
        return Err("Narrative Sync server URL 不能为空".to_string());
    }
    Ok(format!("{trimmed}{suffix}"))
}

fn authorized_request(builder: RequestBuilder, settings: &NarrativeSyncSettings) -> RequestBuilder {
    if settings.auth_token.trim().is_empty() {
        builder
    } else {
        builder.bearer_auth(settings.auth_token.trim())
    }
}

fn parse_json_response<T: for<'de> Deserialize<'de>>(
    response: reqwest::blocking::Response,
) -> Result<T, String> {
    let status = response.status();
    let raw = response
        .text()
        .map_err(|error| format!("failed to read response body: {error}"))?;
    if !status.is_success() {
        return Err(format!("server returned {status}: {raw}"));
    }
    serde_json::from_str(&raw).map_err(|error| format!("failed to parse response JSON: {error}"))
}

#[cfg(test)]
mod tests {
    use super::{
        collect_pending_operations, normalize_sync_settings, WorkspaceDocumentSyncState,
        WorkspaceSyncState,
    };
    use crate::narrative_workspace::{NarrativeDocumentMeta, NarrativeDocumentPayload};

    #[test]
    fn normalize_sync_settings_trims_server_and_device_defaults() {
        let normalized = normalize_sync_settings(game_protocol::NarrativeSyncSettings {
            server_url: " http://127.0.0.1:4852/ ".to_string(),
            auth_token: "  token  ".to_string(),
            workspace_id: " demo ".to_string(),
            device_label: " ".to_string(),
            last_sync_at: None,
            last_sync_status: " ok ".to_string(),
        });
        assert_eq!(normalized.server_url, "http://127.0.0.1:4852");
        assert_eq!(normalized.auth_token, "token");
        assert_eq!(normalized.workspace_id, "demo");
        assert_eq!(normalized.device_label, "desktop-local");
        assert_eq!(normalized.last_sync_status, "ok");
    }

    #[test]
    fn collect_pending_operations_marks_changed_and_deleted_documents() {
        let documents = vec![NarrativeDocumentPayload {
            document_key: "task-a".to_string(),
            original_slug: "task-a".to_string(),
            file_name: "task-a.md".to_string(),
            relative_path: "narrative/tasks/task-a.md".to_string(),
            meta: NarrativeDocumentMeta {
                doc_type: "task_setup".to_string(),
                slug: "task-a".to_string(),
                title: "Task A".to_string(),
                status: "draft".to_string(),
                tags: vec![],
                related_docs: vec![],
                source_refs: vec![],
            },
            markdown: "# Task A".to_string(),
            validation: Vec::new(),
        }];
        let sync_state = WorkspaceSyncState {
            head_revision: 4,
            documents: [(
                "removed-scene".to_string(),
                WorkspaceDocumentSyncState {
                    doc_id: "removed-scene".to_string(),
                    revision: 2,
                    content_hash: 1,
                    deleted: false,
                    updated_at: "1".to_string(),
                },
            )]
            .into_iter()
            .collect(),
            last_sync_at: None,
        };

        let operations = collect_pending_operations(&documents, &sync_state);
        assert!(operations
            .iter()
            .any(|operation| operation.kind == "upsert" && operation.slug == "task-a"));
        assert!(operations
            .iter()
            .any(|operation| operation.kind == "delete" && operation.slug == "removed-scene"));
    }
}
