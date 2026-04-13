use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;
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
    #[serde(default = "current_layout_version")]
    pub version: u32,
    #[serde(default = "default_left_sidebar_visible")]
    pub left_sidebar_visible: bool,
    #[serde(default = "default_left_sidebar_width")]
    pub left_sidebar_width: i32,
    #[serde(default = "default_chat_panel_width")]
    pub chat_panel_width: i32,
    #[serde(default = "default_left_sidebar_view")]
    pub left_sidebar_view: String,
    #[serde(default = "default_right_sidebar_visible")]
    pub right_sidebar_visible: bool,
    #[serde(default = "default_right_sidebar_width")]
    pub right_sidebar_width: i32,
    #[serde(default = "default_right_sidebar_view")]
    pub right_sidebar_view: String,
    #[serde(default = "default_bottom_panel_visible")]
    pub bottom_panel_visible: bool,
    #[serde(default = "default_bottom_panel_height")]
    pub bottom_panel_height: i32,
    #[serde(default = "default_bottom_panel_view")]
    pub bottom_panel_view: String,
    #[serde(default)]
    pub open_document_keys: Vec<String>,
    #[serde(default)]
    pub active_document_key: Option<String>,
    #[serde(default)]
    pub zen_mode: bool,
    #[serde(default, skip_serializing)]
    pub items: Vec<NarrativePanelLayoutItem>,
    #[serde(default, skip_serializing)]
    pub collapsed_panels: Vec<String>,
    #[serde(default, skip_serializing)]
    pub hidden_panels: Vec<String>,
}

impl Default for NarrativeWorkspaceLayout {
    fn default() -> Self {
        Self {
            version: current_layout_version(),
            left_sidebar_visible: default_left_sidebar_visible(),
            left_sidebar_width: default_left_sidebar_width(),
            chat_panel_width: default_chat_panel_width(),
            left_sidebar_view: default_left_sidebar_view(),
            right_sidebar_visible: default_right_sidebar_visible(),
            right_sidebar_width: default_right_sidebar_width(),
            right_sidebar_view: default_right_sidebar_view(),
            bottom_panel_visible: default_bottom_panel_visible(),
            bottom_panel_height: default_bottom_panel_height(),
            bottom_panel_view: default_bottom_panel_view(),
            open_document_keys: Vec::new(),
            active_document_key: None,
            zen_mode: false,
            items: Vec::new(),
            collapsed_panels: Vec::new(),
            hidden_panels: Vec::new(),
        }
    }
}

impl NarrativeWorkspaceLayout {
    fn normalized(self) -> Self {
        let migrated_from_v1 = self.version < current_layout_version()
            || !self.items.is_empty()
            || !self.collapsed_panels.is_empty()
            || !self.hidden_panels.is_empty();

        if migrated_from_v1 {
            return Self::default();
        }

        let mut open_document_keys = dedupe_strings(self.open_document_keys);
        let active_document_key = normalize_optional_value(self.active_document_key.as_deref());
        if let Some(active_document_key) = active_document_key.as_ref() {
            if !open_document_keys.contains(active_document_key) {
                open_document_keys.insert(0, active_document_key.clone());
            }
        }

        Self {
            version: current_layout_version(),
            left_sidebar_visible: self.left_sidebar_visible,
            left_sidebar_width: clamp_i32(self.left_sidebar_width, 220, 460),
            chat_panel_width: clamp_i32(self.chat_panel_width, 320, 720),
            left_sidebar_view: normalize_left_sidebar_view(self.left_sidebar_view),
            right_sidebar_visible: self.right_sidebar_visible,
            right_sidebar_width: clamp_i32(self.right_sidebar_width, 260, 520),
            right_sidebar_view: normalize_right_sidebar_view(self.right_sidebar_view),
            bottom_panel_visible: self.bottom_panel_visible,
            bottom_panel_height: clamp_i32(self.bottom_panel_height, 180, 440),
            bottom_panel_view: normalize_bottom_panel_view(self.bottom_panel_view),
            open_document_keys,
            active_document_key,
            zen_mode: self.zen_mode,
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
    #[serde(default = "default_session_restore_mode")]
    pub session_restore_mode: String,
    #[serde(default)]
    pub workspace_layouts: HashMap<String, NarrativeWorkspaceLayout>,
    #[serde(default)]
    pub workspace_agent_sessions: HashMap<String, Value>,
}

impl NarrativeAppSettings {
    pub fn normalized(mut self) -> Self {
        self.last_workspace = normalize_optional_path(self.last_workspace.as_deref());
        self.connected_project_root =
            normalize_optional_path(self.connected_project_root.as_deref());
        self.recent_workspaces =
            normalize_recent_paths(&self.recent_workspaces, self.last_workspace.as_deref());
        self.recent_project_roots = normalize_recent_paths(
            &self.recent_project_roots,
            self.connected_project_root.as_deref(),
        );
        self.session_restore_mode = normalize_session_restore_mode(&self.session_restore_mode);
        self.workspace_layouts = normalize_workspace_layouts(self.workspace_layouts);
        self.workspace_agent_sessions =
            normalize_workspace_agent_sessions(self.workspace_agent_sessions);
        self
    }

    pub fn with_inferred_defaults(mut self) -> Self {
        let inferred = infer_default_narrative_app_settings();

        if self.last_workspace.is_none() {
            self.last_workspace = inferred.last_workspace;
        }
        if self.connected_project_root.is_none() {
            self.connected_project_root = inferred.connected_project_root;
        }

        if let Some(workspace_root) =
            normalize_optional_path(std::env::var("CDC_NARRATIVE_WORKSPACE_ROOT").ok().as_deref())
        {
            self.last_workspace = Some(workspace_root);
        }
        if let Some(project_root) =
            normalize_optional_path(std::env::var("CDC_NARRATIVE_PROJECT_ROOT").ok().as_deref())
        {
            self.connected_project_root = Some(project_root);
        }

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
    fs::write(&path, raw)
        .map_err(|error| format!("failed to write {}: {error}", path.display()))?;
    Ok(normalized)
}

pub fn read_narrative_app_settings(app: &AppHandle) -> Result<NarrativeAppSettings, String> {
    let path = narrative_app_settings_path(app)?;
    if !path.exists() {
        return Ok(NarrativeAppSettings::default()
            .with_inferred_defaults()
            .normalized());
    }

    let raw = fs::read_to_string(&path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let parsed: NarrativeAppSettings = serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
    Ok(parsed.with_inferred_defaults().normalized())
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
    Some(to_forward_slashes(resolved))
}

fn infer_default_narrative_app_settings() -> NarrativeAppSettings {
    let current_dir = std::env::current_dir().ok();
    infer_default_narrative_app_settings_from_base(current_dir.as_deref())
}

fn infer_default_narrative_app_settings_from_base(base_dir: Option<&Path>) -> NarrativeAppSettings {
    let project_root = base_dir.and_then(find_connected_project_root);
    let workspace_root = project_root
        .as_deref()
        .and_then(find_workspace_root_within_project)
        .or_else(|| base_dir.and_then(find_workspace_root_from_ancestors));

    NarrativeAppSettings {
        recent_workspaces: Vec::new(),
        last_workspace: workspace_root.map(to_forward_slashes),
        connected_project_root: project_root.map(to_forward_slashes),
        recent_project_roots: Vec::new(),
        session_restore_mode: default_session_restore_mode(),
        workspace_layouts: HashMap::new(),
        workspace_agent_sessions: HashMap::new(),
    }
}

fn find_connected_project_root(base_dir: &Path) -> Option<PathBuf> {
    base_dir
        .ancestors()
        .find(|path| path.join("project.godot").is_file())
        .and_then(resolve_existing_dir)
}

fn find_workspace_root_within_project(project_root: &Path) -> Option<PathBuf> {
    resolve_existing_dir(&project_root.join("docs").join("narrative"))
}

fn find_workspace_root_from_ancestors(base_dir: &Path) -> Option<PathBuf> {
    base_dir
        .ancestors()
        .find_map(|path| resolve_existing_dir(&path.join("docs").join("narrative")))
}

fn resolve_existing_dir(path: &Path) -> Option<PathBuf> {
    if !path.is_dir() {
        return None;
    }

    path.canonicalize()
        .ok()
        .or_else(|| Some(path.to_path_buf()))
}

fn to_forward_slashes(path: PathBuf) -> String {
    let raw = path.to_string_lossy().replace('\\', "/");
    if let Some(stripped) = raw.strip_prefix("//?/UNC/") {
        return format!("//{stripped}");
    }
    if let Some(stripped) = raw.strip_prefix("//?/") {
        return stripped.to_string();
    }
    raw
}

fn current_layout_version() -> u32 {
    2
}

fn normalize_workspace_layouts(
    values: HashMap<String, NarrativeWorkspaceLayout>,
) -> HashMap<String, NarrativeWorkspaceLayout> {
    let mut normalized = HashMap::new();

    for (workspace_root, layout) in values {
        let Some(key) = normalize_optional_path(Some(workspace_root.as_str())) else {
            continue;
        };

        normalized.insert(key, layout.normalized());
    }

    normalized
}

fn normalize_workspace_agent_sessions(values: HashMap<String, Value>) -> HashMap<String, Value> {
    let mut normalized = HashMap::new();
    for (workspace_root, payload) in values {
        let Some(key) = normalize_optional_path(Some(workspace_root.as_str())) else {
            continue;
        };
        if payload.is_object() {
            normalized.insert(key, payload);
        }
    }
    normalized
}

fn default_left_sidebar_visible() -> bool {
    true
}

fn default_left_sidebar_width() -> i32 {
    300
}

fn default_left_sidebar_view() -> String {
    "explorer".to_string()
}

fn default_chat_panel_width() -> i32 {
    440
}

fn default_right_sidebar_visible() -> bool {
    true
}

fn default_right_sidebar_width() -> i32 {
    320
}

fn default_right_sidebar_view() -> String {
    "inspector".to_string()
}

fn default_bottom_panel_visible() -> bool {
    true
}

fn default_bottom_panel_height() -> i32 {
    220
}

fn default_bottom_panel_view() -> String {
    "problems".to_string()
}

fn default_session_restore_mode() -> String {
    "ask".to_string()
}

fn normalize_session_restore_mode(value: &str) -> String {
    match value.trim() {
        "always" => "always".to_string(),
        "documents_only" => "documents_only".to_string(),
        _ => default_session_restore_mode(),
    }
}

fn clamp_i32(value: i32, min: i32, max: i32) -> i32 {
    value.clamp(min, max)
}

fn normalize_optional_value(raw: Option<&str>) -> Option<String> {
    let trimmed = raw.unwrap_or_default().trim();
    if trimmed.is_empty() {
        return None;
    }
    Some(trimmed.to_string())
}

fn normalize_left_sidebar_view(value: String) -> String {
    match value.trim() {
        "explorer" | "search" | "outline" | "ai" | "session" => value.trim().to_string(),
        _ => default_left_sidebar_view(),
    }
}

fn normalize_right_sidebar_view(value: String) -> String {
    match value.trim() {
        "inspector" | "review" | "bundle" | "session" => value.trim().to_string(),
        _ => default_right_sidebar_view(),
    }
}

fn normalize_bottom_panel_view(value: String) -> String {
    match value.trim() {
        "problems" | "ai_runs" | "prompt_debug" | "bundle_preview" => value.trim().to_string(),
        _ => default_bottom_panel_view(),
    }
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

#[cfg(test)]
mod tests {
    use super::{
        infer_default_narrative_app_settings_from_base, normalize_workspace_layouts,
        NarrativeAppSettings, NarrativePanelLayoutItem, NarrativeWorkspaceLayout,
    };
    use std::collections::HashMap;
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn infers_workspace_and_project_roots_from_repo_layout() {
        let root = unique_temp_dir("narrative-app-settings-infer");
        let repo_root = root.join("cdc_survival_game");
        let editor_root = repo_root.join("tools").join("narrative_lab");
        let workspace_root = repo_root.join("docs").join("narrative");

        fs::create_dir_all(&editor_root).unwrap();
        fs::create_dir_all(&workspace_root).unwrap();
        fs::write(repo_root.join("project.godot"), "").unwrap();

        let inferred = infer_default_narrative_app_settings_from_base(Some(&editor_root));

        assert_eq!(
            inferred.last_workspace.as_deref(),
            Some(workspace_root.to_string_lossy().replace('\\', "/").as_str())
        );
        assert_eq!(
            inferred.connected_project_root.as_deref(),
            Some(repo_root.to_string_lossy().replace('\\', "/").as_str())
        );

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn preserves_user_paths_when_defaults_are_merged() {
        let settings = NarrativeAppSettings {
            last_workspace: Some("G:/custom/workspace".to_string()),
            connected_project_root: Some("G:/custom/project".to_string()),
            ..NarrativeAppSettings::default()
        };

        let merged = settings.with_inferred_defaults();

        assert_eq!(
            merged.last_workspace.as_deref(),
            Some("G:/custom/workspace")
        );
        assert_eq!(
            merged.connected_project_root.as_deref(),
            Some("G:/custom/project")
        );
    }

    #[test]
    fn migrates_v1_workspace_layouts_to_v2_defaults() {
        let layouts = HashMap::from([(
            "D:/repo/docs/narrative".to_string(),
            NarrativeWorkspaceLayout {
                version: 1,
                items: vec![NarrativePanelLayoutItem {
                    panel_id: "library".to_string(),
                    x: 0,
                    y: 0,
                    w: 4,
                    h: 8,
                    min_w: None,
                    min_h: None,
                }],
                collapsed_panels: vec!["review".to_string()],
                hidden_panels: vec!["dock".to_string()],
                ..NarrativeWorkspaceLayout::default()
            },
        )]);

        let normalized = normalize_workspace_layouts(layouts);
        let layout = normalized.get("D:/repo/docs/narrative").unwrap();

        assert_eq!(layout.version, 2);
        assert!(layout.left_sidebar_visible);
        assert!(layout.right_sidebar_visible);
        assert!(layout.bottom_panel_visible);
        assert_eq!(layout.left_sidebar_view, "explorer");
        assert_eq!(layout.chat_panel_width, 440);
        assert_eq!(layout.right_sidebar_view, "inspector");
        assert_eq!(layout.bottom_panel_view, "problems");
        assert!(layout.open_document_keys.is_empty());
        assert!(layout.items.is_empty());
    }

    #[test]
    fn normalizes_v2_workspace_layout_values() {
        let layouts = HashMap::from([(
            "D:/repo/docs/narrative".to_string(),
            NarrativeWorkspaceLayout {
                version: 2,
                left_sidebar_width: 999,
                chat_panel_width: 999,
                left_sidebar_view: "unknown".to_string(),
                right_sidebar_width: 80,
                right_sidebar_view: "review".to_string(),
                bottom_panel_height: 1000,
                bottom_panel_view: "mystery".to_string(),
                open_document_keys: vec![
                    "scene/intro".to_string(),
                    "scene/intro".to_string(),
                    "scene/outro".to_string(),
                ],
                active_document_key: Some("scene/finale".to_string()),
                ..NarrativeWorkspaceLayout::default()
            },
        )]);

        let normalized = normalize_workspace_layouts(layouts);
        let layout = normalized.get("D:/repo/docs/narrative").unwrap();

        assert_eq!(layout.version, 2);
        assert_eq!(layout.left_sidebar_width, 460);
        assert_eq!(layout.chat_panel_width, 720);
        assert_eq!(layout.left_sidebar_view, "explorer");
        assert_eq!(layout.right_sidebar_width, 260);
        assert_eq!(layout.right_sidebar_view, "review");
        assert_eq!(layout.bottom_panel_height, 440);
        assert_eq!(layout.bottom_panel_view, "problems");
        assert_eq!(
            layout.open_document_keys,
            vec![
                "scene/finale".to_string(),
                "scene/intro".to_string(),
                "scene/outro".to_string()
            ]
        );
        assert_eq!(layout.active_document_key.as_deref(), Some("scene/finale"));
    }

    fn unique_temp_dir(prefix: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!("{prefix}-{nanos}"))
    }
}
