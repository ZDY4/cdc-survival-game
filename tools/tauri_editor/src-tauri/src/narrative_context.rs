use std::collections::BTreeMap;
use std::fs;
use std::path::Path;

use serde::Serialize;
use serde_json::{json, Value};

use crate::narrative_provider::NarrativeGenerateRequest;
use crate::narrative_workspace::load_narrative_documents;

const RUNTIME_CATEGORIES: &[&str] = &[
    "quests",
    "dialogues",
    "characters",
    "map_locations",
    "structures",
];

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeContextBuildResult {
    pub context: Value,
    pub used_context_refs: Vec<String>,
    pub workspace_context_refs: Vec<String>,
    pub project_context_refs: Vec<String>,
    pub source_conflicts: Vec<String>,
    pub project_context_warning: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectContextSnapshotSeed {
    pub summary: String,
    pub source_refs: Vec<String>,
    pub runtime_indexes: Value,
    pub story_background: Value,
}

pub fn build_narrative_context(
    workspace_root: &Path,
    project_root: Option<&Path>,
    request: &NarrativeGenerateRequest,
    max_context_records: usize,
) -> Result<NarrativeContextBuildResult, String> {
    let narrative_documents = load_narrative_documents(workspace_root)?;
    let mut workspace_context_refs = Vec::new();

    let related_doc_records = narrative_documents
        .iter()
        .filter(|document| request.related_doc_slugs.contains(&document.meta.slug))
        .map(|document| {
            workspace_context_refs.push(format!("narrative:{}", document.meta.slug));
            json!({
                "slug": document.meta.slug,
                "docType": document.meta.doc_type,
                "title": document.meta.title,
                "summary": summarize_markdown(&document.markdown),
            })
        })
        .collect::<Vec<_>>();

    let same_type_docs = narrative_documents
        .iter()
        .filter(|document| document.meta.doc_type == request.doc_type)
        .take(max_context_records.clamp(3, 10))
        .map(|document| {
            workspace_context_refs.push(format!("narrative:{}", document.meta.slug));
            json!({
                "slug": document.meta.slug,
                "title": document.meta.title,
                "summary": summarize_markdown(&document.markdown),
            })
        })
        .collect::<Vec<_>>();

    let (runtime_indexes, project_context_refs, story_background, project_context_warning) =
        load_project_context(project_root, request, max_context_records)?;
    let source_conflicts = detect_source_conflicts(request, &runtime_indexes);
    let used_context_refs = unique_strings(
        workspace_context_refs
            .iter()
            .cloned()
            .chain(project_context_refs.iter().cloned())
            .collect(),
    );

    Ok(NarrativeContextBuildResult {
        context: json!({
            "docType": request.doc_type,
            "targetSlug": request.target_slug,
            "action": request.action,
            "userPrompt": request.user_prompt,
            "editorInstruction": request.editor_instruction,
            "selectionText": request.selected_text,
            "currentMarkdownSummary": summarize_markdown(&request.current_markdown),
            "templateHints": template_hints(&request.doc_type),
            "sameTypeDocuments": same_type_docs,
            "relatedDocuments": related_doc_records,
            "runtimeIndexes": runtime_indexes,
            "storyBackground": story_background,
            "projectContextStatus": project_context_warning,
        }),
        used_context_refs,
        workspace_context_refs: unique_strings(workspace_context_refs),
        project_context_refs,
        source_conflicts,
        project_context_warning,
    })
}

pub fn build_project_context_snapshot_seed(
    project_root: &Path,
    max_context_records: usize,
) -> Result<ProjectContextSnapshotSeed, String> {
    let request = NarrativeGenerateRequest {
        doc_type: "project_brief".to_string(),
        target_slug: "snapshot".to_string(),
        action: "create".to_string(),
        user_prompt: "build project context snapshot".to_string(),
        editor_instruction: String::new(),
        current_markdown: String::new(),
        selected_range: None,
        selected_text: String::new(),
        related_doc_slugs: Vec::new(),
        derived_target_doc_type: None,
    };
    let (runtime_indexes, project_context_refs, story_background, _) =
        load_project_context(Some(project_root), &request, max_context_records)?;
    let quest_count = runtime_indexes
        .get("quests")
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or(0);
    let dialogue_count = runtime_indexes
        .get("dialogues")
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or(0);
    let character_count = runtime_indexes
        .get("characters")
        .and_then(Value::as_array)
        .map(Vec::len)
        .unwrap_or(0);

    Ok(ProjectContextSnapshotSeed {
        summary: format!(
            "Project snapshot includes {quest_count} quests, {dialogue_count} dialogues, and {character_count} characters."
        ),
        source_refs: project_context_refs,
        runtime_indexes: serde_json::to_value(runtime_indexes)
            .map_err(|error| format!("failed to serialize runtime indexes: {error}"))?,
        story_background,
    })
}

fn load_project_context(
    project_root: Option<&Path>,
    request: &NarrativeGenerateRequest,
    max_context_records: usize,
) -> Result<(BTreeMap<String, Value>, Vec<String>, Value, String), String> {
    let Some(project_root) = project_root else {
        return Ok((
            BTreeMap::new(),
            Vec::new(),
            Value::Null,
            "未连接项目，仅使用 narrative 文稿与模板上下文。".to_string(),
        ));
    };
    if !project_root.is_dir() {
        return Ok((
            BTreeMap::new(),
            Vec::new(),
            Value::Null,
            format!(
                "项目路径不可用，已降级为纯 narrative 模式: {}",
                project_root.to_string_lossy()
            ),
        ));
    }

    let runtime_indexes = load_runtime_indexes(project_root, request, max_context_records)?;
    let mut project_context_refs = runtime_indexes
        .keys()
        .map(|category| format!("runtime:{category}"))
        .collect::<Vec<_>>();

    let story_background = load_story_background(project_root)?;
    if !story_background.is_null() {
        project_context_refs.push("runtime:story_chapters".to_string());
    }

    Ok((
        runtime_indexes,
        unique_strings(project_context_refs),
        story_background,
        format!("已连接项目上下文: {}", project_root.to_string_lossy().replace('\\', "/")),
    ))
}

fn load_runtime_indexes(
    project_root: &Path,
    request: &NarrativeGenerateRequest,
    max_context_records: usize,
) -> Result<BTreeMap<String, Value>, String> {
    let mut result = BTreeMap::new();
    let intent = format!(
        "{} {} {}",
        request.user_prompt, request.editor_instruction, request.current_markdown
    )
    .to_lowercase();

    for category in RUNTIME_CATEGORIES {
        let records = load_runtime_category(project_root, category)?;
        let mut values = records.into_iter().collect::<Vec<_>>();
        values.sort_by(|left, right| {
            score_runtime_record(&left.0, &left.1, &intent)
                .cmp(&score_runtime_record(&right.0, &right.1, &intent))
                .reverse()
                .then_with(|| left.0.cmp(&right.0))
        });
        let entries = values
            .into_iter()
            .take(max_context_records.clamp(2, 6))
            .map(|(id, value)| {
                json!({
                    "id": id,
                    "summary": runtime_summary(category, &value),
                })
            })
            .collect::<Vec<_>>();
        result.insert((*category).to_string(), json!(entries));
    }

    Ok(result)
}

fn load_runtime_category(
    project_root: &Path,
    category: &str,
) -> Result<BTreeMap<String, Value>, String> {
    let mut result = BTreeMap::new();
    match category {
        "quests" => load_directory_records(&project_root.join("data").join("quests"), "quest_id", &mut result)?,
        "dialogues" => {
            load_directory_records(&project_root.join("data").join("dialogues"), "dialog_id", &mut result)?
        }
        "characters" => {
            load_directory_records(&project_root.join("data").join("characters"), "id", &mut result)?
        }
        "map_locations" => {
            load_overworld_location_records(
                &project_root.join("data").join("overworld"),
                &mut result,
            )?
        }
        "structures" => {
            load_object_file(&project_root.join("data").join("json").join("structures.json"), &mut result)?
        }
        _ => {}
    }
    Ok(result)
}

fn load_directory_records(
    dir: &Path,
    id_field: &str,
    target: &mut BTreeMap<String, Value>,
) -> Result<(), String> {
    if !dir.exists() {
        return Ok(());
    }
    let mut entries = fs::read_dir(dir)
        .map_err(|error| format!("failed to read {}: {error}", dir.display()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("failed to enumerate {}: {error}", dir.display()))?;
    entries.sort_by_key(|entry| entry.file_name());
    for entry in entries {
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("json") {
            continue;
        }
        let raw = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
        let parsed: Value = serde_json::from_str(&raw)
            .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
        let id = parsed
            .get(id_field)
            .and_then(value_to_id)
            .unwrap_or_else(|| {
                path.file_stem()
                    .and_then(|value| value.to_str())
                    .unwrap_or_default()
                    .to_string()
            });
        if !id.is_empty() {
            target.insert(id, parsed);
        }
    }
    Ok(())
}

fn load_object_file(path: &Path, target: &mut BTreeMap<String, Value>) -> Result<(), String> {
    if !path.exists() {
        return Ok(());
    }
    let raw = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    let parsed: Value = serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
    if let Value::Object(map) = parsed {
        for (key, value) in map {
            target.insert(key, value);
        }
    }
    Ok(())
}

fn load_overworld_location_records(
    dir: &Path,
    target: &mut BTreeMap<String, Value>,
) -> Result<(), String> {
    if !dir.exists() {
        return Ok(());
    }

    let mut entries = fs::read_dir(dir)
        .map_err(|error| format!("failed to read {}: {error}", dir.display()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("failed to enumerate {}: {error}", dir.display()))?;
    entries.sort_by_key(|entry| entry.file_name());

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
                target.insert(location_id.to_string(), location.clone());
            }
        }
    }

    Ok(())
}

fn load_story_background(project_root: &Path) -> Result<Value, String> {
    let path = project_root.join("data").join("json").join("story_chapters.json");
    if !path.exists() {
        return Ok(Value::Null);
    }
    let raw = fs::read_to_string(&path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    serde_json::from_str(&raw).map_err(|error| format!("failed to parse {}: {error}", path.display()))
}

fn detect_source_conflicts(
    request: &NarrativeGenerateRequest,
    runtime_indexes: &BTreeMap<String, Value>,
) -> Vec<String> {
    let mut conflicts = Vec::new();
    let body = request.current_markdown.to_lowercase();
    for (category, entries) in runtime_indexes {
        for entry in entries.as_array().into_iter().flatten() {
            let id = entry.get("id").and_then(Value::as_str).unwrap_or_default();
            if !id.is_empty() && body.contains(id) && request.related_doc_slugs.contains(&id.to_string()) {
                conflicts.push(format!("{category}:{id}"));
            }
        }
    }
    unique_strings(conflicts)
}

fn template_hints(doc_type: &str) -> Vec<String> {
    match doc_type {
        "character_card" => vec![
            "聚焦角色动机、秘密、关系与成长轨迹".to_string(),
            "写法应便于后续拆成对白、事件和个人任务".to_string(),
        ],
        "chapter_outline" => vec![
            "明确章节目标、关键事件、分支点和角色推进".to_string(),
            "为后续任务拆解留下清晰的事件链".to_string(),
        ],
        "branch_sheet" => vec![
            "把每个选择的即时结果、中期影响和长期回收说清楚".to_string(),
            "避免只写概念，不写触发条件".to_string(),
        ],
        _ => vec!["保持文稿可读、可审稿，并保留结构化落地提示".to_string()],
    }
}

fn summarize_markdown(markdown: &str) -> String {
    let mut lines = markdown
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .take(6)
        .collect::<Vec<_>>();
    if lines.is_empty() {
        return "(empty)".to_string();
    }
    if lines.len() > 3 {
        lines.truncate(3);
    }
    lines.join(" / ")
}

fn runtime_summary(category: &str, value: &Value) -> String {
    let object = value.as_object();
    match category {
        "quests" => format!(
            "{} | {}",
            object.and_then(|map| map.get("title")).and_then(Value::as_str).unwrap_or("quest"),
            object
                .and_then(|map| map.get("description"))
                .and_then(Value::as_str)
                .unwrap_or_default()
        ),
        "dialogues" => format!(
            "{} | {} nodes",
            object.and_then(|map| map.get("dialog_id")).and_then(Value::as_str).unwrap_or("dialog"),
            object
                .and_then(|map| map.get("nodes"))
                .and_then(Value::as_array)
                .map(Vec::len)
                .unwrap_or(0)
        ),
        "characters" => format!(
            "{} | {}",
            object.and_then(|map| map.get("name")).and_then(Value::as_str).unwrap_or("character"),
            object.and_then(|map| map.get("description")).and_then(Value::as_str).unwrap_or_default()
        ),
        _ => object
            .and_then(|map| map.get("title").or_else(|| map.get("name")))
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_string(),
    }
}

fn score_runtime_record(id: &str, value: &Value, intent: &str) -> i32 {
    let search = format!("{id} {}", value).to_lowercase();
    intent
        .split(|character: char| !character.is_alphanumeric() && !matches!(character, '_' | '-'))
        .filter(|token| token.len() >= 3)
        .fold(0, |total, token| {
            if search.contains(token) {
                total + 5
            } else {
                total
            }
        })
}

fn value_to_id(value: &Value) -> Option<String> {
    match value {
        Value::String(text) => Some(text.clone()),
        Value::Number(number) => Some(number.to_string()),
        _ => None,
    }
}

fn unique_strings(values: Vec<String>) -> Vec<String> {
    let mut ordered = BTreeMap::new();
    for value in values {
        if value.trim().is_empty() {
            continue;
        }
        ordered.entry(value.clone()).or_insert(value);
    }
    ordered.into_values().collect()
}
