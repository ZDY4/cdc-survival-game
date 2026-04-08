use std::fs;
use std::path::PathBuf;
use std::sync::{
    mpsc::{self, Receiver, TryRecvError},
    Arc, Mutex,
};
use std::thread;
use std::time::Duration;

use bevy::prelude::Resource;
use bevy_egui::egui;
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};

pub const DEFAULT_BASE_URL: &str = "https://api.openai.com/v1";
pub const DEFAULT_MODEL: &str = "gpt-4.1-mini";
pub const DEFAULT_TIMEOUT_SEC: u64 = 45;
pub const DEFAULT_MAX_CONTEXT_RECORDS: usize = 24;
const CHAT_COMPLETIONS_PATH: &str = "/chat/completions";
const MODELS_PATH: &str = "/models";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiChatSettings {
    pub base_url: String,
    pub model: String,
    pub api_key: String,
    pub timeout_sec: u64,
    pub max_context_records: usize,
}

impl Default for AiChatSettings {
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

impl AiChatSettings {
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AiChatRole {
    System,
    User,
    Assistant,
}

impl AiChatRole {
    pub fn label(self) -> &'static str {
        match self {
            Self::System => "System",
            Self::User => "User",
            Self::Assistant => "Assistant",
        }
    }

    fn request_role(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::User => "user",
            Self::Assistant => "assistant",
        }
    }
}

#[derive(Debug, Clone)]
pub struct AiChatMessage {
    pub role: AiChatRole,
    pub content: String,
}

#[derive(Debug, Clone)]
pub struct AiPromptSubmission {
    pub settings: AiChatSettings,
    pub prompt: String,
    pub conversation: Vec<AiChatMessage>,
}

#[derive(Resource, Debug)]
pub struct AiChatState<TResult> {
    pub app_id: String,
    pub settings: AiChatSettings,
    pub prompt_input: String,
    pub conversation: Vec<AiChatMessage>,
    pub result: Option<TResult>,
    pub provider_status: String,
    pub pending_status: String,
    pub show_settings_window: bool,
    pub scroll_to_bottom: bool,
}

impl<TResult> AiChatState<TResult> {
    pub fn new(app_id: impl Into<String>, settings: AiChatSettings) -> Self {
        Self {
            app_id: app_id.into(),
            settings,
            prompt_input: String::new(),
            conversation: Vec::new(),
            result: None,
            provider_status: String::new(),
            pending_status: String::new(),
            show_settings_window: false,
            scroll_to_bottom: false,
        }
    }

    pub fn load(app_id: impl Into<String>) -> Self {
        let app_id = app_id.into();
        let settings = load_ai_chat_settings(&app_id).unwrap_or_else(|_| AiChatSettings::default());
        Self::new(app_id, settings)
    }

    pub fn push_chat_message(&mut self, role: AiChatRole, content: impl Into<String>) {
        let content = content.into();
        if content.trim().is_empty() {
            return;
        }
        self.conversation.push(AiChatMessage { role, content });
        self.scroll_to_bottom = true;
        let max_messages = self.settings.max_context_records.max(6);
        let overflow = self.conversation.len().saturating_sub(max_messages);
        if overflow > 0 {
            self.conversation.drain(0..overflow);
        }
    }

    pub fn clear_result(&mut self) {
        self.result = None;
    }
}

#[derive(Debug)]
pub struct ProviderSuccess {
    pub raw_text: String,
    pub payload: Value,
}

#[derive(Debug)]
pub struct ProviderFailure {
    pub status_code: u16,
    pub error: String,
}

enum AiWorkerMessage<TResult> {
    ConnectionTest(Result<String, String>),
    Generation(Result<TResult, String>),
}

#[derive(Resource)]
pub struct AiChatWorkerState<TResult> {
    receiver: Option<Arc<Mutex<Receiver<AiWorkerMessage<TResult>>>>>,
}

impl<TResult> Default for AiChatWorkerState<TResult> {
    fn default() -> Self {
        Self { receiver: None }
    }
}

impl<TResult> AiChatWorkerState<TResult> {
    pub fn is_busy(&self) -> bool {
        self.receiver.is_some()
    }
}

pub enum AiChatUiAction<THostAction = ()> {
    OpenSettings,
    SaveSettings,
    TestConnection,
    SubmitPrompt,
    Host(THostAction),
}

pub fn prepare_prompt_submission<TResult>(
    ai: &mut AiChatState<TResult>,
) -> Result<AiPromptSubmission, String> {
    if ai.prompt_input.trim().is_empty() {
        return Err("Prompt cannot be empty.".to_string());
    }

    let submission = AiPromptSubmission {
        settings: ai.settings.clone().normalized(),
        prompt: ai.prompt_input.trim().to_string(),
        conversation: ai.conversation.clone(),
    };
    ai.push_chat_message(AiChatRole::User, submission.prompt.clone());
    ai.prompt_input.clear();
    Ok(submission)
}

pub fn render_ai_chat_panel<TResult, THostAction, F>(
    ui: &mut egui::Ui,
    ai: &mut AiChatState<TResult>,
    busy: bool,
    title: &str,
    submit_label: &str,
    mut render_result: F,
) -> Vec<AiChatUiAction<THostAction>>
where
    F: FnMut(&mut egui::Ui, &TResult, bool) -> Option<THostAction>,
{
    let mut actions = Vec::new();
    let should_scroll_to_bottom = ai.scroll_to_bottom;

    ui.set_width(ui.available_width());
    ui.vertical(|ui| {
        ui.horizontal(|ui| {
            ui.strong(title);
            ui.label(format!("Model: {}", ai.settings.model));
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                if ui.button("Settings").clicked() {
                    actions.push(AiChatUiAction::OpenSettings);
                }
            });
        });
        ui.separator();

        ui.allocate_ui_with_layout(
            egui::vec2(ui.available_width(), ui.available_height().max(0.0)),
            egui::Layout::bottom_up(egui::Align::Min),
            |ui| {
                ui.group(|ui| {
                    ui.set_width(ui.available_width());
                    ui.add_sized(
                        [ui.available_width(), 112.0],
                        egui::TextEdit::multiline(&mut ai.prompt_input)
                            .desired_rows(5)
                            .hint_text("Describe the change you want..."),
                    );
                    ui.add_space(6.0);
                    ui.horizontal(|ui| {
                        if busy && !ai.pending_status.is_empty() {
                            ui.label(&ai.pending_status);
                        } else {
                            ui.label(" ");
                        }
                        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                            if ui
                                .add_enabled(!busy, egui::Button::new(submit_label))
                                .clicked()
                            {
                                actions.push(AiChatUiAction::SubmitPrompt);
                            }
                        });
                    });
                });

                ui.separator();

                ui.allocate_ui_with_layout(
                    egui::vec2(ui.available_width(), ui.available_height().max(0.0)),
                    egui::Layout::top_down(egui::Align::Min),
                    |ui| {
                        egui::ScrollArea::vertical()
                            .id_salt(format!("{}_chat_messages", ai.app_id))
                            .auto_shrink([false, false])
                            .stick_to_bottom(should_scroll_to_bottom)
                            .show(ui, |ui| {
                                ui.set_width(ui.available_width());
                                if ai.conversation.is_empty() && ai.result.is_none() {
                                    render_empty_chat_state(ui, title);
                                } else {
                                    for message in &ai.conversation {
                                        render_chat_message(ui, message);
                                        ui.add_space(8.0);
                                    }
                                    if let Some(result) = ai.result.as_ref() {
                                        if let Some(host_action) = render_result_message(
                                            ui,
                                            result,
                                            busy,
                                            &mut render_result,
                                        ) {
                                            actions.push(AiChatUiAction::Host(host_action));
                                        }
                                    }
                                }
                            });
                    },
                );
            },
        );
    });

    ai.scroll_to_bottom = false;
    actions
}

fn render_empty_chat_state(ui: &mut egui::Ui, title: &str) {
    let empty_height = ui.available_height().max(180.0);
    ui.allocate_ui_with_layout(
        egui::vec2(ui.available_width(), empty_height),
        egui::Layout::top_down(egui::Align::Center),
        |ui| {
            ui.add_space(empty_height * 0.3);
            ui.vertical_centered(|ui| {
                ui.strong(format!("{title} is ready"));
                ui.label("Start a conversation below to generate a new result.");
            });
        },
    );
}

fn render_chat_message(ui: &mut egui::Ui, message: &AiChatMessage) {
    ui.group(|ui| {
        ui.set_width(ui.available_width());
        ui.horizontal(|ui| {
            ui.strong(message.role.label());
        });
        ui.add_space(4.0);
        ui.label(&message.content);
    });
}

fn render_result_message<TResult, THostAction, F>(
    ui: &mut egui::Ui,
    result: &TResult,
    busy: bool,
    render_result: &mut F,
) -> Option<THostAction>
where
    F: FnMut(&mut egui::Ui, &TResult, bool) -> Option<THostAction>,
{
    let mut action = None;
    ui.group(|ui| {
        ui.set_width(ui.available_width());
        ui.horizontal(|ui| {
            ui.strong("Assistant");
            ui.label("Latest result");
        });
        ui.add_space(4.0);
        action = render_result(ui, result, busy);
    });
    action
}

pub fn render_ai_settings_window<TResult>(
    ctx: &egui::Context,
    ai: &mut AiChatState<TResult>,
    busy: bool,
) -> Vec<AiChatUiAction> {
    let mut actions = Vec::new();
    if !ai.show_settings_window {
        return actions;
    }

    let mut open = ai.show_settings_window;
    egui::Window::new("AI Settings")
        .open(&mut open)
        .collapsible(false)
        .resizable(true)
        .default_width(420.0)
        .show(ctx, |ui| {
            ui.label("Base URL");
            ui.text_edit_singleline(&mut ai.settings.base_url);
            ui.label("Model");
            ui.text_edit_singleline(&mut ai.settings.model);
            ui.label("API Key");
            ui.add(egui::TextEdit::singleline(&mut ai.settings.api_key).password(true));
            ui.label("Timeout (sec)");
            ui.add(egui::DragValue::new(&mut ai.settings.timeout_sec).range(5..=300));
            ui.label("Context messages");
            ui.add(egui::DragValue::new(&mut ai.settings.max_context_records).range(6..=128));

            ui.separator();
            ui.horizontal(|ui| {
                if ui.button("Save Settings").clicked() {
                    actions.push(AiChatUiAction::SaveSettings);
                }
                if ui
                    .add_enabled(!busy, egui::Button::new("Test Connection"))
                    .clicked()
                {
                    actions.push(AiChatUiAction::TestConnection);
                }
            });

            if !ai.provider_status.is_empty() {
                ui.separator();
                ui.label(&ai.provider_status);
            }
            if !ai.pending_status.is_empty() {
                ui.label(&ai.pending_status);
            }
        });
    ai.show_settings_window = open;
    actions
}

pub fn load_ai_chat_settings(app_id: &str) -> Result<AiChatSettings, String> {
    let path = ai_settings_path(app_id);
    if !path.exists() {
        return Ok(AiChatSettings::default());
    }
    let raw = fs::read_to_string(&path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let parsed: AiChatSettings = serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
    Ok(parsed.normalized())
}

pub fn save_ai_chat_settings(app_id: &str, settings: &AiChatSettings) -> Result<(), String> {
    let path = ai_settings_path(app_id);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("failed to create {}: {error}", parent.display()))?;
    }
    let raw = serde_json::to_string_pretty(&settings.clone().normalized())
        .map_err(|error| format!("failed to serialize AI settings: {error}"))?;
    fs::write(&path, raw).map_err(|error| format!("failed to write {}: {error}", path.display()))
}

pub fn persist_ai_chat_settings<TResult>(ai: &mut AiChatState<TResult>) -> Result<String, String> {
    let normalized = ai.settings.clone().normalized();
    save_ai_chat_settings(&ai.app_id, &normalized)?;
    ai.settings = normalized;
    Ok(format!(
        "Saved AI settings to {}.",
        ai_settings_path(&ai.app_id).display()
    ))
}

pub fn start_connection_test<TResult: Send + 'static>(
    ai: &mut AiChatState<TResult>,
    worker: &mut AiChatWorkerState<TResult>,
) {
    let settings = ai.settings.clone().normalized();
    ai.pending_status = "Testing AI provider connection...".to_string();
    let (sender, receiver) = mpsc::channel();
    worker.receiver = Some(Arc::new(Mutex::new(receiver)));
    thread::spawn(move || {
        let _ = sender.send(AiWorkerMessage::ConnectionTest(
            test_ai_provider_connection(&settings),
        ));
    });
}

pub fn start_generation_job<TResult, TParse>(
    ai: &mut AiChatState<TResult>,
    worker: &mut AiChatWorkerState<TResult>,
    pending_status: impl Into<String>,
    payload: Value,
    parse_result: TParse,
) where
    TResult: Send + 'static,
    TParse: FnOnce(ProviderSuccess) -> Result<TResult, String> + Send + 'static,
{
    let settings = ai.settings.clone().normalized();
    ai.pending_status = pending_status.into();
    ai.provider_status.clear();
    ai.result = None;

    let (sender, receiver) = mpsc::channel();
    worker.receiver = Some(Arc::new(Mutex::new(receiver)));
    thread::spawn(move || {
        let result = perform_chat_completion(&settings, &payload)
            .map_err(|error| normalize_provider_error(&error))
            .and_then(parse_result);
        let _ = sender.send(AiWorkerMessage::Generation(result));
    });
}

pub fn poll_generation_job<TResult, TAssistant, TStatus>(
    ai: &mut AiChatState<TResult>,
    worker: &mut AiChatWorkerState<TResult>,
    assistant_message: TAssistant,
    success_status: TStatus,
) where
    TAssistant: Fn(&TResult) -> String,
    TStatus: Fn(&TResult) -> String,
{
    let Some(receiver) = worker.receiver.as_ref().cloned() else {
        return;
    };
    let message = match receiver.lock() {
        Ok(guard) => match guard.try_recv() {
            Ok(message) => Some(message),
            Err(TryRecvError::Empty) => None,
            Err(TryRecvError::Disconnected) => {
                ai.pending_status.clear();
                ai.provider_status = "AI worker disconnected.".to_string();
                worker.receiver = None;
                return;
            }
        },
        Err(_) => {
            ai.pending_status.clear();
            ai.provider_status = "AI worker lock poisoned.".to_string();
            worker.receiver = None;
            return;
        }
    };
    let Some(message) = message else {
        return;
    };

    worker.receiver = None;
    ai.pending_status.clear();
    match message {
        AiWorkerMessage::ConnectionTest(result) => {
            ai.provider_status = result.unwrap_or_else(|error| error);
        }
        AiWorkerMessage::Generation(result) => match result {
            Ok(result) => {
                ai.push_chat_message(AiChatRole::Assistant, assistant_message(&result));
                ai.provider_status = success_status(&result);
                ai.result = Some(result);
            }
            Err(error) => {
                ai.push_chat_message(AiChatRole::System, format!("Generation failed: {error}"));
                ai.provider_status = error;
                ai.result = None;
            }
        },
    }
}

pub fn conversation_payload(messages: &[AiChatMessage]) -> Vec<Value> {
    messages
        .iter()
        .map(|message| {
            json!({
                "role": message.role.request_role(),
                "content": message.content,
            })
        })
        .collect()
}

fn ai_settings_path(app_id: &str) -> PathBuf {
    if let Ok(app_data) = std::env::var("APPDATA") {
        let trimmed = app_data.trim();
        if !trimmed.is_empty() {
            return PathBuf::from(trimmed)
                .join("cdc-survival-game")
                .join(app_id)
                .join("ai_settings.json");
        }
    }

    let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..");
    repo_root
        .join(".local")
        .join(app_id)
        .join("ai_settings.json")
}

fn test_ai_provider_connection(settings: &AiChatSettings) -> Result<String, String> {
    let settings = settings.clone().normalized();
    let base_url = settings.base_url.trim().trim_end_matches('/').to_string();
    let api_key = settings.effective_api_key();
    if base_url.is_empty() {
        return Err("Base URL cannot be empty.".to_string());
    }
    if api_key.is_empty() {
        return Err("API key is not configured.".to_string());
    }

    let client = build_http_client(settings.timeout_sec)?;
    let response = client
        .get(format!("{base_url}{MODELS_PATH}"))
        .bearer_auth(api_key)
        .header("Accept", "application/json")
        .send();

    match response {
        Ok(response) if response.status().is_success() => {
            Ok("AI provider connection succeeded.".to_string())
        }
        Ok(response) => {
            let status = response.status().as_u16();
            let body = response.text().unwrap_or_default();
            Err(map_http_error(status, &body))
        }
        Err(error) => Err(format!("Network failure: {error}")),
    }
}

fn perform_chat_completion(
    settings: &AiChatSettings,
    payload: &Value,
) -> Result<ProviderSuccess, ProviderFailure> {
    let provider_config = payload
        .get("provider_config")
        .and_then(Value::as_object)
        .cloned()
        .unwrap_or_default();
    let base_url = provider_config
        .get("base_url")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .trim_end_matches('/')
        .to_string();
    let api_key = provider_config
        .get("api_key")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();
    let model = provider_config
        .get("model")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    if base_url.is_empty() {
        return Err(ProviderFailure {
            status_code: 0,
            error: "Base URL cannot be empty.".to_string(),
        });
    }
    if model.is_empty() {
        return Err(ProviderFailure {
            status_code: 0,
            error: "Model cannot be empty.".to_string(),
        });
    }
    if api_key.is_empty() {
        return Err(ProviderFailure {
            status_code: 0,
            error: "API key is not configured.".to_string(),
        });
    }

    let client = build_http_client(settings.timeout_sec).map_err(|error| ProviderFailure {
        status_code: 0,
        error,
    })?;
    let request_body = json!({
        "model": model,
        "messages": payload.get("messages").cloned().unwrap_or_else(|| json!([])),
        "temperature": payload.get("temperature").and_then(Value::as_f64).unwrap_or(0.2),
        "response_format": { "type": "json_object" },
        "max_tokens": payload.get("max_tokens").and_then(Value::as_u64).unwrap_or(2600),
    });

    for attempt in 0..=1 {
        let response = client
            .post(format!("{base_url}{CHAT_COMPLETIONS_PATH}"))
            .bearer_auth(&api_key)
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .json(&request_body)
            .send();

        match response {
            Ok(response) => {
                let status = response.status().as_u16();
                let raw_body = response.text().unwrap_or_default();
                if !(200..300).contains(&status) {
                    if attempt == 0 && (status == 429 || status >= 500) {
                        thread::sleep(Duration::from_secs(1));
                        continue;
                    }
                    return Err(ProviderFailure {
                        status_code: status,
                        error: map_http_error(status, &raw_body),
                    });
                }

                let response_data: Value =
                    serde_json::from_str(&raw_body).map_err(|error| ProviderFailure {
                        status_code: status,
                        error: format!("Response is not valid JSON: {error}"),
                    })?;
                let raw_content = extract_message_content(&response_data);
                let payload =
                    extract_json_payload(&raw_content).map_err(|error| ProviderFailure {
                        status_code: status,
                        error,
                    })?;

                return Ok(ProviderSuccess {
                    raw_text: raw_content,
                    payload,
                });
            }
            Err(error) => {
                if attempt == 0 {
                    continue;
                }
                return Err(ProviderFailure {
                    status_code: 0,
                    error: format!("Network request failed: {error}"),
                });
            }
        }
    }

    Err(ProviderFailure {
        status_code: 0,
        error: "AI generation failed.".to_string(),
    })
}

fn build_http_client(timeout_sec: u64) -> Result<Client, String> {
    Client::builder()
        .timeout(Duration::from_secs(timeout_sec.max(5)))
        .build()
        .map_err(|error| format!("Request initialization failed: {error}"))
}

fn extract_json_payload(raw_text: &str) -> Result<Value, String> {
    let trimmed = raw_text.trim();
    if trimmed.is_empty() {
        return Err("Response was empty.".to_string());
    }
    if let Ok(parsed) = serde_json::from_str::<Value>(trimmed) {
        if parsed.is_object() {
            return Ok(parsed);
        }
    }
    let start_index = trimmed
        .find('{')
        .ok_or_else(|| "Could not find JSON object in the response.".to_string())?;
    let end_index = trimmed
        .rfind('}')
        .ok_or_else(|| "Could not find JSON object in the response.".to_string())?;
    let slice = &trimmed[start_index..=end_index];
    let reparsed: Value =
        serde_json::from_str(slice).map_err(|error| format!("JSON parse failed: {error}"))?;
    if !reparsed.is_object() {
        return Err("Response JSON must be an object.".to_string());
    }
    Ok(reparsed)
}

fn extract_message_content(response_data: &Value) -> String {
    if let Some(content) = response_data
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|choices| choices.first())
        .and_then(|choice| choice.get("message"))
        .and_then(|message| message.get("content"))
    {
        match content {
            Value::String(text) => return text.clone(),
            Value::Array(parts) => {
                let joined = parts
                    .iter()
                    .filter_map(|part| part.get("text").and_then(Value::as_str))
                    .collect::<Vec<_>>()
                    .join("\n");
                if !joined.trim().is_empty() {
                    return joined;
                }
            }
            _ => {}
        }
    }
    String::new()
}

fn map_http_error(status_code: u16, raw_text: &str) -> String {
    match status_code {
        400 => "Bad request (400).".to_string(),
        401 => "Authentication failed. Check the API key (401).".to_string(),
        403 => "Request was rejected (403).".to_string(),
        404 => "Endpoint was not found (404).".to_string(),
        408 => "Request timed out (408).".to_string(),
        429 => "Rate limited. Retry later (429).".to_string(),
        500 | 502 | 503 | 504 => format!("AI service is temporarily unavailable ({status_code})."),
        _ => {
            if raw_text.trim().is_empty() {
                format!("HTTP error {status_code}")
            } else {
                format!(
                    "HTTP error {status_code}: {}",
                    raw_text.chars().take(160).collect::<String>()
                )
            }
        }
    }
}

fn normalize_provider_error(error: &ProviderFailure) -> String {
    if error.status_code == 401 || error.error.contains("Authentication") {
        return format!("Authentication failed: {}", error.error);
    }
    if error.status_code == 429 || error.error.contains("Rate limited") {
        return format!("Rate limited: {}", error.error);
    }
    if error.status_code >= 500 || error.error.contains("temporarily unavailable") {
        return format!("Provider service error: {}", error.error);
    }
    if error.error.contains("JSON") {
        return format!("Provider output was not valid JSON: {}", error.error);
    }
    if error.error.contains("Network") || error.error.contains("Request initialization") {
        return format!("Network failure: {}", error.error);
    }
    error.error.clone()
}

#[cfg(test)]
mod tests {
    use super::{
        extract_json_payload, AiChatRole, AiChatSettings, AiChatState, DEFAULT_BASE_URL,
        DEFAULT_MAX_CONTEXT_RECORDS, DEFAULT_MODEL,
    };

    #[test]
    fn settings_normalization_falls_back_to_defaults() {
        let normalized = AiChatSettings {
            base_url: "  ".to_string(),
            model: String::new(),
            api_key: "  secret  ".to_string(),
            timeout_sec: 1,
            max_context_records: 1,
        }
        .normalized();

        assert_eq!(normalized.base_url, DEFAULT_BASE_URL);
        assert_eq!(normalized.model, DEFAULT_MODEL);
        assert_eq!(normalized.api_key, "secret");
        assert_eq!(normalized.timeout_sec, 5);
        assert_eq!(normalized.max_context_records, 6);
        assert_ne!(DEFAULT_MAX_CONTEXT_RECORDS, 6);
    }

    #[test]
    fn push_chat_message_trims_history_to_context_limit() {
        let mut state = AiChatState::<()>::new(
            "test_editor",
            AiChatSettings {
                max_context_records: 6,
                ..AiChatSettings::default()
            },
        );
        for index in 0..10 {
            state.push_chat_message(AiChatRole::User, format!("message-{index}"));
        }

        assert_eq!(state.conversation.len(), 6);
        assert_eq!(state.conversation[0].content, "message-4");
    }

    #[test]
    fn extract_json_payload_recovers_embedded_object() {
        let payload = extract_json_payload("noise\n{\"hello\":\"world\"}\nmore")
            .expect("json object should be recovered");

        assert_eq!(payload["hello"], "world");
    }
}
