use std::time::Duration;

use reqwest::blocking::Client;
use tauri::AppHandle;

use crate::ai_settings::{read_ai_settings, AiConnectionTestResult, AiSettings};

const MODELS_PATH: &str = "/models";

#[tauri::command]
pub fn test_ai_provider(
    app: AppHandle,
    settings: Option<AiSettings>,
) -> Result<AiConnectionTestResult, String> {
    let settings = settings.unwrap_or(read_ai_settings(&app)?).normalized();
    let base_url = settings.base_url.trim().trim_end_matches('/').to_string();
    let api_key = settings.effective_api_key();

    if base_url.is_empty() {
        return Ok(AiConnectionTestResult {
            ok: false,
            error: "Base URL 不能为空".to_string(),
        });
    }
    if api_key.is_empty() {
        return Ok(AiConnectionTestResult {
            ok: false,
            error: "API Key 未配置".to_string(),
        });
    }

    let client = build_http_client(settings.timeout_sec)?;
    let response = client
        .get(format!("{base_url}{MODELS_PATH}"))
        .bearer_auth(api_key)
        .header("Accept", "application/json")
        .send();

    match response {
        Ok(response) if response.status().is_success() => Ok(AiConnectionTestResult {
            ok: true,
            error: String::new(),
        }),
        Ok(response) => {
            let status = response.status().as_u16();
            let body = response.text().unwrap_or_default();
            Ok(AiConnectionTestResult {
                ok: false,
                error: map_http_error(status, &body),
            })
        }
        Err(error) => Ok(AiConnectionTestResult {
            ok: false,
            error: format!("网络失败: {error}"),
        }),
    }
}

fn build_http_client(timeout_sec: u64) -> Result<Client, String> {
    Client::builder()
        .timeout(Duration::from_secs(timeout_sec.max(5)))
        .build()
        .map_err(|error| format!("failed to build ai http client: {error}"))
}

fn map_http_error(status_code: u16, raw_text: &str) -> String {
    match status_code {
        400 => "请求格式无效，请检查 Base URL 与模型配置。".to_string(),
        401 => "API Key 无效或已过期。".to_string(),
        403 => "当前 API Key 没有访问该模型的权限。".to_string(),
        404 => "未找到对应模型或接口地址。".to_string(),
        408 => "请求超时，请检查网络或增大 Timeout。".to_string(),
        429 => "请求过于频繁，稍后再试。".to_string(),
        500 | 502 | 503 | 504 => format!("AI 服务暂时不可用 ({status_code})"),
        _ => {
            let suffix = if raw_text.trim().is_empty() {
                String::new()
            } else {
                format!(": {}", summarize_error_body(raw_text))
            };
            format!("HTTP 错误 {status_code}{suffix}")
        }
    }
}

fn summarize_error_body(raw_text: &str) -> String {
    let trimmed = raw_text.trim();
    if trimmed.is_empty() {
        return String::new();
    }

    let collapsed = trimmed.split_whitespace().collect::<Vec<_>>().join(" ");
    if collapsed.chars().count() <= 140 {
        return collapsed;
    }

    collapsed.chars().take(140).collect::<String>() + "..."
}
