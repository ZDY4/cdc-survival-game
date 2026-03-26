use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

use crate::narrative_templates::{
    default_markdown, default_title, doc_type_directory, is_known_doc_type,
    narrative_doc_type_entries, slugify, DEFAULT_NARRATIVE_STATUS,
};
use crate::{to_forward_slashes, EditorBootstrap, MigrationStage, ValidationIssue};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeDocumentMeta {
    pub doc_type: String,
    pub slug: String,
    pub title: String,
    pub status: String,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub related_docs: Vec<String>,
    #[serde(default)]
    pub source_refs: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeDocumentPayload {
    pub document_key: String,
    pub original_slug: String,
    pub file_name: String,
    pub relative_path: String,
    pub meta: NarrativeDocumentMeta,
    pub markdown: String,
    pub validation: Vec<ValidationIssue>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeWorkspacePayload {
    pub bootstrap: EditorBootstrap,
    pub data_directory: String,
    pub document_count: usize,
    pub doc_types: Vec<crate::narrative_templates::NarrativeDocTypeEntry>,
    pub documents: Vec<NarrativeDocumentPayload>,
    pub workspace_root: String,
    pub workspace_name: String,
    pub connected_project_root: Option<String>,
    pub project_context_status: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateNarrativeDocumentInput {
    pub doc_type: String,
    pub slug: Option<String>,
    pub title: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveNarrativeDocumentInput {
    pub original_slug: Option<String>,
    pub document: NarrativeDocumentPayload,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SaveNarrativeDocumentResult {
    pub saved_slug: String,
    pub deleted_slug: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DeleteNarrativeDocumentResult {
    pub deleted_slug: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeDocumentSummary {
    pub slug: String,
    pub title: String,
    pub heading_count: usize,
    pub headings: Vec<String>,
    pub excerpt: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PrepareStructuringBundleInput {
    pub document_slugs: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StructuringBundlePayload {
    pub document_slugs: Vec<String>,
    pub combined_markdown: String,
    pub summary: String,
    pub suggested_targets: Vec<String>,
    pub source_refs: Vec<String>,
    pub workspace_root: String,
    pub connected_project_root: Option<String>,
    pub generated_at: String,
    pub export_path: Option<String>,
}

#[tauri::command]
pub fn load_narrative_workspace(
    workspace_root: String,
    project_root: Option<String>,
) -> Result<NarrativeWorkspacePayload, String> {
    let workspace_root_path = resolve_workspace_root(&workspace_root)?;
    ensure_workspace_layout(&workspace_root_path)?;
    let connected_project_root = normalize_project_root_input(project_root.as_deref())?;
    let documents = load_narrative_documents(&workspace_root_path)?;

    Ok(NarrativeWorkspacePayload {
        bootstrap: narrative_bootstrap(&workspace_root_path, connected_project_root.as_deref()),
        data_directory: to_forward_slashes(narrative_root_dir(&workspace_root_path)),
        document_count: documents.len(),
        doc_types: narrative_doc_type_entries(),
        documents,
        workspace_root: to_forward_slashes(&workspace_root_path),
        workspace_name: workspace_name(&workspace_root_path),
        connected_project_root: connected_project_root.clone(),
        project_context_status: describe_project_context(connected_project_root.as_deref())?,
    })
}

#[tauri::command]
pub fn load_narrative_document(
    workspace_root: String,
    slug: String,
) -> Result<NarrativeDocumentPayload, String> {
    let workspace_root_path = resolve_workspace_root(&workspace_root)?;
    find_document_by_slug(&workspace_root_path, &slug)?
        .ok_or_else(|| format!("未找到文稿: {slug}"))
}

#[tauri::command]
pub fn create_narrative_document(
    workspace_root: String,
    input: CreateNarrativeDocumentInput,
) -> Result<NarrativeDocumentPayload, String> {
    let workspace_root_path = resolve_workspace_root(&workspace_root)?;
    ensure_workspace_layout(&workspace_root_path)?;

    let doc_type = normalize_doc_type(&input.doc_type)?;
    let title = input
        .title
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .unwrap_or_else(|| default_title(&doc_type));
    let slug = input
        .slug
        .as_deref()
        .map(slugify)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| unique_slug(&workspace_root_path, &doc_type, &title).unwrap_or_else(|_| doc_type.clone()));
    let meta = NarrativeDocumentMeta {
        doc_type: doc_type.clone(),
        slug: slug.clone(),
        title: title.clone(),
        status: DEFAULT_NARRATIVE_STATUS.to_string(),
        tags: Vec::new(),
        related_docs: Vec::new(),
        source_refs: Vec::new(),
    };
    let markdown = default_markdown(&doc_type, &title);

    build_document_payload_from_parts(&workspace_root_path, meta, markdown, None)
}

#[tauri::command]
pub fn save_narrative_document(
    workspace_root: String,
    input: SaveNarrativeDocumentInput,
) -> Result<SaveNarrativeDocumentResult, String> {
    let workspace_root_path = resolve_workspace_root(&workspace_root)?;
    ensure_workspace_layout(&workspace_root_path)?;

    let mut document = input.document;
    document.meta.doc_type = normalize_doc_type(&document.meta.doc_type)?;
    document.meta.slug = normalize_slug(&document.meta.slug, &document.meta.title)?;
    if document.meta.title.trim().is_empty() {
        document.meta.title = default_title(&document.meta.doc_type);
    }
    if document.meta.status.trim().is_empty() {
        document.meta.status = DEFAULT_NARRATIVE_STATUS.to_string();
    }

    let validation = validate_document_meta(&document.meta);
    if validation.iter().any(|issue| issue.severity == "error") {
        return Err(format!("文稿 {} 存在校验错误，无法保存", document.meta.slug));
    }

    let path = narrative_file_path(&workspace_root_path, &document.meta.doc_type, &document.meta.slug)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("failed to create {}: {error}", parent.display()))?;
    }

    let serialized = serialize_document(&document.meta, &document.markdown);
    fs::write(&path, serialized)
        .map_err(|error| format!("failed to write {}: {error}", path.display()))?;

    let mut deleted_slug = None;
    if let Some(original_slug) = input.original_slug {
        let trimmed = original_slug.trim();
        if !trimmed.is_empty() && trimmed != document.meta.slug {
            if let Some(old_document) = find_document_by_slug(&workspace_root_path, trimmed)? {
                let old_path = narrative_file_path(
                    &workspace_root_path,
                    &old_document.meta.doc_type,
                    &old_document.meta.slug,
                )?;
                if old_path.exists() {
                    fs::remove_file(&old_path).map_err(|error| {
                        format!("failed to delete renamed markdown {}: {error}", old_path.display())
                    })?;
                }
                deleted_slug = Some(trimmed.to_string());
            }
        }
    }

    Ok(SaveNarrativeDocumentResult {
        saved_slug: document.meta.slug,
        deleted_slug,
    })
}

#[tauri::command]
pub fn delete_narrative_document(
    workspace_root: String,
    slug: String,
) -> Result<DeleteNarrativeDocumentResult, String> {
    let workspace_root_path = resolve_workspace_root(&workspace_root)?;
    if let Some(document) = find_document_by_slug(&workspace_root_path, &slug)? {
        let path = narrative_file_path(
            &workspace_root_path,
            &document.meta.doc_type,
            &document.meta.slug,
        )?;
        if path.exists() {
            fs::remove_file(&path)
                .map_err(|error| format!("failed to delete {}: {error}", path.display()))?;
        }
    }
    Ok(DeleteNarrativeDocumentResult { deleted_slug: slug })
}

#[tauri::command]
pub fn summarize_narrative_document(
    workspace_root: String,
    slug: String,
    current_markdown: Option<String>,
) -> Result<NarrativeDocumentSummary, String> {
    let workspace_root_path = resolve_workspace_root(&workspace_root)?;
    let document = find_document_by_slug(&workspace_root_path, &slug)?
        .ok_or_else(|| format!("未找到文稿: {slug}"))?;
    let markdown = current_markdown.unwrap_or(document.markdown);
    Ok(summarize_document(&document.meta.slug, &document.meta.title, &markdown))
}

#[tauri::command]
pub fn prepare_structuring_bundle(
    workspace_root: String,
    project_root: Option<String>,
    input: PrepareStructuringBundleInput,
) -> Result<StructuringBundlePayload, String> {
    let workspace_root_path = resolve_workspace_root(&workspace_root)?;
    ensure_workspace_layout(&workspace_root_path)?;
    let connected_project_root = normalize_project_root_input(project_root.as_deref())?;

    let mut collected = Vec::new();
    for slug in &input.document_slugs {
        if let Some(document) = find_document_by_slug(&workspace_root_path, slug)? {
            collected.push(document);
        }
    }
    if collected.is_empty() {
        return Err("请先选择至少一份 narrative 文稿".to_string());
    }

    let combined_markdown = collected
        .iter()
        .map(|document| {
            format!(
                "# [{}] {}\n\n{}",
                document.meta.doc_type, document.meta.title, document.markdown
            )
        })
        .collect::<Vec<_>>()
        .join("\n\n---\n\n");
    let source_refs = unique_strings(
        collected
            .iter()
            .flat_map(|document| document.meta.source_refs.iter().cloned())
            .collect(),
    );
    let suggested_targets = unique_strings(
        collected
            .iter()
            .flat_map(|document| suggested_targets_for_doc_type(&document.meta.doc_type))
            .map(ToString::to_string)
            .collect(),
    );
    let generated_at = current_timestamp();
    let export_path = write_structuring_bundle_export(
        &workspace_root_path,
        &generated_at,
        &collected,
        &combined_markdown,
        &suggested_targets,
        &source_refs,
        connected_project_root.clone(),
    )?;

    Ok(StructuringBundlePayload {
        document_slugs: collected.iter().map(|document| document.meta.slug.clone()).collect(),
        summary: format!("已打包 {} 份 narrative 文稿，供第二阶段结构化拆解使用。", collected.len()),
        combined_markdown,
        suggested_targets,
        source_refs,
        workspace_root: to_forward_slashes(&workspace_root_path),
        connected_project_root,
        generated_at,
        export_path: Some(to_forward_slashes(export_path)),
    })
}

pub fn load_narrative_documents(
    workspace_root: &Path,
) -> Result<Vec<NarrativeDocumentPayload>, String> {
    let root = narrative_root_dir(workspace_root);
    if !root.exists() {
        return Ok(Vec::new());
    }

    let mut files = Vec::new();
    collect_markdown_files(&root, &mut files)?;

    let mut documents = Vec::new();
    for path in files {
        let raw = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
        let (meta, markdown) = parse_document(&path, &raw)?;
        documents.push(build_document_payload_from_parts(
            workspace_root,
            meta,
            markdown,
            Some(&path),
        )?);
    }

    documents.sort_by(|left, right| left.meta.slug.cmp(&right.meta.slug));
    Ok(documents)
}

pub fn resolve_workspace_root(workspace_root: &str) -> Result<PathBuf, String> {
    let candidate = resolve_input_path(workspace_root)?;
    fs::create_dir_all(&candidate)
        .map_err(|error| format!("failed to create workspace root {}: {error}", candidate.display()))?;
    candidate
        .canonicalize()
        .map_err(|error| format!("failed to resolve workspace root {}: {error}", candidate.display()))
}

pub fn normalize_project_root_input(project_root: Option<&str>) -> Result<Option<String>, String> {
    let trimmed = project_root.unwrap_or_default().trim();
    if trimmed.is_empty() {
        return Ok(None);
    }
    Ok(Some(to_forward_slashes(resolve_input_path(trimmed)?)))
}

pub fn resolve_connected_project_root(project_root: Option<&str>) -> Result<Option<PathBuf>, String> {
    let trimmed = project_root.unwrap_or_default().trim();
    if trimmed.is_empty() {
        return Ok(None);
    }

    let candidate = resolve_input_path(trimmed)?;
    if !candidate.is_dir() {
        return Ok(None);
    }

    candidate
        .canonicalize()
        .map(Some)
        .map_err(|error| format!("failed to resolve project root {}: {error}", candidate.display()))
}

fn find_document_by_slug(
    workspace_root: &Path,
    slug: &str,
) -> Result<Option<NarrativeDocumentPayload>, String> {
    let target = slug.trim();
    if target.is_empty() {
        return Ok(None);
    }
    Ok(load_narrative_documents(workspace_root)?
        .into_iter()
        .find(|document| document.meta.slug == target))
}

fn narrative_root_dir(workspace_root: &Path) -> PathBuf {
    workspace_root.join("narrative")
}

fn exports_root_dir(workspace_root: &Path) -> PathBuf {
    workspace_root.join("exports")
}

fn narrative_file_path(workspace_root: &Path, doc_type: &str, slug: &str) -> Result<PathBuf, String> {
    Ok(narrative_root_dir(workspace_root)
        .join(doc_type_directory(doc_type))
        .join(format!("{slug}.md")))
}

fn build_document_payload_from_parts(
    workspace_root: &Path,
    meta: NarrativeDocumentMeta,
    markdown: String,
    source_path: Option<&Path>,
) -> Result<NarrativeDocumentPayload, String> {
    let path = if let Some(path) = source_path {
        path.to_path_buf()
    } else {
        narrative_file_path(workspace_root, &meta.doc_type, &meta.slug)?
    };
    let file_name = path
        .file_name()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_string();
    let relative_path = relative_to_workspace(workspace_root, &path)?;
    let validation = validate_document_meta(&meta);

    Ok(NarrativeDocumentPayload {
        document_key: meta.slug.clone(),
        original_slug: meta.slug.clone(),
        file_name,
        relative_path,
        meta,
        markdown,
        validation,
    })
}

fn validate_document_meta(meta: &NarrativeDocumentMeta) -> Vec<ValidationIssue> {
    let mut issues = Vec::new();
    if !is_known_doc_type(&meta.doc_type) {
        issues.push(crate::document_error(
            "docType",
            format!("未知文稿类型: {}", meta.doc_type),
        ));
    }
    if meta.slug.trim().is_empty() {
        issues.push(crate::document_error("slug", "slug 不能为空"));
    }
    if meta.title.trim().is_empty() {
        issues.push(crate::document_error("title", "title 不能为空"));
    }
    issues
}

fn normalize_doc_type(doc_type: &str) -> Result<String, String> {
    let normalized = doc_type.trim().to_lowercase();
    if !is_known_doc_type(&normalized) {
        return Err(format!("未知 narrative 文稿类型: {doc_type}"));
    }
    Ok(normalized)
}

fn normalize_slug(slug: &str, title: &str) -> Result<String, String> {
    let normalized = slugify(slug);
    if !normalized.is_empty() {
        return Ok(normalized);
    }
    let fallback = slugify(title);
    if fallback.is_empty() {
        return Err("slug 不能为空".to_string());
    }
    Ok(fallback)
}

fn unique_slug(workspace_root: &Path, doc_type: &str, title: &str) -> Result<String, String> {
    let base = slugify(title);
    let prefix = if base.is_empty() {
        doc_type.to_string()
    } else {
        base
    };
    let root = narrative_root_dir(workspace_root);
    let mut candidate = prefix.clone();
    let mut index = 1usize;
    loop {
        let path = root
            .join(doc_type_directory(doc_type))
            .join(format!("{candidate}.md"));
        if !path.exists() {
            return Ok(candidate);
        }
        index += 1;
        candidate = format!("{prefix}-{index}");
    }
}

fn collect_markdown_files(root: &Path, files: &mut Vec<PathBuf>) -> Result<(), String> {
    let mut entries = fs::read_dir(root)
        .map_err(|error| format!("failed to read {}: {error}", root.display()))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|error| format!("failed to enumerate {}: {error}", root.display()))?;
    entries.sort_by_key(|entry| entry.file_name());

    for entry in entries {
        let path = entry.path();
        if path.is_dir() {
            collect_markdown_files(&path, files)?;
            continue;
        }
        if path.extension().and_then(|value| value.to_str()) == Some("md") {
            if path
                .file_name()
                .and_then(|value| value.to_str())
                .unwrap_or_default()
                .starts_with('.')
            {
                continue;
            }
            files.push(path);
        }
    }
    Ok(())
}

fn parse_document(path: &Path, raw: &str) -> Result<(NarrativeDocumentMeta, String), String> {
    let (meta_map, markdown) = split_frontmatter(raw)?;
    let inferred_doc_type = path
        .parent()
        .and_then(|value| value.file_name())
        .and_then(|value| value.to_str())
        .and_then(doc_type_from_directory)
        .unwrap_or("scene_draft");
    let inferred_slug = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or_default()
        .to_string();

    let meta = NarrativeDocumentMeta {
        doc_type: meta_map
            .get("doc_type")
            .cloned()
            .unwrap_or_else(|| inferred_doc_type.to_string()),
        slug: meta_map
            .get("slug")
            .cloned()
            .unwrap_or_else(|| inferred_slug.clone()),
        title: meta_map
            .get("title")
            .cloned()
            .unwrap_or_else(|| default_title(inferred_doc_type)),
        status: meta_map
            .get("status")
            .cloned()
            .unwrap_or_else(|| DEFAULT_NARRATIVE_STATUS.to_string()),
        tags: parse_list(meta_map.get("tags")),
        related_docs: parse_list(meta_map.get("related_docs")),
        source_refs: parse_list(meta_map.get("source_refs")),
    };

    Ok((meta, markdown))
}

fn split_frontmatter(raw: &str) -> Result<(BTreeMap<String, String>, String), String> {
    let normalized = raw.replace("\r\n", "\n");
    if !normalized.starts_with("---\n") {
        return Ok((BTreeMap::new(), normalized.trim_start().to_string()));
    }
    let rest = &normalized[4..];
    let Some(end_index) = rest.find("\n---\n") else {
        return Err("frontmatter 未正确闭合".to_string());
    };
    let frontmatter = &rest[..end_index];
    let markdown = rest[end_index + 5..].trim_start_matches('\n').to_string();
    let mut meta = BTreeMap::new();
    for line in frontmatter.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let Some((key, value)) = trimmed.split_once(':') else {
            continue;
        };
        meta.insert(key.trim().to_string(), value.trim().to_string());
    }
    Ok((meta, markdown))
}

fn serialize_document(meta: &NarrativeDocumentMeta, markdown: &str) -> String {
    let mut output = String::from("---\n");
    output.push_str(&format!("doc_type: {}\n", meta.doc_type));
    output.push_str(&format!("slug: {}\n", meta.slug));
    output.push_str(&format!("title: {}\n", meta.title.trim()));
    output.push_str(&format!("status: {}\n", meta.status.trim()));
    output.push_str(&format!("tags: {}\n", format_list(&meta.tags)));
    output.push_str(&format!("related_docs: {}\n", format_list(&meta.related_docs)));
    output.push_str(&format!("source_refs: {}\n", format_list(&meta.source_refs)));
    output.push_str("---\n\n");
    output.push_str(markdown.trim_end());
    output.push('\n');
    output
}

fn parse_list(raw: Option<&String>) -> Vec<String> {
    let Some(raw) = raw else {
        return Vec::new();
    };
    let trimmed = raw.trim();
    if !(trimmed.starts_with('[') && trimmed.ends_with(']')) {
        return Vec::new();
    }
    trimmed[1..trimmed.len() - 1]
        .split(',')
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.trim_matches('"').trim_matches('\'').to_string())
        .collect()
}

fn format_list(values: &[String]) -> String {
    format!("[{}]", values.join(", "))
}

fn doc_type_from_directory(directory: &str) -> Option<&'static str> {
    match directory {
        "project" => Some("project_brief"),
        "world" => Some("world_bible"),
        "characters" => Some("character_card"),
        "arcs" => Some("arc_outline"),
        "chapters" => Some("chapter_outline"),
        "branches" => Some("branch_sheet"),
        "scenes" => Some("scene_draft"),
        _ => None,
    }
}

fn summarize_document(slug: &str, title: &str, markdown: &str) -> NarrativeDocumentSummary {
    let headings = markdown
        .lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            trimmed
                .strip_prefix('#')
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToString::to_string)
        })
        .collect::<Vec<_>>();
    let excerpt = markdown
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .take(3)
        .collect::<Vec<_>>()
        .join(" ");

    NarrativeDocumentSummary {
        slug: slug.to_string(),
        title: title.to_string(),
        heading_count: headings.len(),
        headings,
        excerpt,
    }
}

fn suggested_targets_for_doc_type(doc_type: &str) -> Vec<&'static str> {
    match doc_type {
        "character_card" | "dialogue_tone_sheet" => vec!["character", "dialogue"],
        "chapter_outline" | "arc_outline" | "branch_sheet" | "scene_draft" => {
            vec!["quest", "dialogue", "branch_condition"]
        }
        "world_bible" | "faction_note" | "project_brief" => vec!["quest", "dialogue", "clue"],
        _ => vec!["quest", "dialogue"],
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

fn ensure_workspace_layout(workspace_root: &Path) -> Result<(), String> {
    fs::create_dir_all(workspace_root)
        .map_err(|error| format!("failed to create workspace root {}: {error}", workspace_root.display()))?;
    fs::create_dir_all(narrative_root_dir(workspace_root))
        .map_err(|error| format!("failed to create narrative dir: {error}"))?;
    fs::create_dir_all(exports_root_dir(workspace_root))
        .map_err(|error| format!("failed to create exports dir: {error}"))?;

    let directories = narrative_doc_type_entries()
        .into_iter()
        .map(|entry| entry.directory)
        .collect::<BTreeSet<_>>();
    for directory in directories {
        let path = narrative_root_dir(workspace_root).join(directory);
        fs::create_dir_all(&path)
            .map_err(|error| format!("failed to create {}: {error}", path.display()))?;
    }
    Ok(())
}

fn resolve_input_path(raw: &str) -> Result<PathBuf, String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err("路径不能为空".to_string());
    }

    let candidate = PathBuf::from(trimmed);
    if candidate.is_absolute() {
        return Ok(candidate);
    }

    std::env::current_dir()
        .map(|current| current.join(candidate))
        .map_err(|error| format!("failed to resolve current directory: {error}"))
}

fn relative_to_workspace(workspace_root: &Path, path: &Path) -> Result<String, String> {
    let relative = path
        .strip_prefix(workspace_root)
        .map_err(|error| format!("failed to relativize {}: {error}", path.display()))?;
    Ok(to_forward_slashes(relative))
}

fn workspace_name(workspace_root: &Path) -> String {
    workspace_root
        .file_name()
        .and_then(|value| value.to_str())
        .filter(|value| !value.trim().is_empty())
        .map(ToString::to_string)
        .unwrap_or_else(|| to_forward_slashes(workspace_root))
}

fn describe_project_context(project_root: Option<&str>) -> Result<String, String> {
    let Some(raw_root) = project_root else {
        return Ok("未连接项目，将只使用 narrative 文稿与模板上下文。".to_string());
    };

    let resolved = resolve_input_path(raw_root)?;
    if resolved.is_dir() {
        Ok(format!("已连接项目上下文: {}", to_forward_slashes(resolved)))
    } else {
        Ok(format!(
            "项目路径不可用，已降级为纯 narrative 模式: {}",
            to_forward_slashes(resolved)
        ))
    }
}

fn narrative_bootstrap(workspace_root: &Path, project_root: Option<&str>) -> EditorBootstrap {
    EditorBootstrap {
        app_name: "CDC Narrative Lab",
        workspace_root: to_forward_slashes(workspace_root),
        shared_rust_path: project_root.unwrap_or("Not connected").to_string(),
        active_stage: "Phase 1: Narrative Authoring",
        stages: vec![
            MigrationStage {
                id: "phase-1",
                title: "Phase 1: Narrative Authoring",
                description:
                    "Use markdown-first planning docs to explore worldbuilding, arcs, scenes, and branches.",
            },
            MigrationStage {
                id: "phase-2",
                title: "Phase 2: Structuring Handoff",
                description:
                    "Prepare curated bundles that can later be decomposed into quests, dialogues, and character data.",
            },
            MigrationStage {
                id: "phase-3",
                title: "Phase 3: Project Integration",
                description:
                    "Optionally connect a game project to enrich AI context with story chapters and runtime constraints.",
            },
        ],
        editor_domains: vec![
            "Narrative planning and review",
            "Character, arc, chapter, and scene drafting",
            "Branch ideation and tone sheets",
            "Structuring bundle export for stage-two editors",
        ],
    }
}

fn current_timestamp() -> String {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs().to_string())
        .unwrap_or_else(|_| "0".to_string())
}

fn write_structuring_bundle_export(
    workspace_root: &Path,
    generated_at: &str,
    documents: &[NarrativeDocumentPayload],
    combined_markdown: &str,
    suggested_targets: &[String],
    source_refs: &[String],
    connected_project_root: Option<String>,
) -> Result<PathBuf, String> {
    let export_dir = exports_root_dir(workspace_root);
    fs::create_dir_all(&export_dir)
        .map_err(|error| format!("failed to create {}: {error}", export_dir.display()))?;

    let export_path = export_dir.join(format!("structuring_bundle_{generated_at}.json"));
    let payload = serde_json::json!({
        "workspaceRoot": to_forward_slashes(workspace_root),
        "connectedProjectRoot": connected_project_root,
        "generatedAt": generated_at,
        "documentSlugs": documents.iter().map(|document| document.meta.slug.clone()).collect::<Vec<_>>(),
        "documents": documents.iter().map(|document| serde_json::json!({
            "docType": document.meta.doc_type,
            "slug": document.meta.slug,
            "title": document.meta.title,
            "relativePath": document.relative_path,
            "sourceRefs": document.meta.source_refs,
            "markdown": document.markdown,
        })).collect::<Vec<_>>(),
        "combinedMarkdown": combined_markdown,
        "suggestedTargets": suggested_targets,
        "sourceRefs": source_refs,
    });
    let raw = serde_json::to_string_pretty(&payload)
        .map_err(|error| format!("failed to serialize structuring bundle: {error}"))?;
    fs::write(&export_path, raw)
        .map_err(|error| format!("failed to write {}: {error}", export_path.display()))?;
    Ok(export_path)
}

#[cfg(test)]
mod tests {
    use super::{parse_document, serialize_document, split_frontmatter, NarrativeDocumentMeta};
    use std::path::PathBuf;

    #[test]
    fn split_frontmatter_parses_meta_and_markdown() {
        let raw = "---\ndoc_type: chapter_outline\nslug: test\nrelated_docs: [a, b]\n---\n\n# Title\nBody";
        let (meta, markdown) = split_frontmatter(raw).expect("frontmatter should parse");
        assert_eq!(meta.get("doc_type").map(String::as_str), Some("chapter_outline"));
        assert_eq!(meta.get("slug").map(String::as_str), Some("test"));
        assert_eq!(markdown, "# Title\nBody");
    }

    #[test]
    fn parse_document_infers_missing_fields() {
        let path = PathBuf::from("narrative/chapters/chapter_01.md");
        let (meta, markdown) = parse_document(&path, "# Heading\nText").expect("document should parse");
        assert_eq!(meta.doc_type, "chapter_outline");
        assert_eq!(meta.slug, "chapter_01");
        assert!(markdown.contains("Heading"));
    }

    #[test]
    fn serialize_document_writes_frontmatter() {
        let raw = serialize_document(
            &NarrativeDocumentMeta {
                doc_type: "scene_draft".to_string(),
                slug: "test-scene".to_string(),
                title: "Test Scene".to_string(),
                status: "draft".to_string(),
                tags: vec!["dark".to_string()],
                related_docs: vec!["chapter-a".to_string()],
                source_refs: vec!["story_chapters".to_string()],
            },
            "# Test\n\nBody",
        );
        assert!(raw.starts_with("---\n"));
        assert!(raw.contains("doc_type: scene_draft"));
        assert!(raw.contains("related_docs: [chapter-a]"));
    }
}
