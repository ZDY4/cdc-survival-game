use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::{Path as AxumPath, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::IntoResponse;
use axum::routing::{get, post, put};
use axum::{Json, Router};
use game_protocol::{
    CloudNarrativeDocument, CloudWorkspaceMeta, NarrativeSyncPushDocument, NarrativeSyncRequest,
    NarrativeSyncResponse, ProjectContextSnapshot, SyncConflictPayload,
};
use serde::{Deserialize, Serialize};

#[derive(Clone)]
struct AppState {
    data_root: PathBuf,
    auth_token: Option<String>,
    write_lock: Arc<Mutex<()>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceRecord {
    meta: CloudWorkspaceMeta,
    head_revision: u64,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CreateWorkspaceInput {
    name: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ChangesQuery {
    since_revision: Option<u64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeleteQuery {
    base_revision: Option<u64>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct MobileAiGatewayRequest {
    request: serde_json::Value,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct MobileAiGatewayResponse {
    ok: bool,
    message: String,
}

#[tokio::main]
async fn main() {
    let data_root = env::var("NARRATIVE_SYNC_DATA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("data"));
    fs::create_dir_all(&data_root).expect("failed to create narrative sync data dir");

    let auth_token = env::var("NARRATIVE_SYNC_AUTH_TOKEN")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty());
    let state = AppState {
        data_root,
        auth_token,
        write_lock: Arc::new(Mutex::new(())),
    };

    let app = Router::new()
        .route("/health", get(health))
        .route("/workspaces", get(list_workspaces).post(create_workspace))
        .route("/workspaces/:workspace_id/changes", get(get_changes))
        .route("/workspaces/:workspace_id/sync", post(sync_workspace))
        .route(
            "/workspaces/:workspace_id/documents/:doc_id",
            put(upsert_document).delete(delete_document),
        )
        .route(
            "/workspaces/:workspace_id/project-snapshots",
            post(upload_project_snapshot),
        )
        .route(
            "/workspaces/:workspace_id/project-snapshots/latest",
            get(load_latest_project_snapshot),
        )
        .route(
            "/workspaces/:workspace_id/mobile-ai/generate",
            post(mobile_ai_generate),
        )
        .route(
            "/workspaces/:workspace_id/mobile-ai/revise",
            post(mobile_ai_revise),
        )
        .with_state(state);

    let port = env::var("NARRATIVE_SYNC_PORT")
        .ok()
        .and_then(|value| value.parse::<u16>().ok())
        .unwrap_or(4852);
    let address = SocketAddr::from(([127, 0, 0, 1], port));
    println!("Narrative Sync server listening on http://{address}");
    let listener = tokio::net::TcpListener::bind(address)
        .await
        .expect("failed to bind narrative sync server");
    axum::serve(listener, app)
        .await
        .expect("failed to run narrative sync server");
}

async fn health() -> impl IntoResponse {
    Json(serde_json::json!({ "ok": true }))
}

async fn list_workspaces(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Vec<CloudWorkspaceMeta>>, AppError> {
    authorize(&state, &headers)?;
    let mut workspaces = Vec::new();
    for entry in fs::read_dir(&state.data_root)
        .map_err(|error| AppError::internal(format!("failed to read data root: {error}")))?
    {
        let entry = entry.map_err(|error| AppError::internal(format!("failed to enumerate data root: {error}")))?;
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        if let Ok(record) = load_workspace_record(&state, &path) {
            workspaces.push(record.meta);
        }
    }
    workspaces.sort_by(|left, right| left.name.cmp(&right.name));
    Ok(Json(workspaces))
}

async fn create_workspace(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(input): Json<CreateWorkspaceInput>,
) -> Result<Json<CloudWorkspaceMeta>, AppError> {
    authorize(&state, &headers)?;
    if input.name.trim().is_empty() {
        return Err(AppError::bad_request("workspace name cannot be empty"));
    }
    let _guard = state
        .write_lock
        .lock()
        .map_err(|_| AppError::internal("failed to lock workspace writer"))?;
    let workspace_id = format!("{}-{}", slugify(&input.name), unix_timestamp());
    let workspace_dir = workspace_dir(&state, &workspace_id);
    fs::create_dir_all(docs_dir(&workspace_dir))
        .map_err(|error| AppError::internal(format!("failed to create workspace dir: {error}")))?;
    let meta = CloudWorkspaceMeta {
        workspace_id: workspace_id.clone(),
        name: input.name.trim().to_string(),
        document_count: 0,
        updated_at: unix_timestamp(),
    };
    save_workspace_record(
        &workspace_dir,
        &WorkspaceRecord {
            meta: meta.clone(),
            head_revision: 0,
        },
    )?;
    Ok(Json(meta))
}

async fn get_changes(
    State(state): State<AppState>,
    headers: HeaderMap,
    AxumPath(workspace_id): AxumPath<String>,
    Query(query): Query<ChangesQuery>,
) -> Result<Json<NarrativeSyncResponse>, AppError> {
    authorize(&state, &headers)?;
    let workspace_dir = workspace_dir(&state, &workspace_id);
    let record = load_workspace_record(&state, &workspace_dir)?;
    let documents = load_workspace_documents(&workspace_dir)?
        .into_values()
        .filter(|document| document.revision > query.since_revision.unwrap_or(0))
        .collect::<Vec<_>>();
    Ok(Json(NarrativeSyncResponse {
        workspace: record.meta,
        head_revision: record.head_revision,
        documents,
        conflicts: Vec::new(),
        project_snapshot: load_latest_snapshot_if_exists(&workspace_dir)?,
    }))
}

async fn sync_workspace(
    State(state): State<AppState>,
    headers: HeaderMap,
    AxumPath(workspace_id): AxumPath<String>,
    Json(request): Json<NarrativeSyncRequest>,
) -> Result<Json<NarrativeSyncResponse>, AppError> {
    authorize(&state, &headers)?;
    let _guard = state
        .write_lock
        .lock()
        .map_err(|_| AppError::internal("failed to lock workspace writer"))?;
    let workspace_dir = workspace_dir(&state, &workspace_id);
    ensure_workspace_layout(&workspace_dir)?;
    let mut record = load_or_init_workspace_record(&workspace_dir, &workspace_id)?;
    let mut documents = load_workspace_documents(&workspace_dir)?;
    let mut conflicts = Vec::new();

    for doc_id in &request.delete_doc_ids {
        let Some(existing) = documents.get_mut(doc_id) else {
            continue;
        };
        record.head_revision += 1;
        existing.deleted_at = Some(unix_timestamp());
        existing.updated_at = unix_timestamp();
        existing.revision = record.head_revision;
        save_document(&workspace_dir, existing)?;
    }

    for push in &request.push_documents {
        apply_push_document(
            &workspace_dir,
            &mut record,
            &mut documents,
            push,
            &mut conflicts,
        )?;
    }

    record.meta.document_count = documents
        .values()
        .filter(|document| document.deleted_at.is_none())
        .count();
    record.meta.updated_at = unix_timestamp();
    save_workspace_record(&workspace_dir, &record)?;

    let changed_documents = documents
        .into_values()
        .filter(|document| document.revision > request.since_revision)
        .collect::<Vec<_>>();
    Ok(Json(NarrativeSyncResponse {
        workspace: record.meta,
        head_revision: record.head_revision,
        documents: changed_documents,
        conflicts,
        project_snapshot: load_latest_snapshot_if_exists(&workspace_dir)?,
    }))
}

async fn upsert_document(
    State(state): State<AppState>,
    headers: HeaderMap,
    AxumPath((workspace_id, _doc_id)): AxumPath<(String, String)>,
    Json(push): Json<NarrativeSyncPushDocument>,
) -> Result<Json<CloudNarrativeDocument>, AppError> {
    authorize(&state, &headers)?;
    let _guard = state
        .write_lock
        .lock()
        .map_err(|_| AppError::internal("failed to lock workspace writer"))?;
    let workspace_dir = workspace_dir(&state, &workspace_id);
    ensure_workspace_layout(&workspace_dir)?;
    let mut record = load_or_init_workspace_record(&workspace_dir, &workspace_id)?;
    let mut documents = load_workspace_documents(&workspace_dir)?;
    let mut conflicts = Vec::new();
    let doc_id = push.document.doc_id.clone();
    apply_push_document(
        &workspace_dir,
        &mut record,
        &mut documents,
        &push,
        &mut conflicts,
    )?;
    if !conflicts.is_empty() {
        return Err(AppError::conflict("document revision conflict"));
    }
    record.meta.document_count = documents
        .values()
        .filter(|document| document.deleted_at.is_none())
        .count();
    record.meta.updated_at = unix_timestamp();
    save_workspace_record(&workspace_dir, &record)?;
    let document = documents
        .get(&doc_id)
        .cloned()
        .ok_or_else(|| AppError::internal("document missing after upsert"))?;
    Ok(Json(document))
}

async fn delete_document(
    State(state): State<AppState>,
    headers: HeaderMap,
    AxumPath((workspace_id, doc_id)): AxumPath<(String, String)>,
    Query(query): Query<DeleteQuery>,
) -> Result<Json<CloudNarrativeDocument>, AppError> {
    authorize(&state, &headers)?;
    let _guard = state
        .write_lock
        .lock()
        .map_err(|_| AppError::internal("failed to lock workspace writer"))?;
    let workspace_dir = workspace_dir(&state, &workspace_id);
    let mut record = load_workspace_record(&state, &workspace_dir)?;
    let mut documents = load_workspace_documents(&workspace_dir)?;
    let current_revision = documents
        .get(&doc_id)
        .map(|document| document.revision)
        .ok_or_else(|| AppError::not_found("document not found"))?;
    if query.base_revision.unwrap_or(current_revision) != current_revision {
        return Err(AppError::conflict("document revision conflict"));
    }
    let updated = {
        let existing = documents
            .get_mut(&doc_id)
            .ok_or_else(|| AppError::not_found("document not found"))?;
        record.head_revision += 1;
        existing.deleted_at = Some(unix_timestamp());
        existing.updated_at = unix_timestamp();
        existing.revision = record.head_revision;
        save_document(&workspace_dir, existing)?;
        existing.clone()
    };
    record.meta.document_count = documents
        .values()
        .filter(|document| document.deleted_at.is_none())
        .count();
    record.meta.updated_at = unix_timestamp();
    save_workspace_record(&workspace_dir, &record)?;
    Ok(Json(updated))
}

async fn upload_project_snapshot(
    State(state): State<AppState>,
    headers: HeaderMap,
    AxumPath(workspace_id): AxumPath<String>,
    Json(snapshot): Json<ProjectContextSnapshot>,
) -> Result<Json<ProjectContextSnapshot>, AppError> {
    authorize(&state, &headers)?;
    let _guard = state
        .write_lock
        .lock()
        .map_err(|_| AppError::internal("failed to lock workspace writer"))?;
    let workspace_dir = workspace_dir(&state, &workspace_id);
    ensure_workspace_layout(&workspace_dir)?;
    let latest_path = workspace_dir.join("latest_project_snapshot.json");
    let raw = serde_json::to_string_pretty(&snapshot)
        .map_err(|error| AppError::internal(format!("failed to serialize snapshot: {error}")))?;
    fs::write(&latest_path, raw)
        .map_err(|error| AppError::internal(format!("failed to write snapshot: {error}")))?;
    Ok(Json(snapshot))
}

async fn load_latest_project_snapshot(
    State(state): State<AppState>,
    headers: HeaderMap,
    AxumPath(workspace_id): AxumPath<String>,
) -> Result<Json<ProjectContextSnapshot>, AppError> {
    authorize(&state, &headers)?;
    let workspace_dir = workspace_dir(&state, &workspace_id);
    let snapshot = load_latest_snapshot_if_exists(&workspace_dir)?
        .ok_or_else(|| AppError::not_found("project snapshot not found"))?;
    Ok(Json(snapshot))
}

async fn mobile_ai_generate(
    State(state): State<AppState>,
    headers: HeaderMap,
    AxumPath(_workspace_id): AxumPath<String>,
    Json(payload): Json<MobileAiGatewayRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    authorize(&state, &headers)?;
    mobile_ai_gateway_response(payload)
}

async fn mobile_ai_revise(
    State(state): State<AppState>,
    headers: HeaderMap,
    AxumPath(_workspace_id): AxumPath<String>,
    Json(payload): Json<MobileAiGatewayRequest>,
) -> Result<Json<serde_json::Value>, AppError> {
    authorize(&state, &headers)?;
    mobile_ai_gateway_response(payload)
}

fn mobile_ai_gateway_response(
    payload: MobileAiGatewayRequest,
) -> Result<Json<serde_json::Value>, AppError> {
    let provider_url = env::var("NARRATIVE_MOBILE_AI_URL")
        .ok()
        .map(|value| value.trim().trim_end_matches('/').to_string())
        .filter(|value| !value.is_empty());

    let Some(provider_url) = provider_url else {
        return Err(AppError::not_implemented(
            "mobile AI gateway is not configured; set NARRATIVE_MOBILE_AI_URL to enable it",
        ));
    };

    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(60))
        .build()
        .map_err(|error| AppError::internal(format!("failed to build AI gateway client: {error}")))?;
    let response = client
        .post(provider_url)
        .json(&payload.request)
        .send()
        .map_err(|error| AppError::internal(format!("failed to call mobile AI gateway: {error}")))?;
    let status = response.status();
    let raw = response
        .text()
        .map_err(|error| AppError::internal(format!("failed to read AI gateway response: {error}")))?;
    if !status.is_success() {
        return Err(AppError::internal(format!("mobile AI gateway returned {status}: {raw}")));
    }
    let parsed = serde_json::from_str::<serde_json::Value>(&raw)
        .unwrap_or_else(|_| serde_json::json!(MobileAiGatewayResponse {
            ok: true,
            message: raw,
        }));
    Ok(Json(parsed))
}

fn authorize(state: &AppState, headers: &HeaderMap) -> Result<(), AppError> {
    let Some(expected) = &state.auth_token else {
        return Ok(());
    };
    let actual = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .unwrap_or_default();
    if actual == expected {
        Ok(())
    } else {
        Err(AppError::unauthorized("invalid bearer token"))
    }
}

fn apply_push_document(
    workspace_dir: &Path,
    record: &mut WorkspaceRecord,
    documents: &mut BTreeMap<String, CloudNarrativeDocument>,
    push: &NarrativeSyncPushDocument,
    conflicts: &mut Vec<SyncConflictPayload>,
) -> Result<(), AppError> {
    let doc_id = if push.document.doc_id.trim().is_empty() {
        push.document.slug.clone()
    } else {
        push.document.doc_id.clone()
    };
    let existing = documents.get(&doc_id).cloned();
    if let Some(existing) = existing {
        if push.base_revision != existing.revision && existing.markdown != push.document.markdown {
            record.head_revision += 1;
            let conflict_slug = format!("{}.conflict-{}", push.document.slug, record.head_revision);
            let conflict_doc_id = format!("{doc_id}__conflict__{}", record.head_revision);
            let conflict_document = CloudNarrativeDocument {
                doc_id: conflict_doc_id.clone(),
                slug: conflict_slug.clone(),
                doc_type: push.document.doc_type.clone(),
                title: format!("{} (Conflict Draft)", push.document.title),
                status: push.document.status.clone(),
                tags: push.document.tags.clone(),
                related_docs: push.document.related_docs.clone(),
                source_refs: push.document.source_refs.clone(),
                markdown: push.document.markdown.clone(),
                revision: record.head_revision,
                updated_at: unix_timestamp(),
                deleted_at: None,
            };
            save_document(workspace_dir, &conflict_document)?;
            documents.insert(conflict_doc_id.clone(), conflict_document.clone());
            conflicts.push(SyncConflictPayload {
                slug: push.document.slug.clone(),
                doc_id,
                local_revision: push.base_revision,
                remote_revision: existing.revision,
                conflict_doc_slug: conflict_slug,
                message: "Remote revision advanced; stored local draft as conflict document.".to_string(),
            });
            return Ok(());
        }
    }

    record.head_revision += 1;
    let next = CloudNarrativeDocument {
        doc_id: doc_id.clone(),
        slug: push.document.slug.clone(),
        doc_type: push.document.doc_type.clone(),
        title: push.document.title.clone(),
        status: push.document.status.clone(),
        tags: push.document.tags.clone(),
        related_docs: push.document.related_docs.clone(),
        source_refs: push.document.source_refs.clone(),
        markdown: push.document.markdown.clone(),
        revision: record.head_revision,
        updated_at: unix_timestamp(),
        deleted_at: None,
    };
    save_document(workspace_dir, &next)?;
    documents.insert(doc_id, next);
    Ok(())
}

fn load_or_init_workspace_record(
    workspace_dir: &Path,
    workspace_id: &str,
) -> Result<WorkspaceRecord, AppError> {
    if workspace_dir.join("workspace.json").exists() {
        return load_workspace_record_from_dir(workspace_dir);
    }
    let record = WorkspaceRecord {
        meta: CloudWorkspaceMeta {
            workspace_id: workspace_id.to_string(),
            name: workspace_id.to_string(),
            document_count: 0,
            updated_at: unix_timestamp(),
        },
        head_revision: 0,
    };
    save_workspace_record(workspace_dir, &record)?;
    Ok(record)
}

fn load_workspace_record(_state: &AppState, workspace_dir: &Path) -> Result<WorkspaceRecord, AppError> {
    if !workspace_dir.exists() {
        return Err(AppError::not_found("workspace not found"));
    }
    load_workspace_record_from_dir(workspace_dir)
}

fn load_workspace_record_from_dir(workspace_dir: &Path) -> Result<WorkspaceRecord, AppError> {
    let path = workspace_dir.join("workspace.json");
    let raw = fs::read_to_string(&path)
        .map_err(|error| AppError::internal(format!("failed to read {}: {error}", path.display())))?;
    serde_json::from_str(&raw)
        .map_err(|error| AppError::internal(format!("failed to parse {}: {error}", path.display())))
}

fn save_workspace_record(workspace_dir: &Path, record: &WorkspaceRecord) -> Result<(), AppError> {
    ensure_workspace_layout(workspace_dir)?;
    let raw = serde_json::to_string_pretty(record)
        .map_err(|error| AppError::internal(format!("failed to serialize workspace record: {error}")))?;
    fs::write(workspace_dir.join("workspace.json"), raw)
        .map_err(|error| AppError::internal(format!("failed to write workspace record: {error}")))
}

fn load_workspace_documents(
    workspace_dir: &Path,
) -> Result<BTreeMap<String, CloudNarrativeDocument>, AppError> {
    let mut documents = BTreeMap::new();
    let docs_dir = docs_dir(workspace_dir);
    if !docs_dir.exists() {
        return Ok(documents);
    }
    for entry in fs::read_dir(&docs_dir)
        .map_err(|error| AppError::internal(format!("failed to read docs dir: {error}")))?
    {
        let entry = entry.map_err(|error| AppError::internal(format!("failed to enumerate docs dir: {error}")))?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let raw = fs::read_to_string(&path)
            .map_err(|error| AppError::internal(format!("failed to read {}: {error}", path.display())))?;
        let document: CloudNarrativeDocument = serde_json::from_str(&raw)
            .map_err(|error| AppError::internal(format!("failed to parse {}: {error}", path.display())))?;
        documents.insert(document.doc_id.clone(), document);
    }
    Ok(documents)
}

fn save_document(workspace_dir: &Path, document: &CloudNarrativeDocument) -> Result<(), AppError> {
    ensure_workspace_layout(workspace_dir)?;
    let raw = serde_json::to_string_pretty(document)
        .map_err(|error| AppError::internal(format!("failed to serialize document: {error}")))?;
    fs::write(doc_path(workspace_dir, &document.doc_id), raw)
        .map_err(|error| AppError::internal(format!("failed to write document: {error}")))
}

fn load_latest_snapshot_if_exists(
    workspace_dir: &Path,
) -> Result<Option<ProjectContextSnapshot>, AppError> {
    let path = workspace_dir.join("latest_project_snapshot.json");
    if !path.exists() {
        return Ok(None);
    }
    let raw = fs::read_to_string(&path)
        .map_err(|error| AppError::internal(format!("failed to read {}: {error}", path.display())))?;
    let snapshot = serde_json::from_str(&raw)
        .map_err(|error| AppError::internal(format!("failed to parse {}: {error}", path.display())))?;
    Ok(Some(snapshot))
}

fn ensure_workspace_layout(workspace_dir: &Path) -> Result<(), AppError> {
    fs::create_dir_all(docs_dir(workspace_dir))
        .map_err(|error| AppError::internal(format!("failed to create workspace layout: {error}")))
}

fn workspace_dir(state: &AppState, workspace_id: &str) -> PathBuf {
    state.data_root.join(workspace_id)
}

fn docs_dir(workspace_dir: &Path) -> PathBuf {
    workspace_dir.join("documents")
}

fn doc_path(workspace_dir: &Path, doc_id: &str) -> PathBuf {
    docs_dir(workspace_dir).join(format!("{doc_id}.json"))
}

fn unix_timestamp() -> String {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs().to_string())
        .unwrap_or_else(|_| "0".to_string())
}

fn slugify(raw: &str) -> String {
    let mut output = String::new();
    let mut previous_dash = false;
    for character in raw.trim().chars() {
        let normalized = if character.is_ascii_alphanumeric() {
            Some(character.to_ascii_lowercase())
        } else if character.is_whitespace() || matches!(character, '_' | '-') {
            Some('-')
        } else {
            None
        };

        let Some(character) = normalized else {
            continue;
        };
        if character == '-' {
            if previous_dash || output.is_empty() {
                continue;
            }
            previous_dash = true;
        } else {
            previous_dash = false;
        }
        output.push(character);
    }
    output.trim_matches('-').to_string()
}

#[derive(Debug, Clone)]
struct AppError {
    status: StatusCode,
    message: String,
}

impl AppError {
    fn bad_request(message: impl Into<String>) -> Self {
        Self {
            status: StatusCode::BAD_REQUEST,
            message: message.into(),
        }
    }

    fn unauthorized(message: impl Into<String>) -> Self {
        Self {
            status: StatusCode::UNAUTHORIZED,
            message: message.into(),
        }
    }

    fn not_found(message: impl Into<String>) -> Self {
        Self {
            status: StatusCode::NOT_FOUND,
            message: message.into(),
        }
    }

    fn conflict(message: impl Into<String>) -> Self {
        Self {
            status: StatusCode::CONFLICT,
            message: message.into(),
        }
    }

    fn not_implemented(message: impl Into<String>) -> Self {
        Self {
            status: StatusCode::NOT_IMPLEMENTED,
            message: message.into(),
        }
    }

    fn internal(message: impl Into<String>) -> Self {
        Self {
            status: StatusCode::INTERNAL_SERVER_ERROR,
            message: message.into(),
        }
    }
}

impl IntoResponse for AppError {
    fn into_response(self) -> axum::response::Response {
        (
            self.status,
            Json(serde_json::json!({
                "ok": false,
                "message": self.message,
            })),
        )
            .into_response()
    }
}
