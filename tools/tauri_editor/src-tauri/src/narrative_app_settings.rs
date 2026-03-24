use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};

const MAX_RECENT_PATHS: usize = 8;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeAppSettings {
    #[serde(default)]
    pub recent_workspaces: Vec<String>,
    #[serde(default)]
    pub last_workspace: Option<String>,
    #[serde(default)]
    pub connected_project_root: Option<String>,
    #[serde(default)]
    pub recent_project_roots: Vec<String>,
}

impl NarrativeAppSettings {
    pub fn normalized(mut self) -> Self {
        self.last_workspace = normalize_optional_path(self.last_workspace.as_deref());
        self.connected_project_root = normalize_optional_path(self.connected_project_root.as_deref());
        self.recent_workspaces = normalize_recent_paths(&self.recent_workspaces, self.last_workspace.as_deref());
        self.recent_project_roots =
            normalize_recent_paths(&self.recent_project_roots, self.connected_project_root.as_deref());
        self
    }
}

#[tauri::command]
pub fn load_narrative_app_settings(app: AppHandle) -> Result<NarrativeAppSettings, String> {
    read_narrative_app_settings(&app)
}

#[tauri::command]
pub fn save_narrative_app_settings(
    app: AppHandle,
    settings: NarrativeAppSettings,
) -> Result<NarrativeAppSettings, String> {
    let normalized = settings.normalized();
    let path = narrative_app_settings_path(&app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("failed to create {}: {error}", parent.display()))?;
    }

    let raw = serde_json::to_string_pretty(&normalized)
        .map_err(|error| format!("failed to serialize narrative app settings: {error}"))?;
    fs::write(&path, raw).map_err(|error| format!("failed to write {}: {error}", path.display()))?;
    Ok(normalized)
}

pub fn read_narrative_app_settings(app: &AppHandle) -> Result<NarrativeAppSettings, String> {
    let path = narrative_app_settings_path(app)?;
    if !path.exists() {
        return Ok(NarrativeAppSettings::default());
    }

    let raw = fs::read_to_string(&path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let parsed: NarrativeAppSettings = serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
    Ok(parsed.normalized())
}

fn narrative_app_settings_path(app: &AppHandle) -> Result<PathBuf, String> {
    let config_dir = app
        .path()
        .app_config_dir()
        .map_err(|error| format!("failed to resolve app config dir: {error}"))?;
    Ok(config_dir.join("narrative_app_settings.json"))
}

fn normalize_recent_paths(values: &[String], preferred: Option<&str>) -> Vec<String> {
    let mut result = Vec::new();
    if let Some(value) = normalize_optional_path(preferred) {
        result.push(value);
    }

    for value in values {
        let Some(normalized) = normalize_optional_path(Some(value.as_str())) else {
            continue;
        };
        if !result.contains(&normalized) {
            result.push(normalized);
        }
        if result.len() >= MAX_RECENT_PATHS {
            break;
        }
    }

    result
}

fn normalize_optional_path(raw: Option<&str>) -> Option<String> {
    let trimmed = raw.unwrap_or_default().trim();
    if trimmed.is_empty() {
        return None;
    }

    let candidate = PathBuf::from(trimmed);
    let resolved = if candidate.is_absolute() {
        candidate
    } else {
        std::env::current_dir().ok()?.join(candidate)
    };
    Some(resolved.to_string_lossy().replace('\\', "/"))
}
