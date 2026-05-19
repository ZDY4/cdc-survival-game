use std::path::{Path, PathBuf};
use std::process::Command;

use bevy::gltf::GltfAssetLabel;
use bevy::log::{info, warn};
use bevy::prelude::*;

use crate::bbmodel_links::{
    clear_explicit_link, resolve_blockbench_source, save_explicit_link,
    sibling_bbmodel_relative_path,
};
use crate::catalog::{spawn_catalog_scan_task_for_root, CatalogLoadingTask};
use crate::preview::default_viewer_orbit;
use crate::state::{PreviewCamera, PreviewState, ViewerAppState, ViewerAssetRoot, ViewerUiState};

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub(crate) enum GltfViewerCommand {
    SelectModel(String),
    OpenModelInBlockbench(String),
    ReloadModel(String),
    OpenModelDirectory(String),
    SaveBbmodelLink,
    ClearBbmodelLink,
    UseSiblingBbmodelLink,
    ToggleSocketEditor,
    RescanCatalog,
}

pub(crate) fn handle_viewer_commands(
    mut commands: Commands,
    mut requests: MessageReader<GltfViewerCommand>,
    mut ui_state: ResMut<ViewerUiState>,
    mut preview_state: ResMut<PreviewState>,
    asset_root: Res<ViewerAssetRoot>,
    asset_server: Res<AssetServer>,
    mut next_state: ResMut<NextState<ViewerAppState>>,
    mut preview_camera: Query<&mut game_editor::PreviewCameraController, With<PreviewCamera>>,
    loading_tasks: Query<(), With<CatalogLoadingTask>>,
) {
    for request in requests.read() {
        match request {
            GltfViewerCommand::SelectModel(path) => {
                select_model(path, &mut ui_state, &mut preview_state, &mut preview_camera);
                info!("gltf viewer selected model: {path}");
            }
            GltfViewerCommand::OpenModelInBlockbench(path) => {
                select_model(path, &mut ui_state, &mut preview_state, &mut preview_camera);
                match open_model_in_blockbench(&asset_root.0, path) {
                    Ok(source_label) => {
                        ui_state.external_tool_status = Some(source_label);
                    }
                    Err(error) => {
                        warn!("failed to open model in Blockbench: {error}");
                        ui_state.external_tool_status = Some(error);
                    }
                }
            }
            GltfViewerCommand::ReloadModel(path) => {
                select_model(path, &mut ui_state, &mut preview_state, &mut preview_camera);
                reload_model(
                    &asset_server,
                    &mut preview_state,
                    &mut ui_state,
                    path.clone(),
                );
                info!("gltf viewer requested model reload: {path}");
            }
            GltfViewerCommand::OpenModelDirectory(path) => {
                select_model(path, &mut ui_state, &mut preview_state, &mut preview_camera);
                match open_model_directory(&asset_root.0, path) {
                    Ok(directory) => {
                        ui_state.external_tool_status =
                            Some(format!("已打开模型目录: {}", directory.display()));
                    }
                    Err(error) => {
                        warn!("failed to open model directory: {error}");
                        ui_state.external_tool_status = Some(error);
                    }
                }
            }
            GltfViewerCommand::SaveBbmodelLink => {
                let Some(path) = ui_state.selected_model_path.clone() else {
                    ui_state.bbmodel_link_status = Some("未选择 glTF 模型".to_string());
                    continue;
                };
                match save_explicit_link(&asset_root.0, &path, &ui_state.bbmodel_link_draft) {
                    Ok(bbmodel_path) => {
                        ui_state.bbmodel_link_draft = bbmodel_path.clone();
                        ui_state.bbmodel_link_status =
                            Some(format!("已保存显式关联: {bbmodel_path}"));
                        ui_state.bbmodel_link_model_path = None;
                    }
                    Err(error) => {
                        warn!("failed to save bbmodel link: {error}");
                        ui_state.bbmodel_link_status = Some(error);
                    }
                }
            }
            GltfViewerCommand::ClearBbmodelLink => {
                let Some(path) = ui_state.selected_model_path.clone() else {
                    ui_state.bbmodel_link_status = Some("未选择 glTF 模型".to_string());
                    continue;
                };
                match clear_explicit_link(&asset_root.0, &path) {
                    Ok(()) => {
                        ui_state.bbmodel_link_status = Some("已清除显式关联".to_string());
                        ui_state.bbmodel_link_model_path = None;
                    }
                    Err(error) => {
                        warn!("failed to clear bbmodel link: {error}");
                        ui_state.bbmodel_link_status = Some(error);
                    }
                }
            }
            GltfViewerCommand::UseSiblingBbmodelLink => {
                let Some(path) = ui_state.selected_model_path.clone() else {
                    ui_state.bbmodel_link_status = Some("未选择 glTF 模型".to_string());
                    continue;
                };
                let Some(sibling) = sibling_bbmodel_relative_path(&asset_root.0, &path) else {
                    ui_state.bbmodel_link_status = Some("当前 glTF 没有同名 bbmodel".to_string());
                    continue;
                };
                ui_state.bbmodel_link_draft = sibling.clone();
                match save_explicit_link(&asset_root.0, &path, &sibling) {
                    Ok(bbmodel_path) => {
                        ui_state.bbmodel_link_status =
                            Some(format!("已保存同名 bbmodel 关联: {bbmodel_path}"));
                        ui_state.bbmodel_link_model_path = None;
                    }
                    Err(error) => {
                        warn!("failed to save sibling bbmodel link: {error}");
                        ui_state.bbmodel_link_status = Some(error);
                    }
                }
            }
            GltfViewerCommand::ToggleSocketEditor => {
                ui_state.show_socket_editor = !ui_state.show_socket_editor;
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

fn select_model(
    path: &str,
    ui_state: &mut ViewerUiState,
    preview_state: &mut PreviewState,
    preview_camera: &mut Query<&mut game_editor::PreviewCameraController, With<PreviewCamera>>,
) {
    ui_state.selected_model_path = Some(path.to_string());
    preview_state.requested_model_path = Some(path.to_string());
    preview_state.model_size = None;
    ui_state.external_tool_status = None;
    ui_state.bbmodel_link_model_path = None;
    if let Ok(mut preview_camera) = preview_camera.single_mut() {
        preview_camera.set_orbit(default_viewer_orbit());
    }
}

fn reload_model(
    asset_server: &AssetServer,
    preview_state: &mut PreviewState,
    ui_state: &mut ViewerUiState,
    path: String,
) {
    asset_server.reload(GltfAssetLabel::Scene(0).from_asset(path.clone()));
    preview_state.applied_model_path = None;
    preview_state.framed_model_path = None;
    preview_state.requested_model_path = Some(path.clone());
    preview_state.model_size = None;
    preview_state.load_status = crate::state::PreviewLoadStatus::Loading;
    ui_state.external_tool_status = Some(format!("已请求重载: {path}"));
}

fn open_model_in_blockbench(asset_root: &Path, relative_path: &str) -> Result<String, String> {
    let source = resolve_blockbench_source(asset_root, relative_path)?;
    let blockbench_dir = std::env::var_os("CDC_BLOCKBENCH_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(r"D:\Projects\blockbench"));
    let blockbench_dir = blockbench_dir
        .canonicalize()
        .map_err(|error| format!("Blockbench 目录无效 {}: {error}", blockbench_dir.display()))?;
    if !blockbench_dir.is_dir() {
        return Err(format!(
            "Blockbench 目录不存在: {}",
            blockbench_dir.display()
        ));
    }

    let electron = blockbench_dir
        .join("node_modules")
        .join(".bin")
        .join(if cfg!(windows) {
            "electron.cmd"
        } else {
            "electron"
        });
    if !electron.is_file() {
        return Err(format!("找不到 Electron 启动器: {}", electron.display()));
    }

    Command::new(&electron)
        .arg("--remote-debugging-port=9223")
        .arg(".")
        .arg(&source.absolute_path)
        .current_dir(&blockbench_dir)
        .spawn()
        .map_err(|error| format!("启动 Blockbench 失败 {}: {error}", electron.display()))?;

    Ok(source.opened_label())
}

fn open_model_directory(asset_root: &Path, relative_path: &str) -> Result<PathBuf, String> {
    let model_path = asset_root.join(relative_path);
    let model_path = model_path
        .canonicalize()
        .map_err(|error| format!("模型路径无效 {}: {error}", model_path.display()))?;
    if !model_path.is_file() {
        return Err(format!("模型不是文件: {}", model_path.display()));
    }
    let directory = model_path
        .parent()
        .ok_or_else(|| format!("无法解析模型目录: {}", model_path.display()))?
        .to_path_buf();

    if cfg!(windows) {
        Command::new("explorer")
            .arg(&directory)
            .spawn()
            .map_err(|error| format!("打开目录失败 {}: {error}", directory.display()))?;
    } else if cfg!(target_os = "macos") {
        Command::new("open")
            .arg(&directory)
            .spawn()
            .map_err(|error| format!("打开目录失败 {}: {error}", directory.display()))?;
    } else {
        Command::new("xdg-open")
            .arg(&directory)
            .spawn()
            .map_err(|error| format!("打开目录失败 {}: {error}", directory.display()))?;
    }

    Ok(directory)
}
