use std::collections::BTreeMap;
use std::fs;
use std::path::{Component, Path, PathBuf};

use crate::state::ViewerUiState;

const LINK_FILE_NAME: &str = ".cdc_bbmodel_links.json";

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum BlockbenchSourceKind {
    ExplicitBbmodel,
    AutomaticSiblingBbmodel,
    GltfFallback,
    MissingExplicitFallbackSibling,
    MissingExplicitFallbackGltf,
}

#[derive(Debug, Clone)]
pub(crate) struct BlockbenchSource {
    pub(crate) absolute_path: PathBuf,
    pub(crate) relative_path: String,
    pub(crate) kind: BlockbenchSourceKind,
}

impl BlockbenchSource {
    pub(crate) fn status_label(&self) -> String {
        match self.kind {
            BlockbenchSourceKind::ExplicitBbmodel => {
                format!("显式关联: {}", self.relative_path)
            }
            BlockbenchSourceKind::AutomaticSiblingBbmodel => {
                format!("同名自动关联: {}", self.relative_path)
            }
            BlockbenchSourceKind::GltfFallback => "未关联，打开 glTF".to_string(),
            BlockbenchSourceKind::MissingExplicitFallbackSibling => {
                format!("关联文件缺失，使用同名 bbmodel: {}", self.relative_path)
            }
            BlockbenchSourceKind::MissingExplicitFallbackGltf => {
                "关联文件缺失，打开 glTF".to_string()
            }
        }
    }

    pub(crate) fn opened_label(&self) -> String {
        match self.kind {
            BlockbenchSourceKind::ExplicitBbmodel
            | BlockbenchSourceKind::AutomaticSiblingBbmodel
            | BlockbenchSourceKind::MissingExplicitFallbackSibling => {
                format!(
                    "已打开 Blockbench bbmodel: {}",
                    self.absolute_path.display()
                )
            }
            BlockbenchSourceKind::GltfFallback
            | BlockbenchSourceKind::MissingExplicitFallbackGltf => {
                format!("已打开 Blockbench glTF: {}", self.absolute_path.display())
            }
        }
    }
}

pub(crate) fn sync_bbmodel_link_ui_state(asset_root: &Path, ui_state: &mut ViewerUiState) {
    if ui_state.bbmodel_link_model_path == ui_state.selected_model_path {
        return;
    }
    ui_state.bbmodel_link_model_path = ui_state.selected_model_path.clone();
    ui_state.bbmodel_link_draft.clear();

    let Some(gltf_path) = ui_state.selected_model_path.as_deref() else {
        ui_state.bbmodel_link_status = Some("未选择 glTF 模型".to_string());
        return;
    };

    let explicit = load_links(asset_root)
        .ok()
        .and_then(|links| links.get(gltf_path).cloned());
    if let Some(explicit) = explicit {
        ui_state.bbmodel_link_draft = explicit;
    } else if let Some(sibling) = sibling_bbmodel_relative_path(asset_root, gltf_path) {
        ui_state.bbmodel_link_draft = sibling;
    }

    ui_state.bbmodel_link_status = match resolve_blockbench_source(asset_root, gltf_path) {
        Ok(source) => Some(source.status_label()),
        Err(error) => Some(error),
    };
}

pub(crate) fn resolve_blockbench_source(
    asset_root: &Path,
    gltf_relative_path: &str,
) -> Result<BlockbenchSource, String> {
    let gltf_relative_path = normalize_relative_asset_path(gltf_relative_path, "gltf")?;
    let gltf_absolute_path = resolve_existing_asset_path(asset_root, &gltf_relative_path, "gltf")?;
    let links = load_links(asset_root)?;
    let explicit = links.get(&gltf_relative_path).cloned();
    let sibling = sibling_bbmodel_relative_path(asset_root, &gltf_relative_path);

    if let Some(explicit) = explicit {
        let explicit = normalize_relative_asset_path(&explicit, "bbmodel")?;
        if let Ok(absolute_path) = resolve_existing_asset_path(asset_root, &explicit, "bbmodel") {
            return Ok(BlockbenchSource {
                absolute_path,
                relative_path: explicit,
                kind: BlockbenchSourceKind::ExplicitBbmodel,
            });
        }
        if let Some(sibling) = sibling {
            let absolute_path = resolve_existing_asset_path(asset_root, &sibling, "bbmodel")?;
            return Ok(BlockbenchSource {
                absolute_path,
                relative_path: sibling,
                kind: BlockbenchSourceKind::MissingExplicitFallbackSibling,
            });
        }
        return Ok(BlockbenchSource {
            absolute_path: gltf_absolute_path,
            relative_path: gltf_relative_path,
            kind: BlockbenchSourceKind::MissingExplicitFallbackGltf,
        });
    }

    if let Some(sibling) = sibling {
        let absolute_path = resolve_existing_asset_path(asset_root, &sibling, "bbmodel")?;
        return Ok(BlockbenchSource {
            absolute_path,
            relative_path: sibling,
            kind: BlockbenchSourceKind::AutomaticSiblingBbmodel,
        });
    }

    Ok(BlockbenchSource {
        absolute_path: gltf_absolute_path,
        relative_path: gltf_relative_path,
        kind: BlockbenchSourceKind::GltfFallback,
    })
}

pub(crate) fn save_explicit_link(
    asset_root: &Path,
    gltf_relative_path: &str,
    bbmodel_relative_path: &str,
) -> Result<String, String> {
    let gltf_relative_path = normalize_relative_asset_path(gltf_relative_path, "gltf")?;
    let bbmodel_relative_path = normalize_relative_asset_path(bbmodel_relative_path, "bbmodel")?;
    resolve_existing_asset_path(asset_root, &gltf_relative_path, "gltf")?;
    resolve_existing_asset_path(asset_root, &bbmodel_relative_path, "bbmodel")?;

    let mut links = load_links(asset_root)?;
    links.insert(gltf_relative_path, bbmodel_relative_path.clone());
    save_links(asset_root, &links)?;
    Ok(bbmodel_relative_path)
}

pub(crate) fn clear_explicit_link(
    asset_root: &Path,
    gltf_relative_path: &str,
) -> Result<(), String> {
    let gltf_relative_path = normalize_relative_asset_path(gltf_relative_path, "gltf")?;
    let mut links = load_links(asset_root)?;
    links.remove(&gltf_relative_path);
    save_links(asset_root, &links)
}

pub(crate) fn sibling_bbmodel_relative_path(
    asset_root: &Path,
    gltf_relative_path: &str,
) -> Option<String> {
    let gltf_relative_path = normalize_relative_asset_path(gltf_relative_path, "gltf").ok()?;
    let mut sibling = PathBuf::from(gltf_relative_path);
    sibling.set_extension("bbmodel");
    let sibling_relative = path_to_asset_relative_string(&sibling)?;
    resolve_existing_asset_path(asset_root, &sibling_relative, "bbmodel").ok()?;
    Some(sibling_relative)
}

pub(crate) fn normalize_relative_asset_path(path: &str, extension: &str) -> Result<String, String> {
    let trimmed = path.trim().replace('\\', "/");
    if trimmed.is_empty() {
        return Err("路径不能为空".to_string());
    }
    let path = Path::new(&trimmed);
    if path.is_absolute() {
        return Err(format!("路径必须是资产根相对路径: {trimmed}"));
    }
    for component in path.components() {
        if matches!(
            component,
            Component::ParentDir | Component::RootDir | Component::Prefix(_)
        ) {
            return Err(format!("路径不能越过资产根: {trimmed}"));
        }
    }
    if path
        .extension()
        .and_then(|value| value.to_str())
        .is_none_or(|value| !value.eq_ignore_ascii_case(extension))
    {
        return Err(format!("路径必须是 .{extension}: {trimmed}"));
    }
    path_to_asset_relative_string(path).ok_or_else(|| format!("路径无效: {trimmed}"))
}

fn resolve_existing_asset_path(
    asset_root: &Path,
    relative_path: &str,
    extension: &str,
) -> Result<PathBuf, String> {
    let relative_path = normalize_relative_asset_path(relative_path, extension)?;
    let root = asset_root
        .canonicalize()
        .map_err(|error| format!("资产根无效 {}: {error}", asset_root.display()))?;
    let absolute_path = root.join(&relative_path);
    let absolute_path = absolute_path
        .canonicalize()
        .map_err(|error| format!("资产文件不存在 {}: {error}", absolute_path.display()))?;
    if !absolute_path.starts_with(&root) {
        return Err(format!("资产路径越过资产根: {}", absolute_path.display()));
    }
    if !absolute_path.is_file() {
        return Err(format!("资产路径不是文件: {}", absolute_path.display()));
    }
    Ok(absolute_path)
}

fn load_links(asset_root: &Path) -> Result<BTreeMap<String, String>, String> {
    let path = link_file_path(asset_root);
    if !path.exists() {
        return Ok(BTreeMap::new());
    }
    let raw = fs::read_to_string(&path)
        .map_err(|error| format!("读取 bbmodel 关联失败 {}: {error}", path.display()))?;
    serde_json::from_str(&raw)
        .map_err(|error| format!("解析 bbmodel 关联失败 {}: {error}", path.display()))
}

fn save_links(asset_root: &Path, links: &BTreeMap<String, String>) -> Result<(), String> {
    let path = link_file_path(asset_root);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("创建关联目录失败 {}: {error}", parent.display()))?;
    }
    let raw =
        serde_json::to_string_pretty(links).map_err(|error| format!("序列化关联失败: {error}"))?;
    fs::write(&path, format!("{raw}\n"))
        .map_err(|error| format!("写入 bbmodel 关联失败 {}: {error}", path.display()))
}

fn link_file_path(asset_root: &Path) -> PathBuf {
    asset_root.join(LINK_FILE_NAME)
}

fn path_to_asset_relative_string(path: &Path) -> Option<String> {
    Some(path.to_string_lossy().replace('\\', "/"))
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    use super::{
        clear_explicit_link, normalize_relative_asset_path, resolve_blockbench_source,
        save_explicit_link, BlockbenchSourceKind,
    };

    #[test]
    fn automatic_sibling_bbmodel_is_used_without_explicit_link() {
        let root = temp_asset_root("auto_sibling");
        write_file(&root.join("props/crate.gltf"));
        write_file(&root.join("props/crate.bbmodel"));

        let source = resolve_blockbench_source(&root, "props/crate.gltf").expect("source resolves");

        assert_eq!(source.kind, BlockbenchSourceKind::AutomaticSiblingBbmodel);
        assert_eq!(source.relative_path, "props/crate.bbmodel");
    }

    #[test]
    fn explicit_link_wins_over_sibling() {
        let root = temp_asset_root("explicit_wins");
        write_file(&root.join("props/crate.gltf"));
        write_file(&root.join("props/crate.bbmodel"));
        write_file(&root.join("sources/custom_crate.bbmodel"));

        save_explicit_link(&root, "props/crate.gltf", "sources/custom_crate.bbmodel")
            .expect("link saves");
        let source = resolve_blockbench_source(&root, "props/crate.gltf").expect("source resolves");

        assert_eq!(source.kind, BlockbenchSourceKind::ExplicitBbmodel);
        assert_eq!(source.relative_path, "sources/custom_crate.bbmodel");
    }

    #[test]
    fn missing_explicit_link_falls_back_to_sibling_or_gltf() {
        let root = temp_asset_root("missing_explicit");
        write_file(&root.join("props/crate.gltf"));
        write_file(&root.join("props/crate.bbmodel"));
        fs::write(
            root.join(".cdc_bbmodel_links.json"),
            "{\n  \"props/crate.gltf\": \"missing/source.bbmodel\"\n}\n",
        )
        .expect("link file writes");

        let source = resolve_blockbench_source(&root, "props/crate.gltf").expect("source resolves");
        assert_eq!(
            source.kind,
            BlockbenchSourceKind::MissingExplicitFallbackSibling
        );

        fs::remove_file(root.join("props/crate.bbmodel")).expect("sibling removed");
        let source = resolve_blockbench_source(&root, "props/crate.gltf").expect("source resolves");
        assert_eq!(
            source.kind,
            BlockbenchSourceKind::MissingExplicitFallbackGltf
        );
    }

    #[test]
    fn relative_paths_cannot_escape_asset_root() {
        assert!(normalize_relative_asset_path("../crate.bbmodel", "bbmodel").is_err());
        assert!(normalize_relative_asset_path("props/crate.bbmodel", "bbmodel").is_ok());
    }

    #[test]
    fn clear_link_restores_automatic_sibling() {
        let root = temp_asset_root("clear_link");
        write_file(&root.join("props/crate.gltf"));
        write_file(&root.join("props/crate.bbmodel"));
        write_file(&root.join("sources/custom_crate.bbmodel"));
        save_explicit_link(&root, "props/crate.gltf", "sources/custom_crate.bbmodel")
            .expect("link saves");

        clear_explicit_link(&root, "props/crate.gltf").expect("link clears");
        let source = resolve_blockbench_source(&root, "props/crate.gltf").expect("source resolves");

        assert_eq!(source.kind, BlockbenchSourceKind::AutomaticSiblingBbmodel);
        assert_eq!(source.relative_path, "props/crate.bbmodel");
    }

    fn temp_asset_root(name: &str) -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system time works")
            .as_nanos();
        let root = std::env::temp_dir().join(format!("cdc_bbmodel_links_{name}_{stamp}"));
        fs::create_dir_all(&root).expect("root creates");
        root
    }

    fn write_file(path: &PathBuf) {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("parent creates");
        }
        fs::write(path, "{}\n").expect("file writes");
    }
}
