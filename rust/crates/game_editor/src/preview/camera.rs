use bevy::camera::Viewport;
use bevy::ecs::message::MessageReader;
use bevy::input::mouse::{MouseMotion, MouseWheel};
use bevy::prelude::*;

#[derive(Debug, Clone, Copy, Default)]
pub struct PreviewViewportRect {
    pub min_x: f32,
    pub min_y: f32,
    pub width: f32,
    pub height: f32,
}

impl PreviewViewportRect {
    pub fn contains(self, cursor: Vec2) -> bool {
        cursor.x >= self.min_x
            && cursor.x <= self.min_x + self.width
            && cursor.y >= self.min_y
            && cursor.y <= self.min_y + self.height
    }
}

#[derive(Debug, Clone, Copy)]
pub struct PreviewOrbitCamera {
    pub focus: Vec3,
    pub yaw_radians: f32,
    pub pitch_radians: f32,
    pub radius: f32,
}

impl Default for PreviewOrbitCamera {
    fn default() -> Self {
        Self {
            focus: Vec3::new(0.0, 0.95, 0.0),
            yaw_radians: -0.55,
            pitch_radians: -0.2,
            radius: 3.6,
        }
    }
}

#[derive(Component, Debug, Clone, Copy)]
pub struct PreviewCameraController {
    pub orbit: PreviewOrbitCamera,
    pub focus_anchor: Vec3,
    pub viewport_rect: Option<PreviewViewportRect>,
    pub pitch_min: f32,
    pub pitch_max: f32,
    pub radius_min: f32,
    pub radius_max: f32,
    pub rotate_speed_x: f32,
    pub rotate_speed_y: f32,
    pub zoom_speed: f32,
    pub pan_speed: f32,
    pub pan_max_focus_offset: f32,
}

impl Default for PreviewCameraController {
    fn default() -> Self {
        let orbit = PreviewOrbitCamera::default();
        Self {
            orbit,
            focus_anchor: orbit.focus,
            viewport_rect: None,
            pitch_min: -1.2,
            pitch_max: 0.72,
            radius_min: 0.5,
            radius_max: 24.0,
            rotate_speed_x: 0.012,
            rotate_speed_y: 0.008,
            zoom_speed: 0.2,
            pan_speed: 1.0,
            pan_max_focus_offset: 1.5,
        }
    }
}

impl PreviewCameraController {
    pub fn set_orbit(&mut self, orbit: PreviewOrbitCamera) {
        self.orbit = orbit;
        self.focus_anchor = orbit.focus;
    }

    fn clamp_focus(&mut self) {
        let offset = self.orbit.focus - self.focus_anchor;
        let max_offset = self.pan_max_focus_offset.max(0.0);
        if offset.length_squared() > max_offset * max_offset && offset != Vec3::ZERO {
            self.orbit.focus = self.focus_anchor + offset.normalize() * max_offset;
        }
    }
}

pub fn apply_preview_orbit_camera(transform: &mut Transform, orbit: PreviewOrbitCamera) {
    let yaw = Quat::from_rotation_y(orbit.yaw_radians);
    let pitch = Quat::from_rotation_x(orbit.pitch_radians);
    let offset = yaw * pitch * Vec3::new(0.0, 0.0, orbit.radius.max(0.5));
    *transform = Transform::from_translation(orbit.focus + offset).looking_at(orbit.focus, Vec3::Y);
}

pub fn preview_camera_input_system(
    mouse_buttons: Res<ButtonInput<MouseButton>>,
    mut mouse_motion: MessageReader<MouseMotion>,
    mut mouse_wheel: MessageReader<MouseWheel>,
    window: Single<&Window>,
    mut controller_query: Query<(&mut PreviewCameraController, Option<&Projection>)>,
) {
    let Ok((mut controller, projection)) = controller_query.single_mut() else {
        mouse_motion.clear();
        mouse_wheel.clear();
        return;
    };
    let Some(viewport) = controller.viewport_rect else {
        return;
    };
    let Some(cursor) = window.cursor_position() else {
        return;
    };
    if !viewport.contains(cursor) {
        mouse_motion.clear();
        mouse_wheel.clear();
        return;
    }

    let pitch_min = controller.pitch_min.min(controller.pitch_max);
    let pitch_max = controller.pitch_min.max(controller.pitch_max);
    let radius_min = controller.radius_min.min(controller.radius_max);
    let radius_max = controller.radius_min.max(controller.radius_max);

    let total_mouse_delta = mouse_motion
        .read()
        .fold(Vec2::ZERO, |acc, event| acc + event.delta);

    if mouse_buttons.pressed(MouseButton::Left) {
        controller.orbit.yaw_radians -= total_mouse_delta.x * controller.rotate_speed_x;
        controller.orbit.pitch_radians = (controller.orbit.pitch_radians
            - total_mouse_delta.y * controller.rotate_speed_y)
            .clamp(pitch_min, pitch_max);
    } else if mouse_buttons.pressed(MouseButton::Right) {
        let mut transform = Transform::IDENTITY;
        apply_preview_orbit_camera(&mut transform, controller.orbit);
        let right = transform.right().as_vec3();
        let up = transform.up().as_vec3();
        let viewport_width = viewport.width.max(1.0);
        let viewport_height = viewport.height.max(1.0);
        let view_height = match projection {
            Some(Projection::Perspective(perspective)) => {
                2.0 * controller.orbit.radius.max(radius_min) * (perspective.fov * 0.5).tan()
            }
            Some(Projection::Orthographic(orthographic)) => orthographic.area.height(),
            _ => controller.orbit.radius.max(radius_min) * 2.0,
        };
        let view_width = view_height * (viewport_width / viewport_height);
        let pan_delta = right * (-total_mouse_delta.x / viewport_width * view_width)
            + up * (total_mouse_delta.y / viewport_height * view_height);
        let pan_speed = controller.pan_speed;
        controller.orbit.focus += pan_delta * pan_speed;
        controller.clamp_focus();
    }

    for event in mouse_wheel.read() {
        controller.orbit.radius = (controller.orbit.radius - event.y * controller.zoom_speed)
            .clamp(radius_min, radius_max);
    }
}

pub fn preview_camera_sync_system(
    window: Single<&Window>,
    mut camera_query: Query<(&mut Camera, &mut Transform, &PreviewCameraController)>,
) {
    for (mut camera, mut transform, controller) in &mut camera_query {
        camera.viewport = controller.viewport_rect.map(|rect| {
            let scale_factor = window.scale_factor() as f32;
            let min_x = rect.min_x * scale_factor;
            let min_y = rect.min_y * scale_factor;
            let width = rect.width * scale_factor;
            let height = rect.height * scale_factor;
            let max_width = window.physical_width() as f32;
            let max_height = window.physical_height() as f32;
            let physical_position = UVec2::new(
                min_x.clamp(0.0, (max_width - 1.0).max(0.0)) as u32,
                min_y.clamp(0.0, (max_height - 1.0).max(0.0)) as u32,
            );
            let physical_size = UVec2::new(
                width.clamp(1.0, (max_width - physical_position.x as f32).max(1.0)) as u32,
                height.clamp(1.0, (max_height - physical_position.y as f32).max(1.0)) as u32,
            );
            Viewport {
                physical_position,
                physical_size,
                depth: 0.0..1.0,
            }
        });
        apply_preview_orbit_camera(&mut transform, controller.orbit);
    }
}
