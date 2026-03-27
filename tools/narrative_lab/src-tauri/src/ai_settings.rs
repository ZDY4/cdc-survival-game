use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};

const DEFAULT_BASE_URL: &str = "https://api.openai.com/v1";
const DEFAULT_MODEL: &str = "gpt-4.1-mini";
const DEFAULT_TIMEOUT_SEC: u64 = 45;
const DEFAULT_MAX_CONTEXT_RECORDS: usize = 24;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiSettings {
    pub base_url: String,
    pub model: String,
    pub api_key: String,
    pub timeout_sec: u64,
    pub max_context_records: usize,
}

impl Default for AiSettings {
    fn default() -> Self {
        Self {
            base_url: DEFAULT_BASE_URL.to_string(),
            model: DEFAULT_MODEL.to_string(),
            api_key: String::new(),
            timeout_sec: DEFAULT_TIMEOUT_SEC,
            max_context_records: DEFAULT_MAX_CONTEXT_RECORDS,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiConnectionTestResult {
    pub ok: bool,
    pub error: String,
}

impl AiSettings {
    pub fn normalized(mut self) -> Self {
        self.base_url = if self.base_url.trim().is_empty() {
            DEFAULT_BASE_URL.to_string()
        } else {
            self.base_url.trim().trim_end_matches('/').to_string()
        };
        self.model = if self.model.trim().is_empty() {
            DEFAULT_MODEL.to_string()
        } else {
            self.model.trim().to_string()
        };
        self.api_key = self.api_key.trim().to_string();
        self.timeout_sec = self.timeout_sec.max(5);
        self.max_context_records = self.max_context_records.max(6);
        self
    }

    pub fn effective_api_key(&self) -> String {
        if !self.api_key.trim().is_empty() {
            return self.api_key.trim().to_string();
        }

        for env_key in ["OPENAI_API_KEY", "AI_API_KEY"] {
            let value = std::env::var(env_key).unwrap_or_default();
            if !value.trim().is_empty() {
                return value.trim().to_string();
            }
        }

        String::new()
    }
}

#[tauri::command]
pub fn load_ai_settings(app: AppHandle) -> Result<AiSettings, String> {
    read_ai_settings(&app)
}

#[tauri::command]
pub fn save_ai_settings(app: AppHandle, settings: AiSettings) -> Result<AiSettings, String> {
    let normalized = settings.normalized();
    let path = ai_settings_path(&app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("failed to create {}: {error}", parent.display()))?;
    }

    let raw = serde_json::to_string_pretty(&normalized)
        .map_err(|error| format!("failed to serialize ai settings: {error}"))?;
    fs::write(&path, raw)
        .map_err(|error| format!("failed to write {}: {error}", path.display()))?;
    Ok(normalized)
}

pub fn read_ai_settings(app: &AppHandle) -> Result<AiSettings, String> {
    let path = ai_settings_path(app)?;
    if !path.exists() {
        return Ok(AiSettings::default());
    }

    let raw = fs::read_to_string(&path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let parsed: AiSettings = serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
    Ok(parsed.normalized())
}

fn ai_settings_path(app: &AppHandle) -> Result<PathBuf, String> {
    let config_dir = app
        .path()
        .app_config_dir()
        .map_err(|error| format!("failed to resolve app config dir: {error}"))?;
    Ok(config_dir.join("ai_settings.json"))
}
