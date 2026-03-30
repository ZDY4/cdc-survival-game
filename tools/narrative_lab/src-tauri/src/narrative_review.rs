use serde::{Deserialize, Serialize};
use serde_json::json;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeSelectionRange {
    pub start: usize,
    pub end: usize,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeReviewResult {
    pub review_notes: Vec<String>,
    pub risk_level: String,
    pub change_scope: String,
    pub diff_preview: String,
}

pub fn validate_selection(
    current_markdown: &str,
    selected_range: Option<&NarrativeSelectionRange>,
    selected_text: &str,
    action: &str,
) -> Result<Option<NarrativeSelectionRange>, String> {
    if !matches!(
        action,
        "rewrite_selection" | "expand_selection" | "insert_after_selection"
    ) {
        return Ok(None);
    }

    let Some(range) = selected_range.cloned() else {
        return Err("当前操作需要有效的文本选区".to_string());
    };
    if range.start > range.end {
        return Err("选区范围超出当前文稿长度".to_string());
    }
    let normalized_range = normalize_selection_range(current_markdown, &range)?;
    let actual = slice_markdown(current_markdown, &normalized_range)?;
    if !selected_text.is_empty() && actual != selected_text {
        return Err("选区文本与当前编辑器内容不一致，请重新选择后再生成".to_string());
    }

    Ok(Some(normalized_range))
}

pub fn change_scope_for_action(action: &str) -> &'static str {
    match action {
        "rewrite_selection" | "expand_selection" => "selection",
        "insert_after_selection" => "insertion",
        "derive_new_doc" => "new_doc",
        _ => "document",
    }
}

pub fn build_review_result(
    action: &str,
    current_markdown: &str,
    selected_range: Option<&NarrativeSelectionRange>,
    draft_markdown: &str,
    mut review_notes: Vec<String>,
) -> NarrativeReviewResult {
    let change_scope = change_scope_for_action(action).to_string();
    let diff_preview = diff_preview_for(action, current_markdown, selected_range, draft_markdown);
    let risk_level = risk_level_for(action, current_markdown, selected_range, draft_markdown);

    if draft_markdown.trim().is_empty() {
        review_notes.push("AI 返回了空文稿，已禁止直接应用。".to_string());
    }
    if change_scope == "selection" && selected_range.is_none() {
        review_notes.push("当前草稿依赖选区替换，但选区信息缺失。".to_string());
    }
    if risk_level == "high" {
        review_notes.push("本次改动影响范围较大，应用前请重点检查上下文衔接。".to_string());
    }

    NarrativeReviewResult {
        review_notes,
        risk_level,
        change_scope,
        diff_preview,
    }
}

pub fn prompt_debug_payload(
    action: &str,
    selection: Option<&NarrativeSelectionRange>,
    workspace_context_refs: &[String],
    project_context_refs: &[String],
    project_context_warning: &str,
    source_conflicts: &[String],
    extra: serde_json::Value,
) -> serde_json::Value {
    json!({
        "action": action,
        "selection": selection,
        "workspaceNarrativeRefs": workspace_context_refs,
        "connectedProjectRefs": project_context_refs,
        "projectContextWarning": project_context_warning,
        "usedContextRefs": workspace_context_refs.iter().chain(project_context_refs.iter()).cloned().collect::<Vec<_>>(),
        "sourceConflicts": source_conflicts,
        "extra": extra
    })
}

fn risk_level_for(
    action: &str,
    current_markdown: &str,
    selected_range: Option<&NarrativeSelectionRange>,
    draft_markdown: &str,
) -> String {
    if draft_markdown.trim().is_empty() {
        return "high".to_string();
    }

    match action {
        "rewrite_selection" | "expand_selection" | "insert_after_selection" => {
            if let Some(range) = selected_range {
                let base_len = slice_markdown(current_markdown, range)
                    .map(|selection| selection.chars().count())
                    .unwrap_or_else(|_| range.end.saturating_sub(range.start))
                    .max(1);
                let ratio = draft_markdown.chars().count() as f64 / base_len as f64;
                if ratio > 3.0 {
                    "high".to_string()
                } else if ratio > 1.5 {
                    "medium".to_string()
                } else {
                    "low".to_string()
                }
            } else {
                "high".to_string()
            }
        }
        "derive_new_doc" => "medium".to_string(),
        _ => {
            if draft_markdown.len() > current_markdown.len().saturating_mul(2) {
                "high".to_string()
            } else if draft_markdown != current_markdown {
                "medium".to_string()
            } else {
                "low".to_string()
            }
        }
    }
}

fn diff_preview_for(
    action: &str,
    current_markdown: &str,
    selected_range: Option<&NarrativeSelectionRange>,
    draft_markdown: &str,
) -> String {
    match action {
        "rewrite_selection" | "expand_selection" => {
            let before = selected_range
                .and_then(|range| slice_markdown(current_markdown, range).ok())
                .map(ToString::to_string)
                .unwrap_or_default();
            format!(
                "Current selection\n{}\n\nDraft replacement\n{}",
                normalize_excerpt(&before),
                normalize_excerpt(draft_markdown),
            )
        }
        "insert_after_selection" => {
            let anchor = selected_range
                .and_then(|range| slice_markdown(current_markdown, range).ok())
                .map(ToString::to_string)
                .unwrap_or_default();
            format!(
                "Insert after selection\n{}\n\nInserted text\n{}",
                normalize_excerpt(&anchor),
                normalize_excerpt(draft_markdown),
            )
        }
        _ => format!(
            "Current document\n{}\n\nDraft document\n{}",
            normalize_excerpt(current_markdown),
            normalize_excerpt(draft_markdown),
        ),
    }
}

fn normalize_selection_range(
    current_markdown: &str,
    range: &NarrativeSelectionRange,
) -> Result<NarrativeSelectionRange, String> {
    let start = utf16_offset_to_byte_index(current_markdown, range.start)
        .ok_or_else(|| "选区起点不是合法字符边界，请重新选择后再试".to_string())?;
    let end = utf16_offset_to_byte_index(current_markdown, range.end)
        .ok_or_else(|| "选区终点不是合法字符边界，请重新选择后再试".to_string())?;

    if start > end || end > current_markdown.len() {
        return Err("选区范围超出当前文稿长度".to_string());
    }

    Ok(NarrativeSelectionRange { start, end })
}

fn utf16_offset_to_byte_index(input: &str, utf16_offset: usize) -> Option<usize> {
    if utf16_offset == 0 {
        return Some(0);
    }

    let mut utf16_count = 0usize;
    for (byte_index, ch) in input.char_indices() {
        if utf16_count == utf16_offset {
            return Some(byte_index);
        }
        utf16_count += ch.len_utf16();
        if utf16_count == utf16_offset {
            return Some(byte_index + ch.len_utf8());
        }
        if utf16_count > utf16_offset {
            return None;
        }
    }

    if utf16_count == utf16_offset {
        Some(input.len())
    } else {
        None
    }
}

fn slice_markdown<'a>(
    current_markdown: &'a str,
    range: &NarrativeSelectionRange,
) -> Result<&'a str, String> {
    current_markdown
        .get(range.start..range.end)
        .ok_or_else(|| "选区范围不是合法 UTF-8 字符边界".to_string())
}

fn normalize_excerpt(input: &str) -> String {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return "(empty)".to_string();
    }
    let max_chars = 1200usize;
    if trimmed.chars().count() <= max_chars {
        return trimmed.to_string();
    }
    trimmed.chars().take(max_chars).collect::<String>() + "..."
}
