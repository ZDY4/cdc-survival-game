use std::fs;
use std::path::PathBuf;
use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};

const MAX_RECENT_PATHS: usize = 8;

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct NarrativePanelLayoutItem {
    pub panel_id: String,
    pub x: i32,
    pub y: i32,
    pub w: i32,
    pub h: i32,
    #[serde(default)]
    pub min_w: Option<i32>,
    #[serde(default)]
    pub min_h: Option<i32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeWorkspaceLayout {
    #[serde(default = "default_layout_version")]
    pub version: u32,
    #[serde(default)]
    pub items: Vec<NarrativePanelLayoutItem>,
    #[serde(default)]
    pub collapsed_panels: Vec<String>,
    #[serde(default)]
    pub hidden_panels: Vec<String>,
}

impl Default for NarrativeWorkspaceLayout {
    fn default() -> Self {
        Self {
            version: default_layout_version(),
            items: Vec::new(),
            collapsed_panels: Vec::new(),
            hidden_panels: Vec::new(),
        }
    }
}

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
    #[serde(default)]
    pub workspace_layouts: HashMap<String, NarrativeWorkspaceLayout>,
}

impl NarrativeAppSettings {
    pub fn normalized(mut self) -> Self {
        self.last_workspace = normalize_optional_path(self.last_workspace.as_deref());
        self.connected_project_root = normalize_optional_path(self.connected_project_root.as_deref());
        self.recent_workspaces = normalize_recent_paths(&self.recent_workspaces, self.last_workspace.as_deref());
        self.recent_project_roots =
            normalize_recent_paths(&self.recent_project_roots, self.connected_project_root.as_deref());
        self.workspace_layouts = normalize_workspace_layouts(self.workspace_layouts);
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

fn default_layout_version() -> u32 {
    1
}

fn normalize_workspace_layouts(
    values: HashMap<String, NarrativeWorkspaceLayout>,
) -> HashMap<String, NarrativeWorkspaceLayout> {
    let mut normalized = HashMap::new();

    for (workspace_root, layout) in values {
        let Some(key) = normalize_optional_path(Some(workspace_root.as_str())) else {
            continue;
        };

        normalized.insert(
            key,
            NarrativeWorkspaceLayout {
                version: if layout.version == 0 {
                    default_layout_version()
                } else {
                    layout.version
                },
                items: layout.items,
                collapsed_panels: dedupe_strings(layout.collapsed_panels),
                hidden_panels: dedupe_strings(layout.hidden_panels),
            },
        );
    }

    normalized
}

fn dedupe_strings(values: Vec<String>) -> Vec<String> {
    let mut result = Vec::new();
    for value in values {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            continue;
        }
        let owned = trimmed.to_string();
        if !result.contains(&owned) {
            result.push(owned);
        }
    }
    result
}
