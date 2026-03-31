use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

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

    push_section(&mut output, "Strategy", &[input.strategy_summary.trim().to_string()]);

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

    push_section(
        &mut output,
        "Source Documents",
        &input.source_document_keys,
    );
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
