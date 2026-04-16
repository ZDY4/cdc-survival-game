use std::path::PathBuf;

use bevy::prelude::*;

#[derive(States, Debug, Clone, Copy, PartialEq, Eq, Hash, Default)]
pub(crate) enum ViewerAppState {
    #[default]
    Loading,
    Ready,
}

#[derive(Resource, Debug, Clone)]
pub(crate) struct ViewerAssetRoot(pub(crate) PathBuf);

#[derive(Resource, Debug, Clone)]
pub(crate) struct ViewerUiState {
    pub(crate) search_text: String,
    pub(crate) selected_model_path: Option<String>,
    pub(crate) show_ground: bool,
}

impl Default for ViewerUiState {
    fn default() -> Self {
        Self {
            search_text: String::new(),
            selected_model_path: None,
            show_ground: false,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum PreviewLoadStatus {
    Idle,
    Loading,
    Ready,
    Failed(String),
}

impl Default for PreviewLoadStatus {
    fn default() -> Self {
        Self::Idle
    }
}

impl PreviewLoadStatus {
    pub(crate) fn label(&self) -> String {
        match self {
            Self::Idle => "未选择模型".to_string(),
            Self::Loading => "加载中…".to_string(),
            Self::Ready => "已加载".to_string(),
            Self::Failed(error) => format!("加载失败: {error}"),
        }
    }
}

#[derive(Resource, Debug, Default)]
pub(crate) struct PreviewState {
    pub(crate) host_entity: Option<Entity>,
    pub(crate) scene_instance: Option<Entity>,
    pub(crate) scene_handle: Option<Handle<Scene>>,
    pub(crate) requested_model_path: Option<String>,
    pub(crate) applied_model_path: Option<String>,
    pub(crate) framed_model_path: Option<String>,
    pub(crate) load_status: PreviewLoadStatus,
}

#[derive(Resource, Debug, Clone, Default)]
pub(crate) struct ViewerUiStyleState {
    pub(crate) initialized: bool,
}

#[derive(Component)]
pub(crate) struct PreviewCamera;
