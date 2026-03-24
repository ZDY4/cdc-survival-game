use std::path::PathBuf;
use std::time::Duration;

use game_data::{DialogueData, QuestDefinition};
use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tauri::AppHandle;

use crate::ai_context::{build_context, ContextBuildResult};
use crate::ai_review::{
    build_review_warnings, empty_record, summarize_dialogue_diff, summarize_quest_diff,
    validate_draft_contract, AiDiffSummary,
};
use crate::ai_settings::{read_ai_settings, AiConnectionTestResult, AiSettings};
use crate::quest_workspace::{quest_file_path, quest_validation_catalog, validate_quest_record};

const CHAT_COMPLETIONS_PATH: &str = "/chat/completions";
const MODELS_PATH: &str = "/models";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AiGenerateRequest {
    pub mode: String,
    pub target_id: String,
    pub user_prompt: String,
    pub adjustment_prompt: String,
    #[serde(default)]
    pub current_record: Value,
    #[serde(default)]
    pub previous_draft: Option<Value>,
    #[serde(default)]
    pub previous_validation_errors: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiDraftPayload {
    pub record_type: String,
    pub operation: String,
    pub target_id: String,
    pub summary: String,
    pub warnings: Vec<String>,
    pub record: Value,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AiGenerationResponse {
    pub draft: Option<AiDraftPayload>,
    pub validation_errors: Vec<String>,
    pub provider_error: String,
    pub diff_summary: AiDiffSummary,
    pub review_warnings: Vec<String>,
    pub prompt_debug: Value,
    pub raw_output: String,
}

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

#[tauri::command]
pub fn generate_dialogue_draft(
    app: AppHandle,
    request: AiGenerateRequest,
) -> Result<AiGenerationResponse, String> {
    generate_draft(&app, "dialog", request)
}

#[tauri::command]
pub fn generate_quest_draft(
    app: AppHandle,
    request: AiGenerateRequest,
) -> Result<AiGenerationResponse, String> {
    generate_draft(&app, "quest", request)
}

fn generate_draft(
    app: &AppHandle,
    data_type: &str,
    request: AiGenerateRequest,
) -> Result<AiGenerationResponse, String> {
    if request.user_prompt.trim().is_empty() {
        return Err("请先填写主提示词".to_string());
    }

    let settings = read_ai_settings(app)?.normalized();
    let repo_root = repo_root()?;
    let request_value = serde_json::to_value(&request)
        .map_err(|error| format!("failed to encode ai request: {error}"))?;
    let request_object = request_value
        .as_object()
        .cloned()
        .ok_or_else(|| "failed to encode ai request object".to_string())?;
    let context_result = build_context(&repo_root, data_type, &request_object, settings.max_context_records)?;
    let rules = generation_rules(data_type);
    let request_meta = build_request_meta(
        data_type,
        &request,
        &settings,
        &context_result,
        rules.len() + additional_constraints(data_type).len() + minimal_change_rules(&request).len(),
    );
    let prompt_payload = build_prompt_payload(
        data_type,
        &request,
        &settings,
        &context_result.context,
        &rules,
    );

    match perform_chat_completion(&settings, &prompt_payload) {
        Ok(provider_success) => finalize_generation(
            data_type,
            request,
            provider_success.raw_text,
            provider_success.payload,
            request_meta,
        ),
        Err(provider_error) => Ok(AiGenerationResponse {
            draft: None,
            validation_errors: Vec::new(),
            provider_error: normalize_provider_error(&provider_error),
            diff_summary: AiDiffSummary::default(),
            review_warnings: Vec::new(),
            prompt_debug: json!({
                "request_meta": request_meta,
                "validation_errors": [],
                "provider_error": normalize_provider_error(&provider_error),
                "diff_summary": {}
            }),
            raw_output: provider_error.raw_text,
        }),
    }
}

fn finalize_generation(
    data_type: &str,
    request: AiGenerateRequest,
    raw_output: String,
    payload: Value,
    request_meta: Value,
) -> Result<AiGenerationResponse, String> {
    let draft_object = payload
        .as_object()
        .cloned()
        .ok_or_else(|| "AI 返回的顶层结果不是 JSON 对象".to_string())?;

    let mut validation_errors = validate_draft_contract(data_type, &draft_object);
    let draft = AiDraftPayload {
        record_type: draft_object
            .get("record_type")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        operation: draft_object
            .get("operation")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        target_id: draft_object
            .get("target_id")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        summary: draft_object
            .get("summary")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
        warnings: draft_object
            .get("warnings")
            .and_then(Value::as_array)
            .map(|values| {
                values
                    .iter()
                    .filter_map(Value::as_str)
                    .map(ToString::to_string)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default(),
        record: draft_object
            .get("record")
            .cloned()
            .unwrap_or_else(|| json!({})),
    };

    validation_errors.extend(type_specific_validation(
        data_type,
        &request.mode,
        &request.target_id,
        &draft.record,
    )?);

    let before = if request.mode == "create" {
        json!({})
    } else {
        request.current_record.clone()
    };
    let diff_summary = match data_type {
        "dialog" => summarize_dialogue_diff(&before, &draft.record),
        "quest" => summarize_quest_diff(&before, &draft.record),
        _ => AiDiffSummary::default(),
    };
    let review_warnings = build_review_warnings(
        &request.mode,
        &request.user_prompt,
        &request.adjustment_prompt,
        draft.record.as_object(),
        &diff_summary,
    );

    Ok(AiGenerationResponse {
        draft: Some(draft),
        validation_errors: validation_errors.clone(),
        provider_error: String::new(),
        diff_summary: diff_summary.clone(),
        review_warnings,
        prompt_debug: json!({
            "request_meta": request_meta,
            "validation_errors": validation_errors,
            "provider_error": "",
            "diff_summary": diff_summary
        }),
        raw_output,
    })
}

fn type_specific_validation(
    data_type: &str,
    mode: &str,
    target_id: &str,
    record: &Value,
) -> Result<Vec<String>, String> {
    let mut errors = Vec::new();
    let record_object = record
        .as_object()
        .ok_or_else(|| "record 必须是对象".to_string())?;
    if empty_record(Some(record_object)) {
        errors.push("record 不能为空对象".to_string());
        return Ok(errors);
    }

    match data_type {
        "dialog" => {
            let dialog: DialogueData = serde_json::from_value(record.clone())
                .map_err(|error| format!("对话草稿结构无效: {error}"))?;
            let dialog_id = dialog.dialog_id.trim();
            if dialog_id.is_empty() {
                errors.push("dialog_id 不能为空".to_string());
            }
            if mode == "create" && !dialog_id.is_empty() && dialogue_file_path(dialog_id)?.exists() {
                errors.push(format!("新建模式下不能复用已有 dialog_id: {dialog_id}"));
            }
            if mode == "revise" && !target_id.trim().is_empty() && dialog_id != target_id.trim() {
                errors.push("调整模式下 dialog_id 必须保持为当前记录 ID".to_string());
            }
            errors.extend(
                crate::validate_dialogue(&dialog)
                    .into_iter()
                    .map(|issue| issue.message)
                    .collect::<Vec<_>>(),
            );
        }
        "quest" => {
            let quest: QuestDefinition = serde_json::from_value(record.clone())
                .map_err(|error| format!("任务草稿结构无效: {error}"))?;
            let quest_id = quest.quest_id.trim();
            if quest_id.is_empty() {
                errors.push("quest_id 不能为空".to_string());
            }
            if mode == "create" && !quest_id.is_empty() && quest_file_path(quest_id)?.exists() {
                errors.push(format!("新建模式下不能复用已有任务 ID: {quest_id}"));
            }
            if mode == "revise" && !target_id.trim().is_empty() && quest_id != target_id.trim() {
                errors.push("调整模式下 quest_id 必须保持为当前任务 ID".to_string());
            }
            let mut catalog = quest_validation_catalog(None)?;
            if !quest_id.is_empty() {
                catalog.quest_ids.insert(quest_id.to_string());
            }
            errors.extend(
                validate_quest_record(&quest, &catalog)
                    .into_iter()
                    .map(|issue| issue.message)
                    .collect::<Vec<_>>(),
            );
        }
        _ => {}
    }

    Ok(errors)
}

fn build_prompt_payload(
    data_type: &str,
    request: &AiGenerateRequest,
    settings: &AiSettings,
    context: &Value,
    rules: &[String],
) -> Value {
    let system_prompt = [
        format!(
            "[输出协议]\n{}",
            [
                "你正在为 Godot 生存游戏编辑器生成结构化内容。",
                "只能输出一个 JSON 对象，不能输出 Markdown、解释或代码块。",
                "输出必须严格遵守合同：{\"record_type\":\"dialog|quest\",\"operation\":\"create|revise\",\"target_id\":\"string\",\"summary\":\"string\",\"warnings\":[\"string\"],\"record\":{}}。",
                "record 必须是该类型最终落盘 JSON 格式，而不是表单子集。",
                "不得引用上下文中不存在的 ID；如果确实需要新 ID，必须贴合项目现有命名风格。"
            ]
            .join("\n")
        ),
        format!(
            "[类型约束]\n{}",
            rules.iter()
                .chain(additional_constraints(data_type).iter())
                .cloned()
                .collect::<Vec<_>>()
                .join("\n")
        ),
        format!(
            "[最小修改原则]\n{}",
            minimal_change_rules(request).join("\n")
        ),
    ]
    .join("\n\n");

    json!({
        "provider_config": {
            "base_url": settings.base_url,
            "model": settings.model,
            "api_key": settings.effective_api_key(),
            "timeout_sec": settings.timeout_sec
        },
        "temperature": 0.25,
        "max_tokens": 2200,
        "messages": [
            { "role": "system", "content": system_prompt },
            {
                "role": "user",
                "content": serde_json::to_string_pretty(&json!({
                    "request": request,
                    "context": context
                }))
                .unwrap_or_else(|_| "{}".to_string())
            }
        ]
    })
}

fn build_request_meta(
    data_type: &str,
    request: &AiGenerateRequest,
    settings: &AiSettings,
    context_result: &ContextBuildResult,
    rule_count: usize,
) -> Value {
    json!({
        "data_type": data_type,
        "mode": request.mode,
        "target_id": request.target_id,
        "provider": {
            "base_url": settings.base_url,
            "model": settings.model
        },
        "context_stats": context_result.context_stats,
        "truncation": context_result.truncation,
        "allowed_reference_groups": context_result.allowed_reference_groups,
        "suggested_reference_groups": context_result.suggested_reference_groups,
        "rule_count": rule_count
    })
}

fn generation_rules(data_type: &str) -> Vec<String> {
    match data_type {
        "dialog" => vec![
            "record_type must be 'dialog'".to_string(),
            "record must contain dialog_id, nodes, and connections".to_string(),
            "every node id must be unique".to_string(),
            "choice/condition/dialog/action next fields must stay consistent with the connections array".to_string(),
        ],
        "quest" => vec![
            "record_type must be 'quest'".to_string(),
            "record must use the flow graph schema instead of the legacy objectives/rewards schema".to_string(),
            "flow.start_node_id must point to an existing start node".to_string(),
            "the flow must contain exactly one start node and at least one end node".to_string(),
        ],
        _ => Vec::new(),
    }
}

fn additional_constraints(data_type: &str) -> Vec<String> {
    match data_type {
        "dialog" => vec![
            "如果新增节点，必须补全 next / true_next / false_next / options[].next 以及 connections。".to_string(),
            "如果保留旧节点，不得无故断开原有关键路径，除非用户明确要求重构。".to_string(),
        ],
        "quest" => vec![
            "如果新增 flow 节点，必须补全连接信息和可达路径。".to_string(),
            "如果保留旧节点，不得无故断开 start 到 end 的关键路径，除非用户明确要求重构。".to_string(),
        ],
        _ => Vec::new(),
    }
}

fn minimal_change_rules(request: &AiGenerateRequest) -> Vec<String> {
    let mut rules = vec!["优先保持世界观、命名风格、文案语气与上下文样本一致。".to_string()];
    if request.mode == "revise" {
        rules.extend([
            "未被用户提到的字段尽量保持不变。".to_string(),
            "禁止随意重命名主 ID、删除节点、替换现有引用，除非用户明确要求。".to_string(),
            "如果上一次草稿和本地校验错误已提供，请以最小修改方式修正。".to_string(),
        ]);
    } else {
        rules.push("新建模式下优先复用现有引用集合，不要发明新的外部依赖 ID。".to_string());
    }
    rules
}

struct ProviderSuccess {
    raw_text: String,
    payload: Value,
}

struct ProviderFailure {
    status_code: u16,
    error: String,
    raw_text: String,
}

fn perform_chat_completion(
    settings: &AiSettings,
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
            error: "Base URL 不能为空".to_string(),
            raw_text: String::new(),
        });
    }
    if model.is_empty() {
        return Err(ProviderFailure {
            status_code: 0,
            error: "Model 不能为空".to_string(),
            raw_text: String::new(),
        });
    }
    if api_key.is_empty() {
        return Err(ProviderFailure {
            status_code: 0,
            error: "API Key 未配置".to_string(),
            raw_text: String::new(),
        });
    }

    let client = build_http_client(settings.timeout_sec).map_err(|error| ProviderFailure {
        status_code: 0,
        error,
        raw_text: String::new(),
    })?;
    let request_body = json!({
        "model": model,
        "messages": payload.get("messages").cloned().unwrap_or_else(|| json!([])),
        "temperature": payload.get("temperature").and_then(Value::as_f64).unwrap_or(0.25),
        "response_format": { "type": "json_object" },
        "max_tokens": payload.get("max_tokens").and_then(Value::as_u64).unwrap_or(2200),
    });

    let mut last_failure: Option<ProviderFailure> = None;
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
                    let failure = ProviderFailure {
                        status_code: status,
                        error: map_http_error(status, &raw_body),
                        raw_text: raw_body,
                    };
                    if attempt == 0 && (status == 429 || status >= 500) {
                        std::thread::sleep(Duration::from_secs(1));
                        last_failure = Some(failure);
                        continue;
                    }
                    return Err(failure);
                }

                let response_data: Value = serde_json::from_str(&raw_body).map_err(|error| ProviderFailure {
                    status_code: status,
                    error: format!("响应不是合法 JSON: {error}"),
                    raw_text: raw_body.clone(),
                })?;
                let raw_content = extract_message_content(&response_data);
                let payload = extract_json_payload(&raw_content).map_err(|error| ProviderFailure {
                    status_code: status,
                    error,
                    raw_text: raw_content.clone(),
                })?;

                return Ok(ProviderSuccess {
                    raw_text: raw_content,
                    payload,
                });
            }
            Err(error) => {
                let failure = ProviderFailure {
                    status_code: 0,
                    error: format!("网络请求失败: {error}"),
                    raw_text: String::new(),
                };
                if attempt == 0 {
                    last_failure = Some(failure);
                    continue;
                }
                return Err(failure);
            }
        }
    }

    Err(last_failure.unwrap_or(ProviderFailure {
        status_code: 0,
        error: "AI 生成失败".to_string(),
        raw_text: String::new(),
    }))
}

fn build_http_client(timeout_sec: u64) -> Result<Client, String> {
    Client::builder()
        .timeout(Duration::from_secs(timeout_sec.max(5)))
        .build()
        .map_err(|error| format!("请求初始化失败: {error}"))
}

fn extract_json_payload(raw_text: &str) -> Result<Value, String> {
    let trimmed = raw_text.trim();
    if trimmed.is_empty() {
        return Err("响应为空".to_string());
    }

    if let Ok(parsed) = serde_json::from_str::<Value>(trimmed) {
        if parsed.is_object() {
            return Ok(parsed);
        }
    }

    let start_index = trimmed.find('{').ok_or_else(|| "响应中未找到 JSON 对象".to_string())?;
    let end_index = trimmed.rfind('}').ok_or_else(|| "响应中未找到 JSON 对象".to_string())?;
    if end_index < start_index {
        return Err("响应中未找到 JSON 对象".to_string());
    }

    let slice = &trimmed[start_index..=end_index];
    let reparsed: Value =
        serde_json::from_str(slice).map_err(|error| format!("JSON 解析失败: {error}"))?;
    if !reparsed.is_object() {
        return Err("响应中未找到 JSON 对象".to_string());
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
        400 => "请求格式错误 (400)".to_string(),
        401 => "鉴权失败，请检查 API Key (401)".to_string(),
        403 => "请求被拒绝 (403)".to_string(),
        404 => "接口地址不存在 (404)".to_string(),
        408 => "请求超时 (408)".to_string(),
        429 => "请求过于频繁，请稍后重试 (429)".to_string(),
        500 | 502 | 503 | 504 => format!("AI 服务暂时不可用 ({status_code})"),
        _ => {
            let suffix = if raw_text.trim().is_empty() {
                String::new()
            } else {
                format!(": {}", raw_text.chars().take(160).collect::<String>())
            };
            format!("HTTP 错误 {status_code}{suffix}")
        }
    }
}

fn normalize_provider_error(error: &ProviderFailure) -> String {
    if error.status_code == 401 || error.error.contains("鉴权") {
        return format!("鉴权失败: {}", error.error);
    }
    if error.status_code == 429 || error.error.contains("频繁") {
        return format!("限流: {}", error.error);
    }
    if error.status_code >= 500 || error.error.contains("服务") {
        return format!("服务错误: {}", error.error);
    }
    if error.error.contains("JSON") {
        return format!("输出 JSON 非法: {}", error.error);
    }
    if error.error.contains("网络") || error.error.contains("初始化失败") || error.status_code == 0
    {
        return format!("网络失败: {}", error.error);
    }
    error.error.clone()
}

fn repo_root() -> Result<PathBuf, String> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("..")
        .join("..");
    root.canonicalize()
        .map_err(|error| format!("failed to resolve repo root: {error}"))
}

fn dialogue_file_path(dialog_id: &str) -> Result<PathBuf, String> {
    Ok(repo_root()?.join("data").join("dialogues").join(format!("{dialog_id}.json")))
}
