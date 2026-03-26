use std::{thread, time::Duration};

use reqwest::blocking::Client;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use tauri::AppHandle;

use crate::ai_settings::{read_ai_settings, AiSettings};
use crate::narrative_context::build_narrative_context;
use crate::narrative_review::{
    build_review_result, prompt_debug_payload, validate_selection, NarrativeSelectionRange,
};
use crate::narrative_templates::{default_markdown, doc_type_label, is_known_doc_type};
use crate::narrative_workspace::{resolve_connected_project_root, resolve_workspace_root};

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeGenerateRequest {
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
pub struct NarrativeGenerateResponse {
    pub engine_mode: String,
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
}

#[derive(Debug, Clone)]
struct AgentSpec {
    agent_id: &'static str,
    label: &'static str,
    focus: &'static str,
    instructions: Vec<String>,
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
pub fn generate_narrative_draft(
    app: AppHandle,
    workspace_root: String,
    project_root: Option<String>,
    request: NarrativeGenerateRequest,
) -> Result<NarrativeGenerateResponse, String> {
    run_narrative_generation(&app, &workspace_root, project_root.as_deref(), request)
}

#[tauri::command]
pub fn revise_narrative_draft(
    app: AppHandle,
    workspace_root: String,
    project_root: Option<String>,
    request: NarrativeGenerateRequest,
) -> Result<NarrativeGenerateResponse, String> {
    run_narrative_generation(&app, &workspace_root, project_root.as_deref(), request)
}

fn run_narrative_generation(
    app: &AppHandle,
    workspace_root: &str,
    project_root: Option<&str>,
    mut request: NarrativeGenerateRequest,
) -> Result<NarrativeGenerateResponse, String> {
    normalize_request(&mut request)?;
    let selection = validate_selection(
        &request.current_markdown,
        request.selected_range.as_ref(),
        &request.selected_text,
        &request.action,
    )?;
    let settings = read_ai_settings(app)?.normalized();
    let workspace_root_path = resolve_workspace_root(workspace_root)?;
    let project_root_path = resolve_connected_project_root(project_root)?;
    let context = build_narrative_context(
        &workspace_root_path,
        project_root_path.as_deref(),
        &request,
        settings.max_context_records,
    )?;

    let agent_runs = run_specialist_agents(&settings, &request, &context.context);
    let completed_runs = agent_runs
        .iter()
        .filter(|run| run.status == "completed" && !run.draft_markdown.trim().is_empty())
        .cloned()
        .collect::<Vec<_>>();

    if completed_runs.is_empty() {
        let provider_error = summarize_agent_failures(&agent_runs);
        return Ok(NarrativeGenerateResponse {
            engine_mode: "multi_agent".to_string(),
            draft_markdown: String::new(),
            summary: String::new(),
            review_notes: vec!["所有写作 agent 都未能产出可用草稿。".to_string()],
            risk_level: "high".to_string(),
            change_scope: crate::narrative_review::change_scope_for_action(&request.action).to_string(),
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
                    "engineMode": "multi_agent",
                    "agentRuns": &agent_runs,
                }),
            ),
            raw_output: String::new(),
            used_context_refs: context.used_context_refs,
            diff_preview: "暂无草稿可预览".to_string(),
            provider_error,
            synthesis_notes: vec!["合稿阶段未执行，因为没有可用的专长草稿。".to_string()],
            agent_runs,
        });
    }

    let synthesis_payload = build_synthesis_payload(&request, &context.context, &settings, &completed_runs);
    match perform_chat_completion(&settings, &synthesis_payload) {
        Ok(success) => finalize_generation(
            request,
            selection,
            context,
            success.raw_text,
            success.payload,
            agent_runs,
            None,
        ),
        Err(error) => {
            let fallback = completed_runs
                .iter()
                .find(|run| run.agent_id == "structure-architect")
                .or_else(|| completed_runs.first())
                .cloned();
            if let Some(fallback_run) = fallback {
                return Ok(build_fallback_response(
                    request,
                    selection,
                    context,
                    fallback_run,
                    agent_runs,
                    normalize_provider_error(&error),
                ));
            }

            Ok(NarrativeGenerateResponse {
                engine_mode: "multi_agent".to_string(),
                draft_markdown: String::new(),
                summary: String::new(),
                review_notes: vec!["合稿阶段失败，且没有可回退的专长草稿。".to_string()],
                risk_level: "high".to_string(),
                change_scope: crate::narrative_review::change_scope_for_action(&request.action).to_string(),
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
                        "engineMode": "multi_agent",
                        "agentRuns": &agent_runs,
                        "synthesisError": normalize_provider_error(&error),
                    }),
                ),
                raw_output: error.raw_text.clone(),
                used_context_refs: context.used_context_refs,
                diff_preview: "暂无草稿可预览".to_string(),
                provider_error: normalize_provider_error(&error),
                synthesis_notes: vec!["合稿阶段失败，未生成最终草稿。".to_string()],
                agent_runs,
            })
        }
    }
}

fn finalize_generation(
    request: NarrativeGenerateRequest,
    selection: Option<NarrativeSelectionRange>,
    context: crate::narrative_context::NarrativeContextBuildResult,
    raw_output: String,
    payload: Value,
    agent_runs: Vec<NarrativeAgentRun>,
    synthesis_warning: Option<String>,
) -> Result<NarrativeGenerateResponse, String> {
    let object = payload
        .as_object()
        .cloned()
        .ok_or_else(|| "AI 返回的 narrative 结果不是 JSON 对象".to_string())?;
    let draft_markdown = object
        .get("draft_markdown")
        .or_else(|| object.get("draftMarkdown"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();
    let model_notes = read_string_list(
        object
            .get("review_notes")
            .or_else(|| object.get("reviewNotes")),
    );
    let synthesis_notes = read_string_list(
        object
            .get("synthesis_notes")
            .or_else(|| object.get("synthesisNotes")),
    );
    let review = build_review_result(
        &request.action,
        &request.current_markdown,
        selection.as_ref(),
        &draft_markdown,
        model_notes,
    );
    let mut review_notes = review.review_notes;
    let failed_agents = agent_runs
        .iter()
        .filter(|run| run.status == "failed")
        .map(|run| format!("{}: {}", run.label, run.provider_error))
        .collect::<Vec<_>>();
    if !failed_agents.is_empty() {
        review_notes.push(format!(
            "部分专长 agent 失败，但系统仍基于可用草稿完成合稿: {}",
            failed_agents.join(" | ")
        ));
    }
    if let Some(warning) = synthesis_warning {
        review_notes.push(warning);
    }

    let summary = object
        .get("summary")
        .and_then(Value::as_str)
        .unwrap_or_else(|| default_summary_for_action(&request.action))
        .to_string();

    let agent_risk = highest_agent_risk(&agent_runs);

    Ok(NarrativeGenerateResponse {
        engine_mode: "multi_agent".to_string(),
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
                "engineMode": "multi_agent",
                "agentRuns": &agent_runs,
            }),
        ),
        raw_output,
        used_context_refs: context.used_context_refs,
        diff_preview: review.diff_preview,
        provider_error: String::new(),
        synthesis_notes,
        agent_runs,
    })
}

fn build_fallback_response(
    request: NarrativeGenerateRequest,
    selection: Option<NarrativeSelectionRange>,
    context: crate::narrative_context::NarrativeContextBuildResult,
    fallback_run: NarrativeAgentRun,
    agent_runs: Vec<NarrativeAgentRun>,
    synthesis_error: String,
) -> NarrativeGenerateResponse {
    let review = build_review_result(
        &request.action,
        &request.current_markdown,
        selection.as_ref(),
        &fallback_run.draft_markdown,
        fallback_run.notes.clone(),
    );

    NarrativeGenerateResponse {
        engine_mode: "multi_agent".to_string(),
        draft_markdown: fallback_run.draft_markdown.clone(),
        summary: format!("合稿阶段失败，已回退到 {} 的草稿。", fallback_run.label),
        review_notes: {
            let mut notes = review.review_notes;
            notes.push(format!(
                "多 agent 合稿失败，当前结果来自 {}。合稿错误: {}",
                fallback_run.label, synthesis_error
            ));
            notes
        },
        risk_level: highest_risk([&review.risk_level, "high"]),
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
                "engineMode": "multi_agent",
                "agentRuns": &agent_runs,
                "synthesisError": synthesis_error,
                "fallbackAgent": fallback_run.agent_id.clone(),
            }),
        ),
        raw_output: fallback_run.raw_output.clone(),
        used_context_refs: context.used_context_refs,
        diff_preview: review.diff_preview,
        provider_error: String::new(),
        synthesis_notes: vec![
            "合稿阶段失败，系统自动回退到单个专长 agent 的草稿。".to_string(),
            synthesis_error,
        ],
        agent_runs,
    }
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

fn run_specialist_agents(
    settings: &AiSettings,
    request: &NarrativeGenerateRequest,
    context: &Value,
) -> Vec<NarrativeAgentRun> {
    let specs = build_agent_specs(request);
    let mut handles = Vec::new();
    for spec in specs {
        let owned_spec = spec.clone();
        let settings_clone = settings.clone();
        let request_clone = request.clone();
        let context_clone = context.clone();
        let handle =
            thread::spawn(move || run_single_agent(settings_clone, request_clone, context_clone, owned_spec));
        handles.push((spec, handle));
    }

    let mut results = Vec::new();
    for (spec, handle) in handles {
        match handle.join() {
            Ok(result) => results.push(result),
            Err(_) => results.push(failed_agent_run(spec, "agent thread panicked".to_string())),
        }
    }
    results
}

fn run_single_agent(
    settings: AiSettings,
    request: NarrativeGenerateRequest,
    context: Value,
    spec: AgentSpec,
) -> NarrativeAgentRun {
    let payload = build_specialist_payload(&request, &context, &settings, &spec);
    match perform_chat_completion_owned(settings, payload) {
        Ok(success) => match parse_specialist_payload(&spec, success.payload, success.raw_text.clone()) {
            Ok(run) => run,
            Err(error) => failed_agent_run(
                spec,
                format!("failed to parse specialist response: {error}"),
            )
            .with_raw_output(success.raw_text),
        },
        Err(error) => failed_agent_run(spec, normalize_provider_error(&error)).with_raw_output(error.raw_text),
    }
}

fn build_agent_specs(request: &NarrativeGenerateRequest) -> Vec<AgentSpec> {
    if matches!(
        request.action.as_str(),
        "rewrite_selection" | "expand_selection" | "insert_after_selection"
    ) {
        return vec![
            AgentSpec {
                agent_id: "continuity-editor",
                label: "连续性编辑",
                focus: "保证与上下文设定、叙事逻辑和信息顺序连续。",
                instructions: vec![
                    "优先守住上下文连续性和设定一致性。".to_string(),
                    "不要为了炫技破坏已有节奏。".to_string(),
                ],
            },
            AgentSpec {
                agent_id: "voice-director",
                label: "文风导演",
                focus: "优化语气、画面感、可读性和情绪推进。",
                instructions: vec![
                    "让文字更好读，但不要偏离原意。".to_string(),
                    "优先处理语气、节奏、意象与情绪波形。".to_string(),
                ],
            },
            AgentSpec {
                agent_id: "drama-intensifier",
                label: "戏剧强化",
                focus: "提升张力、冲突和角色选择的压迫感。",
                instructions: vec![
                    "增强戏剧推动力，但避免凭空加入与上下文冲突的新事实。".to_string(),
                    "如果是插入或扩写，优先补足冲突和悬念。".to_string(),
                ],
            },
        ];
    }

    vec![
        AgentSpec {
            agent_id: "structure-architect",
            label: "结构策划",
            focus: "负责整体结构、信息顺序、章节推进与大纲清晰度。",
            instructions: vec![
                "优先保证结构完整、推进明确、章节层次清楚。".to_string(),
                "让文稿更适合后续拆成任务、对话和分支。".to_string(),
            ],
        },
        AgentSpec {
            agent_id: "character-dramaturge",
            label: "人物戏剧师",
            focus: "负责人物动机、关系张力、情绪弧线和对白潜台词。",
            instructions: vec![
                "优先挖清角色真正想要什么，以及冲突来自哪里。".to_string(),
                "让角色行为和表达更像有内在驱动力的人。".to_string(),
            ],
        },
        AgentSpec {
            agent_id: "branch-designer",
            label: "分支设计师",
            focus: "负责选择点、后果、回收和可玩分支思维。",
            instructions: vec![
                "优先补强决策点、代价、后果和回收线索。".to_string(),
                "避免把分支写成只有文案差异、没有立场差异。".to_string(),
            ],
        },
        AgentSpec {
            agent_id: "prose-director",
            label: "场景导演",
            focus: "负责可读性、场景画面、节奏控制与叙事感染力。",
            instructions: vec![
                "优先提升整体读感，让文稿既清晰又有文学张力。".to_string(),
                "保持信息密度，不要空泛抒情。".to_string(),
            ],
        },
    ]
}

fn build_specialist_payload(
    request: &NarrativeGenerateRequest,
    context: &Value,
    settings: &AiSettings,
    spec: &AgentSpec,
) -> Value {
    let contract = [
        "只能输出一个 JSON 对象，不能输出 Markdown 解释、不能输出代码块。",
        "输出合同：{\"draft_markdown\":\"string\",\"summary\":\"string\",\"notes\":[\"string\"],\"risk_level\":\"low|medium|high\"}。",
        "draft_markdown 必须只包含正文 Markdown，不要包含 YAML frontmatter。",
    ]
    .join("\n");

    json!({
        "provider_config": {
            "base_url": settings.base_url,
            "model": settings.model,
            "api_key": settings.effective_api_key(),
            "timeout_sec": settings.timeout_sec,
        },
        "temperature": 0.55,
        "max_tokens": 2200,
        "messages": [
            {
                "role": "system",
                "content": format!(
                    "[你的身份]\n你是 Narrative Lab 中的专长写作 agent：{}。\n聚焦点：{}\n\n[输出协议]\n{}\n\n[专长要求]\n{}\n\n[通用要求]\n{}\n{}",
                    spec.label,
                    spec.focus,
                    contract,
                    spec.instructions.join("\n"),
                    build_action_rules(request).join("\n"),
                    "只产出你认为最强的一版草稿，不要分析过程。",
                ),
            },
            {
                "role": "user",
                "content": serde_json::to_string_pretty(&json!({
                    "request": request,
                    "context": context,
                    "specialist": {
                        "agentId": spec.agent_id,
                        "label": spec.label,
                        "focus": spec.focus,
                    }
                }))
                .unwrap_or_else(|_| "{}".to_string()),
            },
        ]
    })
}

fn build_synthesis_payload(
    request: &NarrativeGenerateRequest,
    context: &Value,
    settings: &AiSettings,
    agent_runs: &[NarrativeAgentRun],
) -> Value {
    let contract = [
        "只能输出一个 JSON 对象，不能输出 Markdown 解释、不能输出代码块。",
        "输出合同：{\"draft_markdown\":\"string\",\"summary\":\"string\",\"review_notes\":[\"string\"],\"synthesis_notes\":[\"string\"],\"risk_level\":\"low|medium|high\",\"change_scope\":\"document|selection|insertion|new_doc\"}。",
        "draft_markdown 必须只包含最终合稿后的正文 Markdown，不要包含 YAML frontmatter。",
    ]
    .join("\n");

    let compact_agents = agent_runs
        .iter()
        .filter(|run| run.status == "completed")
        .map(|run| {
            json!({
                "agentId": run.agent_id,
                "label": run.label,
                "focus": run.focus,
                "summary": run.summary,
                "notes": run.notes,
                "riskLevel": run.risk_level,
                "draftMarkdown": run.draft_markdown,
            })
        })
        .collect::<Vec<_>>();

    json!({
        "provider_config": {
            "base_url": settings.base_url,
            "model": settings.model,
            "api_key": settings.effective_api_key(),
            "timeout_sec": settings.timeout_sec,
        },
        "temperature": 0.35,
        "max_tokens": 2800,
        "messages": [
            {
                "role": "system",
                "content": format!(
                    "[你的身份]\n你是 Narrative Lab 的总编合稿 agent，负责整合多个专长 agent 的草稿。\n\n[输出协议]\n{}\n\n[合稿要求]\n{}\n{}\n{}",
                    contract,
                    "不要把多个草稿简单拼接；要产出一份统一、自然、可直接审阅的最终稿。",
                    "如果几个 agent 冲突，优先选择最连贯、最有执行价值、最适合后续结构化拆解的版本。",
                    build_action_rules(request).join("\n"),
                ),
            },
            {
                "role": "user",
                "content": serde_json::to_string_pretty(&json!({
                    "request": request,
                    "context": context,
                    "agentDrafts": compact_agents,
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

fn parse_specialist_payload(
    spec: &AgentSpec,
    payload: Value,
    raw_output: String,
) -> Result<NarrativeAgentRun, String> {
    let object = payload
        .as_object()
        .cloned()
        .ok_or_else(|| "specialist response is not an object".to_string())?;
    Ok(NarrativeAgentRun {
        agent_id: spec.agent_id.to_string(),
        label: spec.label.to_string(),
        focus: spec.focus.to_string(),
        status: "completed".to_string(),
        summary: object
            .get("summary")
            .and_then(Value::as_str)
            .unwrap_or(spec.focus)
            .to_string(),
        notes: read_string_list(object.get("notes")),
        risk_level: normalize_risk(
            object
                .get("risk_level")
                .or_else(|| object.get("riskLevel"))
                .and_then(Value::as_str)
                .unwrap_or("medium"),
        ),
        draft_markdown: object
            .get("draft_markdown")
            .or_else(|| object.get("draftMarkdown"))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim()
            .to_string(),
        raw_output,
        provider_error: String::new(),
    })
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

fn failed_agent_run(spec: AgentSpec, error: String) -> NarrativeAgentRun {
    NarrativeAgentRun {
        agent_id: spec.agent_id.to_string(),
        label: spec.label.to_string(),
        focus: spec.focus.to_string(),
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

fn summarize_agent_failures(agent_runs: &[NarrativeAgentRun]) -> String {
    let summaries = agent_runs
        .iter()
        .filter(|run| !run.provider_error.trim().is_empty())
        .map(|run| format!("{}: {}", run.label, run.provider_error))
        .collect::<Vec<_>>();
    if summaries.is_empty() {
        "所有写作 agent 都未返回可用草稿。".to_string()
    } else {
        summaries.join(" | ")
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
    match value {
        "high" => "high".to_string(),
        "medium" => "medium".to_string(),
        _ => "low".to_string(),
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
) -> Result<ProviderSuccess, ProviderFailure> {
    perform_chat_completion_owned(settings.clone(), payload.clone())
}

fn perform_chat_completion_owned(
    settings: AiSettings,
    payload: Value,
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
    let request_body = json!({
        "model": model,
        "messages": payload.get("messages").cloned().unwrap_or_else(|| json!([])),
        "temperature": payload.get("temperature").and_then(Value::as_f64).unwrap_or(0.45),
        "response_format": { "type": "json_object" },
        "max_tokens": payload.get("max_tokens").and_then(Value::as_u64).unwrap_or(2600),
    });

    let mut last_failure: Option<ProviderFailure> = None;
    for attempt in 0..=1 {
        let response = client
            .post(format!("{base_url}/chat/completions"))
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
                        thread::sleep(Duration::from_secs(1));
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

fn build_http_client(timeout_sec: u64) -> Result<Client, String> {
    Client::builder()
        .timeout(Duration::from_secs(timeout_sec.max(5)))
        .build()
        .map_err(|error| format!("failed to create HTTP client: {error}"))
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

fn extract_json_payload(raw_content: &str) -> Result<Value, String> {
    let trimmed = raw_content.trim();
    if trimmed.is_empty() {
        return Err("AI 未返回可解析内容".to_string());
    }
    serde_json::from_str(trimmed).map_err(|error| format!("AI 返回内容不是合法 JSON 对象: {error}"))
}

fn map_http_error(status: u16, raw_body: &str) -> String {
    match status {
        400 => format!("AI 请求无效: {}", summarize_error_body(raw_body)),
        401 => "AI 认证失败，请检查 API Key".to_string(),
        403 => "AI 请求被拒绝，请检查权限或账号状态".to_string(),
        404 => "AI 接口不存在，请检查 Base URL".to_string(),
        429 => "AI 请求过于频繁，请稍后再试".to_string(),
        500..=599 => format!("AI 服务暂时不可用: {}", summarize_error_body(raw_body)),
        _ => format!("AI 请求失败({status}): {}", summarize_error_body(raw_body)),
    }
}

fn summarize_error_body(raw_body: &str) -> String {
    let trimmed = raw_body.trim();
    if trimmed.is_empty() {
        return "empty response".to_string();
    }
    if trimmed.len() <= 240 {
        return trimmed.to_string();
    }
    format!("{}...", &trimmed[..240])
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

fn default_summary_for_action(action: &str) -> &'static str {
    match action {
        "create" => "Narrative draft generated from the current template.",
        "revise_document" => "Narrative draft revised from the full document context.",
        "rewrite_selection" => "Selection rewrite draft generated.",
        "expand_selection" => "Selection expansion draft generated.",
        "insert_after_selection" => "Insertion draft generated after the current selection.",
        "derive_new_doc" => "Derived narrative draft generated as a new document.",
        _ => "Narrative draft ready for review.",
    }
}
