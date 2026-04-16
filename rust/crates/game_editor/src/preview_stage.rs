use bevy::camera::{CameraOutputMode, ClearColorConfig};
use bevy::prelude::*;
use bevy::render::render_resource::BlendState;
use bevy_egui::{EguiGlobalSettings, PrimaryEguiContext};

use crate::{
    spawn_preview_floor, spawn_preview_light_rig, spawn_preview_scene_host, PreviewCameraController,
};

#[derive(Debug, Clone)]
pub struct PreviewStageConfig {
    pub clear_color: Color,
    pub projection: Projection,
    pub camera_transform: Transform,
    pub controller: PreviewCameraController,
    pub floor_size: Vec2,
    pub floor_color: Color,
    pub spawn_scene_host: bool,
}

#[derive(Debug, Clone, Copy)]
pub struct PreviewStageEntities {
    pub preview_camera: Entity,
    pub egui_camera: Entity,
    pub floor: Entity,
    pub scene_host: Option<Entity>,
}

pub fn setup_preview_stage(
    commands: &mut Commands,
    egui_global_settings: &mut EguiGlobalSettings,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    config: &PreviewStageConfig,
) -> PreviewStageEntities {
    egui_global_settings.auto_create_primary_context = false;

    let scene_host = config
        .spawn_scene_host
        .then(|| spawn_preview_scene_host(commands));
    spawn_preview_light_rig(commands);
    let floor = spawn_preview_floor(
        commands,
        meshes,
        materials,
        config.floor_size,
        config.floor_color,
    );

    let preview_camera = commands
        .spawn((
            Camera3d::default(),
            Camera {
                order: 0,
                clear_color: ClearColorConfig::Custom(config.clear_color),
                ..default()
            },
            config.projection.clone(),
            config.camera_transform,
            config.controller,
        ))
        .id();
    let egui_camera = commands
        .spawn((
            PrimaryEguiContext,
            Camera2d,
            Camera {
                order: 1,
                output_mode: CameraOutputMode::Write {
                    blend_state: Some(BlendState::ALPHA_BLENDING),
                    clear_color: ClearColorConfig::None,
                },
                clear_color: ClearColorConfig::Custom(Color::NONE),
                ..default()
            },
        ))
        .id();

    PreviewStageEntities {
        preview_camera,
        egui_camera,
        floor,
        scene_host,
    }
}
