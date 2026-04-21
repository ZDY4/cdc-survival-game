use std::collections::BTreeSet;
use std::fs;
use std::path::Path;
use std::process::Command;

use game_data::{
    validate_character_definition, CharacterDefinition, ItemDefinition, ItemEditorService,
    MapDefinition, MapEditorService, RecipeDefinition, RecipeEditorService,
};
use serde::de::DeserializeOwned;

pub(super) fn validate_changed_content(repo_root: &Path) -> Result<i32, String> {
    let changed_paths = collect_changed_supported_paths(repo_root)?;
    println!("mode: validate_changed");
    println!("changed_supported_files: {}", changed_paths.len());

    if changed_paths.is_empty() {
        println!("status: no_supported_changes");
        return Ok(0);
    }

    let mut has_invalid = false;
    for relative_path in &changed_paths {
        let report = validate_changed_path(repo_root, relative_path)?;
        println!(
            "- [{}] {} {} @ {}",
            if report.ok { "ok" } else { "invalid" },
            report.kind,
            report.id.as_deref().unwrap_or("-"),
            report.relative_path
        );
        for diagnostic in report.diagnostics {
            println!("  {diagnostic}");
        }
        has_invalid |= !report.ok;
    }

    println!("status: {}", if has_invalid { "invalid" } else { "ok" });
    Ok(if has_invalid { 2 } else { 0 })
}

pub(super) fn collect_changed_supported_paths(repo_root: &Path) -> Result<Vec<String>, String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .arg("status")
        .arg("--short")
        .arg("--untracked-files=all")
        .arg("--")
        .arg("data/items")
        .arg("data/recipes")
        .arg("data/characters")
        .arg("data/maps")
        .output()
        .map_err(|error| format!("failed to run git status: {error}"))?;
    if !output.status.success() {
        return Err(format!(
            "git status failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut paths = BTreeSet::new();
    for line in stdout.lines() {
        if line.len() < 3 {
            continue;
        }
        let status = &line[..2];
        if status.contains('D') && !line.contains(" -> ") {
            continue;
        }
        let raw_path = line[3..].trim();
        if raw_path.is_empty() {
            continue;
        }
        let path = raw_path
            .split(" -> ")
            .last()
            .unwrap_or(raw_path)
            .replace('\\', "/");
        if is_supported_content_path(&path) && repo_root.join(&path).exists() {
            paths.insert(path);
        }
    }

    Ok(paths.into_iter().collect())
}

fn is_supported_content_path(path: &str) -> bool {
    path.ends_with(".json")
        && (path.starts_with("data/items/")
            || path.starts_with("data/recipes/")
            || path.starts_with("data/characters/")
            || path.starts_with("data/maps/"))
}

fn validate_changed_path(
    repo_root: &Path,
    relative_path: &str,
) -> Result<ValidationReport, String> {
    let absolute_path = repo_root.join(relative_path);
    if relative_path.starts_with("data/items/") {
        validate_item_path(repo_root, relative_path, &absolute_path)
    } else if relative_path.starts_with("data/recipes/") {
        validate_recipe_path(repo_root, relative_path, &absolute_path)
    } else if relative_path.starts_with("data/characters/") {
        validate_character_path(relative_path, &absolute_path)
    } else if relative_path.starts_with("data/maps/") {
        validate_map_path(repo_root, relative_path, &absolute_path)
    } else {
        Err(format!("unsupported changed content path: {relative_path}"))
    }
}

fn validate_item_path(
    repo_root: &Path,
    relative_path: &str,
    absolute_path: &Path,
) -> Result<ValidationReport, String> {
    let definition = read_json_file::<ItemDefinition>(absolute_path)?;
    let result =
        ItemEditorService::with_data_root(repo_root.join("data/items"), repo_root.join("data"))
            .validate_definition_result(&definition)
            .map_err(|error| error.to_string())?;
    Ok(ValidationReport {
        kind: "item".to_string(),
        id: Some(definition.id.to_string()),
        relative_path: relative_path.to_string(),
        ok: result.diagnostics.is_empty(),
        diagnostics: result
            .diagnostics
            .into_iter()
            .map(|diagnostic| {
                format!(
                    "[{:?}] {}: {}",
                    diagnostic.severity, diagnostic.code, diagnostic.message
                )
            })
            .collect(),
    })
}

fn validate_recipe_path(
    repo_root: &Path,
    relative_path: &str,
    absolute_path: &Path,
) -> Result<ValidationReport, String> {
    let definition = read_json_file::<RecipeDefinition>(absolute_path)?;
    let result =
        RecipeEditorService::with_data_root(repo_root.join("data/recipes"), repo_root.join("data"))
            .validate_definition_result(&definition)
            .map_err(|error| error.to_string())?;
    Ok(ValidationReport {
        kind: "recipe".to_string(),
        id: Some(definition.id.clone()),
        relative_path: relative_path.to_string(),
        ok: result.diagnostics.is_empty(),
        diagnostics: result
            .diagnostics
            .into_iter()
            .map(|diagnostic| {
                format!(
                    "[{:?}] {}: {}",
                    diagnostic.severity, diagnostic.code, diagnostic.message
                )
            })
            .collect(),
    })
}

fn validate_character_path(
    relative_path: &str,
    absolute_path: &Path,
) -> Result<ValidationReport, String> {
    let definition = read_json_file::<CharacterDefinition>(absolute_path)?;
    let validation = validate_character_definition(&definition);
    let ok = validation.is_ok();
    let diagnostics = validation
        .err()
        .into_iter()
        .map(|error| format!("[Error] validation_error: {error}"))
        .collect::<Vec<_>>();
    Ok(ValidationReport {
        kind: "character".to_string(),
        id: Some(definition.id.to_string()),
        relative_path: relative_path.to_string(),
        ok,
        diagnostics,
    })
}

fn validate_map_path(
    repo_root: &Path,
    relative_path: &str,
    absolute_path: &Path,
) -> Result<ValidationReport, String> {
    let definition = read_json_file::<MapDefinition>(absolute_path)?;
    let result =
        MapEditorService::with_data_root(repo_root.join("data/maps"), repo_root.join("data"))
            .validate_definition_result(&definition)
            .map_err(|error| error.to_string())?;
    Ok(ValidationReport {
        kind: "map".to_string(),
        id: Some(definition.id.to_string()),
        relative_path: relative_path.to_string(),
        ok: result.diagnostics.is_empty(),
        diagnostics: result
            .diagnostics
            .into_iter()
            .map(|diagnostic| {
                format!(
                    "[{:?}] {}: {}",
                    diagnostic.severity, diagnostic.code, diagnostic.message
                )
            })
            .collect(),
    })
}

pub(super) fn read_json_file<T>(path: &Path) -> Result<T, String>
where
    T: DeserializeOwned,
{
    let raw = fs::read_to_string(path)
        .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
    serde_json::from_str(&raw)
        .map_err(|error| format!("failed to parse {}: {error}", path.display()))
}

#[derive(Debug)]
struct ValidationReport {
    kind: String,
    id: Option<String>,
    relative_path: String,
    ok: bool,
    diagnostics: Vec<String>,
}
