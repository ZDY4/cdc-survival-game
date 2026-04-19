use std::path::Path;

use game_data::{
    file_backed::write_json_atomically, MapEditCommand, MapEditTarget, MapEditorService,
};

use super::changed::collect_changed_supported_paths;
use super::content::{
    find_character_document, find_item_document, find_map_document, find_recipe_document,
};
use super::ContentKind;

pub(super) fn format_content(
    kind: Option<ContentKind>,
    target_id: Option<&str>,
    repo_root: &Path,
) -> Result<i32, String> {
    match (kind, target_id) {
        (Some(kind), Some(target_id)) => {
            let report = format_single(kind, target_id, repo_root)?;
            print_single_report(&report);
            Ok(0)
        }
        (None, None) => format_changed(repo_root),
        _ => Err("invalid format arguments".to_string()),
    }
}

fn format_changed(repo_root: &Path) -> Result<i32, String> {
    let changed_paths = collect_changed_supported_paths(repo_root)?;
    println!("mode: format_changed");
    println!("changed_supported_files: {}", changed_paths.len());
    if changed_paths.is_empty() {
        println!("status: no_supported_changes");
        return Ok(0);
    }

    let mut changed_count = 0usize;
    for relative_path in &changed_paths {
        let report = format_changed_path(relative_path, repo_root)?;
        changed_count += usize::from(report.changed);
        println!(
            "- [{}] {} {} @ {}",
            if report.changed { "changed" } else { "unchanged" },
            report.kind,
            report.id,
            report.relative_path
        );
    }
    println!("rewritten_files: {changed_count}");
    println!("status: ok");
    Ok(0)
}

fn format_single(kind: ContentKind, target_id: &str, repo_root: &Path) -> Result<FormatReport, String> {
    match kind {
        ContentKind::Item => format_item(target_id, repo_root),
        ContentKind::Recipe => format_recipe(target_id, repo_root),
        ContentKind::Character => format_character(target_id, repo_root),
        ContentKind::Map => format_map(target_id, repo_root),
    }
}

fn format_changed_path(relative_path: &str, repo_root: &Path) -> Result<FormatReport, String> {
    if relative_path.starts_with("data/items/") {
        let target_id = relative_path
            .strip_prefix("data/items/")
            .and_then(|path| path.strip_suffix(".json"))
            .ok_or_else(|| format!("failed to derive item id from {relative_path}"))?;
        format_item(target_id, repo_root)
    } else if relative_path.starts_with("data/recipes/") {
        let target_id = relative_path
            .strip_prefix("data/recipes/")
            .and_then(|path| path.strip_suffix(".json"))
            .ok_or_else(|| format!("failed to derive recipe id from {relative_path}"))?;
        format_recipe(target_id, repo_root)
    } else if relative_path.starts_with("data/characters/") {
        let target_id = relative_path
            .strip_prefix("data/characters/")
            .and_then(|path| path.strip_suffix(".json"))
            .ok_or_else(|| format!("failed to derive character id from {relative_path}"))?;
        format_character(target_id, repo_root)
    } else if relative_path.starts_with("data/maps/") {
        let target_id = relative_path
            .strip_prefix("data/maps/")
            .and_then(|path| path.strip_suffix(".json"))
            .ok_or_else(|| format!("failed to derive map id from {relative_path}"))?;
        format_map(target_id, repo_root)
    } else {
        Err(format!("unsupported changed content path: {relative_path}"))
    }
}

fn format_item(target_id: &str, repo_root: &Path) -> Result<FormatReport, String> {
    let document = find_item_document(target_id, repo_root)?;
    let path = repo_root.join(&document.relative_path);
    let changed = write_pretty_json(&path, &document.definition)?;
    Ok(FormatReport::new(
        "item",
        document.definition.id.to_string(),
        document.relative_path,
        changed,
    ))
}

fn format_recipe(target_id: &str, repo_root: &Path) -> Result<FormatReport, String> {
    let document = find_recipe_document(target_id, repo_root)?;
    let path = repo_root.join(&document.relative_path);
    let changed = write_pretty_json(&path, &document.definition)?;
    Ok(FormatReport::new(
        "recipe",
        document.definition.id,
        document.relative_path,
        changed,
    ))
}

fn format_character(target_id: &str, repo_root: &Path) -> Result<FormatReport, String> {
    let entry = find_character_document(target_id, repo_root)?;
    let changed = write_pretty_json(&entry.path, &entry.definition)?;
    Ok(FormatReport::new(
        "character",
        entry.definition.id.to_string(),
        entry.relative_path,
        changed,
    ))
}

fn format_map(target_id: &str, repo_root: &Path) -> Result<FormatReport, String> {
    let entry = find_map_document(target_id, repo_root)?;
    let result = MapEditorService::with_data_root(repo_root.join("data/maps"), repo_root.join("data"))
        .execute(MapEditCommand::FormatMap {
            target: MapEditTarget::Path(entry.path),
        })
        .map_err(|error| error.to_string())?;
    Ok(FormatReport::new(
        "map",
        entry.definition.id.to_string(),
        entry.relative_path,
        result.changed,
    ))
}

fn write_pretty_json<T>(path: &Path, value: &T) -> Result<bool, String>
where
    T: serde::Serialize,
{
    let raw = serde_json::to_string_pretty(value)
        .map_err(|error| format!("failed to serialize {}: {error}", path.display()))?;
    write_json_atomically(
        path,
        &raw,
        |path, source| format!("failed to create directory {}: {source}", path.display()),
        |path, source| format!("failed to write temporary file {}: {source}", path.display()),
        |path, source| format!("failed to replace file {}: {source}", path.display()),
    )
}

fn print_single_report(report: &FormatReport) {
    println!("mode: format");
    println!("kind: {}", report.kind);
    println!("id: {}", report.id);
    println!("relative_path: {}", report.relative_path);
    println!("changed: {}", report.changed);
}

#[derive(Debug)]
struct FormatReport {
    kind: String,
    id: String,
    relative_path: String,
    changed: bool,
}

impl FormatReport {
    fn new(
        kind: impl Into<String>,
        id: impl Into<String>,
        relative_path: impl Into<String>,
        changed: bool,
    ) -> Self {
        Self {
            kind: kind.into(),
            id: id.into(),
            relative_path: relative_path.into(),
            changed,
        }
    }
}
