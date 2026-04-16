use bevy::asset::LoadState;
use bevy::camera::primitives::MeshAabb;
use bevy::log::warn;
use bevy::prelude::*;
use game_editor::{
    apply_preview_orbit_camera, replace_preview_scene, PreviewCameraController, PreviewFloor,
    PreviewOrbitCamera,
};

use crate::state::{PreviewCamera, PreviewLoadStatus, PreviewState, ViewerUiState};

const CAMERA_RADIUS_MIN: f32 = 0.8;
const CAMERA_RADIUS_MAX: f32 = 18.0;
const DEFAULT_MODEL_VIEWPORT_FILL: f32 = 0.5;

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

pub(crate) fn default_viewer_orbit() -> PreviewOrbitCamera {
    PreviewOrbitCamera {
        focus: Vec3::ZERO,
        yaw_radians: -0.55,
        pitch_radians: -0.12,
        radius: 4.4,
    }
}

pub(crate) fn sync_preview_scene_system(
    mut commands: Commands,
    asset_server: Res<AssetServer>,
    mut preview_state: ResMut<PreviewState>,
) {
    if preview_state.requested_model_path == preview_state.applied_model_path {
        return;
    }

    let Some(host_entity) = preview_state.host_entity else {
        return;
    };

    let Some(path) = preview_state.requested_model_path.clone() else {
        if let Some(instance) = preview_state.scene_instance.take() {
            commands.entity(instance).despawn();
        }
        preview_state.scene_handle = None;
        preview_state.applied_model_path = None;
        preview_state.framed_model_path = None;
        preview_state.load_status = PreviewLoadStatus::Idle;
        return;
    };

    let (_, handle) = replace_preview_scene(
        &mut commands,
        &asset_server,
        host_entity,
        &mut preview_state.scene_instance,
        path.clone(),
    );
    preview_state.scene_handle = Some(handle);
    preview_state.applied_model_path = Some(path);
    preview_state.framed_model_path = None;
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
            warn!("gltf viewer failed to load model: {}", error);
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
    let Some(model_path) = preview_state.applied_model_path.as_ref() else {
        return;
    };
    if preview_state.framed_model_path.as_deref() == Some(model_path.as_str()) {
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
    preview_state.framed_model_path = Some(model_path.clone());
}

pub(crate) fn sync_preview_ground_visibility_system(
    ui_state: Res<ViewerUiState>,
    mut floor_query: Query<&mut Visibility, With<PreviewFloor>>,
) {
    let visibility = if ui_state.show_ground {
        Visibility::Visible
    } else {
        Visibility::Hidden
    };
    for mut floor_visibility in &mut floor_query {
        *floor_visibility = visibility;
    }
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

pub(crate) fn paint_axis_gizmo(
    ui: &mut bevy_egui::egui::Ui,
    rect: bevy_egui::egui::Rect,
    orbit: PreviewOrbitCamera,
) {
    let mut camera_transform = Transform::IDENTITY;
    apply_preview_orbit_camera(&mut camera_transform, orbit);

    let right = camera_transform.rotation * Vec3::X;
    let up = camera_transform.rotation * Vec3::Y;
    let forward = camera_transform.rotation * -Vec3::Z;
    let center = bevy_egui::egui::pos2(rect.left() + 38.0, rect.bottom() - 38.0);
    let radius = 16.0;
    let painter = ui.painter();

    painter.circle_filled(
        center,
        24.0,
        bevy_egui::egui::Color32::from_rgba_unmultiplied(18, 21, 28, 196),
    );
    painter.circle_stroke(
        center,
        24.0,
        bevy_egui::egui::Stroke::new(
            1.0,
            bevy_egui::egui::Color32::from_rgba_unmultiplied(210, 215, 224, 64),
        ),
    );

    let mut axes = [
        (
            "X",
            Vec3::X,
            bevy_egui::egui::Color32::from_rgb(210, 61, 56),
        ),
        (
            "Y",
            Vec3::Y,
            bevy_egui::egui::Color32::from_rgb(72, 186, 92),
        ),
        (
            "Z",
            Vec3::Z,
            bevy_egui::egui::Color32::from_rgb(78, 124, 224),
        ),
    ]
    .map(|(label, axis, color)| {
        let screen = bevy_egui::egui::vec2(axis.dot(right), -axis.dot(up)) * radius;
        let depth = axis.dot(forward);
        (depth, label, color, center + screen)
    });
    axes.sort_by(|left, right| {
        left.0
            .partial_cmp(&right.0)
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    for (_, label, color, end) in axes {
        painter.line_segment([center, end], bevy_egui::egui::Stroke::new(2.0, color));
        painter.circle_filled(end, 3.0, color);
        painter.text(
            end + bevy_egui::egui::vec2(6.0, 0.0),
            bevy_egui::egui::Align2::LEFT_CENTER,
            label,
            bevy_egui::egui::FontId::new(10.0, bevy_egui::egui::FontFamily::Proportional),
            color,
        );
    }
}
