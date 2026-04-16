//! 预览相机模式。
//! 负责自由视角 / 游戏固定相机的切换、默认构图和输入能力同步。

use std::f32::consts::{FRAC_PI_4, PI};

use bevy::prelude::*;
use game_bevy::world_render::WorldRenderConfig;
use game_data::ResolvedCharacterAppearancePreview;
use game_editor::{PreviewCameraController, PreviewOrbitCamera};

use crate::preview::{CAMERA_RADIUS_MAX, CAMERA_RADIUS_MIN};

pub(crate) const FREE_PREVIEW_FOV: f32 = FRAC_PI_4;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum PreviewCameraMode {
    #[default]
    Free,
    GameFixed,
}

impl PreviewCameraMode {
    pub(crate) fn toggle_button_label(self) -> &'static str {
        match self {
            Self::Free => "切换到游戏固定相机",
            Self::GameFixed => "切换到自由视角",
        }
    }

    pub(crate) fn interaction_hint(self) -> &'static str {
        match self {
            Self::Free => "左键拖拽旋转，右键平移，滚轮缩放，右侧页签中可直接调整各装备槽位。",
            Self::GameFixed => "已对齐游戏固定相机；滚轮可调远近，拖拽已禁用。",
        }
    }

    pub(crate) fn badge_text(self) -> &'static str {
        match self {
            Self::Free => "自由视角",
            Self::GameFixed => "游戏固定相机",
        }
    }
}

#[derive(Resource, Debug, Clone, Default)]
pub(crate) struct PreviewCameraModeState {
    pub(crate) mode: PreviewCameraMode,
}

pub(crate) fn sync_preview_camera_mode(
    camera_mode: &PreviewCameraModeState,
    preview_camera: &mut PreviewCameraController,
    preview_projection: &mut Projection,
) {
    let (allow_rotate, allow_pan, allow_zoom) = match camera_mode.mode {
        PreviewCameraMode::Free => (true, true, true),
        PreviewCameraMode::GameFixed => (false, false, true),
    };
    preview_camera.allow_rotate = allow_rotate;
    preview_camera.allow_pan = allow_pan;
    preview_camera.allow_zoom = allow_zoom;

    if let Projection::Perspective(perspective) = preview_projection {
        perspective.fov = match camera_mode.mode {
            PreviewCameraMode::Free => FREE_PREVIEW_FOV,
            PreviewCameraMode::GameFixed => WorldRenderConfig::default().camera_fov_radians(),
        };
    }
}

pub(crate) fn reset_active_preview_camera(
    camera_mode: &PreviewCameraModeState,
    preview: Option<&ResolvedCharacterAppearancePreview>,
    preview_camera: &mut PreviewCameraController,
    preview_projection: &mut Projection,
) {
    preview_camera.set_orbit(default_orbit_for_mode(camera_mode.mode, preview));
    sync_preview_camera_mode(camera_mode, preview_camera, preview_projection);
}

pub(crate) fn default_orbit_for_mode(
    mode: PreviewCameraMode,
    preview: Option<&ResolvedCharacterAppearancePreview>,
) -> PreviewOrbitCamera {
    match mode {
        PreviewCameraMode::Free => preview
            .map(free_orbit_for_preview)
            .unwrap_or_else(PreviewOrbitCamera::default),
        PreviewCameraMode::GameFixed => preview
            .map(|preview| fixed_orbit_for_preview(preview, WorldRenderConfig::default()))
            .unwrap_or_else(|| fixed_default_orbit(WorldRenderConfig::default())),
    }
}

pub(crate) fn free_orbit_for_preview(
    preview: &ResolvedCharacterAppearancePreview,
) -> PreviewOrbitCamera {
    PreviewOrbitCamera {
        focus: Vec3::new(0.0, preview.preview_bounds.focus_y, 0.0),
        yaw_radians: -0.55,
        pitch_radians: -0.2,
        radius: (preview.preview_bounds.radius * 2.9).clamp(CAMERA_RADIUS_MIN, CAMERA_RADIUS_MAX),
    }
}

pub(crate) fn fixed_orbit_for_preview(
    preview: &ResolvedCharacterAppearancePreview,
    render_config: WorldRenderConfig,
) -> PreviewOrbitCamera {
    PreviewOrbitCamera {
        focus: Vec3::new(0.0, preview.preview_bounds.focus_y, 0.0),
        yaw_radians: PI - render_config.camera_yaw_radians(),
        pitch_radians: -render_config.camera_pitch_radians(),
        radius: ((preview.preview_bounds.height * 0.5
            / (render_config.camera_fov_radians() * 0.5).tan())
            * 1.1)
            .clamp(CAMERA_RADIUS_MIN, CAMERA_RADIUS_MAX),
    }
}

fn fixed_default_orbit(render_config: WorldRenderConfig) -> PreviewOrbitCamera {
    PreviewOrbitCamera {
        focus: PreviewOrbitCamera::default().focus,
        yaw_radians: PI - render_config.camera_yaw_radians(),
        pitch_radians: -render_config.camera_pitch_radians(),
        radius: PreviewOrbitCamera::default()
            .radius
            .clamp(CAMERA_RADIUS_MIN, CAMERA_RADIUS_MAX),
    }
}
