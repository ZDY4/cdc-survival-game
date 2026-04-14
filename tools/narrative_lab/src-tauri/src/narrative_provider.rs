use std::{
    collections::{BTreeSet, HashMap},
    sync::{Arc, Mutex},
    time::Duration,
};

use futures_util::StreamExt;
use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use tauri::{AppHandle, Emitter, State};
use tokio::time::sleep;
use tokio_util::sync::CancellationToken;

use crate::ai_settings::{read_ai_settings, AiSettings};
use crate::narrative_context::build_narrative_context;
use crate::narrative_review::{
    build_review_result, prompt_debug_payload, validate_selection, NarrativeSelectionRange,
};
use crate::narrative_templates::{default_markdown, doc_type_label, is_known_doc_type};
use crate::narrative_workspace::{resolve_connected_project_root, resolve_workspace_root};

const NARRATIVE_GENERATION_PROGRESS_EVENT: &str = "narrative:generation-progress";
const NARRATIVE_REQUEST_CANCELLED_CODE: &str = "narrative_request_cancelled";
const NARRATIVE_REQUEST_CANCELLED_MESSAGE: &str = "[narrative_request_cancelled] 当前请求已取消";

#[derive(Clone, Default)]
pub struct NarrativeRequestRegistry {
    inner: Arc<Mutex<HashMap<String, NarrativeRequestEntry>>>,
}

#[derive(Clone)]
struct NarrativeRequestEntry {
    stage: String,
    cancellation: CancellationToken,
}

#[derive(Debug, Clone)]
struct RequestedActionsBackfillResult {
    payload: Value,
    diagnostic_flags: Vec<String>,
    agent_runs: Vec<NarrativeAgentRun>,
}

impl RequestedActionsBackfillResult {
    fn passthrough(payload: Value) -> Self {
        Self {
            payload,
            diagnostic_flags: Vec::new(),
            agent_runs: Vec::new(),
        }
    }
}

#[derive(Debug, Clone)]
struct StructuredTurnKindOutput {
    raw_output: String,
    payload: Value,
}

#[derive(Debug, Clone)]
struct StructuredTurnKindAttempt {
    output: Option<StructuredTurnKindOutput>,
    diagnostic_flags: Vec<String>,
    agent_runs: Vec<NarrativeAgentRun>,
    classified_turn_kind: Option<String>,
}

impl StructuredTurnKindAttempt {
    fn skipped() -> Self {
        Self {
            output: None,
            diagnostic_flags: Vec::new(),
            agent_runs: Vec::new(),
            classified_turn_kind: None,
        }
    }
}

#[derive(Debug, Clone, Copy)]
enum ProviderRequestStage {
    PrimaryGeneration,
    TurnKindClassification,
    StructuredContent,
    RequestedActionsBackfill,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeCancelRequestResult {
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub stage: Option<String>,
}

impl NarrativeRequestRegistry {
    fn register(&self, request_id: String, stage: &str) -> Result<CancellationToken, String> {
        let mut guard = self
            .inner
            .lock()
            .map_err(|_| "请求状态注册失败：状态锁不可用".to_string())?;
        let cancellation = CancellationToken::new();
        guard.insert(
            request_id,
            NarrativeRequestEntry {
                stage: stage.to_string(),
                cancellation: cancellation.clone(),
            },
        );
        Ok(cancellation)
    }

    fn remove(&self, request_id: &str) {
        if let Ok(mut guard) = self.inner.lock() {
            guard.remove(request_id);
        }
    }

    fn cancel(&self, request_id: &str) -> Result<NarrativeCancelRequestResult, String> {
        let maybe_entry = {
            let guard = self
                .inner
                .lock()
                .map_err(|_| "取消失败：状态锁不可用".to_string())?;
            guard.get(request_id).cloned()
        };

        match maybe_entry {
            Some(entry) => {
                entry.cancellation.cancel();
                Ok(NarrativeCancelRequestResult {
                    status: "cancelled".to_string(),
                    stage: Some(entry.stage),
                })
            }
            None => Ok(NarrativeCancelRequestResult {
                status: "already_finished".to_string(),
                stage: None,
            }),
        }
    }
}

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

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolveNarrativeActionIntentInput {
    #[serde(default)]
    pub request_id: Option<String>,
    pub submitted_prompt: String,
    pub doc_type: String,
    pub target_slug: String,
    pub user_prompt: String,
    pub editor_instruction: String,
    pub current_markdown: String,
    #[serde(default)]
    pub related_doc_slugs: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ResolveNarrativeActionIntentResult {
    pub action: Option<String>,
    pub assistant_message: String,
    pub questions: Vec<AgentQuestion>,
    pub options: Vec<AgentOption>,
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
pub struct NarrativeTurnKindCorrection {
    pub from: String,
    pub to: String,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeResponseStructureSummary {
    pub question_count: usize,
    pub option_count: usize,
    pub plan_step_count: usize,
    pub requested_action_count: usize,
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
    pub turn_kind_source: String,
    pub turn_kind_correction: Option<NarrativeTurnKindCorrection>,
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
    pub response_structure: NarrativeResponseStructureSummary,
    pub diagnostic_flags: Vec<String>,
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
const SUPPORTED_DOCUMENT_STATUSES: &[&str] =
    &["draft", "review", "active", "completed", "archived"];

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

#[derive(Debug, Clone)]
struct TurnKindResolution {
    kind: String,
    source: String,
    correction: Option<NarrativeTurnKindCorrection>,
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
    request_registry: State<'_, NarrativeRequestRegistry>,
    workspace_root: String,
    project_root: Option<String>,
    request: NarrativeGenerateRequest,
) -> Result<NarrativeGenerateResponse, String> {
    let registry = request_registry.inner().clone();
    let request_id = normalize_optional_request_id(request.request_id.as_deref());
    run_with_registered_request(
        registry,
        request_id,
        "generating",
        move |cancellation| async move {
            run_narrative_generation(
                &app,
                &workspace_root,
                project_root.as_deref(),
                request,
                cancellation.as_ref(),
            )
            .await
        },
    )
    .await
}

#[tauri::command]
pub async fn revise_narrative_draft(
    app: AppHandle,
    request_registry: State<'_, NarrativeRequestRegistry>,
    workspace_root: String,
    project_root: Option<String>,
    request: NarrativeGenerateRequest,
) -> Result<NarrativeGenerateResponse, String> {
    let registry = request_registry.inner().clone();
    let request_id = normalize_optional_request_id(request.request_id.as_deref());
    run_with_registered_request(
        registry,
        request_id,
        "generating",
        move |cancellation| async move {
            run_narrative_generation(
                &app,
                &workspace_root,
                project_root.as_deref(),
                request,
                cancellation.as_ref(),
            )
            .await
        },
    )
    .await
}

#[tauri::command]
pub async fn resolve_narrative_action_intent(
    app: AppHandle,
    request_registry: State<'_, NarrativeRequestRegistry>,
    workspace_root: String,
    project_root: Option<String>,
    input: ResolveNarrativeActionIntentInput,
) -> Result<ResolveNarrativeActionIntentResult, String> {
    let registry = request_registry.inner().clone();
    let request_id = normalize_optional_request_id(input.request_id.as_deref());
    run_with_registered_request(
        registry,
        request_id,
        "resolving_intent",
        move |cancellation| async move {
            run_narrative_action_intent_resolution(
                &app,
                &workspace_root,
                project_root.as_deref(),
                input,
                cancellation.as_ref(),
            )
            .await
        },
    )
    .await
}

#[tauri::command]
pub fn cancel_narrative_request(
    request_id: String,
    request_registry: State<'_, NarrativeRequestRegistry>,
) -> Result<NarrativeCancelRequestResult, String> {
    let normalized = request_id.trim();
    if normalized.is_empty() {
        return Err("requestId 不能为空".to_string());
    }
    request_registry.inner().cancel(normalized)
}

fn normalize_optional_request_id(request_id: Option<&str>) -> Option<String> {
    request_id
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
}

async fn run_with_registered_request<T, F, Fut>(
    registry: NarrativeRequestRegistry,
    request_id: Option<String>,
    stage: &str,
    run: F,
) -> Result<T, String>
where
    F: FnOnce(Option<CancellationToken>) -> Fut,
    Fut: std::future::Future<Output = Result<T, String>>,
{
    let cancellation = if let Some(id) = request_id.as_ref() {
        Some(registry.register(id.clone(), stage)?)
    } else {
        None
    };

    let result = run(cancellation).await;
    if let Some(id) = request_id.as_ref() {
        registry.remove(id);
    }
    result
}

async fn run_narrative_action_intent_resolution(
    app: &AppHandle,
    workspace_root: &str,
    project_root: Option<&str>,
    mut input: ResolveNarrativeActionIntentInput,
    cancellation: Option<&CancellationToken>,
) -> Result<ResolveNarrativeActionIntentResult, String> {
    ensure_not_cancelled(cancellation)?;
    input.request_id = normalize_optional_request_id(input.request_id.as_deref());
    input.submitted_prompt = input.submitted_prompt.trim().to_string();
    input.doc_type = input.doc_type.trim().to_lowercase();
    input.target_slug = input.target_slug.trim().to_string();
    input.user_prompt = input.user_prompt.trim().to_string();
    input.editor_instruction = input.editor_instruction.trim().to_string();
    input.current_markdown = input.current_markdown.trim().to_string();
    input.related_doc_slugs = input
        .related_doc_slugs
        .into_iter()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .collect();

    if !is_known_doc_type(&input.doc_type) {
        return Err(format!("未知文稿类型: {}", input.doc_type));
    }
    if input.submitted_prompt.is_empty() {
        return Err("请至少填写本轮需求".to_string());
    }

    ensure_not_cancelled(cancellation)?;
    let settings = runtime_ai_settings(read_ai_settings(app)?.normalized());
    let workspace_root_path = resolve_workspace_root(workspace_root)?;
    let project_root_path = resolve_connected_project_root(project_root)?;
    let context_request = NarrativeGenerateRequest {
        request_id: input.request_id.clone(),
        doc_type: input.doc_type.clone(),
        target_slug: input.target_slug.clone(),
        action: "revise_document".to_string(),
        user_prompt: input.user_prompt.clone(),
        editor_instruction: input.editor_instruction.clone(),
        current_markdown: input.current_markdown.clone(),
        selected_range: None,
        selected_text: String::new(),
        related_doc_slugs: input.related_doc_slugs.clone(),
        derived_target_doc_type: None,
    };
    let context = build_narrative_context(
        &workspace_root_path,
        project_root_path.as_deref(),
        &context_request,
        settings.max_context_records,
    )?;
    ensure_not_cancelled(cancellation)?;
    let payload = build_action_intent_resolution_payload(&input, &context.context, &settings);
    let success = perform_chat_completion(&settings, &payload, None, cancellation)
        .await
        .map_err(map_provider_failure_to_result_error)?;
    Ok(parse_action_intent_resolution_payload(
        &success.payload,
        &input.submitted_prompt,
    ))
}

async fn run_narrative_generation(
    app: &AppHandle,
    workspace_root: &str,
    project_root: Option<&str>,
    mut request: NarrativeGenerateRequest,
    cancellation: Option<&CancellationToken>,
) -> Result<NarrativeGenerateResponse, String> {
    let progress = NarrativeGenerationProgressEmitter::from_request(app, &request);
    if let Some(progress) = &progress {
        progress.status_step("prepare-request", "准备请求", "正在准备 AI 请求...");
    }
    ensure_not_cancelled_with_progress(cancellation, progress.as_ref())?;
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
    ensure_not_cancelled_with_progress(cancellation, progress.as_ref())?;
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
    ensure_not_cancelled_with_progress(cancellation, progress.as_ref())?;
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
    ensure_not_cancelled(cancellation)?;
    let context = build_narrative_context(
        &workspace_root_path,
        project_root_path.as_deref(),
        &request,
        settings.max_context_records,
    )?;
    ensure_not_cancelled(cancellation)?;
    if let Some(progress) = &progress {
        progress.completed_step(
            "build-context",
            "整理上下文",
            "上下文整理完成。",
            format!("已收集 {} 条上下文引用。", context.used_context_refs.len()),
        );
        progress.status_step("request-model", "请求模型", "正在连接 AI 提供方...");
    }

    let staged_attempt = attempt_structured_turn_kind_generation(
        &settings,
        &request,
        &context.context,
        progress.as_ref(),
        cancellation,
    )
    .await?;

    if let Some(output) = staged_attempt.output {
        if let Some(progress) = &progress {
            progress.completed_step(
                "request-model",
                "请求模型",
                "分阶段模型输出接收完成。",
                output.raw_output.clone(),
            );
            progress.status_step("review-result", "整理结果", "正在整理最终结果...");
        }
        let mut response = finalize_generation(
            "single_agent",
            request,
            selection,
            context,
            output.raw_output,
            output.payload,
            staged_attempt.agent_runs,
        )?;
        append_unique_strings(
            &mut response.diagnostic_flags,
            staged_attempt.diagnostic_flags,
        );
        let staged_flags = response.diagnostic_flags.clone();
        if let Some(prompt_debug) = response.prompt_debug.as_object_mut() {
            prompt_debug.insert(
                "structuredTurnKindRoute".to_string(),
                json!({
                    "attempted": staged_flags
                        .iter()
                        .any(|flag| flag == "structured_turn_kind_stage_attempted"),
                    "classifiedTurnKind": staged_attempt.classified_turn_kind,
                    "usedStagedOutput": true,
                    "flags": staged_flags,
                }),
            );
        }
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
        return Ok(response);
    }

    let payload = build_single_agent_payload(&request, &context.context, &settings);
    match perform_chat_completion_for_stage(
        &settings,
        ProviderRequestStage::PrimaryGeneration,
        &payload,
        progress.as_ref(),
        cancellation,
    )
    .await
    {
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
            let primary_agent_run = build_single_agent_run(&success.payload, &success.raw_text);
            let backfill = maybe_backfill_requested_actions(
                &settings,
                &request,
                &context.context,
                &success.payload,
                progress.as_ref(),
                cancellation,
            )
            .await?;
            let mut agent_runs = staged_attempt.agent_runs;
            agent_runs.push(primary_agent_run);
            agent_runs.extend(backfill.agent_runs);
            let mut response = finalize_generation(
                "single_agent",
                request,
                selection,
                context,
                success.raw_text,
                backfill.payload,
                agent_runs,
            )?;
            append_unique_strings(
                &mut response.diagnostic_flags,
                staged_attempt.diagnostic_flags,
            );
            append_unique_strings(&mut response.diagnostic_flags, backfill.diagnostic_flags);
            let backfill_flags = response.diagnostic_flags.clone();
            if let Some(prompt_debug) = response.prompt_debug.as_object_mut() {
                prompt_debug.insert(
                    "structuredTurnKindRoute".to_string(),
                    json!({
                        "attempted": backfill_flags
                            .iter()
                            .any(|flag| flag == "structured_turn_kind_stage_attempted"),
                        "classifiedTurnKind": staged_attempt.classified_turn_kind,
                        "usedStagedOutput": false,
                        "flags": backfill_flags,
                    }),
                );
                prompt_debug.insert(
                    "requestedActionsBackfill".to_string(),
                    json!({
                        "attempted": backfill_flags
                            .iter()
                            .any(|flag| flag == "requested_actions_backfill_attempted"),
                        "succeeded": backfill_flags
                            .iter()
                            .any(|flag| flag == "requested_actions_backfilled"),
                        "flags": backfill_flags,
                    }),
                );
            }
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
            if is_cancelled_provider_failure(&error) {
                if let Some(progress) = &progress {
                    progress.error_step(
                        "request-model",
                        "请求模型",
                        "当前请求已取消",
                        "当前请求已取消",
                    );
                    progress.completed("当前请求已取消", "当前请求已取消");
                }
                return Err(cancelled_request_error());
            }
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
                turn_kind_source: "provider_error".to_string(),
                turn_kind_correction: None,
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
                response_structure: NarrativeResponseStructureSummary {
                    question_count: 0,
                    option_count: 0,
                    plan_step_count: 0,
                    requested_action_count: 0,
                },
                diagnostic_flags: vec!["provider_error".to_string()],
                requires_user_reply: false,
                execution_steps: failed_execution_steps(
                    "request-model",
                    "请求模型",
                    &provider_error,
                ),
                current_step_id: Some("request-model".to_string()),
                requested_actions: Vec::new(),
                source_document_keys: build_source_document_keys(&request),
                provenance_refs,
                review_queue_items: Vec::new(),
            })
        }
    }
}

async fn attempt_structured_turn_kind_generation(
    settings: &AiSettings,
    request: &NarrativeGenerateRequest,
    context: &Value,
    progress: Option<&NarrativeGenerationProgressEmitter>,
    cancellation: Option<&CancellationToken>,
) -> Result<StructuredTurnKindAttempt, String> {
    if !should_use_structured_turn_kind_staging(settings, request) {
        return Ok(StructuredTurnKindAttempt::skipped());
    }

    let mut attempt = StructuredTurnKindAttempt::skipped();
    attempt
        .diagnostic_flags
        .push("structured_turn_kind_stage_attempted".to_string());

    if let Some(progress) = progress {
        progress.status_step(
            "request-model",
            "请求模型",
            "正在执行短分类，判断本轮更适合哪种对话回合...",
        );
    }

    let classification_payload = build_turn_kind_classification_payload(request, context, settings);
    let classification = match perform_chat_completion_for_stage(
        settings,
        ProviderRequestStage::TurnKindClassification,
        &classification_payload,
        None,
        cancellation,
    )
    .await
    {
        Ok(success) => success,
        Err(error) => {
            if is_cancelled_provider_failure(&error) {
                return Err(cancelled_request_error());
            }
            attempt.diagnostic_flags.push(
                if is_provider_timeout(&error) {
                    "structured_turn_kind_classification_timeout"
                } else {
                    "structured_turn_kind_classification_fallback"
                }
                .to_string(),
            );
            attempt.agent_runs.push(
                failed_agent_run(
                    "turn-kind-classifier",
                    "回合分类助手",
                    "先判断本轮更适合 clarification/options/plan/final_answer。",
                    normalize_provider_error(&error),
                )
                .with_raw_output(error.raw_text),
            );
            return Ok(attempt);
        }
    };

    let classified_turn_kind = classify_turn_kind_from_payload(&classification.payload, request);
    let Some(turn_kind) = classified_turn_kind else {
        attempt
            .diagnostic_flags
            .push("structured_turn_kind_classification_fallback".to_string());
        attempt.agent_runs.push(build_turn_kind_classifier_run(
            &classification.payload,
            &classification.raw_text,
            "final_answer",
        ));
        return Ok(attempt);
    };

    attempt.classified_turn_kind = Some(turn_kind.clone());
    attempt.agent_runs.push(build_turn_kind_classifier_run(
        &classification.payload,
        &classification.raw_text,
        &turn_kind,
    ));
    attempt
        .diagnostic_flags
        .push(format!("structured_turn_kind_classified_{turn_kind}"));

    if turn_kind == "final_answer" {
        attempt
            .diagnostic_flags
            .push("structured_turn_kind_fell_back_to_full_generation".to_string());
        return Ok(attempt);
    }

    if let Some(progress) = progress {
        progress.status_step(
            "request-model",
            "请求模型",
            format!("已判定为 {turn_kind}，正在生成对应内容..."),
        );
    }

    let content_payload =
        build_structured_turn_kind_content_payload(&turn_kind, request, context, settings);
    let content = match perform_chat_completion_for_stage(
        settings,
        ProviderRequestStage::StructuredContent,
        &content_payload,
        None,
        cancellation,
    )
    .await
    {
        Ok(success) => success,
        Err(error) => {
            if is_cancelled_provider_failure(&error) {
                return Err(cancelled_request_error());
            }
            attempt.diagnostic_flags.push(
                if is_provider_timeout(&error) {
                    "structured_turn_kind_generation_timeout"
                } else {
                    "structured_turn_kind_generation_fallback"
                }
                .to_string(),
            );
            attempt.agent_runs.push(
                failed_agent_run(
                    "turn-kind-content",
                    "结构化内容助手",
                    "根据已分类回合生成 questions/options/plan 等窄结构内容。",
                    normalize_provider_error(&error),
                )
                .with_raw_output(error.raw_text),
            );
            return Ok(attempt);
        }
    };

    attempt.agent_runs.push(build_turn_kind_content_run(
        &content.payload,
        &content.raw_text,
        &turn_kind,
    ));
    attempt
        .diagnostic_flags
        .push("structured_turn_kind_generation_succeeded".to_string());
    attempt.output = Some(StructuredTurnKindOutput {
        raw_output: content.raw_text,
        payload: content.payload,
    });
    Ok(attempt)
}

async fn maybe_backfill_requested_actions(
    settings: &AiSettings,
    request: &NarrativeGenerateRequest,
    context: &Value,
    primary_payload: &Value,
    progress: Option<&NarrativeGenerationProgressEmitter>,
    cancellation: Option<&CancellationToken>,
) -> Result<RequestedActionsBackfillResult, String> {
    let Some(primary_object) = primary_payload.as_object() else {
        return Ok(RequestedActionsBackfillResult::passthrough(
            primary_payload.clone(),
        ));
    };
    if !should_attempt_requested_actions_backfill(request, primary_object) {
        return Ok(RequestedActionsBackfillResult::passthrough(
            primary_payload.clone(),
        ));
    }

    if let Some(progress) = progress {
        progress.status_step(
            "review-result",
            "整理结果",
            "正文已生成，正在补提取待批准动作...",
        );
    }

    let mut result = RequestedActionsBackfillResult::passthrough(primary_payload.clone());
    result
        .diagnostic_flags
        .push("requested_actions_backfill_attempted".to_string());

    let extraction_payload =
        build_requested_actions_extraction_payload(request, context, primary_payload, settings);

    match perform_chat_completion_for_stage(
        settings,
        ProviderRequestStage::RequestedActionsBackfill,
        &extraction_payload,
        None,
        cancellation,
    )
    .await
    {
        Ok(success) => {
            let extracted_object = success.payload.as_object().cloned().unwrap_or_default();
            let extracted_actions = read_requested_actions(&extracted_object);
            if extracted_actions.is_empty() {
                result
                    .diagnostic_flags
                    .push("requested_actions_backfill_empty".to_string());
                result
                    .diagnostic_flags
                    .extend(analyze_requested_actions_backfill_payload(&success.payload));
                result.agent_runs.push(build_requested_actions_backfill_run(
                    &success.payload,
                    &success.raw_text,
                ));
                return Ok(result);
            }

            result.payload =
                merge_requested_actions_into_payload(primary_payload, &extracted_actions);
            result
                .diagnostic_flags
                .push("requested_actions_backfilled".to_string());
            result.agent_runs.push(build_requested_actions_backfill_run(
                &success.payload,
                &success.raw_text,
            ));
            Ok(result)
        }
        Err(error) => {
            if is_cancelled_provider_failure(&error) {
                if let Some(progress) = progress {
                    progress.error_step(
                        "review-result",
                        "整理结果",
                        "当前请求已取消",
                        "当前请求已取消",
                    );
                    progress.completed("当前请求已取消", "当前请求已取消");
                }
                return Err(cancelled_request_error());
            }
            result
                .diagnostic_flags
                .push(classify_requested_actions_backfill_failure(&error).to_string());
            result.agent_runs.push(
                failed_agent_run(
                    "action-extractor",
                    "动作提取助手",
                    "在正文已生成后补提取待批准动作。",
                    normalize_provider_error(&error),
                )
                .with_raw_output(error.raw_text),
            );
            Ok(result)
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
    let turn_kind_resolution =
        resolve_turn_kind(&object, &draft_markdown, &questions, &options, &plan_steps);
    let turn_kind = turn_kind_resolution.kind.clone();
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
    let response_structure = NarrativeResponseStructureSummary {
        question_count: questions.len(),
        option_count: options.len(),
        plan_step_count: plan_steps.len(),
        requested_action_count: requested_actions.len(),
    };
    let diagnostic_flags =
        build_generation_diagnostic_flags(&request, &turn_kind, &requested_actions);

    if turn_kind == "options" || turn_kind == "clarification" || turn_kind == "plan" {
        eprintln!(
            "[NarrativeLab] AI response: turn_kind={}, options.len()={}, questions.len()={}, plan_steps.len()={}",
            turn_kind,
            options.len(),
            questions.len(),
            plan_steps.len()
        );
    }

    Ok(NarrativeGenerateResponse {
        engine_mode: engine_mode.to_string(),
        turn_kind: turn_kind.clone(),
        turn_kind_source: turn_kind_resolution.source.clone(),
        turn_kind_correction: turn_kind_resolution.correction.clone(),
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
                "turnKind": turn_kind,
                "turnKindSource": turn_kind_resolution.source.clone(),
                "turnKindCorrection": turn_kind_resolution.correction.clone(),
                "options": options,
                "questions": questions,
                "planSteps": plan_steps,
                "requestedActionCount": requested_actions.len(),
                "diagnosticFlags": diagnostic_flags.clone(),
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
        response_structure,
        diagnostic_flags,
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
    let supported_doc_types =
        "world_bible, task_setup, location_note, character_card, monster_note, item_note";
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
        &format!(
            "create_derived_document 的 payload 必须包含 docType（例如 character_card），可选 title、slug、markdown 字段；docType 只能是 {}。",
            supported_doc_types
        ),
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

fn should_use_structured_turn_kind_staging(
    settings: &AiSettings,
    request: &NarrativeGenerateRequest,
) -> bool {
    if is_local_stub_provider(settings) {
        return false;
    }

    if !matches!(
        request.action.as_str(),
        "create" | "revise_document" | "derive_new_doc"
    ) {
        return false;
    }

    prompt_prefers_structured_turn_kind_stage(&request.user_prompt)
}

fn is_local_stub_provider(settings: &AiSettings) -> bool {
    let base_url = settings.base_url.to_lowercase();
    let model = settings.model.to_lowercase();
    base_url.contains("127.0.0.1")
        || base_url.contains("localhost")
        || model.contains("stub")
        || model.contains("mock")
}

fn prompt_prefers_structured_turn_kind_stage(prompt: &str) -> bool {
    infer_turn_kind_from_prompt(prompt).is_some()
}

fn infer_turn_kind_from_prompt(prompt: &str) -> Option<String> {
    let prompt = prompt.trim();
    let clarification = [
        "先别动笔",
        "还缺哪些必要信息",
        "先告诉我还缺",
        "缺哪些必要信息",
        "先问我",
    ]
    .iter()
    .any(|needle| prompt.contains(needle));
    if clarification {
        return Some("clarification".to_string());
    }

    let options = ["推进方向", "不同方向", "几个方向", "三个方向"]
        .iter()
        .any(|needle| prompt.contains(needle))
        || (prompt.contains("不要直接改正文") && prompt.contains("方向"));
    if options {
        return Some("options".to_string());
    }

    let plan = [
        "执行计划",
        "分步骤",
        "分步计划",
        "等我确认后再继续",
        "先给计划",
    ]
    .iter()
    .any(|needle| prompt.contains(needle));
    if plan {
        return Some("plan".to_string());
    }

    None
}

fn build_turn_kind_classification_payload(
    request: &NarrativeGenerateRequest,
    context: &Value,
    settings: &AiSettings,
) -> Value {
    let contract = [
        "始终只返回一个 JSON 对象，不要输出 Markdown，不要加代码块围栏，不要附加解释文字。",
        "JSON 允许字段：turn_kind, assistant_message。",
        "turn_kind 只能是 final_answer, clarification, options, plan, blocked 之一。",
        "这一轮只负责判断回合类型，不要返回 draft_markdown、questions、options、plan_steps、requested_actions。",
        "如果用户明确要求先提问再继续，返回 clarification。",
        "如果用户明确要求先给方向分叉，返回 options。",
        "如果用户明确要求先给执行步骤或计划，返回 plan。",
        "如果上下文仍不足以判断，返回 blocked。",
        "如果信息足够且用户想直接产出内容，返回 final_answer。",
    ]
    .join("\n");

    json!({
        "provider_config": {
            "base_url": settings.base_url,
            "model": settings.model,
            "api_key": settings.effective_api_key(),
            "timeout_sec": settings.timeout_sec,
        },
        "temperature": 0.1,
        "max_tokens": 600,
        "messages": [
            {
                "role": "system",
                "content": format!(
                    "[你的身份]\n你是 Narrative Lab 的回合分类助手，只判断当前回合更适合哪种对话模式。\n\n[输出协议]\n{}\n\n[判断原则]\n{}\n{}\n{}",
                    contract,
                    "优先尊重用户是否要求“先问、先给选项、先给计划”。",
                    "不要因为能写正文就忽略用户要求的对话模式。",
                    "如果用户说“不要直接改正文”“等我确认后再继续”，通常不是 final_answer。",
                ),
            },
            {
                "role": "user",
                "content": serde_json::to_string_pretty(&json!({
                    "request": build_structured_turn_kind_request_input(request),
                    "context": context,
                }))
                .unwrap_or_else(|_| "{}".to_string()),
            },
        ],
    })
}

fn classify_turn_kind_from_payload(
    payload: &Value,
    request: &NarrativeGenerateRequest,
) -> Option<String> {
    let object = payload.as_object().cloned().unwrap_or_default();
    let explicit = object
        .get("turn_kind")
        .or_else(|| object.get("turnKind"))
        .and_then(Value::as_str)
        .map(str::trim)
        .map(str::to_lowercase);

    match explicit.as_deref() {
        Some("final_answer" | "clarification" | "options" | "plan" | "blocked") => explicit,
        _ => infer_turn_kind_from_prompt(&request.user_prompt),
    }
}

fn build_structured_turn_kind_content_payload(
    turn_kind: &str,
    request: &NarrativeGenerateRequest,
    context: &Value,
    settings: &AiSettings,
) -> Value {
    let (contract, max_tokens) = match turn_kind {
        "clarification" => (
            [
                "始终只返回一个 JSON 对象，不要输出 Markdown，不要加代码块围栏，不要附加解释文字。",
                "JSON 允许字段：turn_kind, assistant_message, questions。",
                "turn_kind 固定为 clarification。",
                "questions 必须提供 1 到 3 个问题，每个问题都要具体、可直接回答。",
                "assistant_message 必须把这些问题以编号列表再重复一遍，确保宿主可从自然语言中兜底解析。",
                "不要返回 options、plan_steps、draft_markdown、requested_actions。",
            ]
            .join("\n"),
            700,
        ),
        "options" => (
            [
                "始终只返回一个 JSON 对象，不要输出 Markdown，不要加代码块围栏，不要附加解释文字。",
                "JSON 允许字段：turn_kind, assistant_message, options。",
                "turn_kind 固定为 options。",
                "options 必须提供 2 到 4 个方向，每个 option 必须包含 followup_prompt。",
                "assistant_message 必须包含与 options 对应的编号列表，格式尽量接近“1. 标题：描述”。",
                "不要返回 questions、plan_steps、draft_markdown、requested_actions。",
            ]
            .join("\n"),
            900,
        ),
        "plan" => (
            [
                "始终只返回一个 JSON 对象，不要输出 Markdown，不要加代码块围栏，不要附加解释文字。",
                "JSON 允许字段：turn_kind, assistant_message, plan_steps。",
                "turn_kind 固定为 plan。",
                "plan_steps 必须提供 3 到 5 步，每步简短明确。",
                "assistant_message 必须把 plan_steps 以编号步骤再重复一遍，确保宿主可从自然语言中兜底解析。",
                "不要返回 questions、options、draft_markdown、requested_actions。",
            ]
            .join("\n"),
            800,
        ),
        _ => (
            [
                "始终只返回一个 JSON 对象，不要输出 Markdown，不要加代码块围栏，不要附加解释文字。",
                "JSON 允许字段：turn_kind, assistant_message。",
                "turn_kind 固定为 blocked。",
                "只说明为什么当前不适合继续，不要返回 questions、options、plan_steps、draft_markdown、requested_actions。",
            ]
            .join("\n"),
            500,
        ),
    };

    json!({
        "provider_config": {
            "base_url": settings.base_url,
            "model": settings.model,
            "api_key": settings.effective_api_key(),
            "timeout_sec": settings.timeout_sec,
        },
        "temperature": 0.2,
        "max_tokens": max_tokens,
        "messages": [
            {
                "role": "system",
                "content": format!(
                    "[你的身份]\n你是 Narrative Lab 的结构化内容助手，只为已经确定的回合类型生成必要字段。\n\n[目标回合]\n{}\n\n[输出协议]\n{}\n\n[工作原则]\n{}\n{}",
                    turn_kind,
                    contract,
                    "严格只返回当前回合需要的字段，减少结构噪音。",
                    "不要偷偷补正文，也不要混入其它回合字段。",
                ),
            },
            {
                "role": "user",
                "content": serde_json::to_string_pretty(&json!({
                    "request": build_structured_turn_kind_request_input(request),
                    "context": context,
                    "targetTurnKind": turn_kind,
                }))
                .unwrap_or_else(|_| "{}".to_string()),
            },
        ],
    })
}

fn build_structured_turn_kind_request_input(request: &NarrativeGenerateRequest) -> Value {
    json!({
        "docType": request.doc_type,
        "targetSlug": request.target_slug,
        "action": request.action,
        "userPrompt": request.user_prompt,
        "editorInstruction": request.editor_instruction,
        "selectedText": request.selected_text,
        "relatedDocSlugs": request.related_doc_slugs,
        "derivedTargetDocType": request.derived_target_doc_type,
        "currentDocument": summarize_markdown_for_narrow_prompt(&request.current_markdown),
    })
}

fn summarize_markdown_for_narrow_prompt(markdown: &str) -> Value {
    let excerpt = excerpt_for_narrow_prompt(markdown, 1200);
    let headings = markdown
        .lines()
        .map(str::trim)
        .filter(|line| line.starts_with('#'))
        .map(|line| line.trim_start_matches('#').trim())
        .filter(|line| !line.is_empty())
        .take(8)
        .map(ToString::to_string)
        .collect::<Vec<_>>();

    json!({
        "excerpt": excerpt,
        "headings": headings,
        "length": markdown.chars().count(),
    })
}

fn excerpt_for_narrow_prompt(value: &str, max_chars: usize) -> String {
    let mut output = String::new();
    for ch in value.chars().take(max_chars) {
        output.push(ch);
    }
    output.trim().to_string()
}

fn build_action_intent_resolution_payload(
    input: &ResolveNarrativeActionIntentInput,
    context: &Value,
    settings: &AiSettings,
) -> Value {
    let contract = [
        "始终只返回一个 JSON 对象，不要输出 Markdown，不要加代码块围栏，不要附加解释文字。",
        "JSON 允许字段：action, assistant_message, questions, options。",
        "action 只能是 create, revise_document, unclear 之一。",
        "如果用户明显是在当前文档上继续修改、润色、补全、扩写、调整，返回 revise_document。",
        "如果用户明显是在基于当前文档拆分、派生、抽取、另起一份独立文档，返回 create。",
        "如果用户要求把当前文档中的一部分移出去、抽出去、拆出去，并且当前文档也要同步去掉这部分内容，优先返回 revise_document。",
        "如果仅凭当前信息仍无法稳定判断，返回 unclear，并提供 1 个 questions 和 2 个 options。",
        "当 action 为 create 或 revise_document 时，questions 和 options 必须为空数组。",
        "当 action 为 unclear 时，assistant_message 要简短说明歧义点。",
        "当 action 为 unclear 时，questions[0].label 必须明确询问“修改当前文档”还是“创建新文档”。",
        "当 action 为 unclear 时，options 必须正好提供两个方向：修改当前文档、创建新文档。",
        "options 的 followup_prompt 必须是面向同一需求的明确后续指令，能让系统下一轮直接执行，不要丢掉原需求。",
    ]
    .join("\n");

    json!({
        "provider_config": {
            "base_url": settings.base_url,
            "model": settings.model,
            "api_key": settings.effective_api_key(),
            "timeout_sec": settings.timeout_sec,
        },
        "temperature": 0.1,
        "max_tokens": 900,
        "messages": [
            {
                "role": "system",
                "content": format!(
                    "[你的身份]\n你是 Narrative Lab 的动作判定助手，负责判断当前这轮需求应该“修改当前文档”还是“创建一份新文档”。\n\n[输出协议]\n{}\n\n[判定原则]\n{}\n{}\n{}\n{}",
                    contract,
                    "优先理解用户意图，而不是机械匹配词语。",
                    "“抽出来放到单独文档”“拆成独立文档”“基于当前内容另写一份”都更接近 create。",
                    "“润色当前文稿”“补全这篇”“继续改这篇”都更接近 revise_document。",
                    "如果用户表达本身已经很明确，不要多问。",
                ),
            },
            {
                "role": "user",
                "content": serde_json::to_string_pretty(&json!({
                    "submittedPrompt": input.submitted_prompt,
                    "request": {
                        "docType": input.doc_type,
                        "targetSlug": input.target_slug,
                        "userPrompt": input.user_prompt,
                        "editorInstruction": input.editor_instruction,
                        "currentMarkdown": input.current_markdown,
                        "relatedDocSlugs": input.related_doc_slugs,
                    },
                    "context": context,
                }))
                .unwrap_or_else(|_| "{}".to_string()),
            },
        ],
    })
}

fn parse_action_intent_resolution_payload(
    payload: &Value,
    submitted_prompt: &str,
) -> ResolveNarrativeActionIntentResult {
    let object = payload.as_object().cloned().unwrap_or_default();
    let action = object
        .get("action")
        .and_then(Value::as_str)
        .map(str::trim)
        .map(str::to_lowercase)
        .and_then(|value| match value.as_str() {
            "create" => Some("create".to_string()),
            "revise_document" => Some("revise_document".to_string()),
            _ => None,
        });

    if action.is_some() {
        return ResolveNarrativeActionIntentResult {
            action,
            assistant_message: object
                .get("assistant_message")
                .or_else(|| object.get("assistantMessage"))
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .unwrap_or_default()
                .to_string(),
            questions: Vec::new(),
            options: Vec::new(),
        };
    }

    let mut questions = read_agent_questions(&object);
    if questions.is_empty() {
        questions.push(AgentQuestion {
            id: "action-intent".to_string(),
            label: "这轮是要修改当前文档，还是基于当前文档创建一份新文档？".to_string(),
            placeholder: "也可以直接回复“修改当前文档”或“创建新文档”。".to_string(),
            required: true,
        });
    }

    let mut options = read_agent_options(&object);
    if options.len() < 2 {
        options = vec![
            AgentOption {
                id: "action-intent-revise".to_string(),
                label: "修改当前文档".to_string(),
                description: "保留这篇文档主体，直接在当前文稿上继续修改。".to_string(),
                followup_prompt: format!("请修改当前文档：{}", submitted_prompt.trim()),
            },
            AgentOption {
                id: "action-intent-create".to_string(),
                label: "创建新文档".to_string(),
                description: "基于当前文稿内容另起一份新的文档草稿。".to_string(),
                followup_prompt: format!(
                    "请基于当前文档创建一份新文档：{}",
                    submitted_prompt.trim()
                ),
            },
        ];
    }

    ResolveNarrativeActionIntentResult {
        action: None,
        assistant_message: object
            .get("assistant_message")
            .or_else(|| object.get("assistantMessage"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or(
                "我还不能稳定判断这轮应该修改当前文档，还是基于它创建一份新文档。请先确认一次。",
            )
            .to_string(),
        questions,
        options,
    }
}

fn build_action_rules(request: &NarrativeGenerateRequest) -> Vec<String> {
    match request.action.as_str() {
        "create" => vec![
            "根据模板生成完整可读文稿。".to_string(),
            "文稿应包含清晰标题层级和结构化落地提示。".to_string(),
            "如果用户明确要求生成多个独立文档，必须使用 requested_actions 为每个目标创建独立的 create_derived_document 动作，不要把多个独立内容合并到一个 draft_markdown 里。".to_string(),
            "当需要在当前会话中创建派生文档时，每个 requested_actions 项的 action_type 设为 create_derived_document，并在 payload 中使用 docType、title、slug、markdown 字段。".to_string(),
        ],
        "revise_document" => vec![
            "在保留文稿主方向的前提下整体改写。".to_string(),
            "不要无故删除重要章节。".to_string(),
            "如果用户要求把当前文档中的某部分拆成独立文档，draft_markdown 应给出移除该部分后的当前文档版本。".to_string(),
            "遇到“从当前文档移出去并单独创建文档”的需求时，同时用 requested_actions.create_derived_document 提供派生文档；payload 必须使用 docType、title、slug、markdown 字段。".to_string(),
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
                .unwrap_or(if draft_markdown.trim().is_empty() {
                    "high"
                } else {
                    "medium"
                }),
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
    let explicit = object
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
        .unwrap_or_default();

    if !explicit.is_empty() {
        return explicit;
    }

    infer_questions_from_text(narrative_response_text(object))
}

fn read_agent_options(object: &Map<String, Value>) -> Vec<AgentOption> {
    let options = object
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
        .unwrap_or_default();

    if options.len() < 2 {
        infer_options_from_text(narrative_response_text(object))
    } else {
        options.into_iter().take(4).collect()
    }
}

fn read_agent_plan_steps(object: &Map<String, Value>) -> Vec<AgentPlanStep> {
    let explicit_steps = object
        .get("plan_steps")
        .or_else(|| object.get("planSteps"))
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .enumerate()
                .filter_map(|(index, value)| parse_agent_plan_step(value, index))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    if !explicit_steps.is_empty() {
        return explicit_steps;
    }

    infer_plan_steps_from_text(
        object
            .get("assistant_message")
            .or_else(|| object.get("assistantMessage"))
            .and_then(Value::as_str)
            .or_else(|| object.get("summary").and_then(Value::as_str))
            .unwrap_or_default(),
    )
}

fn parse_agent_plan_step(value: &Value, index: usize) -> Option<AgentPlanStep> {
    let default_status = if index == 0 { "active" } else { "pending" };

    if let Some(label) = value
        .as_str()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        return Some(AgentPlanStep {
            id: format!("step-{}", index + 1),
            label: strip_plan_step_prefix(label),
            status: normalize_plan_step_status(default_status),
        });
    }

    let object = value.as_object()?;
    let label = object
        .get("label")
        .or_else(|| object.get("title"))
        .or_else(|| object.get("text"))
        .or_else(|| object.get("step"))
        .or_else(|| object.get("description"))
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
            .unwrap_or(default_status),
    );
    Some(AgentPlanStep {
        id,
        label: strip_plan_step_prefix(&label),
        status,
    })
}

fn infer_plan_steps_from_text(text: &str) -> Vec<AgentPlanStep> {
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .filter_map(parse_plan_step_line)
        .take(8)
        .enumerate()
        .map(|(index, label)| AgentPlanStep {
            id: format!("step-{}", index + 1),
            label,
            status: normalize_plan_step_status(if index == 0 { "active" } else { "pending" }),
        })
        .collect()
}

fn narrative_response_text(object: &Map<String, Value>) -> String {
    [
        object
            .get("assistant_message")
            .or_else(|| object.get("assistantMessage"))
            .and_then(Value::as_str)
            .unwrap_or_default(),
        object
            .get("summary")
            .and_then(Value::as_str)
            .unwrap_or_default(),
    ]
    .into_iter()
    .map(str::trim)
    .filter(|value| !value.is_empty())
    .collect::<Vec<_>>()
    .join("\n")
}

fn infer_questions_from_text(text: String) -> Vec<AgentQuestion> {
    let mut questions = Vec::new();
    for raw_line in text.lines() {
        let normalized = strip_plan_step_prefix(raw_line)
            .trim_matches(['-', '*', '•', ' '])
            .trim()
            .to_string();
        if normalized.is_empty() {
            continue;
        }
        if !normalized.contains('？') && !normalized.contains('?') {
            continue;
        }
        let label = normalized
            .split_inclusive(['？', '?'])
            .next()
            .unwrap_or(normalized.as_str())
            .trim()
            .to_string();
        if label.len() < 6
            || questions
                .iter()
                .any(|question: &AgentQuestion| question.label == label)
        {
            continue;
        }
        questions.push(AgentQuestion {
            id: format!("question-{}", questions.len() + 1),
            label,
            placeholder: String::new(),
            required: true,
        });
        if questions.len() >= 3 {
            break;
        }
    }
    questions
}

fn infer_options_from_text(text: String) -> Vec<AgentOption> {
    let mut options = Vec::new();
    for raw_line in text.lines() {
        let normalized = strip_plan_step_prefix(raw_line)
            .trim_matches(['-', '*', '•', ' '])
            .trim()
            .to_string();
        if normalized.is_empty() || normalized.contains('？') || normalized.contains('?') {
            continue;
        }
        let has_list_prefix = raw_line.trim_start().starts_with('-')
            || raw_line.trim_start().starts_with('*')
            || raw_line.trim_start().starts_with('•')
            || raw_line
                .trim_start()
                .chars()
                .next()
                .map(|ch| ch.is_ascii_digit())
                .unwrap_or(false);
        if !has_list_prefix {
            continue;
        }
        let mut parts = normalized.splitn(2, ['：', ':', '-', ' ']);
        let first = parts.next().unwrap_or_default().trim();
        let rest = parts.next().unwrap_or_default().trim();
        let label = if first.len() >= 4 && first.len() <= 24 {
            first.to_string()
        } else {
            normalized.chars().take(24).collect::<String>()
        };
        if label.is_empty()
            || options
                .iter()
                .any(|option: &AgentOption| option.label == label)
        {
            continue;
        }
        options.push(AgentOption {
            id: format!("option-{}", options.len() + 1),
            label: label.clone(),
            description: if rest.is_empty() {
                normalized.clone()
            } else {
                rest.to_string()
            },
            followup_prompt: normalized,
        });
        if options.len() >= 4 {
            break;
        }
    }

    if options.len() < 2 {
        Vec::new()
    } else {
        options
    }
}

fn parse_plan_step_line(line: &str) -> Option<String> {
    let trimmed = strip_plan_step_prefix(line);
    if trimmed.is_empty() || trimmed == line {
        return None;
    }
    Some(trimmed)
}

fn strip_plan_step_prefix(line: &str) -> String {
    let trimmed = line.trim();
    let bullet_trimmed = trimmed
        .strip_prefix("- ")
        .or_else(|| trimmed.strip_prefix("* "))
        .or_else(|| trimmed.strip_prefix("• "))
        .map(str::trim);
    if let Some(value) = bullet_trimmed.filter(|value| !value.is_empty()) {
        return value.to_string();
    }

    let numbered = trimmed.trim_start_matches(|ch: char| ch.is_ascii_digit());
    if numbered.len() != trimmed.len() {
        let numbered = numbered
            .trim_start_matches(['.', '、', ')', '）', ':', '：'])
            .trim();
        if !numbered.is_empty() {
            return numbered.to_string();
        }
    }

    trimmed.to_string()
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
) -> TurnKindResolution {
    let explicit = object
        .get("turn_kind")
        .or_else(|| object.get("turnKind"))
        .and_then(Value::as_str)
        .map(str::trim)
        .unwrap_or_default();

    let (resolved, source, correction_reason) = match explicit {
        "clarification" if questions.is_empty() => {
            if !draft_markdown.trim().is_empty() {
                (
                    "final_answer".to_string(),
                    "corrected_draft".to_string(),
                    Some("clarification 缺少 questions，但存在 draft_markdown。".to_string()),
                )
            } else {
                (
                    "blocked".to_string(),
                    "corrected_invalid".to_string(),
                    Some("clarification 缺少 questions。".to_string()),
                )
            }
        }
        "options" if options.is_empty() => {
            if !draft_markdown.trim().is_empty() {
                (
                    "final_answer".to_string(),
                    "corrected_draft".to_string(),
                    Some("options 缺少 options，但存在 draft_markdown。".to_string()),
                )
            } else {
                (
                    "blocked".to_string(),
                    "corrected_invalid".to_string(),
                    Some("options 缺少 options。".to_string()),
                )
            }
        }
        "plan" if plan_steps.is_empty() => {
            if !draft_markdown.trim().is_empty() {
                (
                    "final_answer".to_string(),
                    "corrected_draft".to_string(),
                    Some("plan 缺少 plan_steps，但存在 draft_markdown。".to_string()),
                )
            } else {
                (
                    "blocked".to_string(),
                    "corrected_invalid".to_string(),
                    Some("plan 缺少 plan_steps。".to_string()),
                )
            }
        }
        "final_answer" | "clarification" | "options" | "plan" | "blocked" => {
            (explicit.to_string(), "explicit".to_string(), None)
        }
        _ if !questions.is_empty() => (
            "clarification".to_string(),
            "inferred_questions".to_string(),
            if explicit.is_empty() {
                None
            } else {
                Some("turn_kind 无效，已根据 questions 推断 clarification。".to_string())
            },
        ),
        _ if !options.is_empty() => (
            "options".to_string(),
            "inferred_options".to_string(),
            if explicit.is_empty() {
                None
            } else {
                Some("turn_kind 无效，已根据 options 推断 options。".to_string())
            },
        ),
        _ if !plan_steps.is_empty() && draft_markdown.trim().is_empty() => (
            "plan".to_string(),
            "inferred_plan".to_string(),
            if explicit.is_empty() {
                None
            } else {
                Some("turn_kind 无效，已根据 plan_steps 推断 plan。".to_string())
            },
        ),
        _ if !draft_markdown.trim().is_empty() => (
            "final_answer".to_string(),
            "inferred_draft".to_string(),
            if explicit.is_empty() {
                None
            } else {
                Some("turn_kind 无效，已根据 draft_markdown 推断 final_answer。".to_string())
            },
        ),
        _ => (
            "blocked".to_string(),
            if explicit.is_empty() {
                "inferred_blocked".to_string()
            } else {
                "corrected_invalid".to_string()
            },
            if explicit.is_empty() {
                None
            } else {
                Some("turn_kind 无效，且缺少可推断结构。".to_string())
            },
        ),
    };

    let correction = if explicit != resolved || correction_reason.is_some() {
        Some(NarrativeTurnKindCorrection {
            from: explicit.to_string(),
            to: resolved.clone(),
            reason: correction_reason
                .unwrap_or_else(|| "turn_kind 与结构不一致，已自动纠偏。".to_string()),
        })
    } else {
        None
    };

    if let Some(correction) = correction.as_ref() {
        eprintln!(
            "[NarrativeLab] turn_kind corrected: {} -> {} (questions={}, options={}, plan={}, draft={})",
            correction.from,
            correction.to,
            questions.len(),
            options.len(),
            plan_steps.len(),
            if draft_markdown.trim().is_empty() { "empty" } else { "present" }
        );
    }

    TurnKindResolution {
        kind: resolved,
        source,
        correction,
    }
}

fn build_generation_diagnostic_flags(
    request: &NarrativeGenerateRequest,
    turn_kind: &str,
    requested_actions: &[AgentActionRequest],
) -> Vec<String> {
    let mut flags = Vec::new();
    let split_like_prompt = prompt_requires_requested_actions_backfill(request);
    if split_like_prompt && turn_kind == "final_answer" && requested_actions.is_empty() {
        flags.push("missing_requested_actions_for_split".to_string());
    }
    flags
}

fn should_attempt_requested_actions_backfill(
    request: &NarrativeGenerateRequest,
    payload: &Map<String, Value>,
) -> bool {
    if !prompt_requires_requested_actions_backfill(request) {
        return false;
    }

    if !read_requested_actions(payload).is_empty() {
        return false;
    }

    let draft_markdown = read_draft_markdown(payload);
    let questions = read_agent_questions(payload);
    let options = read_agent_options(payload);
    let plan_steps = read_agent_plan_steps(payload);
    let turn_kind =
        resolve_turn_kind(payload, &draft_markdown, &questions, &options, &plan_steps).kind;

    turn_kind == "final_answer"
}

fn prompt_requires_requested_actions_backfill(request: &NarrativeGenerateRequest) -> bool {
    let prompt = request.user_prompt.trim();
    let mentions_derivation = [
        "移出去",
        "拆出",
        "单独创建",
        "单独写一份",
        "创建一份",
        "新建文档",
        "另起一份",
        "派生",
    ]
    .iter()
    .any(|needle| prompt.contains(needle));
    let mentions_document_target = [
        "人物设定",
        "角色卡",
        "地点设定",
        "地点文档",
        "任务文档",
        "文档",
    ]
    .iter()
    .any(|needle| prompt.contains(needle));

    (mentions_derivation && mentions_document_target)
        || (request.derived_target_doc_type.is_some()
            && matches!(
                request.action.as_str(),
                "derive_new_doc" | "create" | "revise_document"
            ))
}

fn build_requested_actions_extraction_payload(
    request: &NarrativeGenerateRequest,
    context: &Value,
    primary_payload: &Value,
    settings: &AiSettings,
) -> Value {
    let supported_doc_types =
        "world_bible, task_setup, location_note, character_card, monster_note, item_note";
    let doc_type_hint = infer_requested_action_doc_type_hint(request);
    let contract = [
        "始终只返回一个 JSON 对象，不要输出 Markdown，不要加代码块围栏，不要附加解释文字。",
        "JSON 允许字段：requested_actions。",
        "requested_actions 必须是数组；如果不需要任何动作，返回空数组。",
        "只补提取待批准动作，不要重写正文，不要返回 turn_kind、draft_markdown、questions、options、plan_steps。",
        "当用户要求把内容移出去、拆出去、或基于当前文稿另建独立文档时，如果主结果已经给出正文修订版，优先返回 create_derived_document。",
        "requested_actions 中 action_type 只能是 read_active_document, read_related_documents, create_derived_document, apply_candidate_patch, apply_all_patches, save_active_document, open_document, list_workspace_documents, update_related_documents, rename_active_document, set_document_status, split_plan_into_documents, archive_document。",
        "create_derived_document 的 payload 必须包含 docType，可选 title、slug、markdown；docType 只能是 supported doc types 之一。",
        &format!(
            "supported doc types: {}。",
            supported_doc_types
        ),
        "如果返回 create_derived_document，顶层必须提供 title，payload 中也必须提供 title、docType，并尽量补全 slug、markdown，避免只返回空壳动作。",
    ]
    .join("\n");
    let judgment_rules = [
        "这是第二阶段补提取：当前文稿修订已经完成，你现在只需要判断是否还应补一个待批准动作。",
        "如果用户要求“移出去 / 拆出去 / 单独创建 / 另起一份”独立文档，而 primaryResult 已经给出当前文稿修订版，则通常必须返回恰好一个 create_derived_document。",
        "只有在用户并没有要求创建独立文档，或 primaryResult 已经包含了有效 requested_actions 时，才返回空数组。",
        "不要返回说明文字，不要分析原因，不要把动作写进 summary。",
    ]
    .join("\n");
    let example = json!({
        "requested_actions": [
            {
                "action_type": "create_derived_document",
                "title": "商人老王人物设定",
                "description": "从当前世界观文稿拆出独立角色卡。",
                "payload": {
                    "docType": doc_type_hint
                        .clone()
                        .unwrap_or_else(|| "character_card".to_string()),
                    "title": "商人老王人物设定",
                    "slug": "trader-lao-wang-split",
                    "markdown": "# 商人老王人物设定\n\n- 身份：黑市商人\n- 核心矛盾：..."
                }
            }
        ]
    });

    json!({
        "provider_config": {
            "base_url": settings.base_url,
            "model": settings.model,
            "api_key": settings.effective_api_key(),
            "timeout_sec": settings.timeout_sec,
        },
        "temperature": 0.1,
        "max_tokens": 2400,
        "messages": [
            {
                "role": "system",
                "content": format!(
                    "[你的身份]\n你是 Narrative Lab 的动作提取助手，只负责从已经生成的正文结果中补提取待批准动作。\n\n[输出协议]\n{}\n\n[判断原则]\n{}\n\n[示例]\n{}\n\n[附加要求]\n{}",
                    contract,
                    judgment_rules,
                    serde_json::to_string_pretty(&example).unwrap_or_else(|_| "{}".to_string()),
                    "不要解释流程，不要复述请求，只返回 JSON。",
                ),
            },
            {
                "role": "user",
                "content": serde_json::to_string_pretty(&json!({
                    "task": "extract_requested_actions_only",
                    "userPrompt": request.user_prompt,
                    "action": request.action,
                    "targetDocument": {
                        "docType": request.doc_type,
                        "slug": request.target_slug,
                    },
                    "derivedDocumentHint": {
                        "docType": doc_type_hint,
                    },
                    "context": context,
                    "primaryResult": primary_payload,
                }))
                .unwrap_or_else(|_| "{}".to_string()),
            },
        ],
    })
}

fn build_requested_actions_backfill_run(payload: &Value, raw_output: &str) -> NarrativeAgentRun {
    let object = payload.as_object().cloned().unwrap_or_default();
    let requested_actions = read_requested_actions(&object);
    NarrativeAgentRun {
        agent_id: "action-extractor".to_string(),
        label: "动作提取助手".to_string(),
        focus: "在正文已生成后补提取待批准动作。".to_string(),
        status: "completed".to_string(),
        summary: if requested_actions.is_empty() {
            "未补提取到待批准动作。".to_string()
        } else {
            format!("已补提取 {} 个待批准动作。", requested_actions.len())
        },
        notes: Vec::new(),
        risk_level: if requested_actions.is_empty() {
            "medium".to_string()
        } else {
            highest_risk(
                requested_actions
                    .iter()
                    .map(|action| action.risk_level.as_str()),
            )
        },
        draft_markdown: String::new(),
        raw_output: raw_output.to_string(),
        provider_error: String::new(),
    }
}

fn infer_requested_action_doc_type_hint(request: &NarrativeGenerateRequest) -> Option<String> {
    if let Some(doc_type) = request
        .derived_target_doc_type
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        return Some(doc_type.to_string());
    }

    let prompt = request.user_prompt.trim();
    if ["人物设定", "角色卡", "人物卡", "角色设定"]
        .iter()
        .any(|needle| prompt.contains(needle))
    {
        return Some("character_card".to_string());
    }
    if ["地点设定", "地点文档", "地点卡", "场景设定"]
        .iter()
        .any(|needle| prompt.contains(needle))
    {
        return Some("location_note".to_string());
    }
    if ["任务文档", "任务设定", "任务卡"]
        .iter()
        .any(|needle| prompt.contains(needle))
    {
        return Some("task_setup".to_string());
    }
    if ["怪物设定", "怪物卡"]
        .iter()
        .any(|needle| prompt.contains(needle))
    {
        return Some("monster_note".to_string());
    }
    if ["道具设定", "物品设定", "物品卡", "道具卡"]
        .iter()
        .any(|needle| prompt.contains(needle))
    {
        return Some("item_note".to_string());
    }
    None
}

fn merge_requested_actions_into_payload(
    primary_payload: &Value,
    requested_actions: &[AgentActionRequest],
) -> Value {
    let mut object = primary_payload.as_object().cloned().unwrap_or_default();
    object.insert(
        "requested_actions".to_string(),
        Value::Array(
            requested_actions
                .iter()
                .map(agent_action_request_to_value)
                .collect(),
        ),
    );
    Value::Object(object)
}

fn agent_action_request_to_value(action: &AgentActionRequest) -> Value {
    json!({
        "id": &action.id,
        "action_type": &action.action_type,
        "title": &action.title,
        "description": &action.description,
        "payload": &action.payload,
        "preview_only": action.preview_only,
        "affected_document_keys": &action.affected_document_keys,
        "risk_level": &action.risk_level,
    })
}

fn classify_requested_actions_backfill_failure(failure: &ProviderFailure) -> &'static str {
    if is_provider_timeout(failure) {
        return "requested_actions_backfill_timeout";
    }
    if failure.status_code == 200 {
        "requested_actions_backfill_unparseable"
    } else {
        "requested_actions_backfill_provider_error"
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
        "options" if !options.is_empty() => {
            "我先整理了几个可继续推进的方向，你选一个我就继续。".to_string()
        }
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

fn read_raw_action_type(object: &Map<String, Value>) -> Option<String> {
    object
        .get("action_type")
        .or_else(|| object.get("actionType"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_lowercase)
}

fn derive_action_title(
    action_type: &str,
    object: &Map<String, Value>,
    payload: &Value,
) -> Option<String> {
    read_trimmed_string(object.get("title")).or_else(|| {
        if action_type == "create_derived_document" {
            let payload = payload.as_object();
            read_trimmed_string(payload.and_then(|map| map.get("title")))
                .or_else(|| read_trimmed_string(payload.and_then(|map| map.get("slug"))))
        } else {
            None
        }
    })
}

fn analyze_requested_actions_backfill_payload(payload: &Value) -> Vec<String> {
    let Some(object) = payload.as_object() else {
        return vec!["requested_actions_backfill_non_object".to_string()];
    };
    let Some(value) = object
        .get("requested_actions")
        .or_else(|| object.get("requestedActions"))
    else {
        return vec!["requested_actions_backfill_missing_field".to_string()];
    };
    let Some(actions) = value.as_array() else {
        return vec!["requested_actions_backfill_non_array".to_string()];
    };
    if actions.is_empty() {
        return vec!["requested_actions_backfill_empty_array".to_string()];
    }

    let mut flags = BTreeSet::new();
    let mut parsed_any = false;

    for (index, entry) in actions.iter().enumerate() {
        if parse_agent_action_request(entry, index).is_some() {
            parsed_any = true;
            continue;
        }

        let Some(object) = entry.as_object() else {
            flags.insert("requested_actions_backfill_invalid_entry_shape".to_string());
            continue;
        };

        let Some(action_type) = read_raw_action_type(object) else {
            flags.insert("requested_actions_backfill_missing_action_type".to_string());
            continue;
        };
        if !SUPPORTED_AGENT_ACTION_TYPES.contains(&action_type.as_str()) {
            flags.insert("requested_actions_backfill_unsupported_action_type".to_string());
            continue;
        }

        let raw_payload = object.get("payload").cloned().unwrap_or_else(|| json!({}));
        if action_type == "create_derived_document" {
            let payload_map = raw_payload.as_object().cloned().unwrap_or_default();
            match read_trimmed_string(
                payload_map
                    .get("docType")
                    .or_else(|| payload_map.get("doc_type")),
            ) {
                Some(doc_type) if !is_known_doc_type(&doc_type) => {
                    flags.insert("requested_actions_backfill_invalid_doc_type".to_string());
                }
                None => {
                    flags.insert("requested_actions_backfill_missing_doc_type".to_string());
                }
                _ => {}
            }
        }

        let Some(validated_payload) = validate_action_payload(&action_type, raw_payload) else {
            flags.insert("requested_actions_backfill_invalid_payload".to_string());
            continue;
        };

        let has_top_level_title = read_trimmed_string(object.get("title")).is_some();
        if !has_top_level_title {
            flags.insert("requested_actions_backfill_missing_top_level_title".to_string());
        }
        if derive_action_title(&action_type, object, &validated_payload).is_none() {
            flags.insert("requested_actions_backfill_missing_title".to_string());
        }
    }

    if !parsed_any {
        flags.insert("requested_actions_backfill_all_entries_invalid".to_string());
    }

    flags.into_iter().collect()
}

fn read_trimmed_string(value: Option<&Value>) -> Option<String> {
    value
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
}

fn read_trimmed_string_list(value: Option<&Value>) -> Vec<String> {
    value
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToString::to_string)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn action_supports_preview(action_type: &str) -> bool {
    matches!(
        action_type,
        "create_derived_document"
            | "save_active_document"
            | "update_related_documents"
            | "rename_active_document"
            | "set_document_status"
            | "split_plan_into_documents"
            | "archive_document"
    )
}

fn validate_action_payload(action_type: &str, payload: Value) -> Option<Value> {
    let map = payload.as_object().cloned().unwrap_or_default();
    match action_type {
        "apply_candidate_patch" => {
            let patch_id = read_trimmed_string(map.get("patchId").or_else(|| map.get("patch_id")))?;
            Some(json!({ "patchId": patch_id }))
        }
        "create_derived_document" => {
            let doc_type = read_trimmed_string(map.get("docType").or_else(|| map.get("doc_type")))?;
            if !is_known_doc_type(&doc_type) {
                return None;
            }
            let mut next = Map::new();
            next.insert("docType".to_string(), Value::String(doc_type));
            if let Some(title) = read_trimmed_string(map.get("title")) {
                next.insert("title".to_string(), Value::String(title));
            }
            if let Some(slug) = read_trimmed_string(map.get("slug")) {
                next.insert("slug".to_string(), Value::String(slug));
            }
            if let Some(markdown) = read_trimmed_string(map.get("markdown")) {
                next.insert("markdown".to_string(), Value::String(markdown));
            }
            Some(Value::Object(next))
        }
        "rename_active_document" => {
            let title = read_trimmed_string(map.get("title"));
            let slug = read_trimmed_string(map.get("slug"));
            if title.is_none() && slug.is_none() {
                return None;
            }
            let mut next = Map::new();
            if let Some(title) = title {
                next.insert("title".to_string(), Value::String(title));
            }
            if let Some(slug) = slug {
                next.insert("slug".to_string(), Value::String(slug));
            }
            Some(Value::Object(next))
        }
        "set_document_status" => {
            let status = read_trimmed_string(map.get("status"))?;
            if !SUPPORTED_DOCUMENT_STATUSES.contains(&status.as_str()) {
                return None;
            }
            Some(json!({ "status": status }))
        }
        "open_document" => {
            let slug = read_trimmed_string(
                map.get("slug")
                    .or_else(|| map.get("documentKey"))
                    .or_else(|| map.get("document_key")),
            )?;
            Some(json!({ "slug": slug }))
        }
        "read_related_documents" => Some(json!({
            "documentSlugs": read_trimmed_string_list(
                map.get("documentSlugs").or_else(|| map.get("document_slugs"))
            )
        })),
        "update_related_documents" => {
            let related_docs = read_trimmed_string_list(
                map.get("relatedDocs").or_else(|| map.get("related_docs")),
            );
            let add_document_slugs = read_trimmed_string_list(
                map.get("addDocumentSlugs")
                    .or_else(|| map.get("add_document_slugs")),
            );
            let remove_document_slugs = read_trimmed_string_list(
                map.get("removeDocumentSlugs")
                    .or_else(|| map.get("remove_document_slugs")),
            );
            if related_docs.is_empty()
                && add_document_slugs.is_empty()
                && remove_document_slugs.is_empty()
            {
                return None;
            }
            Some(json!({
                "relatedDocs": related_docs,
                "addDocumentSlugs": add_document_slugs,
                "removeDocumentSlugs": remove_document_slugs,
            }))
        }
        "split_plan_into_documents" => {
            let specs = map
                .get("documents")
                .or_else(|| map.get("documentSpecs"))
                .and_then(Value::as_array)?
                .iter()
                .filter_map(|spec| {
                    let object = spec.as_object()?;
                    let doc_type = read_trimmed_string(
                        object.get("docType").or_else(|| object.get("doc_type")),
                    )?;
                    if !is_known_doc_type(&doc_type) {
                        return None;
                    }
                    let mut next = Map::new();
                    next.insert("docType".to_string(), Value::String(doc_type));
                    if let Some(title) = read_trimmed_string(object.get("title")) {
                        next.insert("title".to_string(), Value::String(title));
                    }
                    if let Some(slug) = read_trimmed_string(object.get("slug")) {
                        next.insert("slug".to_string(), Value::String(slug));
                    }
                    if let Some(markdown) = read_trimmed_string(object.get("markdown")) {
                        next.insert("markdown".to_string(), Value::String(markdown));
                    }
                    if let Some(status) = read_trimmed_string(object.get("status")) {
                        if SUPPORTED_DOCUMENT_STATUSES.contains(&status.as_str()) {
                            next.insert("status".to_string(), Value::String(status));
                        }
                    }
                    Some(Value::Object(next))
                })
                .collect::<Vec<_>>();
            if specs.is_empty() {
                return None;
            }
            Some(json!({ "documents": specs }))
        }
        "archive_document" => {
            let mut next = Map::new();
            if let Some(title_suffix) = read_trimmed_string(map.get("titleSuffix")) {
                next.insert("titleSuffix".to_string(), Value::String(title_suffix));
            }
            Some(Value::Object(next))
        }
        _ => Some(Value::Object(map)),
    }
}

fn parse_agent_action_request(value: &Value, index: usize) -> Option<AgentActionRequest> {
    let object = value.as_object()?;
    let action_type = read_raw_action_type(object)
        .filter(|value| SUPPORTED_AGENT_ACTION_TYPES.contains(&value.as_str()))?;
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
    let preview_only_requested = object
        .get("preview_only")
        .or_else(|| object.get("previewOnly"))
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let preview_only = preview_only_requested && action_supports_preview(&action_type);
    let validated_payload = validate_action_payload(
        &action_type,
        object.get("payload").cloned().unwrap_or_else(|| json!({})),
    )?;
    let title = derive_action_title(&action_type, object, &validated_payload)?;
    let payload = inject_preview_flag(validated_payload, preview_only);
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

fn inject_preview_flag(payload: Value, preview_only: bool) -> Value {
    let mut map = payload.as_object().cloned().unwrap_or_default();
    map.insert("previewOnly".to_string(), Value::Bool(preview_only));
    map.insert("preview_only".to_string(), Value::Bool(preview_only));
    Value::Object(map)
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
    read_trimmed_string_list(value)
}

fn append_unique_strings(target: &mut Vec<String>, values: Vec<String>) {
    for value in values {
        if !target.iter().any(|existing| existing == &value) {
            target.push(value);
        }
    }
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

fn build_turn_kind_classifier_run(
    payload: &Value,
    raw_output: &str,
    classified_turn_kind: &str,
) -> NarrativeAgentRun {
    let object = payload.as_object().cloned().unwrap_or_default();
    let notes = read_string_list(
        object
            .get("notes")
            .or_else(|| object.get("review_notes"))
            .or_else(|| object.get("reviewNotes")),
    );
    NarrativeAgentRun {
        agent_id: "turn-kind-classifier".to_string(),
        label: "回合分类助手".to_string(),
        focus: "先判断当前回合更适合 clarification/options/plan/final_answer。".to_string(),
        status: "completed".to_string(),
        summary: format!("已判断本轮优先进入 {classified_turn_kind}。"),
        notes,
        risk_level: "low".to_string(),
        draft_markdown: String::new(),
        raw_output: raw_output.to_string(),
        provider_error: String::new(),
    }
}

fn build_turn_kind_content_run(
    payload: &Value,
    raw_output: &str,
    turn_kind: &str,
) -> NarrativeAgentRun {
    let object = payload.as_object().cloned().unwrap_or_default();
    let questions = read_agent_questions(&object);
    let options = read_agent_options(&object);
    let plan_steps = read_agent_plan_steps(&object);
    let summary = match turn_kind {
        "clarification" => format!("已生成 {} 个澄清问题。", questions.len()),
        "options" => format!("已生成 {} 个推进方向。", options.len()),
        "plan" => format!("已生成 {} 个执行步骤。", plan_steps.len()),
        _ => "已生成阻塞说明。".to_string(),
    };
    NarrativeAgentRun {
        agent_id: "turn-kind-content".to_string(),
        label: "结构化内容助手".to_string(),
        focus: "根据已分类回合生成 questions/options/plan 等窄结构内容。".to_string(),
        status: "completed".to_string(),
        summary,
        notes: Vec::new(),
        risk_level: "low".to_string(),
        draft_markdown: String::new(),
        raw_output: raw_output.to_string(),
        provider_error: String::new(),
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
            "previewOnly": true,
            "payload": {
                "docType": "task_setup"
            }
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
                    "description": "有描述",
                    "payload": {
                        "docType": "task_setup"
                    }
                },
                {
                    "action_type": "create_derived_document",
                    "title": "   ",
                    "payload": {
                        "docType": "task_setup"
                    }
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
                    "title": "文稿 A",
                    "payload": {
                        "docType": "task_setup"
                    }
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

    #[test]
    fn parse_agent_action_request_injects_preview_flag() {
        let action = json!({
            "action_type": "create_derived_document",
            "title": "派生",
            "previewOnly": true,
            "payload": {
                "docType": "task_setup"
            }
        });
        let parsed = parse_agent_action_request(&action, 0).unwrap();
        assert_eq!(
            parsed.payload.get("previewOnly").and_then(Value::as_bool),
            Some(true)
        );
        assert_eq!(
            parsed.payload.get("preview_only").and_then(Value::as_bool),
            Some(true)
        );
    }

    #[test]
    fn parse_agent_action_request_uses_payload_title_for_create_derived_document() {
        let action = json!({
            "action_type": "create_derived_document",
            "payload": {
                "docType": "character_card",
                "title": "商人老王人物设定",
                "slug": "trader-lao-wang-split"
            }
        });
        let parsed = parse_agent_action_request(&action, 0).unwrap();
        assert_eq!(parsed.title, "商人老王人物设定");
        assert_eq!(
            parsed.payload.get("slug").and_then(Value::as_str),
            Some("trader-lao-wang-split")
        );
    }

    #[test]
    fn parse_agent_action_request_skips_invalid_payloads() {
        let action = json!({
            "action_type": "set_document_status",
            "title": "非法状态",
            "payload": {
                "status": "  "
            }
        });
        assert!(parse_agent_action_request(&action, 0).is_none());
    }

    #[test]
    fn build_action_rules_for_revise_document_support_split_out_requests() {
        let request = NarrativeGenerateRequest {
            request_id: Some("req-1".to_string()),
            doc_type: "world_bible".to_string(),
            target_slug: "doc-1".to_string(),
            action: "revise_document".to_string(),
            user_prompt: "把商人老王移出去单独成稿".to_string(),
            editor_instruction: String::new(),
            current_markdown: "# 示例".to_string(),
            selected_range: None,
            selected_text: String::new(),
            related_doc_slugs: Vec::new(),
            derived_target_doc_type: None,
        };

        let joined = build_action_rules(&request).join("\n");
        assert!(joined.contains("移除该部分后的当前文档版本"));
        assert!(joined.contains("create_derived_document"));
        assert!(joined.contains("docType、title、slug、markdown"));
        assert!(!joined.contains("target_doc_type"));
        assert!(!joined.contains("content 字段"));
    }

    #[test]
    fn parse_agent_action_request_disables_preview_for_unsupported_action() {
        let action = json!({
            "action_type": "open_document",
            "title": "打开文稿",
            "previewOnly": true,
            "payload": {
                "slug": "doc-a"
            }
        });
        let parsed = parse_agent_action_request(&action, 0).unwrap();
        assert!(!parsed.preview_only);
        assert_eq!(
            parsed.payload.get("previewOnly").and_then(Value::as_bool),
            Some(false)
        );
    }

    #[test]
    fn resolve_turn_kind_falls_back_to_final_answer_when_draft_exists() {
        let object = Map::new();
        let resolution = resolve_turn_kind(&object, "# 标题", &[], &[], &[]);
        assert_eq!(resolution.kind, "final_answer");
        assert_eq!(resolution.source, "inferred_draft");
    }

    #[test]
    fn read_agent_options_requires_between_two_and_four_entries() {
        let too_few = json!({
            "options": [
                { "label": "只给一个" }
            ]
        });
        assert!(read_agent_options(too_few.as_object().unwrap()).is_empty());

        let too_many = json!({
            "options": [
                { "label": "A" },
                { "label": "B" },
                { "label": "C" },
                { "label": "D" },
                { "label": "E" }
            ]
        });
        assert_eq!(read_agent_options(too_many.as_object().unwrap()).len(), 4);
    }

    #[test]
    fn read_agent_questions_can_infer_from_question_lines() {
        let payload = json!({
            "assistant_message": "继续之前我需要确认：\n1. 这一章主要推进哪条主线？\n2. 你希望整体基调更偏调查还是冲突？"
        });
        let questions = read_agent_questions(payload.as_object().unwrap());
        assert_eq!(questions.len(), 2);
        assert!(questions[0].label.contains("主线"));
        assert!(questions[1].label.contains("调查还是冲突"));
    }

    #[test]
    fn read_agent_options_can_infer_from_bulleted_lines() {
        let payload = json!({
            "assistant_message": "可以从这几个方向切入：\n1. 医院调查线：强化陈医生的病例线索\n2. 据点秩序线：突出交易区与旧砖秘密\n3. 地下工程线：把守阈人与污染源提前推到前台"
        });
        let options = read_agent_options(payload.as_object().unwrap());
        assert_eq!(options.len(), 3);
        assert_eq!(options[0].label, "医院调查线");
        assert!(options[1].description.contains("旧砖秘密"));
    }

    #[test]
    fn build_generation_diagnostic_flags_marks_missing_split_actions() {
        let request = NarrativeGenerateRequest {
            request_id: Some("req-split".to_string()),
            doc_type: "world_bible".to_string(),
            target_slug: "doc-1".to_string(),
            action: "revise_document".to_string(),
            user_prompt: "把商人老王相关内容移出去，单独创建一份人物设定。".to_string(),
            editor_instruction: String::new(),
            current_markdown: "# 示例".to_string(),
            selected_range: None,
            selected_text: String::new(),
            related_doc_slugs: Vec::new(),
            derived_target_doc_type: None,
        };
        let flags = build_generation_diagnostic_flags(&request, "final_answer", &[]);
        assert!(flags.contains(&"missing_requested_actions_for_split".to_string()));
    }

    #[test]
    fn should_attempt_requested_actions_backfill_for_split_prompt_without_actions() {
        let request = NarrativeGenerateRequest {
            request_id: Some("req-split".to_string()),
            doc_type: "world_bible".to_string(),
            target_slug: "doc-1".to_string(),
            action: "revise_document".to_string(),
            user_prompt: "把商人老王相关内容移出去，单独创建一份人物设定。".to_string(),
            editor_instruction: String::new(),
            current_markdown: "# 示例".to_string(),
            selected_range: None,
            selected_text: String::new(),
            related_doc_slugs: Vec::new(),
            derived_target_doc_type: None,
        };
        let payload = json!({
            "turn_kind": "final_answer",
            "draft_markdown": "# 修订后正文"
        });

        assert!(should_attempt_requested_actions_backfill(
            &request,
            payload.as_object().unwrap()
        ));
    }

    #[test]
    fn should_not_attempt_requested_actions_backfill_when_actions_already_exist() {
        let request = NarrativeGenerateRequest {
            request_id: Some("req-split".to_string()),
            doc_type: "world_bible".to_string(),
            target_slug: "doc-1".to_string(),
            action: "revise_document".to_string(),
            user_prompt: "把商人老王相关内容移出去，单独创建一份人物设定。".to_string(),
            editor_instruction: String::new(),
            current_markdown: "# 示例".to_string(),
            selected_range: None,
            selected_text: String::new(),
            related_doc_slugs: Vec::new(),
            derived_target_doc_type: None,
        };
        let payload = json!({
            "turn_kind": "final_answer",
            "draft_markdown": "# 修订后正文",
            "requested_actions": [
                {
                    "action_type": "create_derived_document",
                    "title": "商人老王人物设定",
                    "payload": {
                        "docType": "character_card"
                    }
                }
            ]
        });

        assert!(!should_attempt_requested_actions_backfill(
            &request,
            payload.as_object().unwrap()
        ));
    }

    #[test]
    fn merge_requested_actions_into_payload_keeps_backfilled_action() {
        let primary_payload = json!({
            "turn_kind": "final_answer",
            "draft_markdown": "# 修订后正文"
        });
        let actions = vec![AgentActionRequest {
            id: "action-1".to_string(),
            action_type: "create_derived_document".to_string(),
            title: "商人老王人物设定".to_string(),
            description: "拆分出独立人物卡。".to_string(),
            payload: json!({
                "docType": "character_card",
                "title": "商人老王",
                "slug": "trader-lao-wang-split",
                "markdown": "# 商人老王\n\n设定正文",
                "previewOnly": false,
                "preview_only": false,
            }),
            approval_policy: "always_require_user".to_string(),
            preview_only: false,
            affected_document_keys: vec!["cdc-world-core".to_string()],
            risk_level: "medium".to_string(),
        }];

        let merged = merge_requested_actions_into_payload(&primary_payload, &actions);
        let parsed = read_requested_actions(merged.as_object().unwrap());
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].action_type, "create_derived_document");
        assert_eq!(
            parsed[0].payload.get("slug").and_then(Value::as_str),
            Some("trader-lao-wang-split")
        );
    }

    #[test]
    fn infer_requested_action_doc_type_hint_prefers_prompt_keywords() {
        let request = NarrativeGenerateRequest {
            request_id: Some("req-hint".to_string()),
            doc_type: "world_bible".to_string(),
            target_slug: "doc-1".to_string(),
            action: "revise_document".to_string(),
            user_prompt: "把商人老王相关内容移出去，单独创建一份人物设定。".to_string(),
            editor_instruction: String::new(),
            current_markdown: "# 示例".to_string(),
            selected_range: None,
            selected_text: String::new(),
            related_doc_slugs: Vec::new(),
            derived_target_doc_type: None,
        };

        assert_eq!(
            infer_requested_action_doc_type_hint(&request).as_deref(),
            Some("character_card")
        );
    }

    #[test]
    fn analyze_requested_actions_backfill_payload_marks_empty_array() {
        let payload = json!({
            "requested_actions": []
        });
        let flags = analyze_requested_actions_backfill_payload(&payload);
        assert_eq!(
            flags,
            vec!["requested_actions_backfill_empty_array".to_string()]
        );
    }

    #[test]
    fn analyze_requested_actions_backfill_payload_marks_invalid_entries() {
        let payload = json!({
            "requested_actions": [
                {
                    "action_type": "create_derived_document",
                    "payload": {
                        "docType": "character_card"
                    }
                },
                {
                    "action_type": "create_derived_document",
                    "title": "坏文稿",
                    "payload": {
                        "docType": "unknown_doc_type"
                    }
                }
            ]
        });
        let flags = analyze_requested_actions_backfill_payload(&payload);
        assert!(flags.contains(&"requested_actions_backfill_all_entries_invalid".to_string()));
        assert!(flags.contains(&"requested_actions_backfill_missing_top_level_title".to_string()));
        assert!(flags.contains(&"requested_actions_backfill_missing_title".to_string()));
        assert!(flags.contains(&"requested_actions_backfill_invalid_doc_type".to_string()));
        assert!(flags.contains(&"requested_actions_backfill_invalid_payload".to_string()));
    }

    #[test]
    fn infer_turn_kind_from_prompt_prefers_clarification() {
        let inferred = infer_turn_kind_from_prompt(
            "我要写一个新篇章，但你先别动笔，先告诉我还缺哪些必要信息。",
        );
        assert_eq!(inferred.as_deref(), Some("clarification"));
    }

    #[test]
    fn infer_turn_kind_from_prompt_prefers_options_and_plan() {
        let options = infer_turn_kind_from_prompt(
            "基于当前文稿先给我三个截然不同的推进方向，不要直接改正文。",
        );
        let plan =
            infer_turn_kind_from_prompt("把当前文稿拆成一个分步骤执行计划，等我确认后再继续。");
        assert_eq!(options.as_deref(), Some("options"));
        assert_eq!(plan.as_deref(), Some("plan"));
    }

    #[test]
    fn should_use_structured_turn_kind_staging_skips_local_stub() {
        let settings = AiSettings {
            base_url: "http://127.0.0.1:18765/v1".to_string(),
            model: "narrative-lab-stub".to_string(),
            api_key: "stub-key".to_string(),
            timeout_sec: 12,
            max_context_records: 12,
        };
        let request = NarrativeGenerateRequest {
            request_id: Some("req-structured".to_string()),
            doc_type: "world_bible".to_string(),
            target_slug: "doc-1".to_string(),
            action: "revise_document".to_string(),
            user_prompt: "把当前文稿拆成一个分步骤执行计划，等我确认后再继续。".to_string(),
            editor_instruction: String::new(),
            current_markdown: "# 示例".to_string(),
            selected_range: None,
            selected_text: String::new(),
            related_doc_slugs: Vec::new(),
            derived_target_doc_type: None,
        };

        assert!(!should_use_structured_turn_kind_staging(
            &settings, &request
        ));
    }

    #[test]
    fn runtime_ai_settings_applies_online_timeout_floor_only() {
        let online = runtime_ai_settings(AiSettings {
            base_url: "https://example.com/v1".to_string(),
            model: "gpt-like".to_string(),
            api_key: "key".to_string(),
            timeout_sec: 45,
            max_context_records: 12,
        });
        let offline = runtime_ai_settings(AiSettings {
            base_url: "http://127.0.0.1:18765/v1".to_string(),
            model: "narrative-lab-stub".to_string(),
            api_key: "stub-key".to_string(),
            timeout_sec: 12,
            max_context_records: 12,
        });

        assert_eq!(online.timeout_sec, 90);
        assert_eq!(offline.timeout_sec, 12);
    }

    #[test]
    fn classify_requested_actions_backfill_failure_marks_timeout() {
        let failure = ProviderFailure {
            status_code: 408,
            error: "AI 请求超时，请检查网络或增大 Timeout。".to_string(),
            raw_text: String::new(),
        };
        assert_eq!(
            classify_requested_actions_backfill_failure(&failure),
            "requested_actions_backfill_timeout"
        );
    }

    #[test]
    fn read_agent_plan_steps_accepts_string_entries_and_title_fields() {
        let payload = json!({
            "plan_steps": [
                "1. 先整理角色名单",
                { "title": "2. 为每个角色补全背景" },
                { "step": "3. 检查格式一致性", "status": "completed" }
            ]
        });
        let steps = read_agent_plan_steps(payload.as_object().unwrap());
        assert_eq!(steps.len(), 3);
        assert_eq!(steps[0].label, "先整理角色名单");
        assert_eq!(steps[0].status, "active");
        assert_eq!(steps[1].label, "为每个角色补全背景");
        assert_eq!(steps[1].status, "pending");
        assert_eq!(steps[2].label, "检查格式一致性");
        assert_eq!(steps[2].status, "completed");
    }

    #[test]
    fn read_agent_plan_steps_falls_back_to_assistant_message_lines() {
        let payload = json!({
            "turn_kind": "plan",
            "assistant_message": "建议按这个计划推进：\n1. 先抽取角色清单\n2. 为每个角色补全背景\n3. 最后统一文档格式"
        });
        let steps = read_agent_plan_steps(payload.as_object().unwrap());
        assert_eq!(steps.len(), 3);
        assert_eq!(steps[0].label, "先抽取角色清单");
        assert_eq!(steps[1].label, "为每个角色补全背景");
        assert_eq!(steps[2].label, "最后统一文档格式");
    }
}

fn risk_score(value: &str) -> i32 {
    match value {
        "high" => 3,
        "medium" => 2,
        _ => 1,
    }
}

fn ensure_not_cancelled(cancellation: Option<&CancellationToken>) -> Result<(), String> {
    if cancellation.is_some_and(CancellationToken::is_cancelled) {
        return Err(cancelled_request_error());
    }
    Ok(())
}

fn ensure_not_cancelled_with_progress(
    cancellation: Option<&CancellationToken>,
    progress: Option<&NarrativeGenerationProgressEmitter>,
) -> Result<(), String> {
    if cancellation.is_some_and(CancellationToken::is_cancelled) {
        if let Some(progress) = progress {
            progress.error_step(
                "request-model",
                "请求模型",
                "当前请求已取消",
                "当前请求已取消",
            );
            progress.completed("当前请求已取消", "当前请求已取消");
        }
        return Err(cancelled_request_error());
    }
    Ok(())
}

fn cancelled_request_error() -> String {
    NARRATIVE_REQUEST_CANCELLED_MESSAGE.to_string()
}

fn map_provider_failure_to_result_error(failure: ProviderFailure) -> String {
    if is_cancelled_provider_failure(&failure) {
        return cancelled_request_error();
    }
    normalize_provider_error(&failure)
}

fn runtime_ai_settings(settings: AiSettings) -> AiSettings {
    let mut next = settings;
    if !is_local_stub_provider(&next) {
        next.timeout_sec = next.timeout_sec.max(90);
    }
    next
}

fn cancelled_provider_failure(raw_text: String) -> ProviderFailure {
    ProviderFailure {
        status_code: 499,
        error: cancelled_request_error(),
        raw_text,
    }
}

fn is_cancelled_provider_failure(failure: &ProviderFailure) -> bool {
    failure.error.contains(NARRATIVE_REQUEST_CANCELLED_CODE)
        || failure.error.contains("当前请求已取消")
}

fn is_provider_timeout(failure: &ProviderFailure) -> bool {
    if failure.status_code == 408 {
        return true;
    }
    let normalized = format!("{} {}", failure.error, failure.raw_text).to_lowercase();
    normalized.contains("超时")
        || normalized.contains("timed out")
        || normalized.contains("timeout")
        || normalized.contains("deadline has elapsed")
}

async fn sleep_with_cancel(
    duration: Duration,
    cancellation: Option<&CancellationToken>,
    raw_text: &str,
) -> Result<(), ProviderFailure> {
    if let Some(token) = cancellation {
        tokio::select! {
            _ = token.cancelled() => Err(cancelled_provider_failure(raw_text.to_string())),
            _ = sleep(duration) => Ok(()),
        }
    } else {
        sleep(duration).await;
        Ok(())
    }
}

async fn perform_chat_completion(
    settings: &AiSettings,
    payload: &Value,
    progress: Option<&NarrativeGenerationProgressEmitter>,
    cancellation: Option<&CancellationToken>,
) -> Result<ProviderSuccess, ProviderFailure> {
    perform_chat_completion_owned(
        settings.clone(),
        payload.clone(),
        progress.cloned(),
        cancellation.cloned(),
    )
    .await
}

async fn perform_chat_completion_for_stage(
    settings: &AiSettings,
    stage: ProviderRequestStage,
    payload: &Value,
    progress: Option<&NarrativeGenerationProgressEmitter>,
    cancellation: Option<&CancellationToken>,
) -> Result<ProviderSuccess, ProviderFailure> {
    let stage_settings = stage_settings(settings, stage);
    perform_chat_completion(&stage_settings, payload, progress, cancellation).await
}

fn stage_settings(settings: &AiSettings, stage: ProviderRequestStage) -> AiSettings {
    let mut next = settings.clone();
    if is_local_stub_provider(&next) {
        return next;
    }

    next.timeout_sec = match stage {
        ProviderRequestStage::TurnKindClassification => next.timeout_sec.max(45),
        ProviderRequestStage::StructuredContent => next.timeout_sec.max(90),
        ProviderRequestStage::RequestedActionsBackfill => next.timeout_sec.max(90),
        ProviderRequestStage::PrimaryGeneration => next.timeout_sec.max(90),
    };
    next
}

async fn perform_chat_completion_owned(
    settings: AiSettings,
    payload: Value,
    progress: Option<NarrativeGenerationProgressEmitter>,
    cancellation: Option<CancellationToken>,
) -> Result<ProviderSuccess, ProviderFailure> {
    if cancellation
        .as_ref()
        .is_some_and(CancellationToken::is_cancelled)
    {
        return Err(cancelled_provider_failure(String::new()));
    }
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
        cancellation.as_ref(),
    )
    .await
    {
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
                cancellation.as_ref(),
            )
            .await
        }
        Err(failure) => Err(failure),
    }
}

async fn perform_chat_completion_with_fallbacks(
    client: &Client,
    base_url: &str,
    api_key: &str,
    model: &str,
    payload: &Value,
    max_tokens: u64,
    progress: Option<&NarrativeGenerationProgressEmitter>,
    cancellation: Option<&CancellationToken>,
) -> Result<ProviderSuccess, ProviderFailure> {
    let request_body = build_chat_completion_request(model, payload, max_tokens, true);

    match send_chat_completion_request(
        client,
        base_url,
        api_key,
        &request_body,
        progress,
        cancellation,
    )
    .await
    {
        Ok(success) => Ok(success),
        Err(failure) if should_retry_without_stream(&failure) => {
            if let Some(progress) = progress {
                progress.status_step(
                    "request-model",
                    "请求模型",
                    "当前提供方不支持流式输出，已切回普通请求...",
                );
            }
            let fallback_request = build_chat_completion_request(model, payload, max_tokens, false);
            match send_chat_completion_request(
                client,
                base_url,
                api_key,
                &fallback_request,
                progress,
                cancellation,
            )
            .await
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
    request.insert("max_tokens".to_string(), json!(max_tokens));
    request.insert("stream".to_string(), json!(stream));
    Value::Object(request)
}

async fn send_chat_completion_request(
    client: &Client,
    base_url: &str,
    api_key: &str,
    request_body: &Value,
    progress: Option<&NarrativeGenerationProgressEmitter>,
    cancellation: Option<&CancellationToken>,
) -> Result<ProviderSuccess, ProviderFailure> {
    let mut last_failure: Option<ProviderFailure> = None;

    for attempt in 0..=1 {
        let request = client
            .post(format!("{base_url}/chat/completions"))
            .bearer_auth(api_key)
            .header("Content-Type", "application/json")
            .header("Accept", "application/json")
            .json(request_body);

        let response = if let Some(token) = cancellation {
            tokio::select! {
                _ = token.cancelled() => return Err(cancelled_provider_failure(String::new())),
                result = request.send() => result,
            }
        } else {
            request.send().await
        };

        match response {
            Ok(response) => {
                let status = response.status().as_u16();
                if !(200..300).contains(&status) {
                    let raw_body = if let Some(token) = cancellation {
                        tokio::select! {
                            _ = token.cancelled() => return Err(cancelled_provider_failure(String::new())),
                            text = response.text() => text.unwrap_or_default(),
                        }
                    } else {
                        response.text().await.unwrap_or_default()
                    };
                    let failure = ProviderFailure {
                        status_code: status,
                        error: map_http_error(status, &raw_body),
                        raw_text: raw_body,
                    };
                    if attempt == 0 && (status == 429 || status >= 500) {
                        sleep_with_cancel(Duration::from_secs(1), cancellation, &failure.raw_text)
                            .await?;
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
                    return read_streaming_chat_completion(
                        response,
                        status,
                        progress,
                        cancellation,
                    )
                    .await;
                }

                if let Some(progress) = progress {
                    progress.status_step("request-model", "请求模型", "正在整理模型返回内容...");
                }
                let raw_body = if let Some(token) = cancellation {
                    tokio::select! {
                        _ = token.cancelled() => return Err(cancelled_provider_failure(String::new())),
                        text = response.text() => text.unwrap_or_default(),
                    }
                } else {
                    response.text().await.unwrap_or_default()
                };
                return parse_non_stream_response(raw_body, status, progress);
            }
            Err(error) => {
                let status_code = if error.is_timeout() { 408 } else { 0 };
                let error_message = if error.is_timeout() {
                    "AI 请求超时，请检查网络或增大 Timeout。".to_string()
                } else {
                    format!("网络请求失败: {error}")
                };
                let failure = ProviderFailure {
                    status_code,
                    error: error_message,
                    raw_text: String::new(),
                };
                if attempt == 0 {
                    sleep_with_cancel(Duration::from_secs(1), cancellation, "").await?;
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
    let combined = format!("{} {}", failure.error, failure.raw_text).to_lowercase();
    if failure.status_code == 400
        && combined.contains("stream")
        && (combined.contains("not supported")
            || combined.contains("unsupported")
            || combined.contains("not valid"))
    {
        return true;
    }

    failure.status_code == 200
        && (combined.contains("error decoding response body")
            || combined.contains("读取流式响应失败")
            || combined.contains("流式响应片段不是合法 json"))
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
    let response_data: Value =
        serde_json::from_str(&raw_body).map_err(|error| ProviderFailure {
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

async fn read_streaming_chat_completion(
    response: reqwest::Response,
    status: u16,
    progress: Option<&NarrativeGenerationProgressEmitter>,
    cancellation: Option<&CancellationToken>,
) -> Result<ProviderSuccess, ProviderFailure> {
    let mut raw_content = String::new();
    let mut stream = response.bytes_stream();
    let mut buffer = String::new();
    let mut stream_done = false;

    while let Some(chunk_result) = if let Some(token) = cancellation {
        tokio::select! {
            _ = token.cancelled() => return Err(cancelled_provider_failure(raw_content.clone())),
            next = stream.next() => next,
        }
    } else {
        stream.next().await
    } {
        let chunk = chunk_result.map_err(|error| ProviderFailure {
            status_code: status,
            error: format!("读取流式响应失败: {error}"),
            raw_text: raw_content.clone(),
        })?;
        buffer.push_str(&String::from_utf8_lossy(&chunk));

        while let Some(newline_index) = buffer.find('\n') {
            let mut line = buffer[..newline_index].to_string();
            if line.ends_with('\r') {
                line.pop();
            }
            buffer.drain(..=newline_index);
            if process_stream_line(&line, status, progress, &mut raw_content)? {
                stream_done = true;
                break;
            }
        }

        if stream_done {
            break;
        }
    }

    if !stream_done && !buffer.trim().is_empty() {
        let _ = process_stream_line(
            buffer.trim_end_matches('\r'),
            status,
            progress,
            &mut raw_content,
        )?;
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

fn process_stream_line(
    line: &str,
    status: u16,
    progress: Option<&NarrativeGenerationProgressEmitter>,
    raw_content: &mut String,
) -> Result<bool, ProviderFailure> {
    let trimmed = line.trim();
    if trimmed.is_empty() || trimmed.starts_with(':') {
        return Ok(false);
    }
    let Some(data) = trimmed.strip_prefix("data:") else {
        return Ok(false);
    };
    let data = data.trim();
    if data == "[DONE]" {
        return Ok(true);
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
    Ok(false)
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
        && lines
            .first()
            .is_some_and(|line| line.trim_start().starts_with("```"))
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
        429 => with_provider_detail("AI 请求过于频繁，请稍后再试。", provider_message.as_deref()),
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
