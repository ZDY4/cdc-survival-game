use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::narrative_templates::doc_type_label;
use crate::narrative_workspace::{
    create_narrative_document, load_narrative_documents, resolve_workspace_root,
    save_narrative_document, CreateNarrativeDocumentInput, NarrativeDocumentPayload,
    NarrativeDocumentSummary, SaveNarrativeDocumentInput,
};

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ExecuteNarrativeAgentActionInput {
    pub request_id: String,
    pub action_type: String,
    #[serde(default)]
    pub payload: Value,
    #[serde(default)]
    pub current_document: Option<NarrativeDocumentPayload>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeAgentActionExecutionResult {
    pub request_id: String,
    pub action_type: String,
    pub status: String,
    pub summary: String,
    pub document: Option<NarrativeDocumentPayload>,
    pub document_summaries: Vec<NarrativeDocumentSummary>,
    pub opened_slug: Option<String>,
}

#[tauri::command]
pub fn execute_narrative_agent_action(
    workspace_root: String,
    input: ExecuteNarrativeAgentActionInput,
) -> Result<NarrativeAgentActionExecutionResult, String> {
    let action_type = input.action_type.trim();
    match action_type {
        "read_active_document" => execute_read_active_document(input),
        "read_related_documents" => execute_read_related_documents(&workspace_root, input),
        "create_derived_document" => execute_create_derived_document(&workspace_root, input),
        "save_active_document" => execute_save_active_document(&workspace_root, input),
        "open_document" => execute_open_document(&workspace_root, input),
        "list_workspace_documents" => execute_list_workspace_documents(&workspace_root, input),
        "update_related_documents" => execute_update_related_documents(&workspace_root, input),
        "rename_active_document" => execute_rename_active_document(&workspace_root, input),
        "set_document_status" => execute_set_document_status(&workspace_root, input),
        "split_plan_into_documents" => execute_split_plan_into_documents(&workspace_root, input),
        "archive_document" => execute_archive_document(&workspace_root, input),
        unsupported => Err(format!("Narrative Lab agent action is not supported by backend: {unsupported}")),
    }
}

fn execute_read_active_document(
    input: ExecuteNarrativeAgentActionInput,
) -> Result<NarrativeAgentActionExecutionResult, String> {
    let Some(document) = input.current_document else {
        return Err("read_active_document 需要 currentDocument".to_string());
    };

    Ok(NarrativeAgentActionExecutionResult {
        request_id: input.request_id,
        action_type: input.action_type,
        status: "completed".to_string(),
        summary: format!("已读取当前文稿《{}》。", document.meta.title),
        document: Some(document),
        document_summaries: Vec::new(),
        opened_slug: None,
    })
}

fn execute_read_related_documents(
    workspace_root: &str,
    input: ExecuteNarrativeAgentActionInput,
) -> Result<NarrativeAgentActionExecutionResult, String> {
    let workspace_root_path = resolve_workspace_root(workspace_root)?;
    let documents = load_narrative_documents(&workspace_root_path)?;
    let requested_slugs = read_slug_list(
        input.payload.get("documentSlugs").or_else(|| input.payload.get("document_slugs")),
    );
    let related_slugs = if requested_slugs.is_empty() {
        input.current_document
            .as_ref()
            .map(|document| document.meta.related_docs.clone())
            .unwrap_or_default()
    } else {
        requested_slugs
    };

    let summaries = documents
        .into_iter()
        .filter(|document| related_slugs.iter().any(|slug| slug == &document.meta.slug))
        .map(|document| summarize_payload(&document))
        .collect::<Vec<_>>();

    Ok(NarrativeAgentActionExecutionResult {
        request_id: input.request_id,
        action_type: input.action_type,
        status: "completed".to_string(),
        summary: if summaries.is_empty() {
            "未找到可读取的关联文稿。".to_string()
        } else {
            format!("已读取 {} 份关联文稿。", summaries.len())
        },
        document: None,
        document_summaries: summaries,
        opened_slug: None,
    })
}

fn execute_create_derived_document(
    workspace_root: &str,
    input: ExecuteNarrativeAgentActionInput,
) -> Result<NarrativeAgentActionExecutionResult, String> {
    let payload = input.payload.as_object().cloned().unwrap_or_default();
    let doc_type = payload
        .get("docType")
        .or_else(|| payload.get("doc_type"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "create_derived_document 需要 docType".to_string())?
        .to_string();
    let title = payload
        .get("title")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string);
    let slug = payload
        .get("slug")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string);
    let markdown_override = payload
        .get("markdown")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string);

    let mut document = create_narrative_document(
        workspace_root.to_string(),
        CreateNarrativeDocumentInput {
            doc_type: doc_type.clone(),
            slug,
            title,
        },
    )?;

    if let Some(markdown) = markdown_override {
        document.markdown = markdown;
    }
    if let Some(source_slug) = input
        .current_document
        .as_ref()
        .map(|document| document.meta.slug.clone())
        .filter(|value| !value.is_empty())
    {
        if !document.meta.related_docs.iter().any(|slug| slug == &source_slug) {
            document.meta.related_docs.push(source_slug);
        }
    }

    let save_result = save_narrative_document(
        workspace_root.to_string(),
        SaveNarrativeDocumentInput {
            original_slug: None,
            document,
        },
    )?;
    let saved_slug = save_result.saved_slug;
    let workspace_root_path = resolve_workspace_root(workspace_root)?;
    let saved_document = load_narrative_documents(&workspace_root_path)?
        .into_iter()
        .find(|document| document.meta.slug == saved_slug)
        .ok_or_else(|| "新建派生文稿后未能重新读取文档".to_string())?;

    Ok(NarrativeAgentActionExecutionResult {
        request_id: input.request_id,
        action_type: input.action_type,
        status: "completed".to_string(),
        summary: format!(
            "已创建并保存 {}《{}》。",
            doc_type_label(&saved_document.meta.doc_type),
            saved_document.meta.title
        ),
        document: Some(saved_document),
        document_summaries: Vec::new(),
        opened_slug: None,
    })
}

fn execute_save_active_document(
    workspace_root: &str,
    input: ExecuteNarrativeAgentActionInput,
) -> Result<NarrativeAgentActionExecutionResult, String> {
    let Some(document) = input.current_document else {
        return Err("save_active_document 需要 currentDocument".to_string());
    };

    let save_result = save_narrative_document(
        workspace_root.to_string(),
        SaveNarrativeDocumentInput {
            original_slug: Some(document.original_slug.clone()),
            document,
        },
    )?;
    let saved_slug = save_result.saved_slug;
    let workspace_root_path = resolve_workspace_root(workspace_root)?;
    let saved_document = load_narrative_documents(&workspace_root_path)?
        .into_iter()
        .find(|entry| entry.meta.slug == saved_slug)
        .ok_or_else(|| "保存后未能重新读取当前文稿".to_string())?;

    Ok(NarrativeAgentActionExecutionResult {
        request_id: input.request_id,
        action_type: input.action_type,
        status: "completed".to_string(),
        summary: format!("已保存当前文稿《{}》。", saved_document.meta.title),
        document: Some(saved_document),
        document_summaries: Vec::new(),
        opened_slug: None,
    })
}

fn execute_open_document(
    workspace_root: &str,
    input: ExecuteNarrativeAgentActionInput,
) -> Result<NarrativeAgentActionExecutionResult, String> {
    let slug = input
        .payload
        .get("slug")
        .or_else(|| input.payload.get("documentKey"))
        .or_else(|| input.payload.get("document_key"))
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "open_document 需要 slug 或 documentKey".to_string())?
        .to_string();
    let workspace_root_path = resolve_workspace_root(workspace_root)?;
    let exists = load_narrative_documents(&workspace_root_path)?
        .into_iter()
        .any(|document| document.meta.slug == slug);
    if !exists {
        return Err(format!("未找到要打开的文稿: {slug}"));
    }

    Ok(NarrativeAgentActionExecutionResult {
        request_id: input.request_id,
        action_type: input.action_type,
        status: "completed".to_string(),
        summary: format!("已确认可以打开文稿 {slug}。"),
        document: None,
        document_summaries: Vec::new(),
        opened_slug: Some(slug),
    })
}

fn execute_list_workspace_documents(
    workspace_root: &str,
    input: ExecuteNarrativeAgentActionInput,
) -> Result<NarrativeAgentActionExecutionResult, String> {
    let workspace_root_path = resolve_workspace_root(workspace_root)?;
    let summaries = load_narrative_documents(&workspace_root_path)?
        .into_iter()
        .map(|document| summarize_payload(&document))
        .collect::<Vec<_>>();

    Ok(NarrativeAgentActionExecutionResult {
        request_id: input.request_id,
        action_type: input.action_type,
        status: "completed".to_string(),
        summary: format!("当前工作区共有 {} 份 narrative 文稿。", summaries.len()),
        document: None,
        document_summaries: summaries,
        opened_slug: None,
    })
}

fn execute_update_related_documents(
    workspace_root: &str,
    input: ExecuteNarrativeAgentActionInput,
) -> Result<NarrativeAgentActionExecutionResult, String> {
    let mut document = input
        .current_document
        .ok_or_else(|| "update_related_documents 需要 currentDocument".to_string())?;
    let replacement = read_slug_list(
        input.payload.get("relatedDocs").or_else(|| input.payload.get("related_docs")),
    );
    let adds = read_slug_list(
        input.payload
            .get("addDocumentSlugs")
            .or_else(|| input.payload.get("add_document_slugs")),
    );
    let removes = read_slug_list(
        input.payload
            .get("removeDocumentSlugs")
            .or_else(|| input.payload.get("remove_document_slugs")),
    );

    let mut next_related = if replacement.is_empty() {
        document.meta.related_docs.clone()
    } else {
        replacement
    };

    for slug in adds {
        if !next_related.iter().any(|entry| entry == &slug) {
            next_related.push(slug);
        }
    }
    next_related.retain(|slug| !removes.iter().any(|entry| entry == slug));
    document.meta.related_docs = next_related;

    let saved_document = save_existing_document(workspace_root, document)?;
    Ok(NarrativeAgentActionExecutionResult {
        request_id: input.request_id,
        action_type: input.action_type,
        status: "completed".to_string(),
        summary: format!(
            "已更新《{}》的关联文稿，共 {} 项。",
            saved_document.meta.title,
            saved_document.meta.related_docs.len()
        ),
        document: Some(saved_document),
        document_summaries: Vec::new(),
        opened_slug: None,
    })
}

fn execute_rename_active_document(
    workspace_root: &str,
    input: ExecuteNarrativeAgentActionInput,
) -> Result<NarrativeAgentActionExecutionResult, String> {
    let mut document = input
        .current_document
        .ok_or_else(|| "rename_active_document 需要 currentDocument".to_string())?;
    let next_title = input
        .payload
        .get("title")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string);
    let next_slug = input
        .payload
        .get("slug")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string);

    if next_title.is_none() && next_slug.is_none() {
        return Err("rename_active_document 至少需要 title 或 slug".to_string());
    }

    if let Some(title) = next_title {
        document.meta.title = title;
    }
    if let Some(slug) = next_slug {
        document.meta.slug = slug;
    }

    let saved_document = save_existing_document(workspace_root, document)?;
    Ok(NarrativeAgentActionExecutionResult {
        request_id: input.request_id,
        action_type: input.action_type,
        status: "completed".to_string(),
        summary: format!("已重命名当前文稿为《{}》。", saved_document.meta.title),
        document: Some(saved_document.clone()),
        document_summaries: Vec::new(),
        opened_slug: Some(saved_document.meta.slug.clone()),
    })
}

fn execute_set_document_status(
    workspace_root: &str,
    input: ExecuteNarrativeAgentActionInput,
) -> Result<NarrativeAgentActionExecutionResult, String> {
    let mut document = input
        .current_document
        .ok_or_else(|| "set_document_status 需要 currentDocument".to_string())?;
    let next_status = input
        .payload
        .get("status")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "set_document_status 需要 status".to_string())?;
    document.meta.status = next_status.to_string();

    let saved_document = save_existing_document(workspace_root, document)?;
    Ok(NarrativeAgentActionExecutionResult {
        request_id: input.request_id,
        action_type: input.action_type,
        status: "completed".to_string(),
        summary: format!(
            "已将《{}》状态更新为 {}。",
            saved_document.meta.title, saved_document.meta.status
        ),
        document: Some(saved_document),
        document_summaries: Vec::new(),
        opened_slug: None,
    })
}

fn execute_archive_document(
    workspace_root: &str,
    mut input: ExecuteNarrativeAgentActionInput,
) -> Result<NarrativeAgentActionExecutionResult, String> {
    let payload = input.payload.as_object().cloned().unwrap_or_default();
    input.payload = Value::Object(payload);
    let mut document = input
        .current_document
        .ok_or_else(|| "archive_document 需要 currentDocument".to_string())?;
    document.meta.status = "archived".to_string();
    if let Some(title_suffix) = input
        .payload
        .get("titleSuffix")
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        document.meta.title = format!("{} {}", document.meta.title.trim(), title_suffix);
    }

    let saved_document = save_existing_document(workspace_root, document)?;
    Ok(NarrativeAgentActionExecutionResult {
        request_id: input.request_id,
        action_type: input.action_type,
        status: "completed".to_string(),
        summary: format!("已归档文稿《{}》。", saved_document.meta.title),
        document: Some(saved_document),
        document_summaries: Vec::new(),
        opened_slug: None,
    })
}

fn execute_split_plan_into_documents(
    workspace_root: &str,
    input: ExecuteNarrativeAgentActionInput,
) -> Result<NarrativeAgentActionExecutionResult, String> {
    let source_slug = input
        .current_document
        .as_ref()
        .map(|document| document.meta.slug.clone())
        .unwrap_or_default();
    let specs = input
        .payload
        .get("documents")
        .or_else(|| input.payload.get("documentSpecs"))
        .and_then(Value::as_array)
        .ok_or_else(|| "split_plan_into_documents 需要 documents".to_string())?;

    let mut saved_documents = Vec::new();
    for (index, spec) in specs.iter().enumerate() {
        let spec_object = spec
            .as_object()
            .ok_or_else(|| format!("split_plan_into_documents.documents[{index}] 必须是对象"))?;
        let doc_type = spec_object
            .get("docType")
            .or_else(|| spec_object.get("doc_type"))
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| format!("split_plan_into_documents.documents[{index}] 缺少 docType"))?
            .to_string();
        let title = spec_object
            .get("title")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToString::to_string);
        let slug = spec_object
            .get("slug")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToString::to_string);
        let markdown = spec_object
            .get("markdown")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToString::to_string);
        let status = spec_object
            .get("status")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToString::to_string);
        let mut document = create_narrative_document(
            workspace_root.to_string(),
            CreateNarrativeDocumentInput { doc_type, slug, title },
        )?;
        if let Some(markdown) = markdown {
            document.markdown = markdown;
        }
        if let Some(status) = status {
            document.meta.status = status;
        }
        if !source_slug.is_empty() && !document.meta.related_docs.iter().any(|entry| entry == &source_slug)
        {
            document.meta.related_docs.push(source_slug.clone());
        }

        save_narrative_document(
            workspace_root.to_string(),
            SaveNarrativeDocumentInput {
                original_slug: None,
                document: document.clone(),
            },
        )?;

        let saved_document = reload_document_by_slug(workspace_root, &document.meta.slug)?;
        saved_documents.push(saved_document);
    }

    let first_document = saved_documents.first().cloned();
    Ok(NarrativeAgentActionExecutionResult {
        request_id: input.request_id,
        action_type: input.action_type,
        status: "completed".to_string(),
        summary: format!("已按计划拆分并创建 {} 份文稿。", saved_documents.len()),
        document: first_document.clone(),
        document_summaries: saved_documents.iter().map(summarize_payload).collect(),
        opened_slug: first_document.map(|document| document.meta.slug),
    })
}

fn save_existing_document(
    workspace_root: &str,
    document: NarrativeDocumentPayload,
) -> Result<NarrativeDocumentPayload, String> {
    let original_slug = document.original_slug.clone();
    let save_result = save_narrative_document(
        workspace_root.to_string(),
        SaveNarrativeDocumentInput {
            original_slug: Some(original_slug),
            document,
        },
    )?;
    reload_document_by_slug(workspace_root, &save_result.saved_slug)
}

fn reload_document_by_slug(
    workspace_root: &str,
    slug: &str,
) -> Result<NarrativeDocumentPayload, String> {
    let workspace_root_path = resolve_workspace_root(workspace_root)?;
    load_narrative_documents(&workspace_root_path)?
        .into_iter()
        .find(|entry| entry.meta.slug == slug)
        .ok_or_else(|| format!("未能重新读取文稿: {slug}"))
}

fn read_slug_list(value: Option<&Value>) -> Vec<String> {
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

fn summarize_payload(document: &NarrativeDocumentPayload) -> NarrativeDocumentSummary {
    let headings = document
        .markdown
        .lines()
        .map(str::trim)
        .filter(|line| line.starts_with('#'))
        .map(|line| line.trim_start_matches('#').trim().to_string())
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>();
    let excerpt = document
        .markdown
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty() && !line.starts_with('#'))
        .unwrap_or_default()
        .chars()
        .take(120)
        .collect::<String>();

    NarrativeDocumentSummary {
        slug: document.meta.slug.clone(),
        title: document.meta.title.clone(),
        heading_count: headings.len(),
        headings,
        excerpt,
    }
}
