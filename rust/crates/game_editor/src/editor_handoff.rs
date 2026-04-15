use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

const HANDOFF_DIR: &str = "tmp/editor_handoff";
const ITEM_EDITOR_SESSION_FILE: &str = "bevy_item_editor.session.json";
const ITEM_EDITOR_SELECTION_FILE: &str = "bevy_item_editor.select_item.json";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ItemEditorSession {
    pub pid: u32,
    pub updated_at_unix_ms: u128,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ItemEditorSelectionRequest {
    pub request_id: String,
    pub item_id: u32,
    pub requested_at_unix_ms: u128,
}

pub fn item_editor_session_path(repo_root: &Path) -> PathBuf {
    repo_root.join(HANDOFF_DIR).join(ITEM_EDITOR_SESSION_FILE)
}

pub fn item_editor_selection_request_path(repo_root: &Path) -> PathBuf {
    repo_root.join(HANDOFF_DIR).join(ITEM_EDITOR_SELECTION_FILE)
}

pub fn read_item_editor_session(repo_root: &Path) -> Result<Option<ItemEditorSession>, String> {
    read_json_if_exists(&item_editor_session_path(repo_root))
}

pub fn write_item_editor_session(repo_root: &Path, pid: u32) -> Result<(), String> {
    write_json(
        &item_editor_session_path(repo_root),
        &ItemEditorSession {
            pid,
            updated_at_unix_ms: unix_timestamp_millis(),
        },
    )
}

pub fn clear_item_editor_session(repo_root: &Path) -> Result<(), String> {
    let path = item_editor_session_path(repo_root);
    if path.exists() {
        fs::remove_file(&path)
            .map_err(|error| format!("failed to remove {}: {error}", path.display()))?;
    }
    Ok(())
}

pub fn read_item_editor_selection_request(
    repo_root: &Path,
) -> Result<Option<ItemEditorSelectionRequest>, String> {
    read_json_if_exists(&item_editor_selection_request_path(repo_root))
}

pub fn clear_item_editor_selection_request(repo_root: &Path) -> Result<(), String> {
    let path = item_editor_selection_request_path(repo_root);
    if path.exists() {
        fs::remove_file(&path)
            .map_err(|error| format!("failed to remove {}: {error}", path.display()))?;
    }
    Ok(())
}

pub fn write_item_editor_selection_request(
    repo_root: &Path,
    item_id: u32,
) -> Result<ItemEditorSelectionRequest, String> {
    let request = ItemEditorSelectionRequest {
        request_id: format!("item-{}-{}", item_id, unix_timestamp_millis()),
        item_id,
        requested_at_unix_ms: unix_timestamp_millis(),
    };
    write_json(&item_editor_selection_request_path(repo_root), &request)?;
    Ok(request)
}

pub fn item_editor_session_is_recent(repo_root: &Path, max_age: Duration) -> Result<bool, String> {
    let Some(session) = read_item_editor_session(repo_root)? else {
        return Ok(false);
    };
    let now = unix_timestamp_millis();
    Ok(now.saturating_sub(session.updated_at_unix_ms) <= max_age.as_millis())
}

fn read_json_if_exists<T>(path: &Path) -> Result<Option<T>, String>
where
    T: for<'de> Deserialize<'de>,
{
    if !path.exists() {
        return Ok(None);
    }

    let raw = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let parsed = serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
    Ok(Some(parsed))
}

fn write_json<T>(path: &Path, value: &T) -> Result<(), String>
where
    T: Serialize,
{
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("failed to create {}: {error}", parent.display()))?;
    }
    let raw = serde_json::to_string_pretty(value)
        .map_err(|error| format!("failed to serialize {}: {error}", path.display()))?;
    fs::write(path, raw).map_err(|error| format!("failed to write {}: {error}", path.display()))
}

fn unix_timestamp_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_millis())
        .unwrap_or_default()
}
