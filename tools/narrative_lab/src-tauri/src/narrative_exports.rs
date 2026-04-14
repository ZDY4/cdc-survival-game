use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::narrative_workspace::{resolve_workspace_root, NarrativeDocumentPayload};
use crate::to_forward_slashes;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeSessionExportInput {
    pub session_id: String,
    pub session_title: String,
    pub workspace_name: String,
    pub active_document: NarrativeDocumentPayload,
    #[serde(default)]
    pub selected_context_documents: Vec<NarrativeDocumentPayload>,
    pub strategy_summary: String,
    #[serde(default)]
    pub latest_turn_kind: Option<String>,
    #[serde(default)]
    pub latest_summary: String,
    #[serde(default)]
    pub latest_draft_markdown: String,
    #[serde(default)]
    pub source_document_keys: Vec<String>,
    #[serde(default)]
    pub provenance_refs: Vec<String>,
    #[serde(default)]
    pub plan_steps: Vec<String>,
    #[serde(default)]
    pub review_queue: Vec<String>,
    #[serde(default)]
    pub pending_actions: Vec<String>,
    #[serde(default)]
    pub action_history: Vec<String>,
    #[serde(default)]
    pub version_history: Vec<String>,
    #[serde(default)]
    pub recent_messages: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeSessionExportResult {
    pub export_path: String,
    pub file_name: String,
    pub summary: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeTurnKindCorrection {
    pub from: String,
    pub to: String,
    pub reason: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeAiConfigSummary {
    pub base_url: String,
    pub model: String,
    pub timeout_sec: u64,
    pub api_key_configured: bool,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeChatRegressionScenarioResult {
    pub id: String,
    pub label: String,
    pub ok: bool,
    pub prompt: String,
    pub mode: String,
    #[serde(default)]
    pub smoke_tier: Option<String>,
    pub failure_kind: String,
    pub actual_turn_kind: String,
    pub expected_turn_kinds: Vec<String>,
    #[serde(default)]
    pub requested_action_type: Option<String>,
    #[serde(default)]
    pub requested_preview_only: Option<bool>,
    pub assistant_message: String,
    pub provider_error: String,
    pub document_changed: bool,
    pub active_document_slug: String,
    #[serde(default)]
    pub derived_document_slug: Option<String>,
    #[serde(default)]
    pub derived_document_path: Option<String>,
    pub context_ref_count: usize,
    pub question_count: usize,
    pub option_count: usize,
    pub plan_step_count: usize,
    pub requested_action_count: usize,
    #[serde(default)]
    pub turn_kind_source: Option<String>,
    #[serde(default)]
    pub turn_kind_correction: Option<NarrativeTurnKindCorrection>,
    #[serde(default)]
    pub diagnostic_flags: Vec<String>,
    pub status_message: String,
    pub summary: String,
    #[serde(default)]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeChatRegressionExportInput {
    pub mode: String,
    pub workspace_root: String,
    #[serde(default)]
    pub connected_project_root: Option<String>,
    #[serde(default)]
    pub ai_config: Option<NarrativeAiConfigSummary>,
    pub started_at: String,
    pub completed_at: String,
    pub ok: bool,
    pub summary: String,
    pub scenario_results: Vec<NarrativeChatRegressionScenarioResult>,
    #[serde(default)]
    pub skipped_scenarios: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeChatRegressionExportResult {
    pub summary: String,
    pub json_path: String,
    pub markdown_path: String,
}

#[tauri::command]
pub fn export_narrative_session_summary(
    workspace_root: String,
    input: NarrativeSessionExportInput,
) -> Result<NarrativeSessionExportResult, String> {
    let workspace_root_path = resolve_workspace_root(&workspace_root)?;
    let export_path = write_session_export(&workspace_root_path, &input)?;
    Ok(NarrativeSessionExportResult {
        file_name: export_path
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("narrative-session-export.md")
            .to_string(),
        summary: format!("已导出会话《{}》。", input.session_title.trim()),
        export_path: to_forward_slashes(export_path),
    })
}

#[tauri::command]
pub fn export_narrative_chat_regression_report(
    workspace_root: String,
    input: NarrativeChatRegressionExportInput,
) -> Result<NarrativeChatRegressionExportResult, String> {
    let workspace_root_path = resolve_workspace_root(&workspace_root)?;
    let (json_path, markdown_path) = write_chat_regression_export(&workspace_root_path, &input)?;
    Ok(NarrativeChatRegressionExportResult {
        summary: input.summary.clone(),
        json_path: to_forward_slashes(json_path),
        markdown_path: to_forward_slashes(markdown_path),
    })
}

fn write_session_export(
    workspace_root: &Path,
    input: &NarrativeSessionExportInput,
) -> Result<PathBuf, String> {
    let export_dir = workspace_root.join("exports").join("narrative_sessions");
    fs::create_dir_all(&export_dir)
        .map_err(|error| format!("failed to create {}: {error}", export_dir.display()))?;
    let timestamp = unix_timestamp();
    let base_slug = sanitize_file_stem(&input.active_document.meta.slug);
    let session_stem = sanitize_file_stem(&input.session_id);
    let file_name = format!("{base_slug}-{session_stem}-{timestamp}.md");
    let export_path = export_dir.join(file_name);
    let markdown = render_session_export(input);
    fs::write(&export_path, markdown)
        .map_err(|error| format!("failed to write {}: {error}", export_path.display()))?;
    Ok(export_path)
}

fn write_chat_regression_export(
    workspace_root: &Path,
    input: &NarrativeChatRegressionExportInput,
) -> Result<(PathBuf, PathBuf), String> {
    let export_dir = workspace_root.join("exports").join("chat_regressions");
    fs::create_dir_all(&export_dir)
        .map_err(|error| format!("failed to create {}: {error}", export_dir.display()))?;

    let timestamp = unix_timestamp();
    let file_stem = format!(
        "narrative-chat-regression-{}-{}",
        sanitize_file_stem(&input.mode),
        timestamp
    );
    let json_path = export_dir.join(format!("{file_stem}.json"));
    let markdown_path = export_dir.join(format!("{file_stem}.md"));

    let json_payload = json!({
        "mode": input.mode,
        "workspaceRoot": input.workspace_root,
        "connectedProjectRoot": input.connected_project_root,
        "aiConfig": input.ai_config,
        "startedAt": input.started_at,
        "completedAt": input.completed_at,
        "ok": input.ok,
        "summary": input.summary,
        "scenarioResults": input.scenario_results,
        "skippedScenarios": input.skipped_scenarios,
    });
    let raw = serde_json::to_string_pretty(&json_payload)
        .map_err(|error| format!("failed to serialize regression export: {error}"))?;
    fs::write(&json_path, raw)
        .map_err(|error| format!("failed to write {}: {error}", json_path.display()))?;

    let markdown = render_chat_regression_export(input);
    fs::write(&markdown_path, markdown)
        .map_err(|error| format!("failed to write {}: {error}", markdown_path.display()))?;

    Ok((json_path, markdown_path))
}

fn render_session_export(input: &NarrativeSessionExportInput) -> String {
    let mut output = String::new();
    let exported_at = unix_timestamp().to_string();
    output.push_str("# Narrative Lab Session Export\n\n");
    output.push_str(&format!("- Session: {}\n", input.session_title.trim()));
    output.push_str(&format!("- Session ID: `{}`\n", input.session_id.trim()));
    output.push_str(&format!("- Workspace: {}\n", input.workspace_name.trim()));
    output.push_str(&format!("- Exported At: `{}`\n", exported_at));
    output.push_str(&format!(
        "- Active Document: {} (`{}`)\n",
        input.active_document.meta.title.trim(),
        input.active_document.meta.slug.trim()
    ));
    output.push_str(&format!(
        "- Document Type: `{}`\n",
        input.active_document.meta.doc_type.trim()
    ));
    output.push_str(&format!(
        "- Document Status: `{}`\n\n",
        input.active_document.meta.status.trim()
    ));

    push_section(
        &mut output,
        "Strategy",
        &[input.strategy_summary.trim().to_string()],
    );

    if let Some(turn_kind) = &input.latest_turn_kind {
        push_section(
            &mut output,
            "Latest Turn",
            &[
                format!("Turn Kind: `{}`", turn_kind.trim()),
                input.latest_summary.trim().to_string(),
            ],
        );
    } else if !input.latest_summary.trim().is_empty() {
        push_section(
            &mut output,
            "Latest Turn",
            &[input.latest_summary.trim().to_string()],
        );
    }

    push_section(&mut output, "Source Documents", &input.source_document_keys);
    push_section(&mut output, "Provenance Refs", &input.provenance_refs);

    if !input.selected_context_documents.is_empty() {
        output.push_str("## Selected Context Documents\n\n");
        for document in &input.selected_context_documents {
            output.push_str(&format!(
                "- {} (`{}`) [{} / {}]\n",
                document.meta.title.trim(),
                document.meta.slug.trim(),
                document.meta.doc_type.trim(),
                document.meta.status.trim()
            ));
        }
        output.push('\n');
    }

    push_section(&mut output, "Plan Steps", &input.plan_steps);
    push_section(&mut output, "Review Queue", &input.review_queue);
    push_section(&mut output, "Pending Actions", &input.pending_actions);
    push_section(&mut output, "Action History", &input.action_history);
    push_section(&mut output, "Version History", &input.version_history);
    push_section(&mut output, "Recent Messages", &input.recent_messages);

    if !input.latest_draft_markdown.trim().is_empty() {
        output.push_str("## Latest Draft\n\n```markdown\n");
        output.push_str(input.latest_draft_markdown.trim());
        output.push_str("\n```\n");
    }

    output
}

fn render_chat_regression_export(input: &NarrativeChatRegressionExportInput) -> String {
    let mut output = String::new();
    output.push_str("# Narrative Chat Regression Report\n\n");
    output.push_str(&format!("- Mode: `{}`\n", input.mode.trim()));
    output.push_str(&format!("- Workspace: `{}`\n", input.workspace_root.trim()));
    if let Some(project_root) = input.connected_project_root.as_ref() {
        if !project_root.trim().is_empty() {
            output.push_str(&format!("- Project Root: `{}`\n", project_root.trim()));
        }
    }
    if let Some(ai_config) = input.ai_config.as_ref() {
        output.push_str(&format!("- AI Base URL: `{}`\n", ai_config.base_url.trim()));
        output.push_str(&format!("- AI Model: `{}`\n", ai_config.model.trim()));
        output.push_str(&format!("- AI Timeout Sec: `{}`\n", ai_config.timeout_sec));
        output.push_str(&format!(
            "- AI Key Configured: `{}`\n",
            if ai_config.api_key_configured {
                "true"
            } else {
                "false"
            }
        ));
    }
    output.push_str(&format!("- Started At: `{}`\n", input.started_at.trim()));
    output.push_str(&format!(
        "- Completed At: `{}`\n",
        input.completed_at.trim()
    ));
    output.push_str(&format!(
        "- Result: `{}`\n",
        if input.ok { "passed" } else { "failed" }
    ));
    output.push_str(&format!("- Summary: {}\n\n", input.summary.trim()));

    let mut failure_groups = std::collections::BTreeMap::<String, usize>::new();
    for result in input.scenario_results.iter().filter(|result| !result.ok) {
        *failure_groups
            .entry(result.failure_kind.trim().to_string())
            .or_insert(0) += 1;
    }
    if !failure_groups.is_empty() {
        output.push_str("## Failure Attribution\n\n");
        for (failure_kind, count) in failure_groups {
            output.push_str(&format!("- `{}`: {}\n", failure_kind, count));
        }
        output.push('\n');
    }

    if !input.skipped_scenarios.is_empty() {
        output.push_str("## Skipped Scenarios\n\n");
        for scenario in &input.skipped_scenarios {
            output.push_str(&format!("- {scenario}\n"));
        }
        output.push('\n');
    }

    output.push_str("## Scenario Results\n\n");
    for result in &input.scenario_results {
        output.push_str(&format!(
            "### {} {}\n\n",
            if result.ok { "PASS" } else { "FAIL" },
            result.label.trim()
        ));
        output.push_str(&format!("- ID: `{}`\n", result.id.trim()));
        if let Some(smoke_tier) = result.smoke_tier.as_ref() {
            output.push_str(&format!("- Smoke Tier: `{}`\n", smoke_tier.trim()));
        }
        output.push_str(&format!(
            "- Failure Kind: `{}`\n",
            result.failure_kind.trim()
        ));
        output.push_str(&format!(
            "- Actual Turn Kind: `{}`\n",
            result.actual_turn_kind.trim()
        ));
        output.push_str(&format!(
            "- Expected Turn Kinds: `{}`\n",
            result.expected_turn_kinds.join("`, `")
        ));
        if let Some(turn_kind_source) = result.turn_kind_source.as_ref() {
            output.push_str(&format!(
                "- Turn Kind Source: `{}`\n",
                turn_kind_source.trim()
            ));
        }
        if let Some(correction) = result.turn_kind_correction.as_ref() {
            output.push_str(&format!(
                "- Turn Kind Correction: `{}` -> `{}` ({})\n",
                correction.from.trim(),
                correction.to.trim(),
                correction.reason.trim()
            ));
        }
        output.push_str(&format!(
            "- Document Changed: `{}`\n",
            if result.document_changed {
                "true"
            } else {
                "false"
            }
        ));
        output.push_str(&format!(
            "- Active Document: `{}`\n",
            result.active_document_slug.trim()
        ));
        if let Some(action_type) = result.requested_action_type.as_ref() {
            output.push_str(&format!("- Requested Action: `{}`\n", action_type.trim()));
        }
        if let Some(preview_only) = result.requested_preview_only {
            output.push_str(&format!(
                "- Preview Only: `{}`\n",
                if preview_only { "true" } else { "false" }
            ));
        }
        if let Some(derived_slug) = result.derived_document_slug.as_ref() {
            output.push_str(&format!("- Derived Document: `{}`\n", derived_slug.trim()));
        }
        if let Some(derived_path) = result.derived_document_path.as_ref() {
            output.push_str(&format!("- Derived Path: `{}`\n", derived_path.trim()));
        }
        output.push_str(&format!(
            "- Context Ref Count: `{}`\n",
            result.context_ref_count
        ));
        output.push_str(&format!("- Questions: `{}`\n", result.question_count));
        output.push_str(&format!("- Options: `{}`\n", result.option_count));
        output.push_str(&format!("- Plan Steps: `{}`\n", result.plan_step_count));
        output.push_str(&format!(
            "- Requested Actions: `{}`\n",
            result.requested_action_count
        ));
        if !result.diagnostic_flags.is_empty() {
            output.push_str(&format!(
                "- Diagnostic Flags: `{}`\n",
                result.diagnostic_flags.join("`, `")
            ));
        }
        if !result.assistant_message.trim().is_empty() {
            output.push_str(&format!(
                "- Assistant Message: {}\n",
                result.assistant_message.trim()
            ));
        }
        if !result.provider_error.trim().is_empty() {
            output.push_str(&format!(
                "- Provider Error: {}\n",
                result.provider_error.trim()
            ));
        }
        output.push_str(&format!("- Status: {}\n", result.status_message.trim()));
        output.push_str(&format!("- Summary: {}\n", result.summary.trim()));
        if let Some(error) = result.error.as_ref() {
            if !error.trim().is_empty() {
                output.push_str(&format!("- Error: {}\n", error.trim()));
            }
        }
        output.push_str("\n");
    }

    output
}

fn push_section(output: &mut String, title: &str, items: &[String]) {
    let normalized = items
        .iter()
        .map(|item| item.trim())
        .filter(|item| !item.is_empty())
        .collect::<Vec<_>>();
    if normalized.is_empty() {
        return;
    }

    output.push_str(&format!("## {title}\n\n"));
    for item in normalized {
        output.push_str(&format!("- {item}\n"));
    }
    output.push('\n');
}

fn sanitize_file_stem(value: &str) -> String {
    let sanitized = value
        .chars()
        .map(|ch| match ch {
            'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' => ch,
            _ => '-',
        })
        .collect::<String>();
    let trimmed = sanitized.trim_matches('-');
    if trimmed.is_empty() {
        "session".to_string()
    } else {
        trimmed.to_string()
    }
}

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0)
}
