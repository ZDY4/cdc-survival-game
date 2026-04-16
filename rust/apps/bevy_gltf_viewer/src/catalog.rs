use std::fs;
use std::path::{Path, PathBuf};

use bevy::log::info;
use bevy::prelude::*;
use bevy::tasks::{block_on, poll_once, AsyncComputeTaskPool, Task};

use crate::state::{PreviewState, ViewerAppState, ViewerAssetRoot, ViewerUiState};

#[derive(Debug, Clone)]
pub(crate) struct ModelEntry {
    pub(crate) display_name: String,
    pub(crate) relative_path: String,
    pub(crate) search_text: String,
}

impl ModelEntry {
    fn new(relative_path: String) -> Self {
        let display_name = Path::new(&relative_path)
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or(relative_path.as_str())
            .to_string();
        Self {
            display_name,
            search_text: relative_path.to_ascii_lowercase(),
            relative_path,
        }
    }
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct ModelCatalog {
    pub(crate) asset_root: PathBuf,
    pub(crate) entries: Vec<ModelEntry>,
}

impl ModelCatalog {
    pub(crate) fn scan(asset_root: &Path) -> Self {
        let mut entries = Vec::new();
        collect_models(asset_root, asset_root, &mut entries);
        entries.sort_by(|left, right| left.relative_path.cmp(&right.relative_path));
        Self {
            asset_root: asset_root.to_path_buf(),
            entries,
        }
    }
}

#[derive(Component)]
pub(crate) struct CatalogLoadingTask(pub(crate) Task<ModelCatalog>);

pub(crate) fn spawn_catalog_scan_task(mut commands: Commands, asset_root: Res<ViewerAssetRoot>) {
    spawn_catalog_scan_task_for_root(&mut commands, &asset_root.0);
}

pub(crate) fn spawn_catalog_scan_task_for_root(commands: &mut Commands, asset_root: &Path) {
    commands.spawn((CatalogLoadingTask(AsyncComputeTaskPool::get().spawn({
        let asset_root = asset_root.to_path_buf();
        async move { ModelCatalog::scan(&asset_root) }
    })),));
}

pub(crate) fn handle_catalog_loading_task(
    mut commands: Commands,
    mut query: Query<(Entity, &mut CatalogLoadingTask)>,
    mut ui_state: ResMut<ViewerUiState>,
    mut preview_state: ResMut<PreviewState>,
    mut next_state: ResMut<NextState<ViewerAppState>>,
) {
    for (entity, mut task) in &mut query {
        if let Some(catalog) = block_on(poll_once(&mut task.0)) {
            info!(
                "gltf viewer catalog loaded: {} model(s)",
                catalog.entries.len()
            );
            ui_state.selected_model_path = catalog
                .entries
                .first()
                .map(|entry| entry.relative_path.clone());
            preview_state.requested_model_path = ui_state.selected_model_path.clone();
            commands.insert_resource(catalog);
            commands.entity(entity).despawn();
            next_state.set(ViewerAppState::Ready);
        }
    }
}

fn collect_models(asset_root: &Path, current_dir: &Path, entries: &mut Vec<ModelEntry>) {
    let Ok(read_dir) = fs::read_dir(current_dir) else {
        return;
    };
    for entry in read_dir.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_models(asset_root, &path, entries);
            continue;
        }
        let Some(extension) = path.extension().and_then(|value| value.to_str()) else {
            continue;
        };
        if extension != "gltf" {
            continue;
        }
        let Ok(relative) = path.strip_prefix(asset_root) else {
            continue;
        };
        let relative = relative.to_string_lossy().replace('\\', "/");
        entries.push(ModelEntry::new(relative));
    }
}
