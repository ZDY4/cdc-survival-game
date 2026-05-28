use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

const HANDOFF_DIR: &str = "tmp/editor_handoff";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EditorKind {
    Item,
    Recipe,
    Dialogue,
    Quest,
    Skill,
    Character,
    Map,
    GltfViewer,
}

impl EditorKind {
    fn file_stem(self) -> &'static str {
        match self {
            Self::Item => "bevy_item_editor",
            Self::Recipe => "bevy_recipe_editor",
            Self::Dialogue => "bevy_dialogue_editor",
            Self::Quest => "bevy_quest_editor",
            Self::Skill => "bevy_skill_editor",
            Self::Character => "bevy_character_editor",
            Self::Map => "bevy_map_editor",
            Self::GltfViewer => "bevy_gltf_viewer",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EditorNavigationAction {
    SelectRecord,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EditorSession {
    pub editor: EditorKind,
    pub pid: u32,
    pub updated_at_unix_ms: u128,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EditorNavigationRequest {
    pub request_id: String,
    pub target_editor: EditorKind,
    pub action: EditorNavigationAction,
    pub target_kind: String,
    pub target_id: String,
    pub requested_at_unix_ms: u128,
}

pub fn editor_session_path(repo_root: &Path, editor: EditorKind) -> PathBuf {
    repo_root
        .join(HANDOFF_DIR)
        .join(format!("{}.session.json", editor.file_stem()))
}

pub fn editor_navigation_request_path(repo_root: &Path, target_editor: EditorKind) -> PathBuf {
    repo_root
        .join(HANDOFF_DIR)
        .join(format!("{}.navigation.json", target_editor.file_stem()))
}

pub fn read_editor_session(
    repo_root: &Path,
    editor: EditorKind,
) -> Result<Option<EditorSession>, String> {
    read_json_if_exists(&editor_session_path(repo_root, editor))
}

pub fn write_editor_session(repo_root: &Path, editor: EditorKind, pid: u32) -> Result<(), String> {
    write_json(
        &editor_session_path(repo_root, editor),
        &EditorSession {
            editor,
            pid,
            updated_at_unix_ms: unix_timestamp_millis(),
        },
    )
}

pub fn clear_editor_session(repo_root: &Path, editor: EditorKind) -> Result<(), String> {
    remove_file_if_exists(&editor_session_path(repo_root, editor))
}

pub fn read_editor_navigation_request(
    repo_root: &Path,
    target_editor: EditorKind,
) -> Result<Option<EditorNavigationRequest>, String> {
    read_json_if_exists(&editor_navigation_request_path(repo_root, target_editor))
}

pub fn clear_editor_navigation_request(
    repo_root: &Path,
    target_editor: EditorKind,
) -> Result<(), String> {
    remove_file_if_exists(&editor_navigation_request_path(repo_root, target_editor))
}

pub fn write_editor_navigation_request(
    repo_root: &Path,
    target_editor: EditorKind,
    action: EditorNavigationAction,
    target_kind: impl Into<String>,
    target_id: impl Into<String>,
) -> Result<EditorNavigationRequest, String> {
    let target_kind = target_kind.into();
    let target_id = target_id.into();
    let request = EditorNavigationRequest {
        request_id: format!(
            "{}-{}-{}",
            target_editor.file_stem(),
            target_kind,
            unix_timestamp_millis()
        ),
        target_editor,
        action,
        target_kind,
        target_id,
        requested_at_unix_ms: unix_timestamp_millis(),
    };
    write_json(
        &editor_navigation_request_path(repo_root, target_editor),
        &request,
    )?;
    Ok(request)
}

pub fn editor_session_is_recent(
    repo_root: &Path,
    editor: EditorKind,
    max_age: Duration,
) -> Result<bool, String> {
    let Some(session) = read_editor_session(repo_root, editor)? else {
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

fn remove_file_if_exists(path: &Path) -> Result<(), String> {
    if path.exists() {
        fs::remove_file(path)
            .map_err(|error| format!("failed to remove {}: {error}", path.display()))?;
    }
    Ok(())
}

fn unix_timestamp_millis() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|value| value.as_millis())
        .unwrap_or_default()
}
