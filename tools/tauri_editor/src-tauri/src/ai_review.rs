use serde::Serialize;
use serde_json::{Map, Value};

#[derive(Debug, Clone, Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct AiDiffSummary {
    pub summary_lines: Vec<String>,
    pub added_paths: Vec<String>,
    pub changed_paths: Vec<String>,
    pub removed_paths: Vec<String>,
    pub risk_level: String,
}

pub fn validate_draft_contract(data_type: &str, draft: &Map<String, Value>) -> Vec<String> {
    let mut errors = Vec::new();

    let record_type = draft
        .get("record_type")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_lowercase();
    if record_type != data_type {
        errors.push("record_type 与当前编辑器类型不一致".to_string());
    }

    let operation = draft
        .get("operation")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim();
    if operation != "create" && operation != "revise" {
        errors.push("operation 必须是 create 或 revise".to_string());
    }

    if !matches!(draft.get("warnings"), Some(Value::Array(_))) {
        errors.push("warnings 必须是数组".to_string());
    }

    let Some(record) = draft.get("record") else {
        errors.push("record 必须是对象".to_string());
        return errors;
    };
    let Some(record_object) = record.as_object() else {
        errors.push("record 必须是对象".to_string());
        return errors;
    };
    if record_object.is_empty() {
        errors.push("record 不能为空对象".to_string());
    }

    errors
}

pub fn summarize_dialogue_diff(before: &Value, after: &Value) -> AiDiffSummary {
    let mut summary_lines = Vec::new();

    let before_nodes = before
        .get("nodes")
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or(0);
    let after_nodes = after
        .get("nodes")
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or(0);
    if before_nodes != after_nodes {
        summary_lines.push(format!("节点数量 {before_nodes} -> {after_nodes}"));
    }

    let before_branches = count_dialogue_branches(before);
    let after_branches = count_dialogue_branches(after);
    if before_branches != after_branches {
        summary_lines.push(format!("分支数量 {before_branches} -> {after_branches}"));
    }

    let before_end_types = collect_dialogue_end_types(before);
    let after_end_types = collect_dialogue_end_types(after);
    if before_end_types != after_end_types {
        summary_lines.push("结束节点类型发生变化".to_string());
    }

    build_diff_summary(before, after, summary_lines)
}

pub fn summarize_quest_diff(before: &Value, after: &Value) -> AiDiffSummary {
    let mut summary_lines = Vec::new();

    let before_nodes = before
        .get("flow")
        .and_then(|value| value.get("nodes"))
        .and_then(Value::as_object)
        .map(Map::len)
        .unwrap_or(0);
    let after_nodes = after
        .get("flow")
        .and_then(|value| value.get("nodes"))
        .and_then(Value::as_object)
        .map(Map::len)
        .unwrap_or(0);
    if before_nodes != after_nodes {
        summary_lines.push(format!("流程节点数量 {before_nodes} -> {after_nodes}"));
    }

    let before_objective_types = collect_quest_objective_types(before);
    let after_objective_types = collect_quest_objective_types(after);
    if before_objective_types != after_objective_types {
        summary_lines.push("任务目标类型发生变化".to_string());
    }

    let before_reward_refs = collect_quest_reward_item_refs(before);
    let after_reward_refs = collect_quest_reward_item_refs(after);
    if before_reward_refs != after_reward_refs {
        summary_lines.push("奖励引用发生变化".to_string());
    }

    let before_prerequisites = collect_quest_prerequisites(before);
    let after_prerequisites = collect_quest_prerequisites(after);
    if before_prerequisites != after_prerequisites {
        summary_lines.push("前置任务发生变化".to_string());
    }

    build_diff_summary(before, after, summary_lines)
}

pub fn build_review_warnings(
    mode: &str,
    user_prompt: &str,
    adjustment_prompt: &str,
    draft_record: Option<&Map<String, Value>>,
    diff_summary: &AiDiffSummary,
) -> Vec<String> {
    let mut warnings = Vec::new();
    if draft_record.map(Map::is_empty).unwrap_or(true) {
        warnings.push("AI 返回了空 record，已禁止应用。".to_string());
    }

    if mode == "revise" && looks_like_minimal_change_request(user_prompt, adjustment_prompt) {
        let total_changes = diff_summary.added_paths.len()
            + diff_summary.changed_paths.len()
            + diff_summary.removed_paths.len();
        if total_changes >= 8 || diff_summary.risk_level == "high" {
            warnings.push(
                "当前是调整模式，但草稿改动范围较大，请重点检查未在提示词中提到的字段。"
                    .to_string(),
            );
        }
    }

    warnings
}

pub fn empty_record(record: Option<&Map<String, Value>>) -> bool {
    record.map(Map::is_empty).unwrap_or(true)
}

fn build_diff_summary(
    before: &Value,
    after: &Value,
    mut summary_lines: Vec<String>,
) -> AiDiffSummary {
    let mut added_paths = Vec::new();
    let mut changed_paths = Vec::new();
    let mut removed_paths = Vec::new();
    collect_diff_paths(
        before,
        after,
        "",
        &mut added_paths,
        &mut changed_paths,
        &mut removed_paths,
    );

    if !added_paths.is_empty() {
        summary_lines.push(format!("新增字段 {} 个", added_paths.len()));
    }
    if !changed_paths.is_empty() {
        summary_lines.push(format!("修改字段 {} 个", changed_paths.len()));
    }
    if !removed_paths.is_empty() {
        summary_lines.push(format!("删除字段 {} 个", removed_paths.len()));
    }
    if summary_lines.is_empty() {
        summary_lines.push("草稿与当前记录没有结构差异".to_string());
    }

    let risk_level = if !removed_paths.is_empty() || primary_id_changed(before, after) {
        "high"
    } else if !added_paths.is_empty() || !changed_paths.is_empty() {
        "medium"
    } else {
        "low"
    };

    AiDiffSummary {
        summary_lines,
        added_paths,
        changed_paths,
        removed_paths,
        risk_level: risk_level.to_string(),
    }
}

fn collect_diff_paths(
    before: &Value,
    after: &Value,
    path: &str,
    added_paths: &mut Vec<String>,
    changed_paths: &mut Vec<String>,
    removed_paths: &mut Vec<String>,
) {
    match (before, after) {
        (Value::Object(before_map), Value::Object(after_map)) => {
            let mut keys = before_map
                .keys()
                .chain(after_map.keys())
                .cloned()
                .collect::<Vec<_>>();
            keys.sort();
            keys.dedup();

            for key in keys {
                let child_path = if path.is_empty() {
                    key.clone()
                } else {
                    format!("{path}.{key}")
                };
                match (before_map.get(&key), after_map.get(&key)) {
                    (None, Some(_)) => added_paths.push(child_path),
                    (Some(_), None) => removed_paths.push(child_path),
                    (Some(left), Some(right)) => collect_diff_paths(
                        left,
                        right,
                        &child_path,
                        added_paths,
                        changed_paths,
                        removed_paths,
                    ),
                    (None, None) => {}
                }
            }
        }
        (Value::Array(before_items), Value::Array(after_items)) => {
            let max_size = before_items.len().max(after_items.len());
            for index in 0..max_size {
                let child_path = if path.is_empty() {
                    format!("root[{index}]")
                } else {
                    format!("{path}[{index}]")
                };
                match (before_items.get(index), after_items.get(index)) {
                    (None, Some(_)) => added_paths.push(child_path),
                    (Some(_), None) => removed_paths.push(child_path),
                    (Some(left), Some(right)) => collect_diff_paths(
                        left,
                        right,
                        &child_path,
                        added_paths,
                        changed_paths,
                        removed_paths,
                    ),
                    (None, None) => {}
                }
            }
        }
        _ => {
            if before != after {
                changed_paths.push(if path.is_empty() {
                    "root".to_string()
                } else {
                    path.to_string()
                });
            }
        }
    }
}

fn primary_id_changed(before: &Value, after: &Value) -> bool {
    for key in ["id", "dialog_id", "quest_id"] {
        let before_id = before
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim();
        let after_id = after
            .get(key)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim();
        if !before_id.is_empty() && !after_id.is_empty() && before_id != after_id {
            return true;
        }
    }
    false
}

fn looks_like_minimal_change_request(user_prompt: &str, adjustment_prompt: &str) -> bool {
    let prompt_text = format!("{user_prompt} {adjustment_prompt}").to_lowercase();
    for token in [
        "微调", "润色", "小改", "只改", "minor", "small", "tweak", "polish", "refine",
    ] {
        if prompt_text.contains(token) {
            return true;
        }
    }
    prompt_text.trim().len() <= 24
}

fn count_dialogue_branches(value: &Value) -> usize {
    let mut total = 0usize;
    for node in value
        .get("nodes")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        match node.get("type").and_then(Value::as_str).unwrap_or_default() {
            "choice" => {
                total += node
                    .get("options")
                    .and_then(Value::as_array)
                    .map(Vec::len)
                    .unwrap_or(0);
            }
            "condition" => {
                if !node
                    .get("true_next")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .trim()
                    .is_empty()
                {
                    total += 1;
                }
                if !node
                    .get("false_next")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .trim()
                    .is_empty()
                {
                    total += 1;
                }
            }
            _ => {}
        }
    }
    total
}

fn collect_dialogue_end_types(value: &Value) -> Vec<String> {
    let mut result = value
        .get("nodes")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter(|node| node.get("type").and_then(Value::as_str) == Some("end"))
        .map(|node| {
            node.get("end_type")
                .and_then(Value::as_str)
                .unwrap_or("normal")
                .trim()
                .to_string()
        })
        .filter(|value| !value.is_empty())
        .collect::<Vec<_>>();
    result.sort();
    result.dedup();
    result
}

fn collect_quest_objective_types(value: &Value) -> Vec<String> {
    let mut result = iter_quest_nodes(value)
        .filter(|node| node.get("type").and_then(Value::as_str) == Some("objective"))
        .filter_map(|node| node.get("objective_type").and_then(Value::as_str))
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    result.sort();
    result.dedup();
    result
}

fn collect_quest_reward_item_refs(value: &Value) -> Vec<String> {
    let mut result = Vec::new();
    for node in iter_quest_nodes(value)
        .filter(|node| node.get("type").and_then(Value::as_str) == Some("reward"))
    {
        for item in node
            .get("rewards")
            .and_then(|value| value.get("items"))
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let id_value = match item.get("id") {
                Some(Value::String(text)) => text.trim().to_string(),
                Some(Value::Number(number)) => number.to_string(),
                _ => String::new(),
            };
            if !id_value.is_empty() {
                result.push(id_value);
            }
        }
    }
    result.sort();
    result.dedup();
    result
}

fn collect_quest_prerequisites(value: &Value) -> Vec<String> {
    let mut result = value
        .get("prerequisites")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .collect::<Vec<_>>();
    result.sort();
    result.dedup();
    result
}

fn iter_quest_nodes(value: &Value) -> impl Iterator<Item = &Value> {
    value
        .get("flow")
        .and_then(|value| value.get("nodes"))
        .and_then(Value::as_object)
        .into_iter()
        .flat_map(|nodes| nodes.values())
}
