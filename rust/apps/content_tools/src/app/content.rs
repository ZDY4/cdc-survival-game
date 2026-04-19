use std::fs;
use std::path::{Path, PathBuf};

use game_data::{
    CharacterDefinition, ItemEditDocument, ItemEditorService, MapDefinition, MapEditorService,
    OverworldDefinition, RecipeEditDocument, RecipeEditorService, validate_character_definition,
};
use serde::de::DeserializeOwned;

use super::ContentKind;

pub(super) fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../..")
}

pub(super) fn locate_content(
    kind: ContentKind,
    target_id: &str,
    repo_root: &Path,
) -> Result<i32, String> {
    let located = match kind {
        ContentKind::Item => locate_item(target_id, repo_root)?,
        ContentKind::Recipe => locate_recipe(target_id, repo_root)?,
        ContentKind::Character => locate_character(target_id, repo_root)?,
        ContentKind::Map => locate_map(target_id, repo_root)?,
    };

    print_location(kind, target_id, &located.relative_path, &located.absolute_path);
    Ok(0)
}

pub(super) fn validate_content(
    kind: ContentKind,
    target_id: &str,
    repo_root: &Path,
) -> Result<i32, String> {
    match kind {
        ContentKind::Item => validate_item(target_id, repo_root),
        ContentKind::Recipe => validate_recipe(target_id, repo_root),
        ContentKind::Character => validate_character(target_id, repo_root),
        ContentKind::Map => validate_map(target_id, repo_root),
    }
}

pub(super) fn find_item_document(
    target_id: &str,
    repo_root: &Path,
) -> Result<ItemEditDocument, String> {
    let item_id = target_id
        .parse::<u32>()
        .map_err(|error| format!("invalid item id {target_id}: {error}"))?;
    let mut document = item_editor_service(repo_root)?
        .load_documents()
        .map_err(|error| error.to_string())?
        .into_iter()
        .find(|document| document.definition.id == item_id)
        .ok_or_else(|| format!("item {item_id} not found"))?;
    document.relative_path = normalize_data_relative_path(&document.relative_path);
    Ok(document)
}

pub(super) fn find_recipe_document(
    target_id: &str,
    repo_root: &Path,
) -> Result<RecipeEditDocument, String> {
    let mut document = recipe_editor_service(repo_root)?
        .load_documents()
        .map_err(|error| error.to_string())?
        .into_iter()
        .find(|document| document.definition.id == target_id)
        .ok_or_else(|| format!("recipe {target_id} not found"))?;
    document.relative_path = normalize_data_relative_path(&document.relative_path);
    Ok(document)
}

pub(super) fn find_character_document(
    target_id: &str,
    repo_root: &Path,
) -> Result<CharacterDocumentEntry, String> {
    scan_character_documents(repo_root)?
        .into_iter()
        .find(|entry| entry.definition.id.as_str() == target_id)
        .ok_or_else(|| format!("character {target_id} not found"))
}

pub(super) fn find_map_document(target_id: &str, repo_root: &Path) -> Result<MapDocumentEntry, String> {
    scan_map_documents(repo_root)?
        .into_iter()
        .find(|entry| entry.definition.id.as_str() == target_id)
        .ok_or_else(|| format!("map {target_id} not found"))
}

pub(super) fn scan_character_documents(repo_root: &Path) -> Result<Vec<CharacterDocumentEntry>, String> {
    scan_json_documents::<CharacterDefinition>(&repo_root.join("data").join("characters"), "character")?
        .into_iter()
        .map(|(path, definition)| {
            Ok(CharacterDocumentEntry {
                relative_path: make_relative_path(repo_root, &path),
                path,
                definition,
            })
        })
        .collect()
}

pub(super) fn scan_map_documents(repo_root: &Path) -> Result<Vec<MapDocumentEntry>, String> {
    scan_json_documents::<MapDefinition>(&repo_root.join("data").join("maps"), "map")?
        .into_iter()
        .map(|(path, definition)| {
            Ok(MapDocumentEntry {
                relative_path: make_relative_path(repo_root, &path),
                path,
                definition,
            })
        })
        .collect()
}

pub(super) fn scan_overworld_documents(
    repo_root: &Path,
) -> Result<Vec<OverworldDocumentEntry>, String> {
    scan_json_documents::<OverworldDefinition>(&repo_root.join("data").join("overworld"), "overworld")?
        .into_iter()
        .map(|(path, definition)| {
            Ok(OverworldDocumentEntry {
                relative_path: make_relative_path(repo_root, &path),
                definition,
            })
        })
        .collect()
}

pub(super) fn make_relative_path(repo_root: &Path, path: &Path) -> String {
    path.strip_prefix(repo_root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

pub(super) fn normalize_data_relative_path(relative_path: &str) -> String {
    let normalized = relative_path.replace('\\', "/");
    if normalized.starts_with("data/") {
        normalized
    } else {
        format!("data/{normalized}")
    }
}

fn locate_item(target_id: &str, repo_root: &Path) -> Result<LocatedContent, String> {
    let document = find_item_document(target_id, repo_root)?;
    resolve_located_content(repo_root, &document.relative_path)
}

fn locate_recipe(target_id: &str, repo_root: &Path) -> Result<LocatedContent, String> {
    let document = find_recipe_document(target_id, repo_root)?;
    resolve_located_content(repo_root, &document.relative_path)
}

fn locate_character(target_id: &str, repo_root: &Path) -> Result<LocatedContent, String> {
    let entry = find_character_document(target_id, repo_root)?;
    Ok(LocatedContent {
        relative_path: entry.relative_path,
        absolute_path: canonical_or_original(entry.path),
    })
}

fn locate_map(target_id: &str, repo_root: &Path) -> Result<LocatedContent, String> {
    let entry = find_map_document(target_id, repo_root)?;
    Ok(LocatedContent {
        relative_path: entry.relative_path,
        absolute_path: canonical_or_original(entry.path),
    })
}

fn validate_item(target_id: &str, repo_root: &Path) -> Result<i32, String> {
    let document = find_item_document(target_id, repo_root)?;
    let result = item_editor_service(repo_root)?
        .validate_definition_result(&document.definition)
        .map_err(|error| error.to_string())?;
    print_validation_header(
        "item",
        target_id,
        &document.relative_path,
        result.diagnostics.is_empty(),
    );
    print_item_diagnostics(&result.diagnostics);
    Ok(if result.diagnostics.is_empty() { 0 } else { 2 })
}

fn validate_recipe(target_id: &str, repo_root: &Path) -> Result<i32, String> {
    let document = find_recipe_document(target_id, repo_root)?;
    let result = recipe_editor_service(repo_root)?
        .validate_definition_result(&document.definition)
        .map_err(|error| error.to_string())?;
    print_validation_header(
        "recipe",
        target_id,
        &document.relative_path,
        result.diagnostics.is_empty(),
    );
    print_recipe_diagnostics(&result.diagnostics);
    Ok(if result.diagnostics.is_empty() { 0 } else { 2 })
}

fn validate_character(target_id: &str, repo_root: &Path) -> Result<i32, String> {
    let entry = find_character_document(target_id, repo_root)?;
    let validation = validate_character_definition(&entry.definition);
    print_validation_header(
        "character",
        target_id,
        &entry.relative_path,
        validation.is_ok(),
    );
    if let Err(error) = validation {
        println!("- [error] validation_error: {error}");
        return Ok(2);
    }
    Ok(0)
}

fn validate_map(target_id: &str, repo_root: &Path) -> Result<i32, String> {
    let entry = find_map_document(target_id, repo_root)?;
    let result = map_editor_service(repo_root)
        .validate_definition_result(&entry.definition)
        .map_err(|error| error.to_string())?;
    print_validation_header(
        "map",
        target_id,
        &entry.relative_path,
        result.diagnostics.is_empty(),
    );
    print_map_diagnostics(&result.diagnostics);
    Ok(if result.diagnostics.is_empty() { 0 } else { 2 })
}

fn scan_json_documents<T>(dir: &Path, label: &str) -> Result<Vec<(PathBuf, T)>, String>
where
    T: DeserializeOwned,
{
    let mut paths = fs::read_dir(dir)
        .map_err(|error| format!("failed to read {label} directory {}: {error}", dir.display()))?
        .filter_map(|entry| entry.ok().map(|value| value.path()))
        .filter(|path| path.extension().and_then(|value| value.to_str()) == Some("json"))
        .collect::<Vec<_>>();
    paths.sort();

    let mut entries = Vec::with_capacity(paths.len());
    for path in paths {
        let raw = fs::read_to_string(&path)
            .map_err(|error| format!("failed to read {}: {error}", path.display()))?;
        let definition = serde_json::from_str(&raw)
            .map_err(|error| format!("failed to parse {}: {error}", path.display()))?;
        entries.push((path, definition));
    }
    Ok(entries)
}

fn item_editor_service(repo_root: &Path) -> Result<ItemEditorService, String> {
    let data_root = data_root(repo_root)?;
    Ok(ItemEditorService::with_data_root(
        data_root.join("items"),
        data_root,
    ))
}

fn recipe_editor_service(repo_root: &Path) -> Result<RecipeEditorService, String> {
    let data_root = data_root(repo_root)?;
    Ok(RecipeEditorService::with_data_root(
        data_root.join("recipes"),
        data_root,
    ))
}

fn map_editor_service(repo_root: &Path) -> MapEditorService {
    let data_root = repo_root.join("data");
    MapEditorService::with_data_root(data_root.join("maps"), data_root)
}

fn data_root(repo_root: &Path) -> Result<PathBuf, String> {
    let data_root = repo_root.join("data");
    if !data_root.exists() {
        return Err(format!("data root does not exist: {}", data_root.display()));
    }
    Ok(data_root)
}

fn resolve_located_content(repo_root: &Path, relative_path: &str) -> Result<LocatedContent, String> {
    let absolute_path = canonical_or_original(repo_root.join(relative_path));
    if !absolute_path.exists() {
        return Err(format!(
            "located relative path does not exist on disk: {relative_path}"
        ));
    }
    Ok(LocatedContent {
        relative_path: relative_path.replace('\\', "/"),
        absolute_path,
    })
}

fn canonical_or_original(path: PathBuf) -> PathBuf {
    let path = path.canonicalize().unwrap_or(path);
    let normalized = path.to_string_lossy().replace("\\\\?\\", "");
    PathBuf::from(normalized)
}

fn print_location(kind: ContentKind, target_id: &str, relative_path: &str, absolute_path: &Path) {
    println!("kind: {}", kind.label());
    println!("id: {target_id}");
    println!("relative_path: {relative_path}");
    println!("absolute_path: {}", absolute_path.display());
}

fn print_validation_header(kind: &str, target_id: &str, relative_path: &str, passed: bool) {
    println!("kind: {kind}");
    println!("id: {target_id}");
    println!("relative_path: {relative_path}");
    println!("status: {}", if passed { "ok" } else { "invalid" });
}

fn print_item_diagnostics(diagnostics: &[game_data::ItemEditDiagnostic]) {
    for diagnostic in diagnostics {
        println!(
            "- [{:?}] {}: {}",
            diagnostic.severity, diagnostic.code, diagnostic.message
        );
    }
}

fn print_recipe_diagnostics(diagnostics: &[game_data::RecipeEditDiagnostic]) {
    for diagnostic in diagnostics {
        println!(
            "- [{:?}] {}: {}",
            diagnostic.severity, diagnostic.code, diagnostic.message
        );
    }
}

fn print_map_diagnostics(diagnostics: &[game_data::MapEditDiagnostic]) {
    for diagnostic in diagnostics {
        println!(
            "- [{:?}] {}: {}",
            diagnostic.severity, diagnostic.code, diagnostic.message
        );
    }
}

#[derive(Debug)]
pub(super) struct LocatedContent {
    pub relative_path: String,
    pub absolute_path: PathBuf,
}

#[derive(Debug)]
pub(super) struct CharacterDocumentEntry {
    pub path: PathBuf,
    pub relative_path: String,
    pub definition: CharacterDefinition,
}

#[derive(Debug)]
pub(super) struct MapDocumentEntry {
    pub path: PathBuf,
    pub relative_path: String,
    pub definition: MapDefinition,
}

#[derive(Debug)]
pub(super) struct OverworldDocumentEntry {
    pub relative_path: String,
    pub definition: OverworldDefinition,
}
