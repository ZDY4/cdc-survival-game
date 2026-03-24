use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum NarrativeExecutorMode {
    DesktopLocal,
    CloudMobile,
}

impl Default for NarrativeExecutorMode {
    fn default() -> Self {
        Self::DesktopLocal
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeSyncSettings {
    #[serde(default)]
    pub server_url: String,
    #[serde(default)]
    pub auth_token: String,
    #[serde(default)]
    pub workspace_id: String,
    #[serde(default)]
    pub device_label: String,
    #[serde(default)]
    pub last_sync_at: Option<String>,
    #[serde(default)]
    pub last_sync_status: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct CloudWorkspaceMeta {
    #[serde(default)]
    pub workspace_id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub document_count: usize,
    #[serde(default)]
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct CloudNarrativeDocument {
    #[serde(default)]
    pub doc_id: String,
    #[serde(default)]
    pub slug: String,
    #[serde(default)]
    pub doc_type: String,
    #[serde(default)]
    pub title: String,
    #[serde(default)]
    pub status: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub related_docs: Vec<String>,
    #[serde(default)]
    pub source_refs: Vec<String>,
    #[serde(default)]
    pub markdown: String,
    #[serde(default)]
    pub revision: u64,
    #[serde(default)]
    pub updated_at: String,
    #[serde(default)]
    pub deleted_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct PendingSyncOperation {
    #[serde(default)]
    pub operation_id: String,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub doc_id: String,
    #[serde(default)]
    pub slug: String,
    #[serde(default)]
    pub base_revision: u64,
    #[serde(default)]
    pub queued_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct SyncConflictPayload {
    #[serde(default)]
    pub slug: String,
    #[serde(default)]
    pub doc_id: String,
    #[serde(default)]
    pub local_revision: u64,
    #[serde(default)]
    pub remote_revision: u64,
    #[serde(default)]
    pub conflict_doc_slug: String,
    #[serde(default)]
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ProjectContextSnapshot {
    #[serde(default)]
    pub snapshot_id: String,
    #[serde(default)]
    pub workspace_id: String,
    #[serde(default)]
    pub project_root_fingerprint: String,
    #[serde(default)]
    pub generated_at: String,
    #[serde(default)]
    pub summary: String,
    #[serde(default)]
    pub source_refs: Vec<String>,
    #[serde(default)]
    pub runtime_indexes: Value,
    #[serde(default)]
    pub story_background: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeSyncPushDocument {
    #[serde(default)]
    pub document: CloudNarrativeDocument,
    #[serde(default)]
    pub base_revision: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeSyncRequest {
    #[serde(default)]
    pub device_label: String,
    #[serde(default)]
    pub since_revision: u64,
    #[serde(default)]
    pub push_documents: Vec<NarrativeSyncPushDocument>,
    #[serde(default)]
    pub delete_doc_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeSyncResponse {
    #[serde(default)]
    pub workspace: CloudWorkspaceMeta,
    #[serde(default)]
    pub head_revision: u64,
    #[serde(default)]
    pub documents: Vec<CloudNarrativeDocument>,
    #[serde(default)]
    pub conflicts: Vec<SyncConflictPayload>,
    #[serde(default)]
    pub project_snapshot: Option<ProjectContextSnapshot>,
}
