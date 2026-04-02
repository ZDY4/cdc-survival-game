use std::{
    io::{BufRead, BufReader},
    thread,
    time::Duration,
};

use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use tauri::{AppHandle, Emitter};

use crate::ai_settings::{read_ai_settings, AiSettings};
use crate::narrative_context::build_narrative_context;
use crate::narrative_review::{
    build_review_result, prompt_debug_payload, validate_selection, NarrativeSelectionRange,
};
use crate::narrative_templates::{default_markdown, doc_type_label, is_known_doc_type};
use crate::narrative_workspace::{resolve_connected_project_root, resolve_workspace_root};

const NARRATIVE_GENERATION_PROGRESS_EVENT: &str = "narrative:generation-progress";

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeGenerateRequest {
    #[serde(default)]
    pub request_id: Option<String>,
    pub doc_type: String,
    pub target_slug: String,
    pub action: String,
    pub user_prompt: String,
    pub editor_instruction: String,
    pub current_markdown: String,
    #[serde(default)]
    pub selected_range: Option<NarrativeSelectionRange>,
    #[serde(default)]
    pub selected_text: String,
    #[serde(default)]
    pub related_doc_slugs: Vec<String>,
    #[serde(default)]
    pub derived_target_doc_type: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeAgentRun {
    pub agent_id: String,
    pub label: String,
    pub focus: String,
    pub status: String,
    pub summary: String,
    pub notes: Vec<String>,
    pub risk_level: String,
    pub draft_markdown: String,
    pub raw_output: String,
    pub provider_error: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentQuestion {
    pub id: String,
    pub label: String,
    pub placeholder: String,
    pub required: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentOption {
    pub id: String,
    pub label: String,
    pub description: String,
    pub followup_prompt: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentPlanStep {
    pub id: String,
    pub label: String,
    pub status: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentExecutionStep {
    pub id: String,
    pub label: String,
    pub detail: String,
    pub status: String,
    pub preview_text: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentActionRequest {
    pub id: String,
    pub action_type: String,
    pub title: String,
    pub description: String,
    pub payload: Value,
    pub approval_policy: String,
    pub preview_only: bool,
    pub affected_document_keys: Vec<String>,
    pub risk_level: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ReviewQueueItem {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub description: String,
    pub status: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeGenerateResponse {
    pub engine_mode: String,
    pub turn_kind: String,
    pub assistant_message: String,
    pub draft_markdown: String,
    pub summary: String,
    pub review_notes: Vec<String>,
    pub risk_level: String,
    pub change_scope: String,
    pub prompt_debug: Value,
    pub raw_output: String,
    pub used_context_refs: Vec<String>,
    pub diff_preview: String,
    pub provider_error: String,
    pub synthesis_notes: Vec<String>,
    pub agent_runs: Vec<NarrativeAgentRun>,
    pub questions: Vec<AgentQuestion>,
    pub options: Vec<AgentOption>,
    pub plan_steps: Vec<AgentPlanStep>,
    pub requires_user_reply: bool,
    pub execution_steps: Vec<AgentExecutionStep>,
    pub current_step_id: Option<String>,
    pub requested_actions: Vec<AgentActionRequest>,
    pub source_document_keys: Vec<String>,
    pub provenance_refs: Vec<String>,
    pub review_queue_items: Vec<ReviewQueueItem>,
}

const SUPPORTED_AGENT_ACTION_TYPES: &[&str] = &[
    "read_active_document",
    "read_related_documents",
    "create_derived_document",
    "apply_candidate_patch",
    "apply_all_patches",
    "save_active_document",
    "open_document",
    "list_workspace_documents",
    "update_related_documents",
    "rename_active_document",
    "set_document_status",
    "split_plan_into_documents",
    "archive_document",
];

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct NarrativeGenerationProgressEvent {
    request_id: String,
    stage: String,
    status: String,
    preview_text: String,
    step_id: Option<String>,
    step_label: Option<String>,
    step_status: Option<String>,
}

#[derive(Clone)]
struct NarrativeGenerationProgressEmitter {
    app: AppHandle,
    request_id: String,
}

impl NarrativeGenerationProgressEmitter {
    fn from_request(app: &AppHandle, request: &NarrativeGenerateRequest) -> Option<Self> {
        let request_id = request.request_id.as_ref()?.trim();
        if request_id.is_empty() {
            return None;
        }

        Some(Self {
            app: app.clone(),
            request_id: request_id.to_string(),
        })
    }

    fn emit(
        &self,
        stage: &str,
        status: impl Into<String>,
        preview_text: impl Into<String>,
        step_id: Option<&str>,
        step_label: Option<&str>,
        step_status: Option<&str>,
    ) {
        let payload = NarrativeGenerationProgressEvent {
            request_id: self.request_id.clone(),
            stage: stage.to_string(),
            status: status.into(),
            preview_text: preview_text.into(),
            step_id: step_id.map(ToString::to_string),
            step_label: step_label.map(ToString::to_string),
            step_status: step_status.map(ToString::to_string),
        };
        let _ = self
            .app
            .emit_to("main", NARRATIVE_GENERATION_PROGRESS_EVENT, payload);
    }

    fn completed(&self, status: impl Into<String>, preview_text: impl Into<String>) {
        self.emit("completed", status, preview_text, None, None, None);
    }

    fn status_step(&self, step_id: &str, step_label: &str, status: impl Into<String>) {
        let status = status.into();
        self.emit(
            "status",
            status.clone(),
            status,
            Some(step_id),
            Some(step_label),
            Some("running"),
        );
    }

    fn delta_step(
        &self,
        step_id: &str,
        step_label: &str,
        status: impl Into<String>,
        preview_text: impl Into<String>,
    ) {
        self.emit(
            "delta",
            status,
            preview_text,
            Some(step_id),
            Some(step_label),
            Some("running"),
        );
    }

    fn completed_step(
        &self,
        step_id: &str,
        step_label: &str,
        status: impl Into<String>,
        preview_text: impl Into<String>,
    ) {
        self.emit(
            "completed",
            status,
            preview_text,
            Some(step_id),
            Some(step_label),
            Some("completed"),
        );
    }

    fn error_step(
        &self,
        step_id: &str,
        step_label: &str,
        status: impl Into<String>,
        preview_text: impl Into<String>,
    ) {
        self.emit(
            "error",
            status,
            preview_text,
            Some(step_id),
            Some(step_label),
            Some("failed"),
        );
    }
}

#[derive(Debug)]
struct ProviderSuccess {
    raw_text: String,
    payload: Value,
}

#[derive(Debug)]
struct ProviderFailure {
    status_code: u16,
    error: String,
    raw_text: String,
}

#[tauri::command]
pub async fn generate_narrative_draft(
    app: AppHandle,
    workspace_root: String,
    project_root: Option<String>,
    request: NarrativeGenerateRequest,
) -> Result<NarrativeGenerateResponse, String> {
    run_narrative_generation_in_background(app, workspace_root, project_root, request).await
}

#[tauri::command]
pub async fn revise_narrative_draft(
    app: AppHandle,
    workspace_root: String,
    project_root: Option<String>,
    request: NarrativeGenerateRequest,
) -> Result<NarrativeGenerateResponse, String> {
    run_narrative_generation_in_background(app, workspace_root, project_root, request).await
}

async fn run_narrative_generation_in_background(
    app: AppHandle,
    workspace_root: String,
    project_root: Option<String>,
    request: NarrativeGenerateRequest,
) -> Result<NarrativeGenerateResponse, String> {
    tauri::async_runtime::spawn_blocking(move || {
        run_narrative_generation(&app, &workspace_root, project_root.as_deref(), request)
    })
    .await
    .map_err(|error| format!("narrative generation task failed: {error}"))?
}

fn run_narrative_generation(
    app: &AppHandle,
    workspace_root: &str,
    project_root: Option<&str>,
    mut request: NarrativeGenerateRequest,
) -> Result<NarrativeGenerateResponse, String> {
    let progress = NarrativeGenerationProgressEmitter::from_request(app, &request);
    if let Some(progress) = &progress {
        progress.status_step("prepare-request", "准备请求", "正在准备 AI 请求...");
    }
    normalize_request(&mut request)?;
    if let Some(progress) = &progress {
        progress.completed_step(
            "prepare-request",
            "准备请求",
            "AI 请求准备完成。",
            "请求参数已标准化。",
        );
        progress.status_step("validate-input", "校验输入", "正在校验当前文档与选区...");
    }
    let selection = validate_selection(
        &request.current_markdown,
        request.selected_range.as_ref(),
        &request.selected_text,
        &request.action,
    )?;
    if let Some(progress) = &progress {
        progress.completed_step(
            "validate-input",
            "校验输入",
            "输入校验完成。",
            "文档与选区均可用于本轮生成。",
        );
        progress.status_step("load-settings", "读取设置", "正在读取 AI 设置...");
    }
    let settings = read_ai_settings(app)?.normalized();
    let workspace_root_path = resolve_workspace_root(workspace_root)?;
    let project_root_path = resolve_connected_project_root(project_root)?;
    if let Some(progress) = &progress {
        progress.completed_step(
            "load-settings",
            "读取设置",
            "AI 设置读取完成。",
            format!("当前模型：{}", settings.model),
        );
        progress.status_step("build-context", "整理上下文", "正在整理工作区上下文...");
    }
    let context = build_narrative_context(
        &workspace_root_path,
        project_root_path.as_deref(),
        &request,
        settings.max_context_records,
    )?;
    let payload = build_single_agent_payload(&request, &context.context, &settings);
    if let Some(progress) = &progress {
        progress.completed_step(
            "build-context",
            "整理上下文",
            "上下文整理完成。",
            format!("已收集 {} 条上下文引用。", context.used_context_refs.len()),
        );
        progress.status_step("request-model", "请求模型", "正在连接 AI 提供方...");
    }

    match perform_chat_completion(&settings, &payload, progress.as_ref()) {
        Ok(success) => {
            if let Some(progress) = &progress {
                progress.completed_step(
                    "request-model",
                    "请求模型",
                    "模型输出接收完成。",
                    success.raw_text.clone(),
                );
                progress.status_step("review-result", "整理结果", "正在整理最终结果...");
            }
            let agent_run = build_single_agent_run(&success.payload, &success.raw_text);
            let response = finalize_generation(
                "single_agent",
                request,
                selection,
                context,
                success.raw_text,
                success.payload,
                vec![agent_run],
            )?;
            if let Some(progress) = &progress {
                progress.completed_step(
                    "review-result",
                    "整理结果",
                    "结果整理完成。",
                    summarize_response_preview(&response),
                );
                progress.completed(
                    "AI 输出完成，正在整理结果...",
                    summarize_response_preview(&response),
                );
            }
            Ok(response)
        }
        Err(error) => {
            let provider_error = normalize_provider_error(&error);
            if let Some(progress) = &progress {
                progress.error_step(
                    "request-model",
                    "请求模型",
                    provider_error.clone(),
                    if error.raw_text.trim().is_empty() {
                        provider_error.clone()
                    } else {
                        error.raw_text.clone()
                    },
                );
            }
            let provenance_refs = context.used_context_refs.clone();
            Ok(NarrativeGenerateResponse {
                engine_mode: "single_agent".to_string(),
                turn_kind: "blocked".to_string(),
                assistant_message: provider_error.clone(),
                draft_markdown: String::new(),
                summary: String::new(),
                review_notes: vec!["文档助手本轮没有生成可用草稿。".to_string()],
                risk_level: "high".to_string(),
                change_scope: crate::narrative_review::change_scope_for_action(&request.action)
                    .to_string(),
                prompt_debug: prompt_debug_payload(
                    &request.action,
                    selection.as_ref(),
                    &context.workspace_context_refs,
                    &context.project_context_refs,
                    &context.project_context_warning,
                    &context.source_conflicts,
                    json!({
                        "request": request,
                        "context": context.context.clone(),
                        "engineMode": "single_agent",
                        "providerError": provider_error,
                    }),
                ),
                raw_output: error.raw_text.clone(),
                used_context_refs: context.used_context_refs,
                diff_preview: "暂无草稿可预览".to_string(),
                provider_error: normalize_provider_error(&error),
                synthesis_notes: vec!["当前流程已切换为单 agent 文档助手。".to_string()],
                agent_runs: vec![failed_agent_run(
                    "document-assistant",
                    "文档助手",
                    "负责当前文档的对话、改写与新文档生成。",
                    normalize_provider_error(&error),
                )
                .with_raw_output(error.raw_text)],
                questions: Vec::new(),
                options: Vec::new(),
                plan_steps: Vec::new(),
                requires_user_reply: false,
                execution_steps: failed_execution_steps("request-model", "请求模型", &provider_error),
                current_step_id: Some("request-model".to_string()),
                requested_actions: Vec::new(),
                source_document_keys: build_source_document_keys(&request),
                provenance_refs,
                review_queue_items: Vec::new(),
            })
        }
    }
}

fn finalize_generation(
    engine_mode: &str,
    request: NarrativeGenerateRequest,
    selection: Option<NarrativeSelectionRange>,
    context: crate::narrative_context::NarrativeContextBuildResult,
    raw_output: String,
    payload: Value,
    agent_runs: Vec<NarrativeAgentRun>,
) -> Result<NarrativeGenerateResponse, String> {
    let object = payload
        .as_object()
        .cloned()
        .ok_or_else(|| "AI 返回的 narrative 结果不是 JSON 对象".to_string())?;
    let draft_markdown = read_draft_markdown(&object);
    let questions = read_agent_questions(&object);
    let options = read_agent_options(&object);
    let plan_steps = read_agent_plan_steps(&object);
    let requested_actions = read_requested_actions(&object);
    let turn_kind = resolve_turn_kind(&object, &draft_markdown, &questions, &options, &plan_steps);
    let model_notes = read_string_list(
        object
            .get("review_notes")
            .or_else(|| object.get("reviewNotes")),
    );
    let synthesis_notes = read_synthesis_notes(&object);
    let review = build_review_result(
        &request.action,
        &request.current_markdown,
        selection.as_ref(),
        &draft_markdown,
        model_notes,
    );
    let review_notes = review.review_notes;

    let summary = read_summary(&object, &request.action, &draft_markdown);
    let assistant_message = read_assistant_message(
        &object,
        &turn_kind,
        &summary,
        &draft_markdown,
        &questions,
        &options,
        &plan_steps,
    );

    let agent_risk = highest_agent_risk(&agent_runs);
    let execution_steps = completed_execution_steps(&turn_kind, &summary);
    let source_document_keys = build_source_document_keys(&request);
    let provenance_refs = context.used_context_refs.clone();
    let review_queue_items =
        build_review_queue_items(&turn_kind, &plan_steps, &requested_actions, &draft_markdown);

    Ok(NarrativeGenerateResponse {
        engine_mode: engine_mode.to_string(),
        turn_kind: turn_kind.clone(),
        assistant_message,
        draft_markdown,
        summary,
        review_notes,
        risk_level: highest_risk([
            object
                .get("risk_level")
                .or_else(|| object.get("riskLevel"))
                .and_then(Value::as_str)
                .unwrap_or("low"),
            &review.risk_level,
            &agent_risk,
        ]),
        change_scope: review.change_scope,
        prompt_debug: prompt_debug_payload(
            &request.action,
            selection.as_ref(),
            &context.workspace_context_refs,
            &context.project_context_refs,
            &context.project_context_warning,
            &context.source_conflicts,
            json!({
                "request": request,
                "context": context.context.clone(),
                "engineMode": engine_mode,
                "agentRuns": &agent_runs,
            }),
        ),
        raw_output,
        used_context_refs: context.used_context_refs,
        diff_preview: review.diff_preview,
        provider_error: String::new(),
        synthesis_notes,
        agent_runs,
        questions,
        options,
        plan_steps,
        requires_user_reply: matches!(turn_kind.as_str(), "clarification" | "options" | "plan"),
        execution_steps,
        current_step_id: None,
        requested_actions,
        source_document_keys,
        provenance_refs,
        review_queue_items,
    })
}

fn normalize_request(request: &mut NarrativeGenerateRequest) -> Result<(), String> {
    request.doc_type = request.doc_type.trim().to_lowercase();
    if !is_known_doc_type(&request.doc_type) {
        return Err(format!("未知文稿类型: {}", request.doc_type));
    }
    request.action = request.action.trim().to_lowercase();
    if !matches!(
        request.action.as_str(),
        "create"
            | "revise_document"
            | "rewrite_selection"
            | "expand_selection"
            | "insert_after_selection"
            | "derive_new_doc"
    ) {
        return Err(format!("未知 narrative 操作: {}", request.action));
    }
    request.target_slug = request.target_slug.trim().to_string();
    request.user_prompt = request.user_prompt.trim().to_string();
    request.editor_instruction = request.editor_instruction.trim().to_string();
    request.selected_text = request.selected_text.trim().to_string();
    request.related_doc_slugs = request
        .related_doc_slugs
        .iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect();
    if let Some(doc_type) = &request.derived_target_doc_type {
        if !doc_type.trim().is_empty() && !is_known_doc_type(doc_type.trim()) {
            return Err(format!("未知派生文稿类型: {doc_type}"));
        }
    }
    if request.user_prompt.is_empty() && request.editor_instruction.is_empty() {
        return Err("请至少填写主提示词或修改意见".to_string());
    }
    if request.action == "create" && request.current_markdown.trim().is_empty() {
        request.current_markdown = default_markdown(
            &request.doc_type,
            &format!("{}草稿", doc_type_label(&request.doc_type)),
        );
    }
    Ok(())
}

fn build_single_agent_payload(
    request: &NarrativeGenerateRequest,
    context: &Value,
    settings: &AiSettings,
) -> Value {
    let contract = [
        "始终只返回一个 JSON 对象，不要输出 Markdown 正文，不要加代码块围栏，不要附加解释文字。",
        "JSON 允许字段：turn_kind, assistant_message, draft_markdown, summary, review_notes, synthesis_notes, risk_level, questions, options, plan_steps, requested_actions。",
        "turn_kind 只能是 final_answer, clarification, options, plan, blocked 之一。",
        "当信息足够且适合直接产出结果时，使用 final_answer，并在 draft_markdown 中提供可直接保存的 Markdown 正文。",
        "当关键信息缺失时，使用 clarification，并提供 1 到 3 个 questions。",
        "当存在清晰方向分叉时，使用 options，并提供 2 到 4 个 options，每个 option 必须包含 followup_prompt。",
        "当任务较复杂、适合先说明推进方式时，使用 plan，并提供简短的 plan_steps。",
        "当当前上下文不足以安全继续时，使用 blocked，并说明阻塞原因；此时不要编造正文。",
        "如果你希望用户批准某个 Narrative Lab 动作，使用 requested_actions；动作不会自动执行。",
        "requested_actions 中 action_type 只能是 read_active_document, read_related_documents, create_derived_document, apply_candidate_patch, apply_all_patches, save_active_document, open_document, list_workspace_documents, update_related_documents, rename_active_document, set_document_status, split_plan_into_documents, archive_document。",
        "requested_actions 可选字段：preview_only, affected_document_keys, risk_level；risk_level 只能是 low, medium, high。",
        "只有 final_answer 允许返回非空 draft_markdown。不要包含 YAML frontmatter。",
    ]
    .join("\n");

    json!({
        "provider_config": {
            "base_url": settings.base_url,
            "model": settings.model,
            "api_key": settings.effective_api_key(),
            "timeout_sec": settings.timeout_sec,
        },
        "temperature": 0.35,
        "max_tokens": 4000,
        "messages": [
            {
                "role": "system",
                "content": format!(
                    "[你的身份]\n你是 Narrative Lab 的单一文档助手，负责围绕当前文档与用户意图直接产出结果。\n\n[输出协议]\n{}\n\n[工作方式]\n{}\n{}\n{}\n{}",
                    contract,
                    "优先判断当前信息是否足够；如果不够，就先提问或给选项，不要硬写正文。",
                    "如果用户只是简短打招呼，也要返回简洁自然的 JSON 回合，不要卡在流程解释里。",
                    "优先保持当前文档方向和结构稳定；只有在用户明确要求时才大改。",
                    build_action_rules(request).join("\n"),
                ),
            },
            {
                "role": "user",
                "content": serde_json::to_string_pretty(&json!({
                    "request": request,
                    "context": context,
                }))
                .unwrap_or_else(|_| "{}".to_string()),
            },
        ]
    })
}

fn build_action_rules(request: &NarrativeGenerateRequest) -> Vec<String> {
    match request.action.as_str() {
        "create" => vec![
            "根据模板生成完整可读文稿。".to_string(),
            "文稿应包含清晰标题层级和结构化落地提示。".to_string(),
        ],
        "revise_document" => vec![
            "在保留文稿主方向的前提下整体改写。".to_string(),
            "不要无故删除重要章节。".to_string(),
        ],
        "rewrite_selection" => vec![
            "只输出选中区域的替换片段，不要重写未选中区域。".to_string(),
            "替换片段必须与上下文语气连续。".to_string(),
        ],
        "expand_selection" => vec![
            "围绕选中区域扩展细节，只输出用于替换选区的扩写片段。".to_string(),
            "不要修改未选中区域的设定。".to_string(),
        ],
        "insert_after_selection" => vec![
            "只输出需要插入到选区后的新片段。".to_string(),
            "插入内容必须承接选区后的叙事节奏。".to_string(),
        ],
        "derive_new_doc" => vec![
            "基于当前文稿派生一份新的关联文稿。".to_string(),
            "派生文稿要适配目标文稿类型。".to_string(),
        ],
        _ => Vec::new(),
    }
}

fn build_single_agent_run(payload: &Value, raw_output: &str) -> NarrativeAgentRun {
    let object = payload.as_object().cloned().unwrap_or_default();
    let draft_markdown = read_draft_markdown(&object);

    NarrativeAgentRun {
        agent_id: "document-assistant".to_string(),
        label: "文档助手".to_string(),
        focus: "负责当前文档的对话、改写与新文档生成。".to_string(),
        status: "completed".to_string(),
        summary: read_summary(&object, "revise_document", &draft_markdown),
        notes: read_string_list(
            object
                .get("review_notes")
                .or_else(|| object.get("reviewNotes"))
                .or_else(|| object.get("synthesis_notes"))
                .or_else(|| object.get("synthesisNotes"))
                .or_else(|| object.get("notes")),
        ),
        risk_level: normalize_risk(
            object
                .get("risk_level")
                .or_else(|| object.get("riskLevel"))
                .and_then(Value::as_str)
                .unwrap_or(if draft_markdown.trim().is_empty() { "high" } else { "medium" }),
        ),
        draft_markdown,
        raw_output: raw_output.to_string(),
        provider_error: String::new(),
    }
}

fn read_draft_markdown(object: &Map<String, Value>) -> String {
    object
        .get("draft_markdown")
        .or_else(|| object.get("draftMarkdown"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string()
}

fn read_agent_questions(object: &Map<String, Value>) -> Vec<AgentQuestion> {
    object
        .get("questions")
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .enumerate()
                .filter_map(|(index, value)| {
                    let object = value.as_object()?;
                    let label = object
                        .get("label")
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|value| !value.is_empty())?
                        .to_string();
                    let id = object
                        .get("id")
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .map(ToString::to_string)
                        .unwrap_or_else(|| format!("question-{}", index + 1));
                    let placeholder = object
                        .get("placeholder")
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .unwrap_or_default()
                        .to_string();
                    let required = object
                        .get("required")
                        .and_then(Value::as_bool)
                        .unwrap_or(true);
                    Some(AgentQuestion {
                        id,
                        label,
                        placeholder,
                        required,
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn read_agent_options(object: &Map<String, Value>) -> Vec<AgentOption> {
    object
        .get("options")
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .enumerate()
                .filter_map(|(index, value)| {
                    let object = value.as_object()?;
                    let label = object
                        .get("label")
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|value| !value.is_empty())?
                        .to_string();
                    let description = object
                        .get("description")
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .unwrap_or_default()
                        .to_string();
                    let followup_prompt = object
                        .get("followup_prompt")
                        .or_else(|| object.get("followupPrompt"))
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .unwrap_or(label.as_str())
                        .to_string();
                    let id = object
                        .get("id")
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .map(ToString::to_string)
                        .unwrap_or_else(|| format!("option-{}", index + 1));
                    Some(AgentOption {
                        id,
                        label,
                        description,
                        followup_prompt,
                    })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn read_agent_plan_steps(object: &Map<String, Value>) -> Vec<AgentPlanStep> {
    object
        .get("plan_steps")
        .or_else(|| object.get("planSteps"))
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .enumerate()
                .filter_map(|(index, value)| {
                    let object = value.as_object()?;
                    let label = object
                        .get("label")
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|value| !value.is_empty())?
                        .to_string();
                    let id = object
                        .get("id")
                        .and_then(Value::as_str)
                        .map(str::trim)
                        .filter(|value| !value.is_empty())
                        .map(ToString::to_string)
                        .unwrap_or_else(|| format!("step-{}", index + 1));
                    let status = normalize_plan_step_status(
                        object
                            .get("status")
                            .and_then(Value::as_str)
                            .unwrap_or(if index == 0 { "active" } else { "pending" }),
                    );
                    Some(AgentPlanStep { id, label, status })
                })
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn normalize_plan_step_status(value: &str) -> String {
    match value {
        "active" => "active".to_string(),
        "completed" => "completed".to_string(),
        _ => "pending".to_string(),
    }
}

fn resolve_turn_kind(
    object: &Map<String, Value>,
    draft_markdown: &str,
    questions: &[AgentQuestion],
    options: &[AgentOption],
    plan_steps: &[AgentPlanStep],
) -> String {
    let explicit = object
        .get("turn_kind")
        .or_else(|| object.get("turnKind"))
        .and_then(Value::as_str)
        .map(str::trim)
        .unwrap_or_default();

    match explicit {
        "final_answer" | "clarification" | "options" | "plan" | "blocked" => {
            explicit.to_string()
        }
        _ if !questions.is_empty() => "clarification".to_string(),
        _ if !options.is_empty() => "options".to_string(),
        _ if !plan_steps.is_empty() && draft_markdown.trim().is_empty() => "plan".to_string(),
        _ if !draft_markdown.trim().is_empty() => "final_answer".to_string(),
        _ => "blocked".to_string(),
    }
}

fn read_assistant_message(
    object: &Map<String, Value>,
    turn_kind: &str,
    summary: &str,
    draft_markdown: &str,
    questions: &[AgentQuestion],
    options: &[AgentOption],
    plan_steps: &[AgentPlanStep],
) -> String {
    if let Some(message) = object
        .get("assistant_message")
        .or_else(|| object.get("assistantMessage"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        return message.to_string();
    }

    match turn_kind {
        "clarification" if !questions.is_empty() => {
            let lines = questions
                .iter()
                .enumerate()
                .map(|(index, question)| format!("{}. {}", index + 1, question.label))
                .collect::<Vec<_>>();
            format!("继续之前，我需要你补充这些信息：\n{}", lines.join("\n"))
        }
        "options" if !options.is_empty() => "我先整理了几个可继续推进的方向，你选一个我就继续。".to_string(),
        "plan" if !plan_steps.is_empty() => "我建议先按这个计划推进。".to_string(),
        "blocked" => "当前信息还不足以安全继续，我先不直接改文稿。".to_string(),
        _ if !summary.trim().is_empty() => summary.to_string(),
        _ if !draft_markdown.trim().is_empty() => "已生成一版可继续审阅的结果。".to_string(),
        _ => "AI 已返回结果。".to_string(),
    }
}

fn completed_execution_steps(turn_kind: &str, summary: &str) -> Vec<AgentExecutionStep> {
    vec![
        AgentExecutionStep {
            id: "prepare-request".to_string(),
            label: "准备请求".to_string(),
            detail: "标准化请求并识别当前文档目标。".to_string(),
            status: "completed".to_string(),
            preview_text: "请求参数准备完成。".to_string(),
        },
        AgentExecutionStep {
            id: "build-context".to_string(),
            label: "整理上下文".to_string(),
            detail: "读取当前文档与相关工作区上下文。".to_string(),
            status: "completed".to_string(),
            preview_text: "上下文整理完成。".to_string(),
        },
        AgentExecutionStep {
            id: "request-model".to_string(),
            label: "请求模型".to_string(),
            detail: "向 AI 提供方发送本轮 Narrative 请求。".to_string(),
            status: "completed".to_string(),
            preview_text: "模型已返回结果。".to_string(),
        },
        AgentExecutionStep {
            id: "review-result".to_string(),
            label: "整理结果".to_string(),
            detail: format!("将模型结果整理为 {turn_kind} 回合，并同步到会话。"),
            status: "completed".to_string(),
            preview_text: if summary.trim().is_empty() {
                "结果整理完成。".to_string()
            } else {
                summary.to_string()
            },
        },
    ]
}

fn failed_execution_steps(step_id: &str, step_label: &str, error: &str) -> Vec<AgentExecutionStep> {
    vec![AgentExecutionStep {
        id: step_id.to_string(),
        label: step_label.to_string(),
        detail: "本轮 Narrative 请求在模型阶段失败。".to_string(),
        status: "failed".to_string(),
        preview_text: error.to_string(),
    }]
}

fn read_requested_actions(object: &Map<String, Value>) -> Vec<AgentActionRequest> {
    object
        .get("requested_actions")
        .or_else(|| object.get("requestedActions"))
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .enumerate()
                .filter_map(|(index, value)| parse_agent_action_request(value, index))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn parse_agent_action_request(value: &Value, index: usize) -> Option<AgentActionRequest> {
    let object = value.as_object()?;
    let action_type = object
        .get("action_type")
        .or_else(|| object.get("actionType"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_lowercase)
        .filter(|value| SUPPORTED_AGENT_ACTION_TYPES.contains(&value.as_str()))?;
    let title = object
        .get("title")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())?
        .to_string();
    let description = object
        .get("description")
        .and_then(Value::as_str)
        .map(str::trim)
        .unwrap_or_default()
        .to_string();
    let id = object
        .get("id")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .unwrap_or_else(|| format!("action-{}", index + 1));
    let payload = object.get("payload").cloned().unwrap_or_else(|| json!({}));
    let preview_only = object
        .get("preview_only")
        .or_else(|| object.get("previewOnly"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let affected_document_keys = read_string_list(
        object
            .get("affected_document_keys")
            .or_else(|| object.get("affectedDocumentKeys")),
    );
    let risk_level = normalize_risk(
        object
            .get("risk_level")
            .or_else(|| object.get("riskLevel"))
            .and_then(Value::as_str)
            .unwrap_or("medium"),
    );
    Some(AgentActionRequest {
        id,
        action_type,
        title,
        description,
        payload,
        approval_policy: "always_require_user".to_string(),
        preview_only,
        affected_document_keys,
        risk_level,
    })
}

fn build_source_document_keys(request: &NarrativeGenerateRequest) -> Vec<String> {
    let mut keys = Vec::new();
    let target_slug = request.target_slug.trim();
    if !target_slug.is_empty() {
        keys.push(target_slug.to_string());
    }
    for slug in &request.related_doc_slugs {
        let slug = slug.trim();
        if !slug.is_empty() && !keys.iter().any(|entry| entry == slug) {
            keys.push(slug.to_string());
        }
    }
    keys
}

fn build_review_queue_items(
    turn_kind: &str,
    plan_steps: &[AgentPlanStep],
    requested_actions: &[AgentActionRequest],
    draft_markdown: &str,
) -> Vec<ReviewQueueItem> {
    let mut items = Vec::new();

    if turn_kind == "plan" && !plan_steps.is_empty() {
        items.push(ReviewQueueItem {
            id: "review-plan".to_string(),
            kind: "plan".to_string(),
            title: "计划确认".to_string(),
            description: format!("当前回合包含 {} 个执行步骤待确认。", plan_steps.len()),
            status: "pending".to_string(),
        });
    }

    if turn_kind == "final_answer" && !draft_markdown.trim().is_empty() {
        items.push(ReviewQueueItem {
            id: "review-patch".to_string(),
            kind: "patch".to_string(),
            title: "结果审阅".to_string(),
            description: "当前回合生成了新的文稿内容，可继续审阅或应用。".to_string(),
            status: "pending".to_string(),
        });
    }

    for action in requested_actions {
        items.push(ReviewQueueItem {
            id: format!("review-action-{}", action.id),
            kind: "action".to_string(),
            title: action.title.clone(),
            description: action.description.clone(),
            status: "pending".to_string(),
        });
    }

    items
}

fn read_summary(object: &Map<String, Value>, action: &str, draft_markdown: &str) -> String {
    object
        .get("summary")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .unwrap_or_else(|| derive_summary_from_markdown(action, draft_markdown))
}

fn read_synthesis_notes(object: &Map<String, Value>) -> Vec<String> {
    read_string_list(
        object
            .get("synthesis_notes")
            .or_else(|| object.get("synthesisNotes")),
    )
}

fn derive_summary_from_markdown(action: &str, draft_markdown: &str) -> String {
    let heading = draft_markdown
        .lines()
        .map(str::trim)
        .find(|line| line.starts_with('#'))
        .map(|line| line.trim_start_matches('#').trim())
        .filter(|line| !line.is_empty());

    match (action, heading) {
        ("create", Some(title)) | ("derive_new_doc", Some(title)) => {
            format!("已生成《{title}》草稿。")
        }
        ("revise_document", Some(title)) => format!("已生成《{title}》的修订稿。"),
        (_, Some(title)) => format!("已生成《{title}》的 Markdown 建议。"),
        _ => default_summary_for_action(action).to_string(),
    }
}

fn read_string_list(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(ToString::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn failed_agent_run(agent_id: &str, label: &str, focus: &str, error: String) -> NarrativeAgentRun {
    NarrativeAgentRun {
        agent_id: agent_id.to_string(),
        label: label.to_string(),
        focus: focus.to_string(),
        status: "failed".to_string(),
        summary: String::new(),
        notes: Vec::new(),
        risk_level: "high".to_string(),
        draft_markdown: String::new(),
        raw_output: String::new(),
        provider_error: error,
    }
}

trait AgentRunExt {
    fn with_raw_output(self, raw_output: String) -> Self;
}

impl AgentRunExt for NarrativeAgentRun {
    fn with_raw_output(mut self, raw_output: String) -> Self {
        self.raw_output = raw_output;
        self
    }
}

fn highest_agent_risk(agent_runs: &[NarrativeAgentRun]) -> String {
    let risks = agent_runs
        .iter()
        .map(|run| run.risk_level.as_str())
        .collect::<Vec<_>>();
    highest_risk(risks)
}

fn highest_risk<I, S>(values: I) -> String
where
    I: IntoIterator<Item = S>,
    S: AsRef<str>,
{
    let mut best = "low";
    for value in values {
        let next = normalize_risk(value.as_ref());
        if risk_score(&next) > risk_score(best) {
            best = match next.as_str() {
                "high" => "high",
                "medium" => "medium",
                _ => "low",
            };
        }
    }
    best.to_string()
}

fn normalize_risk(value: &str) -> String {
    let normalized = value.trim().to_lowercase();
    match normalized.as_str() {
        "high" => "high".to_string(),
        "medium" => "medium".to_string(),
        _ => "low".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_agent_action_request_normalizes_fields_and_defaults() {
        let action_value = json!({
            "action_type": "CREATE_DERIVED_DOCUMENT",
            "title": "派生文稿",
            "riskLevel": "HIGH",
            "previewOnly": true
        });
        let action = parse_agent_action_request(&action_value, 0).unwrap();
        assert_eq!(action.id, "action-1");
        assert_eq!(action.action_type, "create_derived_document");
        assert_eq!(action.title, "派生文稿");
        assert!(action.preview_only);
        assert_eq!(action.risk_level, "high");
    }

    #[test]
    fn parse_agent_action_request_skips_unsupported_types() {
        let unsupported = json!({
            "action_type": "unsupported_action",
            "title": "不支持的"
        });
        assert!(parse_agent_action_request(&unsupported, 0).is_none());
    }

    #[test]
    fn read_requested_actions_filters_blank_titles() {
        let list = json!({
            "requested_actions": [
                {
                    "action_type": "create_derived_document",
                    "title": "有效",
                    "description": "有描述"
                },
                {
                    "action_type": "create_derived_document",
                    "title": "   "
                }
            ]
        });
        let parsed = read_requested_actions(list.as_object().unwrap());
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].description, "有描述");
    }

    #[test]
    fn read_requested_actions_respects_multiple_entries() {
        let list = json!({
            "requested_actions": [
                {
                    "action_type": "create_derived_document",
                    "title": "文稿 A"
                },
                {
                    "actionType": "apply_all_patches",
                    "title": "补丁",
                    "preview_only": false,
                    "risk_level": "Medium"
                }
            ]
        });
        let parsed = read_requested_actions(list.as_object().unwrap());
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].id, "action-1");
        assert_eq!(parsed[1].id, "action-2");
        assert_eq!(parsed[1].risk_level, "medium");
        assert!(!parsed[1].preview_only);
    }
}

fn risk_score(value: &str) -> i32 {
    match value {
        "high" => 3,
        "medium" => 2,
        _ => 1,
    }
}

fn perform_chat_completion(
    settings: &AiSettings,
    payload: &Value,
    progress: Option<&NarrativeGenerationProgressEmitter>,
) -> Result<ProviderSuccess, ProviderFailure> {
    perform_chat_completion_owned(settings.clone(), payload.clone(), progress.cloned())
}

fn perform_chat_completion_owned(
    settings: AiSettings,
    payload: Value,
    progress: Option<NarrativeGenerationProgressEmitter>,
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
    if api_key.is_empty() {
        return Err(ProviderFailure {
            status_code: 0,
            error: "API Key 未配置".to_string(),
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

    let client = build_http_client(settings.timeout_sec).map_err(|error| ProviderFailure {
        status_code: 0,
        error,
        raw_text: String::new(),
    })?;
    let base_max_tokens = requested_max_tokens(&payload);

    match perform_chat_completion_with_fallbacks(
        &client,
        &base_url,
        &api_key,
        &model,
        &payload,
        base_max_tokens,
        progress.as_ref(),
    ) {
        Ok(success) => Ok(success),
        Err(failure) if should_retry_with_more_tokens(&failure) => {
            let expanded_max_tokens = expanded_max_tokens(base_max_tokens);
            if expanded_max_tokens <= base_max_tokens {
                return Err(failure);
            }

            if let Some(progress) = &progress {
                progress.status_step(
                    "request-model",
                    "请求模型",
                    "模型输出被截断，已自动提高输出上限后重试...",
                );
            }

            perform_chat_completion_with_fallbacks(
                &client,
                &base_url,
                &api_key,
                &model,
                &payload,
                expanded_max_tokens,
                progress.as_ref(),
            )
        }
        Err(failure) => Err(failure),
    }
}

fn perform_chat_completion_with_fallbacks(
    client: &Client,
    base_url: &str,
    api_key: &str,
    model: &str,
    payload: &Value,
    max_tokens: u64,
    progress: Option<&NarrativeGenerationProgressEmitter>,
) -> Result<ProviderSuccess, ProviderFailure> {
    let request_body = build_chat_completion_request(model, payload, max_tokens, true);

    match send_chat_completion_request(client, base_url, api_key, &request_body, progress) {
        Ok(success) => Ok(success),
        Err(failure) if should_retry_without_stream(&failure) => {
            if let Some(progress) = progress {
                progress.status_step(
                    "request-model",
                    "请求模型",
                    "当前提供方不支持流式输出，已切回普通请求...",
                );
            }
            let fallback_request =
                build_chat_completion_request(model, payload, max_tokens, false);
            match send_chat_completion_request(client, base_url, api_key, &fallback_request, progress)
            {
                Ok(success) => Ok(success),
                Err(second_failure) => Err(second_failure),
            }
        }
        Err(failure) => Err(failure),
    }
}

fn build_http_client(timeout_sec: u64) -> Result<Client, String> {
    Client::builder()
        .timeout(Duration::from_secs(timeout_sec.max(5)))
        .build()
        .map_err(|error| format!("failed to create HTTP client: {error}"))
}

fn build_chat_completion_request(
    model: &str,
    payload: &Value,
    max_tokens: u64,
    stream: bool,
) -> Value {
    let mut request = Map::new();
    request.insert("model".to_string(), json!(model));
    request.insert(
        "messages".to_string(),
        payload
            .get("messages")
            .cloned()
            .unwrap_or_else(|| json!([])),
    );
    request.insert(
        "temperature".to_string(),
        json!(payload
            .get("temperature")
            .and_then(Value::as_f64)
            .unwrap_or(0.45)),
    );
    request.insert(
        "max_tokens".to_string(),
        json!(max_tokens),
    );
    request.insert("stream".to_string(), json!(stream));
    Value::Object(request)
}

fn send_chat_completion_request(
    client: &Client,
    base_url: &str,
    api_key: &str,
    request_body: &Value,
    progress: Option<&NarrativeGenerationProgressEmitter>,
) -> Result<ProviderSuccess, ProviderFailure> {
    let mut last_failure: Option<ProviderFailure> = None;

    for attempt in 0..=1 {
        let response = client
            .post(format!("{base_url}/chat/completions"))
            .bearer_auth(api_key)
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .json(request_body)
            .send();

        match response {
            Ok(response) => {
                let status = response.status().as_u16();
                if !(200..300).contains(&status) {
                    let raw_body = response.text().unwrap_or_default();
                    let failure = ProviderFailure {
                        status_code: status,
                        error: map_http_error(status, &raw_body),
                        raw_text: raw_body,
                    };
                    if attempt == 0 && (status == 429 || status >= 500) {
                        thread::sleep(Duration::from_secs(1));
                        last_failure = Some(failure);
                        continue;
                    }
                    return Err(failure);
                }

                let content_type = response
                    .headers()
                    .get(reqwest::header::CONTENT_TYPE)
                    .and_then(|value| value.to_str().ok())
                    .unwrap_or_default()
                    .to_lowercase();

                if content_type.contains("text/event-stream") {
                    if let Some(progress) = progress {
                        progress.status_step("request-model", "请求模型", "正在接收模型输出...");
                    }
                    return read_streaming_chat_completion(response, status, progress);
                }

                if let Some(progress) = progress {
                    progress.status_step("request-model", "请求模型", "正在整理模型返回内容...");
                }
                let raw_body = response.text().unwrap_or_default();
                return parse_non_stream_response(raw_body, status, progress);
            }
            Err(error) => {
                let failure = ProviderFailure {
                    status_code: 0,
                    error: format!("网络请求失败: {error}"),
                    raw_text: String::new(),
                };
                if attempt == 0 {
                    thread::sleep(Duration::from_secs(1));
                    last_failure = Some(failure);
                    continue;
                }
                return Err(failure);
            }
        }
    }

    Err(last_failure.unwrap_or(ProviderFailure {
        status_code: 0,
        error: "AI 请求失败".to_string(),
        raw_text: String::new(),
    }))
}

fn should_retry_without_stream(failure: &ProviderFailure) -> bool {
    if failure.status_code != 400 {
        return false;
    }

    let combined = format!("{} {}", failure.error, failure.raw_text).to_lowercase();
    combined.contains("stream")
        && (combined.contains("not supported")
            || combined.contains("unsupported")
            || combined.contains("not valid"))
}

fn should_retry_with_more_tokens(failure: &ProviderFailure) -> bool {
    if failure.status_code == 0 {
        return false;
    }

    let normalized = failure.error.to_lowercase();
    normalized.contains("ai 输出被截断")
        || (normalized.contains("eof while parsing")
            && (normalized.contains("json") || normalized.contains("string")))
}

fn requested_max_tokens(payload: &Value) -> u64 {
    payload
        .get("max_tokens")
        .and_then(Value::as_u64)
        .unwrap_or(4000)
        .max(1024)
}

fn expanded_max_tokens(current_max_tokens: u64) -> u64 {
    current_max_tokens.saturating_mul(2).min(8000)
}

fn parse_non_stream_response(
    raw_body: String,
    status: u16,
    progress: Option<&NarrativeGenerationProgressEmitter>,
) -> Result<ProviderSuccess, ProviderFailure> {
    let response_data: Value = serde_json::from_str(&raw_body).map_err(|error| ProviderFailure {
        status_code: status,
        error: format!("响应不是合法 JSON: {error}"),
        raw_text: raw_body.clone(),
    })?;
    let raw_content = extract_message_content(&response_data);
    if let Some(progress) = progress {
        let preview = if raw_content.trim().is_empty() {
            "AI 已返回响应，正在整理结果...".to_string()
        } else {
            raw_content.clone()
        };
        progress.delta_step(
            "request-model",
            "请求模型",
            "AI 已返回完整响应，正在整理结果...",
            preview,
        );
    }
    let payload = extract_narrative_payload(&raw_content).map_err(|error| ProviderFailure {
        status_code: status,
        error,
        raw_text: raw_content.clone(),
    })?;
    Ok(ProviderSuccess {
        raw_text: raw_content,
        payload,
    })
}

fn read_streaming_chat_completion(
    response: reqwest::blocking::Response,
    status: u16,
    progress: Option<&NarrativeGenerationProgressEmitter>,
) -> Result<ProviderSuccess, ProviderFailure> {
    let mut raw_content = String::new();
    let reader = BufReader::new(response);

    for line_result in reader.lines() {
        let line = line_result.map_err(|error| ProviderFailure {
            status_code: status,
            error: format!("读取流式响应失败: {error}"),
            raw_text: raw_content.clone(),
        })?;
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with(':') {
            continue;
        }
        let Some(data) = trimmed.strip_prefix("data:") else {
            continue;
        };
        let data = data.trim();
        if data == "[DONE]" {
            break;
        }

        let event: Value = serde_json::from_str(data).map_err(|error| ProviderFailure {
            status_code: status,
            error: format!("流式响应片段不是合法 JSON: {error}"),
            raw_text: raw_content.clone(),
        })?;
        let delta = extract_stream_delta_content(&event);
        if !delta.is_empty() {
            raw_content.push_str(&delta);
            if let Some(progress) = progress {
                progress.delta_step(
                    "request-model",
                    "请求模型",
                    "AI 正在输出内容...",
                    raw_content.clone(),
                );
            }
        }
    }

    let payload = extract_narrative_payload(&raw_content).map_err(|error| ProviderFailure {
        status_code: status,
        error,
        raw_text: raw_content.clone(),
    })?;
    Ok(ProviderSuccess {
        raw_text: raw_content,
        payload,
    })
}

fn extract_stream_delta_content(event: &Value) -> String {
    let Some(choice) = event
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|choices| choices.first())
    else {
        return String::new();
    };

    let Some(delta) = choice.get("delta") else {
        return String::new();
    };

    if let Some(content) = delta.get("content") {
        if let Some(text) = content.as_str() {
            return text.to_string();
        }

        if let Some(parts) = content.as_array() {
            return parts
                .iter()
                .filter_map(|part| {
                    part.get("text")
                        .and_then(Value::as_str)
                        .or_else(|| part.as_str())
                })
                .collect::<String>();
        }
    }

    String::new()
}

fn extract_message_content(response_data: &Value) -> String {
    response_data
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|choices| choices.first())
        .and_then(|choice| choice.get("message"))
        .and_then(|message| message.get("content"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_string()
}

fn extract_narrative_payload(raw_content: &str) -> Result<Value, String> {
    let trimmed = raw_content.trim();
    if trimmed.is_empty() {
        return Err("AI 未返回可解析内容".to_string());
    }

    if let Ok(payload) = serde_json::from_str::<Value>(trimmed) {
        if payload.is_object() {
            return Ok(payload);
        }
    }

    let draft_markdown = normalize_markdown_output(trimmed);
    if draft_markdown.is_empty() {
        return Err("AI 未返回可应用的 Markdown 内容".to_string());
    }

    Ok(json!({
        "draft_markdown": draft_markdown,
    }))
}

fn normalize_markdown_output(raw_content: &str) -> String {
    let trimmed = raw_content.trim();
    if trimmed.is_empty() {
        return String::new();
    }

    let lines = trimmed.lines().collect::<Vec<_>>();
    if lines.len() >= 2
        && lines.first().is_some_and(|line| line.trim_start().starts_with("```"))
        && lines.last().is_some_and(|line| line.trim() == "```")
    {
        return lines[1..lines.len() - 1].join("\n").trim().to_string();
    }

    trimmed.to_string()
}

fn map_http_error(status: u16, raw_body: &str) -> String {
    let provider_message = extract_provider_error_message(raw_body);

    match status {
        400 => with_provider_detail(
            "AI 请求无效，请检查 Base URL、模型或请求参数。",
            provider_message.as_deref(),
        ),
        401 => with_provider_detail(
            "AI 认证失败，请检查 API Key 是否正确、格式是否有效。",
            provider_message.as_deref(),
        ),
        403 => with_provider_detail(
            "AI 请求被拒绝，请检查权限或账号状态。",
            provider_message.as_deref(),
        ),
        404 => with_provider_detail(
            "AI 接口不存在，请检查 Base URL 或接口路径。",
            provider_message.as_deref(),
        ),
        408 => "AI 请求超时，请检查网络或增大 Timeout。".to_string(),
        429 => with_provider_detail(
            "AI 请求过于频繁，请稍后再试。",
            provider_message.as_deref(),
        ),
        500..=599 => with_provider_detail(
            &format!("AI 服务暂时不可用 ({status})"),
            provider_message.as_deref(),
        ),
        _ => {
            let suffix = if raw_body.trim().is_empty() {
                String::new()
            } else {
                format!(": {}", summarize_error_body(raw_body))
            };
            format!("AI 请求失败({status}){suffix}")
        }
    }
}

fn extract_provider_error_message(raw_text: &str) -> Option<String> {
    let payload: Value = serde_json::from_str(raw_text).ok()?;
    payload
        .get("error")
        .and_then(|value| value.get("message"))
        .and_then(Value::as_str)
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn with_provider_detail(base: &str, detail: Option<&str>) -> String {
    match detail {
        Some(detail) => format!("{base} 服务端返回：{detail}"),
        None => base.to_string(),
    }
}

fn summarize_error_body(raw_body: &str) -> String {
    let trimmed = raw_body.trim();
    if trimmed.is_empty() {
        return "empty response".to_string();
    }

    let collapsed = trimmed.split_whitespace().collect::<Vec<_>>().join(" ");
    if collapsed.chars().count() <= 240 {
        return collapsed;
    }

    collapsed.chars().take(240).collect::<String>() + "..."
}

fn normalize_provider_error(error: &ProviderFailure) -> String {
    if error.error.trim().is_empty() {
        if error.status_code > 0 {
            format!("AI 请求失败({})", error.status_code)
        } else {
            "AI 请求失败".to_string()
        }
    } else {
        error.error.clone()
    }
}

fn summarize_response_preview(response: &NarrativeGenerateResponse) -> String {
    let summary = response.summary.trim();
    if !summary.is_empty() {
        return summary.to_string();
    }
    let draft = response.draft_markdown.trim();
    if !draft.is_empty() {
        return draft.to_string();
    }
    if !response.provider_error.trim().is_empty() {
        return response.provider_error.clone();
    }
    "AI 输出完成，正在同步到会话。".to_string()
}

fn default_summary_for_action(action: &str) -> &'static str {
    match action {
        "create" => "已根据当前模板生成文稿草稿。",
        "revise_document" => "已基于当前文档上下文生成修订稿。",
        "rewrite_selection" => "已生成选区替换内容。",
        "expand_selection" => "已生成选区扩写内容。",
        "insert_after_selection" => "已生成选区后的插入内容。",
        "derive_new_doc" => "已生成派生文稿草稿。",
        _ => "文稿草稿已生成，可开始审阅。",
    }
}
