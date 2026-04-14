use bevy::input::mouse::{MouseScrollUnit, MouseWheel};
use bevy::prelude::*;
use bevy_egui::input::EguiWantsInput;
use game_bevy::world_render::{apply_world_render_camera_projection, WorldRenderConfig};

use crate::state::{EditorCamera, EditorState, EditorUiState, MiddleClickState, OrbitCameraState};

const TEMP_CAMERA_YAW_OFFSET_DEGREES: f32 = 45.0;
const CAMERA_DISTANCE_MIN: f32 = 6.0;
const CAMERA_DISTANCE_MAX: f32 = 160.0;
pub(crate) const CAMERA_PAN_SPEED_MULTIPLIER_MIN: f32 = 0.25;
pub(crate) const CAMERA_PAN_SPEED_MULTIPLIER_MAX: f32 = 4.0;

pub(crate) fn camera_input_system(
    time: Res<Time>,
    window: Single<&Window>,
    camera_query: Single<(&Camera, &Transform), With<EditorCamera>>,
    keys: Res<ButtonInput<KeyCode>>,
    buttons: Res<ButtonInput<MouseButton>>,
    mut wheel_events: MessageReader<MouseWheel>,
    mut orbit_camera: ResMut<OrbitCameraState>,
    ui_state: Res<EditorUiState>,
    mut middle_click_state: ResMut<MiddleClickState>,
    egui_wants_input: Res<EguiWantsInput>,
    mut editor: ResMut<EditorState>,
) {
    let wants_keyboard_input = egui_wants_input.wants_any_keyboard_input();
    let wants_pointer_input = egui_wants_input.wants_any_pointer_input();

    if wants_keyboard_input {
        orbit_camera.yaw_offset = 0.0;
    } else if orbit_camera.is_top_down {
        orbit_camera.yaw_offset = 0.0;
    } else if keys.pressed(KeyCode::KeyQ) && !keys.pressed(KeyCode::KeyE) {
        orbit_camera.yaw_offset = -TEMP_CAMERA_YAW_OFFSET_DEGREES.to_radians();
    } else if keys.pressed(KeyCode::KeyE) && !keys.pressed(KeyCode::KeyQ) {
        orbit_camera.yaw_offset = TEMP_CAMERA_YAW_OFFSET_DEGREES.to_radians();
    } else {
        orbit_camera.yaw_offset = 0.0;
    }

    if !wants_keyboard_input && keys.just_pressed(KeyCode::KeyT) {
        orbit_camera.is_top_down = !orbit_camera.is_top_down;
        orbit_camera.yaw_offset = 0.0;
        editor.status = if orbit_camera.is_top_down {
            "Camera switched to top-down view.".to_string()
        } else {
            "Camera restored to perspective view.".to_string()
        };
    }

    if !wants_keyboard_input {
        let movement = gather_keyboard_movement(&keys);
        if movement != Vec2::ZERO {
            let move_speed = camera_pan_speed(
                orbit_camera.active_distance(),
                ui_state.camera_pan_speed_multiplier,
            ) * time.delta_secs();
            let world_delta = camera_pan_delta(&orbit_camera, movement.normalize(), move_speed);
            orbit_camera.target += world_delta;
        }
    }

    if wants_pointer_input {
        for _ in wheel_events.read() {}
        middle_click_state.drag_anchor_world = None;
    } else {
        for event in wheel_events.read() {
            let unit_scale = match event.unit {
                MouseScrollUnit::Line => 1.0,
                MouseScrollUnit::Pixel => 0.1,
            };
            let next_distance = (*orbit_camera.active_distance_mut() - event.y * unit_scale * 1.8)
                .clamp(CAMERA_DISTANCE_MIN, CAMERA_DISTANCE_MAX);
            *orbit_camera.active_distance_mut() = next_distance;
        }
    }

    if !buttons.pressed(MouseButton::Middle) {
        middle_click_state.drag_anchor_world = None;
        return;
    }

    if wants_pointer_input {
        middle_click_state.drag_anchor_world = None;
        return;
    }

    let Some(cursor_position) = window.cursor_position() else {
        middle_click_state.drag_anchor_world = None;
        return;
    };

    let (camera, camera_transform) = *camera_query;
    let camera_transform = GlobalTransform::from(*camera_transform);
    let Ok(ray) = camera.viewport_to_world(&camera_transform, cursor_position) else {
        middle_click_state.drag_anchor_world = None;
        return;
    };
    let Some(current_point) = ray_point_on_horizontal_plane(ray, 0.0) else {
        middle_click_state.drag_anchor_world = None;
        return;
    };
    let current_world = Vec2::new(current_point.x, current_point.z);

    if buttons.just_pressed(MouseButton::Middle) || middle_click_state.drag_anchor_world.is_none() {
        middle_click_state.drag_anchor_world = Some(current_world);
        return;
    }

    let Some(anchor_world) = middle_click_state.drag_anchor_world else {
        return;
    };
    let pan_delta = anchor_world - current_world;
    if pan_delta.length_squared() <= f32::EPSILON {
        return;
    }

    orbit_camera.target += Vec3::new(pan_delta.x, 0.0, pan_delta.y);
}

pub(crate) fn apply_camera_transform_system(
    orbit_camera: Res<OrbitCameraState>,
    render_config: Res<WorldRenderConfig>,
    mut cameras: Query<(&mut Projection, &mut Transform), With<EditorCamera>>,
) {
    let Ok((mut projection, mut transform)) = cameras.single_mut() else {
        return;
    };

    if let Projection::Perspective(perspective) = &mut *projection {
        apply_world_render_camera_projection(perspective, *render_config);
    }

    let pitch = if orbit_camera.is_top_down {
        90.0_f32.to_radians()
    } else {
        orbit_camera.base_pitch
    };
    let yaw = if orbit_camera.is_top_down {
        0.0
    } else {
        orbit_camera.base_yaw + orbit_camera.yaw_offset
    };
    let distance = if orbit_camera.is_top_down {
        orbit_camera.top_down_distance
    } else {
        orbit_camera.perspective_distance
    };
    let horizontal = distance * pitch.cos();
    let eye = orbit_camera.target
        + Vec3::new(
            horizontal * yaw.sin(),
            distance * pitch.sin(),
            -horizontal * yaw.cos(),
        );

    transform.translation = eye;
    transform.look_at(
        orbit_camera.target,
        if orbit_camera.is_top_down {
            Vec3::Z
        } else {
            Vec3::Y
        },
    );
}

fn gather_keyboard_movement(keys: &ButtonInput<KeyCode>) -> Vec2 {
    let mut movement = Vec2::ZERO;
    if keys.pressed(KeyCode::KeyW) {
        movement.y += 1.0;
    }
    if keys.pressed(KeyCode::KeyS) {
        movement.y -= 1.0;
    }
    if keys.pressed(KeyCode::KeyD) {
        movement.x += 1.0;
    }
    if keys.pressed(KeyCode::KeyA) {
        movement.x -= 1.0;
    }
    movement
}

fn camera_pan_speed(distance: f32, multiplier: f32) -> f32 {
    (distance * 0.45 * multiplier).clamp(4.0, 72.0)
}

fn camera_pan_delta(orbit_camera: &OrbitCameraState, movement: Vec2, move_speed: f32) -> Vec3 {
    if orbit_camera.is_top_down {
        return Vec3::new(movement.x, 0.0, movement.y) * move_speed;
    }

    let yaw = orbit_camera.base_yaw + orbit_camera.yaw_offset;
    let forward = Vec3::new(yaw.sin(), 0.0, yaw.cos());
    let right = Vec3::new(-forward.z, 0.0, forward.x);
    (forward * movement.y + right * movement.x) * move_speed
}

pub(crate) fn ray_point_on_horizontal_plane(ray: Ray3d, plane_height: f32) -> Option<Vec3> {
    let plane_origin = Vec3::new(0.0, plane_height, 0.0);
    ray.plane_intersection_point(plane_origin, InfinitePlane3d::new(Vec3::Y))
}
