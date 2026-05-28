use std::collections::BTreeSet;
use std::fs::{self, DirEntry};
use std::path::{Path, PathBuf};

use serde::de::DeserializeOwned;

pub fn collect_sorted_dir_entries<E, F>(
    dir: &Path,
    map_read_dir_error: F,
) -> Result<Vec<DirEntry>, E>
where
    F: Fn(&Path, std::io::Error) -> E + Copy,
{
    let mut entries = fs::read_dir(dir)
        .map_err(|source| map_read_dir_error(dir, source))?
        .collect::<Result<Vec<_>, _>>()
        .map_err(|source| map_read_dir_error(dir, source))?;
    entries.sort_by_key(|entry| entry.file_name());
    Ok(entries)
}

pub fn read_json_file<T, E, F, G>(
    path: &Path,
    map_read_error: F,
    map_parse_error: G,
) -> Result<T, E>
where
    T: DeserializeOwned,
    F: Fn(&Path, std::io::Error) -> E + Copy,
    G: Fn(&Path, serde_json::Error) -> E + Copy,
{
    let raw = fs::read_to_string(path).map_err(|source| map_read_error(path, source))?;
    serde_json::from_str(&raw).map_err(|source| map_parse_error(path, source))
}

pub fn write_json_atomically<E, F, G, H>(
    path: &Path,
    raw: &str,
    map_create_dir_error: F,
    map_write_temp_error: G,
    map_replace_error: H,
) -> Result<bool, E>
where
    F: Fn(&Path, std::io::Error) -> E + Copy,
    G: Fn(&Path, std::io::Error) -> E + Copy,
    H: Fn(&Path, std::io::Error) -> E + Copy,
{
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|source| map_create_dir_error(parent, source))?;
    }

    if let Ok(existing_raw) = fs::read_to_string(path) {
        if existing_raw == raw {
            return Ok(false);
        }
    }

    let temp_path = temporary_path_for(path);
    fs::write(&temp_path, raw).map_err(|source| map_write_temp_error(&temp_path, source))?;
    if path.exists() {
        fs::remove_file(path).map_err(|source| map_replace_error(path, source))?;
    }
    fs::rename(&temp_path, path).map_err(|source| map_replace_error(path, source))?;
    Ok(true)
}

pub fn relative_path_from_root(path: &Path, data_root: Option<&Path>) -> Option<String> {
    let data_root = data_root?;
    path.strip_prefix(data_root)
        .ok()
        .map(|relative| relative.to_string_lossy().replace('\\', "/"))
}

pub fn duplicate_values<T>(values: impl IntoIterator<Item = T>) -> BTreeSet<T>
where
    T: Ord + Clone,
{
    let mut seen = BTreeSet::new();
    let mut duplicates = BTreeSet::new();
    for value in values {
        if !seen.insert(value.clone()) {
            duplicates.insert(value);
        }
    }
    duplicates
}

fn temporary_path_for(path: &Path) -> PathBuf {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("document.json");
    path.with_file_name(format!("{file_name}.tmp"))
}
