use bevy::prelude::*;
use game_data::GridCoord;

use crate::geometry::GridBounds;
use crate::state::ViewerRenderConfig;

pub(crate) fn level_base_height(level: i32, grid_size: f32) -> f32 {
    level as f32 * grid_size
}

pub(crate) fn level_plane_height(level: i32, grid_size: f32) -> f32 {
    level_base_height(level, grid_size) + grid_size * 0.5
}

pub(crate) fn pick_grid_from_ray(
    ray: Ray3d,
    level: i32,
    grid_size: f32,
    plane_height: f32,
) -> Option<GridCoord> {
    let point = ray_point_on_horizontal_plane(ray, plane_height)?;
    Some(GridCoord::new(
        (point.x / grid_size).floor() as i32,
        level,
        (point.z / grid_size).floor() as i32,
    ))
}

pub(crate) fn ray_point_on_horizontal_plane(ray: Ray3d, plane_height: f32) -> Option<Vec3> {
    let plane_origin = Vec3::new(0.0, plane_height, 0.0);
    ray.plane_intersection_point(plane_origin, InfinitePlane3d::new(Vec3::Y))
}

#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn camera_pan_delta_from_ground_drag(
    previous_ray: Ray3d,
    current_ray: Ray3d,
    plane_height: f32,
) -> Option<Vec2> {
    let previous_point = ray_point_on_horizontal_plane(previous_ray, plane_height)?;
    let current_point = ray_point_on_horizontal_plane(current_ray, plane_height)?;
    Some(Vec2::new(
        previous_point.x - current_point.x,
        previous_point.z - current_point.z,
    ))
}

pub(crate) fn camera_focus_point(
    bounds: GridBounds,
    current_level: i32,
    grid_size: f32,
    pan_offset: Vec2,
) -> Vec3 {
    let center_x = (bounds.min_x + bounds.max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (bounds.min_z + bounds.max_z + 1) as f32 * grid_size * 0.5;
    Vec3::new(
        center_x + pan_offset.x,
        level_plane_height(current_level, grid_size),
        center_z + pan_offset.y,
    )
}

pub(crate) fn camera_world_distance(
    bounds: GridBounds,
    viewport_width: f32,
    viewport_height: f32,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> f32 {
    let world_width = (bounds.max_x - bounds.min_x + 1).max(1) as f32 * grid_size
        + render_config.camera_distance_padding_world;
    let world_depth = (bounds.max_z - bounds.min_z + 1).max(1) as f32 * grid_size
        + render_config.camera_distance_padding_world;
    let (horizontal_fov, vertical_fov) =
        perspective_camera_fovs(viewport_width, viewport_height, render_config);
    let zoom = render_config.zoom_factor.max(0.1);
    let half_visible_width = (world_width / zoom) * 0.5;
    let half_visible_depth = (world_depth / zoom) * 0.5;
    let width_distance = half_visible_width / (horizontal_fov * 0.5).tan().max(0.01);
    let depth_distance = half_visible_depth * render_config.vertical_projection_factor()
        / (vertical_fov * 0.5).tan().max(0.01);

    width_distance.max(depth_distance).max(10.0 * grid_size)
}

pub(crate) fn visible_world_footprint(
    viewport_width: f32,
    viewport_height: f32,
    camera_distance: f32,
    render_config: ViewerRenderConfig,
) -> Vec2 {
    let (horizontal_fov, vertical_fov) =
        perspective_camera_fovs(viewport_width, viewport_height, render_config);
    let width = 2.0 * camera_distance * (horizontal_fov * 0.5).tan();
    let depth = 2.0 * camera_distance * (vertical_fov * 0.5).tan()
        / render_config.vertical_projection_factor().max(0.1);
    Vec2::new(width, depth)
}

pub(crate) fn clamp_camera_pan_offset(
    bounds: GridBounds,
    grid_size: f32,
    pan_offset: Vec2,
    viewport_width: f32,
    viewport_height: f32,
    render_config: ViewerRenderConfig,
) -> Vec2 {
    let center_x = (bounds.min_x + bounds.max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (bounds.min_z + bounds.max_z + 1) as f32 * grid_size * 0.5;
    let half_cell = grid_size * 0.5;
    let camera_distance = camera_world_distance(
        bounds,
        viewport_width,
        viewport_height,
        grid_size,
        render_config,
    );
    let visible_world = visible_world_footprint(
        viewport_width,
        viewport_height,
        camera_distance,
        render_config,
    );
    let half_visible_width = visible_world.x * 0.5;
    let half_visible_depth = visible_world.y * 0.5;
    let focus_min_x = (bounds.min_x as f32 * grid_size + half_visible_width)
        .min(bounds.min_x as f32 * grid_size + half_cell);
    let focus_max_x = ((bounds.max_x + 1) as f32 * grid_size - half_visible_width)
        .max((bounds.max_x + 1) as f32 * grid_size - half_cell);
    let focus_min_z = (bounds.min_z as f32 * grid_size + half_visible_depth)
        .min(bounds.min_z as f32 * grid_size + half_cell);
    let focus_max_z = ((bounds.max_z + 1) as f32 * grid_size - half_visible_depth)
        .max((bounds.max_z + 1) as f32 * grid_size - half_cell);

    let clamped_focus_x = (center_x + pan_offset.x).clamp(focus_min_x, focus_max_x);
    let clamped_focus_z = (center_z + pan_offset.y).clamp(focus_min_z, focus_max_z);

    Vec2::new(clamped_focus_x - center_x, clamped_focus_z - center_z)
}

pub(crate) fn grid_focus_world_position(grid: GridCoord, grid_size: f32, y_offset: f32) -> Vec3 {
    Vec3::new(
        (grid.x as f32 + 0.5) * grid_size,
        level_base_height(grid.y, grid_size) + y_offset,
        (grid.z as f32 + 0.5) * grid_size,
    )
}

fn perspective_camera_fovs(
    viewport_width: f32,
    viewport_height: f32,
    render_config: ViewerRenderConfig,
) -> (f32, f32) {
    let usable_viewport = usable_viewport_size(viewport_width, viewport_height, render_config);
    let aspect = (usable_viewport.x / usable_viewport.y.max(1.0)).max(0.1);
    let vertical_fov = render_config.camera_fov_radians();
    let horizontal_fov = 2.0 * ((vertical_fov * 0.5).tan() * aspect).atan();
    (horizontal_fov, vertical_fov)
}

fn usable_viewport_size(
    viewport_width: f32,
    viewport_height: f32,
    render_config: ViewerRenderConfig,
) -> Vec2 {
    Vec2::new(
        (viewport_width
            - render_config.hud_reserved_width_px
            - render_config.viewport_padding_px * 2.0)
            .max(160.0),
        (viewport_height - render_config.viewport_padding_px * 2.0).max(160.0),
    )
}
