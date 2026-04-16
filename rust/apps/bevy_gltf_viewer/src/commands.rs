use bevy::log::info;
use bevy::prelude::*;

use crate::catalog::{spawn_catalog_scan_task_for_root, CatalogLoadingTask};
use crate::preview::default_viewer_orbit;
use crate::state::{PreviewCamera, PreviewState, ViewerAppState, ViewerAssetRoot, ViewerUiState};

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub(crate) enum GltfViewerCommand {
    SelectModel(String),
    ToggleGround,
    RescanCatalog,
}

pub(crate) fn handle_viewer_commands(
    mut commands: Commands,
    mut requests: MessageReader<GltfViewerCommand>,
    mut ui_state: ResMut<ViewerUiState>,
    mut preview_state: ResMut<PreviewState>,
    asset_root: Res<ViewerAssetRoot>,
    mut next_state: ResMut<NextState<ViewerAppState>>,
    mut preview_camera: Query<&mut game_editor::PreviewCameraController, With<PreviewCamera>>,
    loading_tasks: Query<(), With<CatalogLoadingTask>>,
) {
    for request in requests.read() {
        match request {
            GltfViewerCommand::SelectModel(path) => {
                ui_state.selected_model_path = Some(path.clone());
                preview_state.requested_model_path = Some(path.clone());
                if let Ok(mut preview_camera) = preview_camera.single_mut() {
                    preview_camera.set_orbit(default_viewer_orbit());
                }
                info!("gltf viewer selected model: {path}");
            }
            GltfViewerCommand::ToggleGround => {
                ui_state.show_ground = !ui_state.show_ground;
            }
            GltfViewerCommand::RescanCatalog => {
                if loading_tasks.is_empty() {
                    spawn_catalog_scan_task_for_root(&mut commands, &asset_root.0);
                }
                next_state.set(ViewerAppState::Loading);
            }
        }
    }
}
