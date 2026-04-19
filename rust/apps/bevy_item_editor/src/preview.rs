use bevy::asset::LoadState;
use bevy::camera::primitives::MeshAabb;
use bevy::log::{info, warn};
use bevy::prelude::*;
use game_bevy::{resolve_item_preview_asset_path, resolve_standalone_item_preview};
use game_editor::{replace_preview_scene, PreviewCameraController, PreviewOrbitCamera};

use crate::state::EditorState;

pub(crate) const PREVIEW_BG: Color = Color::srgb(0.095, 0.105, 0.125);
pub(crate) const CAMERA_RADIUS_MIN: f32 = 0.8;
pub(crate) const CAMERA_RADIUS_MAX: f32 = 18.0;
// Keep framing aligned with bevy_gltf_viewer so standalone item previews land at the
// same visual scale when they first appear.
const DEFAULT_MODEL_VIEWPORT_FILL: f32 = 0.5;

#[derive(Component)]
pub(crate) struct PreviewCamera;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum PreviewLoadStatus {
    Idle,
    Missing(String),
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
            Self::Idle => "未选择物品".to_string(),
            Self::Missing(message) => message.clone(),
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
    pub(crate) requested_asset_path: Option<String>,
    pub(crate) requested_transform: Transform,
    pub(crate) requested_item_id: Option<u32>,
    pub(crate) applied_asset_path: Option<String>,
    pub(crate) framed_asset_path: Option<String>,
    pub(crate) item_label: String,
    pub(crate) load_status: PreviewLoadStatus,
}

#[derive(Debug, Clone, Copy)]
struct SceneWorldBounds {
    min: Vec3,
    max: Vec3,
}

impl SceneWorldBounds {
    fn from_point(point: Vec3) -> Self {
        Self {
            min: point,
            max: point,
        }
    }

    fn include_point(&mut self, point: Vec3) {
        self.min = self.min.min(point);
        self.max = self.max.max(point);
    }

    fn center(self) -> Vec3 {
        (self.min + self.max) * 0.5
    }

    fn size(self) -> Vec3 {
        self.max - self.min
    }
}

pub(crate) fn default_preview_orbit() -> PreviewOrbitCamera {
    PreviewOrbitCamera {
        focus: Vec3::ZERO,
        yaw_radians: -0.55,
        pitch_radians: -0.12,
        radius: 4.4,
    }
}

pub(crate) fn sync_preview_request_from_selection(
    editor: Res<EditorState>,
    mut preview_state: ResMut<PreviewState>,
    mut preview_camera: Single<&mut PreviewCameraController, With<PreviewCamera>>,
) {
    let Some(document) = editor.selected_document() else {
        if preview_state.requested_item_id.is_some() {
            preview_state.requested_item_id = None;
            preview_state.requested_asset_path = None;
            preview_state.item_label.clear();
            preview_state.load_status = PreviewLoadStatus::Idle;
        }
        return;
    };

    let Some(preview) = resolve_standalone_item_preview(&document.definition) else {
        preview_state.requested_item_id = Some(document.definition.id);
        preview_state.requested_asset_path = None;
        preview_state.item_label =
            format!("{} · #{}", document.definition.name, document.definition.id);
        preview_state.load_status =
            PreviewLoadStatus::Missing("该物品没有可解析的预览模型".to_string());
        return;
    };
    let next_asset_path = resolve_item_preview_asset_path(&preview.visual_asset);

    if preview_state.requested_item_id == Some(document.definition.id)
        && preview_state.requested_asset_path == next_asset_path
    {
        return;
    }

    preview_state.requested_item_id = Some(document.definition.id);
    preview_state.item_label =
        format!("{} · #{}", document.definition.name, document.definition.id);
    preview_state.requested_transform = transform_from_preview(&preview.preview_transform);
    match next_asset_path {
        Some(asset_path) => {
            preview_state.requested_asset_path = Some(asset_path);
            preview_state.load_status = PreviewLoadStatus::Loading;
        }
        None => {
            preview_state.requested_asset_path = None;
            preview_state.load_status =
                PreviewLoadStatus::Missing(format!("无可预览模型：{}", preview.visual_asset));
        }
    }

    preview_camera.set_orbit(default_preview_orbit());
}

pub(crate) fn sync_preview_scene_system(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut preview_state: ResMut<PreviewState>,
) {
    if preview_state.requested_asset_path == preview_state.applied_asset_path {
        return;
    }

    let Some(host_entity) = preview_state.host_entity else {
        return;
    };

    let Some(path) = preview_state.requested_asset_path.clone() else {
        if let Some(instance) = preview_state.scene_instance.take() {
            commands.entity(instance).despawn();
        }
        preview_state.scene_handle = None;
        preview_state.applied_asset_path = None;
        preview_state.framed_asset_path = None;
        return;
    };

    info!("item editor selected preview asset: {path}");
    let (instance, handle) = replace_preview_scene(
        &mut commands,
        &asset_server,
        host_entity,
        &mut preview_state.scene_instance,
        path.clone(),
    );
    commands
        .entity(instance)
        .insert(preview_state.requested_transform);
    preview_state.scene_handle = Some(handle);
    preview_state.applied_asset_path = Some(path);
    preview_state.framed_asset_path = None;
    preview_state.load_status = PreviewLoadStatus::Loading;
}

pub(crate) fn refresh_preview_load_status_system(
    asset_server: Res<AssetServer>,
    mut preview_state: ResMut<PreviewState>,
) {
    let Some(handle) = preview_state.scene_handle.as_ref() else {
        return;
    };
    let Some(load_state) = asset_server.get_load_state(handle) else {
        return;
    };

    match load_state {
        LoadState::Failed(error) => {
            warn!("item editor failed to load preview asset: {}", error);
            preview_state.load_status = PreviewLoadStatus::Failed(error.to_string());
        }
        LoadState::Loaded => {
            if asset_server
                .recursive_dependency_load_state(handle)
                .is_loaded()
            {
                preview_state.load_status = PreviewLoadStatus::Ready;
            } else {
                preview_state.load_status = PreviewLoadStatus::Loading;
            }
        }
        _ => {
            preview_state.load_status = PreviewLoadStatus::Loading;
        }
    }
}

pub(crate) fn frame_loaded_scene_system(
    mut preview_state: ResMut<PreviewState>,
    mut preview_camera: Single<&mut PreviewCameraController, With<PreviewCamera>>,
    children_query: Query<&Children>,
    mesh_query: Query<(&Mesh3d, &GlobalTransform)>,
    meshes: Res<Assets<Mesh>>,
) {
    if preview_state.load_status != PreviewLoadStatus::Ready {
        return;
    }
    let Some(asset_path) = preview_state.applied_asset_path.as_ref() else {
        return;
    };
    if preview_state.framed_asset_path.as_deref() == Some(asset_path.as_str()) {
        return;
    }
    let Some(scene_root) = preview_state.scene_instance else {
        return;
    };

    let Some(bounds) = scene_world_bounds(scene_root, &children_query, &mesh_query, &meshes) else {
        return;
    };

    let size = bounds.size();
    let half_extents = size * 0.5;
    let vertical_half_fov = std::f32::consts::FRAC_PI_4 * 0.5;
    let target_fill = DEFAULT_MODEL_VIEWPORT_FILL.clamp(0.1, 0.95);
    let radius_y = half_extents.y.max(0.35) / (vertical_half_fov.tan() * target_fill);
    let radius_z = half_extents.z.max(0.35) * 1.35;
    let radius = radius_y
        .max(radius_z)
        .clamp(CAMERA_RADIUS_MIN, CAMERA_RADIUS_MAX);

    preview_camera.set_orbit(PreviewOrbitCamera {
        focus: bounds.center(),
        yaw_radians: -0.55,
        pitch_radians: -0.12,
        radius,
    });
    preview_state.framed_asset_path = Some(asset_path.clone());
}

fn scene_world_bounds(
    root: Entity,
    children_query: &Query<&Children>,
    mesh_query: &Query<(&Mesh3d, &GlobalTransform)>,
    meshes: &Assets<Mesh>,
) -> Option<SceneWorldBounds> {
    let mut stack = vec![root];
    let mut bounds: Option<SceneWorldBounds> = None;

    while let Some(entity) = stack.pop() {
        if let Ok((mesh_handle, transform)) = mesh_query.get(entity) {
            if let Some(mesh) = meshes.get(&mesh_handle.0) {
                if let Some(mesh_aabb) = mesh.compute_aabb() {
                    let center = Vec3::from(mesh_aabb.center);
                    let half_extents = Vec3::from(mesh_aabb.half_extents);
                    let affine = transform.affine();
                    for corner in [
                        Vec3::new(-half_extents.x, -half_extents.y, -half_extents.z),
                        Vec3::new(-half_extents.x, -half_extents.y, half_extents.z),
                        Vec3::new(-half_extents.x, half_extents.y, -half_extents.z),
                        Vec3::new(-half_extents.x, half_extents.y, half_extents.z),
                        Vec3::new(half_extents.x, -half_extents.y, -half_extents.z),
                        Vec3::new(half_extents.x, -half_extents.y, half_extents.z),
                        Vec3::new(half_extents.x, half_extents.y, -half_extents.z),
                        Vec3::new(half_extents.x, half_extents.y, half_extents.z),
                    ] {
                        let world_point = affine.transform_point3(center + corner);
                        match &mut bounds {
                            Some(world_bounds) => world_bounds.include_point(world_point),
                            None => bounds = Some(SceneWorldBounds::from_point(world_point)),
                        }
                    }
                }
            }
        }

        if let Ok(children) = children_query.get(entity) {
            for child in children.iter() {
                stack.push(child);
            }
        }
    }

    bounds
}

fn transform_from_preview(preview: &game_data::PreviewTransform) -> Transform {
    let scale = Vec3::new(
        preview.scale.x.max(0.01),
        preview.scale.y.max(0.01),
        preview.scale.z.max(0.01),
    );
    Transform {
        translation: Vec3::new(preview.offset.x, preview.offset.y, preview.offset.z),
        rotation: Quat::from_euler(
            EulerRot::XYZ,
            preview.rotation_degrees.x.to_radians(),
            preview.rotation_degrees.y.to_radians(),
            preview.rotation_degrees.z.to_radians(),
        ),
        scale,
    }
}
