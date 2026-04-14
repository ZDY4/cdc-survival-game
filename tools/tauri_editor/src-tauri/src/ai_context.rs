use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use serde::Serialize;
use serde_json::{json, Map, Value};

const DIALOG_RELATED: &[&str] = &["dialogues", "characters", "quests"];
const QUEST_RELATED: &[&str] = &[
    "quests",
    "items",
    "dialogues",
    "map_locations",
    "structures",
];

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ContextBuildResult {
    pub context: Value,
    pub context_stats: Value,
    pub truncation: Value,
    pub allowed_reference_groups: Vec<String>,
    pub suggested_reference_groups: Vec<String>,
}

enum CategorySource {
    Directory {
        relative_path: &'static str,
        id_field: &'static str,
    },
    File {
        relative_path: &'static str,
    },
}

pub fn build_context(
    repo_root: &Path,
    data_type: &str,
    request: &Map<String, Value>,
    max_context_records: usize,
) -> Result<ContextBuildResult, String> {
    let normalized_type = data_type.trim().to_lowercase();
    let categories = related_categories(&normalized_type);
    let category_count = categories.len().max(1);
    let same_type_category = map_data_type_to_category(&normalized_type);
    let mut project_counts = Map::new();
    let mut related_indexes = Map::new();
    let mut allowed_reference_ids = Map::new();
    let mut suggested_reference_ids = Map::new();
    let mut truncation = Map::new();

    let intent_text = build_intent_text(request);
    let target_id = request
        .get("target_id")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    let mut same_type_index = Vec::new();
    let mut same_type_examples = Vec::new();
    let mut included_index_records = 0usize;
    let mut included_examples = 0usize;

    for category in &categories {
        let records = load_category(repo_root, category)?;
        project_counts.insert(category.to_string(), json!(records.len()));

        let mut ids = records.keys().cloned().collect::<Vec<_>>();
        ids.sort_by(|left, right| {
            score_record(category, left, records.get(left), &intent_text, &target_id)
                .cmp(&score_record(
                    category,
                    right,
                    records.get(right),
                    &intent_text,
                    &target_id,
                ))
                .reverse()
                .then_with(|| left.cmp(right))
        });

        let allowed_ids = ids.clone();
        allowed_reference_ids.insert(category.to_string(), json!(allowed_ids));
        suggested_reference_ids.insert(
            category.to_string(),
            json!(ids.iter().take(6).cloned().collect::<Vec<_>>()),
        );

        if *category == same_type_category {
            let index_limit = max_context_records.clamp(6, 16);
            let example_limit = (max_context_records / 6).clamp(2, 4);
            same_type_index = ids
                .iter()
                .take(index_limit)
                .filter_map(|id| {
                    records
                        .get(id)
                        .map(|record| summarize_record(category, id, record))
                })
                .collect();
            same_type_examples = ids
                .iter()
                .take(example_limit)
                .filter_map(|id| {
                    records
                        .get(id)
                        .map(|record| example_record(category, &normalized_type, record))
                })
                .collect();

            included_index_records += same_type_index.len();
            included_examples += same_type_examples.len();
            truncation.insert(
                category.to_string(),
                json!({
                    "available": records.len(),
                    "includedIndexRecords": same_type_index.len(),
                    "includedExamples": same_type_examples.len(),
                    "droppedIndexRecords": records.len().saturating_sub(same_type_index.len()),
                    "droppedExamples": records.len().saturating_sub(same_type_examples.len())
                }),
            );
        } else {
            let related_limit = (max_context_records / category_count).clamp(4, 10);
            let entries = ids
                .iter()
                .take(related_limit)
                .filter_map(|id| {
                    records
                        .get(id)
                        .map(|record| summarize_record(category, id, record))
                })
                .collect::<Vec<_>>();
            included_index_records += entries.len();
            related_indexes.insert(category.to_string(), json!(entries));
            truncation.insert(
                category.to_string(),
                json!({
                    "available": records.len(),
                    "includedIndexRecords": entries.len(),
                    "includedExamples": 0,
                    "droppedIndexRecords": records.len().saturating_sub(entries.len()),
                    "droppedExamples": 0
                }),
            );
        }
    }

    let story_background = load_story_background(repo_root)?;
    let context_stats = json!({
        "maxRecords": max_context_records,
        "includedIndexRecords": included_index_records,
        "includedExamples": included_examples,
        "truncatedCategories": truncation
            .iter()
            .filter_map(|(category, stats)| {
                let available = stats.get("available").and_then(Value::as_u64).unwrap_or(0);
                let included = stats
                    .get("includedIndexRecords")
                    .and_then(Value::as_u64)
                    .unwrap_or(0)
                    + stats
                        .get("includedExamples")
                        .and_then(Value::as_u64)
                        .unwrap_or(0);
                if available > included {
                    Some(category.clone())
                } else {
                    None
                }
            })
            .collect::<Vec<_>>(),
        "categoryCounts": project_counts
    });

    let context = json!({
        "data_type": normalized_type,
        "mode": request.get("mode").cloned().unwrap_or_else(|| json!("create")),
        "target_id": target_id,
        "current_record": request.get("current_record").cloned().unwrap_or_else(|| json!({})),
        "project_counts": project_counts,
        "same_type_index": same_type_index,
        "same_type_examples": same_type_examples,
        "related_indexes": related_indexes,
        "allowed_reference_ids": allowed_reference_ids,
        "suggested_reference_ids": suggested_reference_ids,
        "constraints": constraints_for(&normalized_type),
        "context_stats": context_stats,
        "truncation": truncation,
        "story_background": story_background,
    });

    Ok(ContextBuildResult {
        context,
        context_stats,
        truncation: Value::Object(truncation),
        allowed_reference_groups: allowed_reference_ids.keys().cloned().collect::<Vec<_>>(),
        suggested_reference_groups: suggested_reference_ids.keys().cloned().collect::<Vec<_>>(),
    })
}

fn related_categories(data_type: &str) -> Vec<&'static str> {
    match data_type {
        "dialog" => DIALOG_RELATED.to_vec(),
        "quest" => QUEST_RELATED.to_vec(),
        _ => Vec::new(),
    }
}

fn map_data_type_to_category(data_type: &str) -> &'static str {
    match data_type {
        "dialog" => "dialogues",
        "quest" => "quests",
        _ => "",
    }
}

fn constraints_for(data_type: &str) -> Vec<&'static str> {
    match data_type {
        "dialog" => vec![
            "record must contain dialog_id, nodes, and connections",
            "every node id must be unique",
            "choice/condition/dialog/action next fields must stay consistent with the connections array",
        ],
        "quest" => vec![
            "record must use the flow graph schema instead of the legacy objectives/rewards schema",
            "flow.start_node_id must point to an existing start node",
            "the flow must contain exactly one start node and at least one end node",
        ],
        _ => Vec::new(),
    }
}

fn score_record(
    category: &str,
    record_id: &str,
    record: Option<&Value>,
    intent_text: &str,
    target_id: &str,
) -> i32 {
    let mut score = 0i32;
    if !target_id.is_empty() && record_id == target_id {
        score += 100;
    }

    let search_text = build_search_text(category, record_id, record);
    for token in tokenize_intent(intent_text) {
        if search_text.contains(&token) {
            score += 10;
        }
    }

    if category == "dialogues" && search_text.contains("dialog") {
        score += 4;
    }
    if category == "quests" && search_text.contains("quest") {
        score += 4;
    }

    score
}

fn build_search_text(category: &str, record_id: &str, record: Option<&Value>) -> String {
    let mut pieces = vec![category.to_string(), record_id.to_string()];
    if let Some(record) = record {
        pieces.push(record.to_string());
    }
    pieces.join(" ").to_lowercase()
}

fn tokenize_intent(intent_text: &str) -> Vec<String> {
    let mut tokens = intent_text
        .split(|character: char| {
            !character.is_alphanumeric() && character != '_' && character != '-'
        })
        .map(str::trim)
        .filter(|value| value.len() >= 2)
        .map(|value| value.to_lowercase())
        .collect::<Vec<_>>();
    tokens.sort();
    tokens.dedup();
    tokens
}

fn build_intent_text(request: &Map<String, Value>) -> String {
    let current_record = request
        .get("current_record")
        .map(Value::to_string)
        .unwrap_or_default();
    [
        request
            .get("target_id")
            .and_then(Value::as_str)
            .unwrap_or_default(),
        request
            .get("user_prompt")
            .and_then(Value::as_str)
            .unwrap_or_default(),
        request
            .get("adjustment_prompt")
            .and_then(Value::as_str)
            .unwrap_or_default(),
        &current_record,
    ]
    .join(" ")
    .to_lowercase()
}

fn summarize_record(category: &str, record_id: &str, record: &Value) -> Value {
    json!({
        "id": record_id,
        "summary": summary_text(category, record_id, record),
    })
}

fn example_record(category: &str, data_type: &str, record: &Value) -> Value {
    if category == "dialogues" && data_type == "dialog" {
        return trim_dialogue_example(record, 4);
    }
    record.clone()
}

fn summary_text(category: &str, record_id: &str, record: &Value) -> String {
    let object = record.as_object();
    match category {
        "dialogues" => {
            let node_count = object
                .and_then(|value| value.get("nodes"))
                .and_then(Value::as_array)
                .map(Vec::len)
                .unwrap_or(0);
            format!("{record_id} | {node_count} nodes")
        }
        "quests" => {
            let title = object
                .and_then(|value| value.get("title"))
                .and_then(Value::as_str)
                .unwrap_or(record_id);
            format!("{record_id} | {title}")
        }
        "items" | "characters" | "skills" | "skill_trees" | "recipes" => {
            let label = object
                .and_then(|value| value.get("name"))
                .and_then(Value::as_str)
                .unwrap_or(record_id);
            format!("{record_id} | {label}")
        }
        "effects" => {
            let label = object
                .and_then(|value| value.get("name"))
                .and_then(Value::as_str)
                .unwrap_or(record_id);
            format!("{record_id} | {label}")
        }
        "map_locations" | "structures" | "story_chapters" | "clues" => {
            let label = object
                .and_then(|value| value.get("title").or_else(|| value.get("name")))
                .and_then(Value::as_str)
                .unwrap_or(record_id);
            format!("{record_id} | {label}")
        }
        _ => record_id.to_string(),
    }
}

fn trim_dialogue_example(record: &Value, max_nodes: usize) -> Value {
    let Some(object) = record.as_object() else {
        return record.clone();
    };

    let mut trimmed = object.clone();
    if let Some(nodes) = trimmed.get_mut("nodes").and_then(Value::as_array_mut) {
        let shortened = nodes.iter().take(max_nodes).cloned().collect::<Vec<_>>();
        *nodes = shortened;
    }
    Value::Object(trimmed)
}

fn load_story_background(repo_root: &Path) -> Result<Value, String> {
    let path = repo_root
        .join("data")
        .join("json")
        .join("story_chapters.json");
    if !path.exists() {
        return Ok(Value::Null);
    }
    let raw = fs::read_to_string(&path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let parsed: Value = serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
    Ok(parsed)
}

fn load_category(repo_root: &Path, category: &str) -> Result<BTreeMap<String, Value>, String> {
    if category == "map_locations" {
        return load_overworld_location_records(&repo_root.join("data").join("overworld"));
    }

    match category_source(category) {
        Some(CategorySource::Directory {
            relative_path,
            id_field,
        }) => load_directory_records(&repo_root.join(relative_path), id_field),
        Some(CategorySource::File { relative_path }) => {
            load_file_records(&repo_root.join(relative_path))
        }
        None => Ok(BTreeMap::new()),
    }
}

fn category_source(category: &str) -> Option<CategorySource> {
    match category {
        "items" => Some(CategorySource::Directory {
            relative_path: "data/items",
            id_field: "id",
        }),
        "quests" => Some(CategorySource::Directory {
            relative_path: "data/quests",
            id_field: "quest_id",
        }),
        "dialogues" => Some(CategorySource::Directory {
            relative_path: "data/dialogues",
            id_field: "dialog_id",
        }),
        "characters" => Some(CategorySource::Directory {
            relative_path: "data/characters",
            id_field: "id",
        }),
        "skills" => Some(CategorySource::Directory {
            relative_path: "data/skills",
            id_field: "id",
        }),
        "skill_trees" => Some(CategorySource::Directory {
            relative_path: "data/skill_trees",
            id_field: "id",
        }),
        "recipes" => Some(CategorySource::Directory {
            relative_path: "data/recipes",
            id_field: "id",
        }),
        "effects" => Some(CategorySource::Directory {
            relative_path: "data/json/effects",
            id_field: "id",
        }),
        "story_chapters" => Some(CategorySource::File {
            relative_path: "data/json/story_chapters.json",
        }),
        "structures" => Some(CategorySource::File {
            relative_path: "data/json/structures.json",
        }),
        "clues" => Some(CategorySource::File {
            relative_path: "data/json/clues.json",
        }),
        _ => None,
    }
}

fn load_directory_records(dir: &Path, id_field: &str) -> Result<BTreeMap<String, Value>, String> {
    if !dir.exists() {
        return Ok(BTreeMap::new());
    }

    let mut entries = fs::read_dir(dir)
        .map_err(|error| format!("failed to read {}: {error}", dir.display()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("failed to enumerate {}: {error}", dir.display()))?;
    entries.sort_by_key(|entry| entry.file_name());

    let mut result = BTreeMap::new();
    for entry in entries {
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let raw = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
        let parsed: Value = serde_json::from_str(&raw)
            .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
        let id = parsed.get(id_field).map(value_to_id).unwrap_or_else(|| {
            path.file_stem()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .to_string()
        });
        if !id.trim().is_empty() {
            result.insert(id, parsed);
        }
    }
    Ok(result)
}

fn load_file_records(path: &Path) -> Result<BTreeMap<String, Value>, String> {
    if !path.exists() {
        return Ok(BTreeMap::new());
    }

    let raw = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let parsed: Value = serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;

    let mut result = BTreeMap::new();
    match parsed {
        Value::Object(map) => {
            for (key, value) in map {
                result.insert(key, value);
            }
        }
        Value::Array(values) => {
            for value in values {
                if let Some(object) = value.as_object() {
                    let id = object
                        .get("id")
                        .or_else(|| object.get("quest_id"))
                        .or_else(|| object.get("dialog_id"))
                        .map(value_to_id)
                        .unwrap_or_default();
                    if !id.is_empty() {
                        result.insert(id, Value::Object(object.clone()));
                    }
                }
            }
        }
        _ => {}
    }

    Ok(result)
}

fn load_overworld_location_records(dir: &Path) -> Result<BTreeMap<String, Value>, String> {
    if !dir.exists() {
        return Ok(BTreeMap::new());
    }

    let mut entries = fs::read_dir(dir)
        .map_err(|error| format!("failed to read {}: {error}", dir.display()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("failed to enumerate {}: {error}", dir.display()))?;
    entries.sort_by_key(|entry| entry.file_name());

    let mut result = BTreeMap::new();
    for entry in entries {
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let raw = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
        let parsed: Value = serde_json::from_str(&raw)
            .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
        let Some(locations) = parsed.get("locations").and_then(Value::as_array) else {
            continue;
        };
        for location in locations {
            let Some(location_id) = location.get("id").and_then(Value::as_str) else {
                continue;
            };
            let location_id = location_id.trim();
            if !location_id.is_empty() {
                result.insert(location_id.to_string(), location.clone());
            }
        }
    }

    Ok(result)
}

fn value_to_id(value: &Value) -> String {
    match value {
        Value::String(text) => text.trim().to_string(),
        Value::Number(number) => number.to_string(),
        _ => String::new(),
    }
}
