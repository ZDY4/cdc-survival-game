use bevy::camera::{CameraOutputMode, ClearColorConfig};
use bevy::prelude::*;
use bevy::render::render_resource::BlendState;
use bevy_egui::{EguiGlobalSettings, PrimaryEguiContext};

pub fn setup_primary_egui_context_camera(
    commands: &mut Commands,
    egui_global_settings: &mut EguiGlobalSettings,
) -> Entity {
    egui_global_settings.auto_create_primary_context = false;
    commands
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
        .id()
}
