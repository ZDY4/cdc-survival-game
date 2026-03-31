use bevy::prelude::*;
use game_core::{ActorDebugState, SimulationRuntime, SimulationSnapshot};
use game_data::{ActorId, ActorSide, GridCoord, InteractionTargetId, MapObjectKind, WorldCoord};

use crate::state::{ViewerHudPage, ViewerRenderConfig, ViewerState};

#[derive(Debug, Clone, Copy)]
pub(crate) struct GridBounds {
    pub min_x: i32,
    pub max_x: i32,
    pub min_z: i32,
    pub max_z: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum HoveredGridOutlineKind {
    Reachable,
    Hostile,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum OcclusionFocusPoint {
    Actor(ActorId),
    Grid(GridCoord),
}

pub(crate) const MISSING_GEO_BUILDING_PLACEHOLDER_HEIGHT_SCALE: f32 = 1.15;

pub(crate) fn actor_label(actor: &ActorDebugState) -> String {
    if actor.display_name.trim().is_empty() {
        actor.actor_id.0.to_string()
    } else {
        actor.display_name.clone()
    }
}

pub(crate) fn rendered_path_preview(
    runtime: &SimulationRuntime,
    snapshot: &SimulationSnapshot,
    pending_movement: Option<&game_core::PendingMovementIntent>,
) -> Vec<GridCoord> {
    let Some(intent) = pending_movement else {
        return Vec::new();
    };

    if let Ok(plan) = runtime.plan_actor_movement(intent.actor_id, intent.requested_goal) {
        return plan.requested_path;
    }

    let Some(current_position) = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == intent.actor_id)
        .map(|actor| actor.grid_position)
    else {
        return Vec::new();
    };

    std::iter::once(current_position)
        .chain(
            snapshot
                .path_preview
                .iter()
                .copied()
                .skip_while(|grid| *grid != current_position)
                .skip(1),
        )
        .collect()
}

pub(crate) fn level_base_height(level: i32, grid_size: f32) -> f32 {
    level as f32 * grid_size
}

pub(crate) fn level_plane_height(level: i32, grid_size: f32) -> f32 {
    level_base_height(level, grid_size) + grid_size * 0.5
}

pub(crate) fn actor_body_translation(
    world: WorldCoord,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> Vec3 {
    let floor_y = world.y - grid_size * 0.5;
    Vec3::new(
        world.x,
        floor_y
            + (render_config.actor_radius_world + render_config.actor_body_length_world * 0.5)
                * grid_size,
        world.z,
    )
}

pub(crate) fn actor_label_world_position(
    world: WorldCoord,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> Vec3 {
    let floor_y = world.y - grid_size * 0.5;
    Vec3::new(
        world.x,
        floor_y + render_config.actor_label_height_world * grid_size,
        world.z,
    )
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

pub(crate) fn should_rebuild_static_world<Key>(current: &Option<Key>, next: &Key) -> bool
where
    Key: PartialEq,
{
    current.as_ref() != Some(next)
}

pub(crate) fn actor_at_grid(
    snapshot: &SimulationSnapshot,
    grid: GridCoord,
) -> Option<ActorDebugState> {
    snapshot
        .actors
        .iter()
        .find(|actor| actor.grid_position == grid)
        .cloned()
}

pub(crate) fn map_object_at_grid(
    snapshot: &SimulationSnapshot,
    grid: GridCoord,
) -> Option<game_core::MapObjectDebugState> {
    snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.occupied_cells.contains(&grid))
        .max_by_key(|object| usize::from(is_generated_door_object(object)))
        .cloned()
}

pub(crate) fn is_missing_generated_building(
    snapshot: &SimulationSnapshot,
    object: &game_core::MapObjectDebugState,
) -> bool {
    object.kind == MapObjectKind::Building
        && !snapshot
            .generated_buildings
            .iter()
            .any(|building| building.object_id == object.object_id)
}

pub(crate) fn missing_geo_building_placeholder_box(
    object: &game_core::MapObjectDebugState,
    grid_size: f32,
    floor_top: f32,
) -> Option<(Vec3, Vec3)> {
    if object.kind != MapObjectKind::Building {
        return None;
    }

    let (center_x, center_z, footprint_width, footprint_depth) =
        occupied_cells_box_world(&object.occupied_cells, grid_size)?;
    let height = grid_size * MISSING_GEO_BUILDING_PLACEHOLDER_HEIGHT_SCALE;

    Some((
        Vec3::new(center_x, floor_top + height * 0.5, center_z),
        Vec3::new(footprint_width, height, footprint_depth),
    ))
}

pub(crate) fn map_object_debug_label(
    snapshot: &SimulationSnapshot,
    object: &game_core::MapObjectDebugState,
) -> String {
    let mut label = format!("{} ({:?})", object.object_id, object.kind);
    if is_missing_generated_building(snapshot, object) {
        label.push_str(" [missing geo]");
    }
    label
}

pub(crate) fn actor_hit_at_ray(
    snapshot: &SimulationSnapshot,
    current_level: i32,
    ray: Ray3d,
    render_config: ViewerRenderConfig,
) -> Option<(ActorDebugState, f32)> {
    let max_distance = interaction_ray_max_distance(snapshot);
    let ray_end = ray.origin + ray.direction.as_vec3() * max_distance;
    let grid_size = snapshot.grid.grid_size;

    snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position.y == current_level)
        .filter_map(|actor| {
            actor_hit_fraction(actor, ray.origin, ray_end, grid_size, render_config)
                .map(|fraction| (actor.clone(), fraction))
        })
        .min_by(|left, right| left.1.total_cmp(&right.1))
}

pub(crate) fn generated_door_object_hit_at_ray(
    snapshot: &SimulationSnapshot,
    current_level: i32,
    ray: Ray3d,
    floor_thickness_world: f32,
) -> Option<(game_core::MapObjectDebugState, f32)> {
    let max_distance = interaction_ray_max_distance(snapshot);
    let ray_end = ray.origin + ray.direction.as_vec3() * max_distance;
    let grid_size = snapshot.grid.grid_size;
    let floor_top = level_base_height(current_level, grid_size) + floor_thickness_world;

    let (door_id, hit_fraction) = snapshot
        .generated_doors
        .iter()
        .filter(|door| door.level == current_level)
        .filter_map(|door| {
            generated_door_hit_fraction(door, ray.origin, ray_end, grid_size, floor_top)
                .map(|fraction| (door.map_object_id.as_str(), fraction))
        })
        .min_by(|left, right| left.1.total_cmp(&right.1))?;

    snapshot
        .grid
        .map_objects
        .iter()
        .find(|object| object.object_id == door_id)
        .cloned()
        .map(|object| (object, hit_fraction))
}

pub(crate) fn map_object_hit_at_ray(
    snapshot: &SimulationSnapshot,
    current_level: i32,
    ray: Ray3d,
    render_config: ViewerRenderConfig,
) -> Option<(game_core::MapObjectDebugState, f32)> {
    let generated_door_hit = generated_door_object_hit_at_ray(
        snapshot,
        current_level,
        ray,
        render_config.floor_thickness_world,
    );
    let generic_hit = generic_map_object_hit_at_ray(snapshot, current_level, ray, render_config);

    match (generated_door_hit, generic_hit) {
        (Some(door), Some(object)) => {
            if door.1 <= object.1 {
                Some(door)
            } else {
                Some(object)
            }
        }
        (Some(door), None) => Some(door),
        (None, Some(object)) => Some(object),
        (None, None) => None,
    }
}

fn is_generated_door_object(object: &game_core::MapObjectDebugState) -> bool {
    object
        .payload_summary
        .get("generated_door")
        .is_some_and(|value| value == "true")
}

pub(crate) fn just_pressed_hud_page(keys: &ButtonInput<KeyCode>) -> Option<ViewerHudPage> {
    if keys.just_pressed(KeyCode::F1) {
        Some(ViewerHudPage::Overview)
    } else if keys.just_pressed(KeyCode::F2) {
        Some(ViewerHudPage::SelectedActor)
    } else if keys.just_pressed(KeyCode::F3) {
        Some(ViewerHudPage::World)
    } else if keys.just_pressed(KeyCode::F4) {
        Some(ViewerHudPage::Interaction)
    } else if keys.just_pressed(KeyCode::F5) {
        Some(ViewerHudPage::Events)
    } else if keys.just_pressed(KeyCode::F6) {
        Some(ViewerHudPage::Ai)
    } else if keys.just_pressed(KeyCode::F7) {
        Some(ViewerHudPage::Performance)
    } else {
        None
    }
}

pub(crate) fn selected_actor<'a>(
    snapshot: &'a SimulationSnapshot,
    viewer_state: &ViewerState,
) -> Option<&'a ActorDebugState> {
    viewer_state.selected_actor.and_then(|actor_id| {
        snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == actor_id)
    })
}

pub(crate) fn hovered_grid_outline_kind(
    runtime: &SimulationRuntime,
    snapshot: &SimulationSnapshot,
    viewer_state: &ViewerState,
    grid: GridCoord,
) -> Option<HoveredGridOutlineKind> {
    if actor_at_grid(snapshot, grid).is_some_and(|actor| actor.side == ActorSide::Hostile) {
        return Some(HoveredGridOutlineKind::Hostile);
    }

    let actor_id = viewer_state.selected_actor?;
    if !runtime.is_grid_in_bounds(grid) {
        return None;
    }

    let plan = runtime.plan_actor_movement(actor_id, grid).ok()?;
    (plan.requested_steps() > 0).then_some(HoveredGridOutlineKind::Reachable)
}

#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn resolve_occlusion_target<'a>(
    snapshot: &'a SimulationSnapshot,
    viewer_state: &ViewerState,
) -> Option<&'a ActorDebugState> {
    resolve_occlusion_target_actor_id(snapshot, viewer_state).and_then(|actor_id| {
        snapshot
            .actors
            .iter()
            .find(|actor| actor.actor_id == actor_id)
    })
}

pub(crate) fn resolve_occlusion_focus_points(
    snapshot: &SimulationSnapshot,
    viewer_state: &ViewerState,
    hover_focus_enabled: bool,
) -> Vec<OcclusionFocusPoint> {
    let mut points = Vec::new();

    if let Some(actor_id) = resolve_occlusion_target_actor_id(snapshot, viewer_state) {
        points.push(OcclusionFocusPoint::Actor(actor_id));
    }

    if !hover_focus_enabled {
        return points;
    }

    let targeting_hover = viewer_state.targeting_state.as_ref().and_then(|targeting| {
        targeting
            .hovered_grid
            .filter(|grid| grid.y == viewer_state.current_level)
            .filter(|grid| targeting.valid_grids.contains(grid))
    });

    if let Some(grid) = targeting_hover.or(viewer_state.hovered_grid.filter(|grid| {
        grid.y == viewer_state.current_level && viewer_state.targeting_state.is_none()
    })) {
        points.push(OcclusionFocusPoint::Grid(grid));
    }

    points
}

pub(crate) fn grid_focus_world_position(grid: GridCoord, grid_size: f32, y_offset: f32) -> Vec3 {
    Vec3::new(
        (grid.x as f32 + 0.5) * grid_size,
        level_base_height(grid.y, grid_size) + y_offset,
        (grid.z as f32 + 0.5) * grid_size,
    )
}

fn resolve_occlusion_target_actor_id(
    snapshot: &SimulationSnapshot,
    viewer_state: &ViewerState,
) -> Option<ActorId> {
    if let Some(actor) = selected_actor(snapshot, viewer_state) {
        if actor.side == ActorSide::Player {
            return (actor.grid_position.y == viewer_state.current_level).then_some(actor.actor_id);
        }
        return snapshot
            .actors
            .iter()
            .find(|candidate| {
                candidate.side == ActorSide::Player
                    && candidate.grid_position.y == viewer_state.current_level
            })
            .map(|actor| actor.actor_id);
    }

    snapshot
        .actors
        .iter()
        .find(|actor| {
            actor.side == ActorSide::Player && actor.grid_position.y == viewer_state.current_level
        })
        .map(|actor| actor.actor_id)
}

fn interaction_ray_max_distance(snapshot: &SimulationSnapshot) -> f32 {
    let extent = snapshot
        .grid
        .map_width
        .unwrap_or(64)
        .max(snapshot.grid.map_height.unwrap_or(64)) as f32
        * snapshot.grid.grid_size;
    extent.max(snapshot.grid.grid_size * 32.0) * 4.0
}

fn generic_map_object_hit_at_ray(
    snapshot: &SimulationSnapshot,
    current_level: i32,
    ray: Ray3d,
    render_config: ViewerRenderConfig,
) -> Option<(game_core::MapObjectDebugState, f32)> {
    let max_distance = interaction_ray_max_distance(snapshot);
    let ray_end = ray.origin + ray.direction.as_vec3() * max_distance;
    let grid_size = snapshot.grid.grid_size;
    let floor_top =
        level_base_height(current_level, grid_size) + render_config.floor_thickness_world;

    snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.anchor.y == current_level)
        .filter(|object| !is_generated_door_object(object))
        .filter(|object| {
            object.kind == game_data::MapObjectKind::Building || object_has_viewer_function(object)
        })
        .filter_map(|object| {
            map_object_hit_fraction(snapshot, object, ray.origin, ray_end, floor_top, grid_size)
                .map(|fraction| (object.clone(), fraction))
        })
        .min_by(|left, right| left.1.total_cmp(&right.1))
}

fn actor_hit_fraction(
    actor: &ActorDebugState,
    ray_origin: Vec3,
    ray_end: Vec3,
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> Option<f32> {
    let body_translation = actor_body_translation(
        WorldCoord::new(
            (actor.grid_position.x as f32 + 0.5) * grid_size,
            (actor.grid_position.y as f32 + 0.5) * grid_size,
            (actor.grid_position.z as f32 + 0.5) * grid_size,
        ),
        grid_size,
        render_config,
    );
    let body_height = render_config.actor_body_length_world;
    let body_width = (render_config.actor_radius_world * 1.65).max(0.18);
    let body_depth = (render_config.actor_radius_world * 1.2).max(0.16);
    let head_radius = (render_config.actor_radius_world * 0.92).max(0.12);
    let min_y = (-render_config.actor_radius_world - body_height * 0.5)
        .min(body_height * 0.5 - head_radius);
    let max_y = (-render_config.actor_radius_world + body_height * 0.5)
        .max(body_height * 0.5 + head_radius);
    let local_center = Vec3::new(0.0, (min_y + max_y) * 0.5, 0.0);
    let half_extents = Vec3::new(
        (body_width * 0.5).max(head_radius) * grid_size,
        ((max_y - min_y) * 0.5) * grid_size,
        (body_depth * 0.5).max(head_radius) * grid_size,
    );
    let center = body_translation + local_center * grid_size;
    segment_aabb_intersection_fraction(ray_origin, ray_end, center, half_extents)
}

fn map_object_hit_fraction(
    snapshot: &SimulationSnapshot,
    object: &game_core::MapObjectDebugState,
    ray_origin: Vec3,
    ray_end: Vec3,
    floor_top: f32,
    grid_size: f32,
) -> Option<f32> {
    match object.kind {
        MapObjectKind::Building => {
            if is_missing_generated_building(snapshot, object) {
                let (center, size) =
                    missing_geo_building_placeholder_box(object, grid_size, floor_top)?;
                return segment_aabb_intersection_fraction(ray_origin, ray_end, center, size * 0.5);
            }

            let (center_x, center_z, footprint_width, footprint_depth) =
                occupied_cells_box_world(&object.occupied_cells, grid_size)?;
            let body_height = grid_size * (1.08 + object_anchor_noise(object) * 0.34);
            segment_aabb_intersection_fraction(
                ray_origin,
                ray_end,
                Vec3::new(center_x, floor_top + body_height * 0.5, center_z),
                Vec3::new(
                    footprint_width * 0.9 * 0.5,
                    body_height * 0.5,
                    footprint_depth * 0.88 * 0.5,
                ),
            )
        }
        MapObjectKind::Pickup => {
            let (center_x, center_z, _, _) =
                occupied_cells_box_world(&object.occupied_cells, grid_size)?;
            let core_height = grid_size * 0.22;
            let side = grid_size * 0.28;
            let plinth_height = grid_size * 0.08;
            segment_aabb_intersection_fraction(
                ray_origin,
                ray_end,
                Vec3::new(
                    center_x,
                    floor_top + plinth_height + core_height * 0.5,
                    center_z,
                ),
                Vec3::new(side * 0.5, core_height * 0.5, side * 0.5),
            )
        }
        MapObjectKind::Interactive => {
            let (center_x, center_z, footprint_width, footprint_depth) =
                occupied_cells_box_world(&object.occupied_cells, grid_size)?;
            let pillar_height = grid_size * (0.72 + object_anchor_noise(object) * 0.16);
            let width = footprint_width.min(grid_size * 0.46).max(0.16);
            let depth = footprint_depth.min(grid_size * 0.42).max(0.16);
            let pillar_hit = segment_aabb_intersection_fraction(
                ray_origin,
                ray_end,
                Vec3::new(center_x, floor_top + pillar_height * 0.5, center_z),
                Vec3::new(width * 0.5, pillar_height * 0.5, depth * 0.5),
            );
            let cap_hit = segment_aabb_intersection_fraction(
                ray_origin,
                ray_end,
                Vec3::new(
                    center_x,
                    floor_top + pillar_height + grid_size * 0.08,
                    center_z,
                ),
                Vec3::new(
                    width.max(0.16) * 0.58 * 0.5,
                    grid_size * 0.16 * 0.5,
                    grid_size * 0.22 * 0.5,
                ),
            );
            match (pillar_hit, cap_hit) {
                (Some(a), Some(b)) => Some(a.min(b)),
                (Some(a), None) => Some(a),
                (None, Some(b)) => Some(b),
                (None, None) => None,
            }
        }
        MapObjectKind::Trigger => {
            trigger_hit_fraction(object, ray_origin, ray_end, floor_top, grid_size)
        }
        MapObjectKind::AiSpawn => {
            let (center_x, center_z, _, _) =
                occupied_cells_box_world(&object.occupied_cells, grid_size)?;
            let beacon_height = grid_size * (0.34 + object_anchor_noise(object) * 0.16);
            let side = grid_size * 0.28;
            let beacon_hit = segment_aabb_intersection_fraction(
                ray_origin,
                ray_end,
                Vec3::new(center_x, floor_top + beacon_height * 0.5, center_z),
                Vec3::new(side * 0.5, beacon_height * 0.5, side * 0.5),
            );
            let top_hit = segment_aabb_intersection_fraction(
                ray_origin,
                ray_end,
                Vec3::new(
                    center_x,
                    floor_top + beacon_height + grid_size * 0.08,
                    center_z,
                ),
                Vec3::new(side * 0.55 * 0.5, grid_size * 0.16 * 0.5, side * 0.55 * 0.5),
            );
            match (beacon_hit, top_hit) {
                (Some(a), Some(b)) => Some(a.min(b)),
                (Some(a), None) => Some(a),
                (None, Some(b)) => Some(b),
                (None, None) => None,
            }
        }
    }
}

fn trigger_hit_fraction(
    object: &game_core::MapObjectDebugState,
    ray_origin: Vec3,
    ray_end: Vec3,
    floor_top: f32,
    grid_size: f32,
) -> Option<f32> {
    if is_scene_transition_trigger(object) {
        return None;
    }

    object
        .occupied_cells
        .iter()
        .filter_map(|cell| {
            let center_x = (cell.x as f32 + 0.5) * grid_size;
            let center_z = (cell.z as f32 + 0.5) * grid_size;
            let tile_height = grid_size * 0.045;
            segment_aabb_intersection_fraction(
                ray_origin,
                ray_end,
                Vec3::new(center_x, floor_top + tile_height * 0.5, center_z),
                Vec3::new(
                    grid_size * 0.9 * 0.5,
                    tile_height * 0.5,
                    grid_size * 0.9 * 0.5,
                ),
            )
        })
        .min_by(|left, right| left.total_cmp(right))
}

fn object_has_viewer_function(object: &game_core::MapObjectDebugState) -> bool {
    !object.payload_summary.is_empty()
}

fn occupied_cells_box_world(cells: &[GridCoord], grid_size: f32) -> Option<(f32, f32, f32, f32)> {
    let mut min_x = i32::MAX;
    let mut max_x = i32::MIN;
    let mut min_z = i32::MAX;
    let mut max_z = i32::MIN;

    for grid in cells {
        min_x = min_x.min(grid.x);
        max_x = max_x.max(grid.x);
        min_z = min_z.min(grid.z);
        max_z = max_z.max(grid.z);
    }

    if min_x == i32::MAX {
        return None;
    }

    let center_x = (min_x + max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (min_z + max_z + 1) as f32 * grid_size * 0.5;
    let width = (max_x - min_x + 1) as f32 * grid_size;
    let depth = (max_z - min_z + 1) as f32 * grid_size;
    Some((center_x, center_z, width, depth))
}

fn object_anchor_noise(object: &game_core::MapObjectDebugState) -> f32 {
    let mut hash = 409_u32
        .wrapping_mul(0x9E37_79B9)
        .wrapping_add((object.anchor.x as u32).wrapping_mul(0x85EB_CA6B))
        .wrapping_add((object.anchor.z as u32).wrapping_mul(0xC2B2_AE35));
    hash ^= hash >> 15;
    hash = hash.wrapping_mul(0x27D4_EB2D);
    hash ^= hash >> 13;
    (hash & 0xFFFF) as f32 / 65_535.0
}

fn is_scene_transition_trigger(object: &game_core::MapObjectDebugState) -> bool {
    object.kind == game_data::MapObjectKind::Trigger
        && object
            .payload_summary
            .get("trigger_kind")
            .is_some_and(|kind| is_scene_transition_trigger_kind(kind))
}

fn is_scene_transition_trigger_kind(kind: &str) -> bool {
    matches!(
        kind.trim(),
        "enter_subscene" | "enter_overworld" | "exit_to_outdoor" | "enter_outdoor_location"
    )
}

fn generated_door_hit_fraction(
    door: &game_core::GeneratedDoorDebugState,
    ray_origin: Vec3,
    ray_end: Vec3,
    grid_size: f32,
    floor_top: f32,
) -> Option<f32> {
    let (pivot, yaw) = generated_door_pick_transform(door, grid_size, floor_top);
    let (aabb_center, aabb_half_extents) =
        generated_door_pick_aabb(door, pivot, yaw, grid_size, floor_top);
    segment_aabb_intersection_fraction(ray_origin, ray_end, aabb_center, aabb_half_extents)
}

fn generated_door_pick_transform(
    door: &game_core::GeneratedDoorDebugState,
    grid_size: f32,
    floor_top: f32,
) -> (Vec3, f32) {
    let (min_x, max_x, min_z, max_z) =
        geometry_world_bounds(&door.polygon, door.building_anchor, grid_size);
    let pivot = match door.axis {
        game_core::GeometryAxis::Horizontal => Vec3::new(min_x, floor_top, (min_z + max_z) * 0.5),
        game_core::GeometryAxis::Vertical => Vec3::new((min_x + max_x) * 0.5, floor_top, min_z),
    };
    let yaw = if door.is_open {
        match door.axis {
            game_core::GeometryAxis::Horizontal => std::f32::consts::FRAC_PI_2,
            game_core::GeometryAxis::Vertical => -std::f32::consts::FRAC_PI_2,
        }
    } else {
        0.0
    };
    (pivot, yaw)
}

fn generated_door_pick_aabb(
    door: &game_core::GeneratedDoorDebugState,
    pivot: Vec3,
    yaw: f32,
    grid_size: f32,
    floor_top: f32,
) -> (Vec3, Vec3) {
    let rotation = Quat::from_rotation_y(yaw);
    let mut min_x = f32::INFINITY;
    let mut max_x = f32::NEG_INFINITY;
    let mut min_z = f32::INFINITY;
    let mut max_z = f32::NEG_INFINITY;

    for point in door
        .polygon
        .outer
        .iter()
        .chain(door.polygon.holes.iter().flatten())
    {
        let local = Vec3::new(
            (door.building_anchor.x as f32 + point.x as f32) * grid_size - pivot.x,
            0.0,
            (door.building_anchor.z as f32 + point.z as f32) * grid_size - pivot.z,
        );
        let world = pivot + rotation * local;
        min_x = min_x.min(world.x);
        max_x = max_x.max(world.x);
        min_z = min_z.min(world.z);
        max_z = max_z.max(world.z);
    }

    let min_y = floor_top;
    let max_y = floor_top + door.wall_height * grid_size;
    let center = Vec3::new(
        (min_x + max_x) * 0.5,
        (min_y + max_y) * 0.5,
        (min_z + max_z) * 0.5,
    );
    let mut half_extents = Vec3::new(
        (max_x - min_x) * 0.5,
        (max_y - min_y) * 0.5,
        (max_z - min_z) * 0.5,
    );
    let inflate = grid_size * 0.08;
    half_extents.x = half_extents.x.max(inflate);
    half_extents.z = half_extents.z.max(inflate);
    (center, half_extents)
}

fn geometry_world_bounds(
    polygon: &game_core::GeometryPolygon2,
    anchor: GridCoord,
    grid_size: f32,
) -> (f32, f32, f32, f32) {
    let mut min_x = f32::INFINITY;
    let mut max_x = f32::NEG_INFINITY;
    let mut min_z = f32::INFINITY;
    let mut max_z = f32::NEG_INFINITY;
    for point in polygon.outer.iter().chain(polygon.holes.iter().flatten()) {
        let world_x = (anchor.x as f32 + point.x as f32) * grid_size;
        let world_z = (anchor.z as f32 + point.z as f32) * grid_size;
        min_x = min_x.min(world_x);
        max_x = max_x.max(world_x);
        min_z = min_z.min(world_z);
        max_z = max_z.max(world_z);
    }
    (min_x, max_x, min_z, max_z)
}

pub(crate) fn segment_aabb_intersection_fraction(
    start: Vec3,
    end: Vec3,
    aabb_center: Vec3,
    aabb_half_extents: Vec3,
) -> Option<f32> {
    let direction = end - start;
    let min = aabb_center - aabb_half_extents;
    let max = aabb_center + aabb_half_extents;
    let mut t_min = 0.0_f32;
    let mut t_max = 1.0_f32;

    for axis in 0..3 {
        let start_axis = start[axis];
        let direction_axis = direction[axis];
        let min_axis = min[axis];
        let max_axis = max[axis];

        if direction_axis.abs() <= f32::EPSILON {
            if start_axis < min_axis || start_axis > max_axis {
                return None;
            }
            continue;
        }

        let inv_direction = 1.0 / direction_axis;
        let t1 = (min_axis - start_axis) * inv_direction;
        let t2 = (max_axis - start_axis) * inv_direction;
        let (enter, exit) = if t1 <= t2 { (t1, t2) } else { (t2, t1) };
        t_min = t_min.max(enter);
        t_max = t_max.min(exit);

        if t_min > t_max {
            return None;
        }
    }

    Some(t_min.clamp(0.0, 1.0))
}

pub(crate) fn occluder_blocks_target(
    camera_position: Vec3,
    target_position: Vec3,
    aabb_center: Vec3,
    aabb_half_extents: Vec3,
) -> bool {
    segment_aabb_intersection_fraction(
        camera_position,
        target_position,
        aabb_center,
        aabb_half_extents,
    )
    .is_some_and(|t| t <= 1.0)
}

pub(crate) fn focused_target_summary(
    snapshot: &SimulationSnapshot,
    viewer_state: &ViewerState,
) -> String {
    viewer_state
        .focused_target
        .as_ref()
        .map(|target| match target {
            InteractionTargetId::Actor(actor_id) => snapshot
                .actors
                .iter()
                .find(|actor| actor.actor_id == *actor_id)
                .map(|actor| format!("{} ({:?})", actor_label(actor), actor.side))
                .unwrap_or_else(|| format!("actor {:?}", actor_id)),
            InteractionTargetId::MapObject(object_id) => snapshot
                .grid
                .map_objects
                .iter()
                .find(|object| object.object_id == *object_id)
                .map(|object| map_object_debug_label(snapshot, object))
                .unwrap_or_else(|| format!("object {}", object_id)),
        })
        .unwrap_or_else(|| "none".to_string())
}

pub(crate) fn format_optional_grid(grid: Option<GridCoord>) -> String {
    grid.map(|grid| format!("({}, {}, {})", grid.x, grid.y, grid.z))
        .unwrap_or_else(|| "none".to_string())
}

pub(crate) fn movement_block_reasons(
    snapshot: &SimulationSnapshot,
    grid: GridCoord,
) -> Vec<String> {
    let mut reasons = Vec::new();

    if let Some(cell) = snapshot
        .grid
        .map_cells
        .iter()
        .find(|cell| cell.grid == grid)
    {
        if cell.blocks_movement {
            reasons.push(format!("terrain:{}", cell.terrain));
        }
    }
    if snapshot.grid.map_blocked_cells.contains(&grid) {
        reasons.push("map_blocked_set".to_string());
    }
    if snapshot.grid.static_obstacles.contains(&grid) {
        reasons.push("static_obstacle".to_string());
    }

    let actor_names: Vec<String> = snapshot
        .actors
        .iter()
        .filter(|actor| actor.grid_position == grid)
        .map(actor_label)
        .collect();
    if !actor_names.is_empty() {
        reasons.push(format!("runtime_actor:{}", actor_names.join("+")));
    }

    let blocking_objects: Vec<String> = snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.blocks_movement && object.occupied_cells.contains(&grid))
        .map(|object| object.object_id.clone())
        .collect();
    if !blocking_objects.is_empty() {
        reasons.push(format!("object:{}", blocking_objects.join("+")));
    }

    reasons
}

pub(crate) fn sight_block_reasons(snapshot: &SimulationSnapshot, grid: GridCoord) -> Vec<String> {
    let mut reasons = Vec::new();

    if let Some(cell) = snapshot
        .grid
        .map_cells
        .iter()
        .find(|cell| cell.grid == grid)
    {
        if cell.blocks_sight {
            reasons.push(format!("terrain:{}", cell.terrain));
        }
    }

    let blocking_objects: Vec<String> = snapshot
        .grid
        .map_objects
        .iter()
        .filter(|object| object.blocks_sight && object.occupied_cells.contains(&grid))
        .map(|object| object.object_id.clone())
        .collect();
    if !blocking_objects.is_empty() {
        reasons.push(format!("object:{}", blocking_objects.join("+")));
    }

    reasons
}

pub(crate) fn cycle_level(levels: &[i32], current_level: i32, direction: i32) -> Option<i32> {
    if levels.is_empty() {
        return None;
    }

    let current_index = levels
        .iter()
        .position(|level| *level == current_level)
        .unwrap_or(0) as i32;
    let next_index = (current_index + direction).rem_euclid(levels.len() as i32) as usize;
    levels.get(next_index).copied()
}

pub(crate) fn grid_bounds(snapshot: &SimulationSnapshot, level: i32) -> GridBounds {
    if let (Some(width), Some(height)) = (snapshot.grid.map_width, snapshot.grid.map_height) {
        return GridBounds {
            min_x: 0,
            max_x: width.saturating_sub(1) as i32,
            min_z: 0,
            max_z: height.saturating_sub(1) as i32,
        };
    }

    let mut min_x = 0;
    let mut max_x = 5;
    let mut min_z = -1;
    let mut max_z = 4;

    for grid in snapshot
        .actors
        .iter()
        .map(|actor| actor.grid_position)
        .chain(snapshot.grid.static_obstacles.iter().copied())
        .chain(snapshot.path_preview.iter().copied())
        .filter(|grid| grid.y == level)
    {
        min_x = min_x.min(grid.x - 2);
        max_x = max_x.max(grid.x + 2);
        min_z = min_z.min(grid.z - 2);
        max_z = max_z.max(grid.z + 2);
    }

    GridBounds {
        min_x,
        max_x,
        min_z,
        max_z,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        actor_hit_at_ray, actor_label, camera_focus_point, camera_pan_delta_from_ground_drag,
        camera_world_distance, clamp_camera_pan_offset, cycle_level,
        generated_door_object_hit_at_ray, grid_bounds, grid_focus_world_position,
        hovered_grid_outline_kind, just_pressed_hud_page, level_plane_height,
        map_object_hit_at_ray, movement_block_reasons, occluder_blocks_target, pick_grid_from_ray,
        rendered_path_preview, resolve_occlusion_focus_points, resolve_occlusion_target,
        segment_aabb_intersection_fraction, should_rebuild_static_world, visible_world_footprint,
        GridBounds, HoveredGridOutlineKind, OcclusionFocusPoint,
    };
    use crate::state::{ViewerHudPage, ViewerRenderConfig, ViewerState};
    use crate::test_support::actor_debug_state_fixture;
    use bevy::prelude::*;
    use game_core::{
        create_demo_runtime, ActorDebugState, CombatDebugState, DoorOpeningKind,
        GeneratedDoorDebugState, GeometryAxis, GeometryPoint2, GeometryPolygon2, GridDebugState,
        MapCellDebugState, MapObjectDebugState, OverworldStateSnapshot, SimulationSnapshot,
    };
    use game_data::{
        ActorId, ActorKind, ActorSide, GridCoord, InteractionContextSnapshot, MapId,
        MapObjectFootprint, MapObjectKind, MapRotation, TurnState,
    };
    use std::collections::BTreeMap;

    #[test]
    fn level_pick_from_ray_maps_to_expected_grid() {
        let ray = Ray3d::new(Vec3::new(2.2, 6.0, 3.8), -Dir3::Y);

        let grid = pick_grid_from_ray(ray, 1, 1.0, level_plane_height(1, 1.0));

        assert_eq!(grid, Some(GridCoord::new(2, 1, 3)));
    }

    #[test]
    fn hud_page_shortcut_maps_f7_to_performance() {
        let mut keys = ButtonInput::<KeyCode>::default();
        keys.press(KeyCode::F7);

        assert_eq!(
            just_pressed_hud_page(&keys),
            Some(ViewerHudPage::Performance)
        );
    }

    #[test]
    fn level_pick_uses_requested_plane_height() {
        let ray = Ray3d::new(
            Vec3::new(2.2, 6.0, 3.48),
            Dir3::new(Vec3::new(0.3, -1.0, 0.45)).expect("valid ray direction"),
        );

        let center_pick =
            pick_grid_from_ray(ray, 0, 1.0, level_plane_height(0, 1.0)).expect("center pick");
        let floor_pick = pick_grid_from_ray(ray, 0, 1.0, 0.08).expect("floor pick");

        assert_eq!(center_pick, GridCoord::new(3, 0, 5));
        assert_eq!(floor_pick, GridCoord::new(3, 0, 6));
    }

    #[test]
    fn camera_pan_delta_from_ground_drag_tracks_ground_points_instead_of_world_axes() {
        let plane_height = 0.08;
        let previous_ray = Ray3d::new(
            Vec3::new(0.0, 10.0, 8.0),
            Dir3::new(Vec3::new(0.15, -1.0, -0.7)).expect("valid ray direction"),
        );
        let current_ray = Ray3d::new(
            Vec3::new(0.0, 10.0, 8.0),
            Dir3::new(Vec3::new(0.45, -1.0, -0.4)).expect("valid ray direction"),
        );

        let delta = camera_pan_delta_from_ground_drag(previous_ray, current_ray, plane_height)
            .expect("drag rays should hit the ground plane");

        assert!(delta.x < 0.0);
        assert!(delta.y < 0.0);
    }

    #[test]
    fn grid_bounds_ignore_hover_side_effects() {
        let mut actor = actor_debug_state_fixture();
        actor.actor_id = ActorId(1);
        actor.definition_id = Some(game_data::CharacterId("player".into()));
        actor.display_name = "幸存者".into();
        actor.kind = ActorKind::Player;
        actor.side = ActorSide::Player;
        actor.group_id = "player".into();
        actor.grid_position = GridCoord::new(0, 0, 0);

        let snapshot = SimulationSnapshot {
            turn: TurnState::default(),
            actors: vec![actor],
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: None,
                map_height: None,
                default_level: Some(0),
                levels: vec![0],
                static_obstacles: vec![GridCoord::new(2, 0, 1)],
                map_blocked_cells: vec![GridCoord::new(2, 0, 1)],
                map_cells: Vec::new(),
                map_objects: Vec::new(),
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            vision: Default::default(),
            generated_buildings: Vec::new(),
            generated_doors: Vec::new(),
            combat: CombatDebugState {
                in_combat: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            interaction_context: InteractionContextSnapshot::default(),
            overworld: OverworldStateSnapshot::default(),
            path_preview: Vec::new(),
        };

        let bounds = grid_bounds(&snapshot, 0);
        assert_eq!(bounds.min_x, -2);
        assert_eq!(bounds.max_x, 5);
        assert_eq!(bounds.min_z, -2);
        assert_eq!(bounds.max_z, 4);
    }

    #[test]
    fn grid_bounds_use_map_size_when_available() {
        let snapshot = SimulationSnapshot {
            turn: TurnState::default(),
            actors: Vec::new(),
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: Some(MapId("survivor_outpost_01_grid".into())),
                map_width: Some(12),
                map_height: Some(8),
                default_level: Some(0),
                levels: vec![0, 1],
                static_obstacles: Vec::new(),
                map_blocked_cells: Vec::new(),
                map_cells: Vec::new(),
                map_objects: Vec::new(),
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            vision: Default::default(),
            generated_buildings: Vec::new(),
            generated_doors: Vec::new(),
            combat: CombatDebugState {
                in_combat: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            interaction_context: InteractionContextSnapshot::default(),
            overworld: OverworldStateSnapshot::default(),
            path_preview: Vec::new(),
        };

        let bounds = grid_bounds(&snapshot, 1);
        assert_eq!(bounds.min_x, 0);
        assert_eq!(bounds.max_x, 11);
        assert_eq!(bounds.min_z, 0);
        assert_eq!(bounds.max_z, 7);
    }

    #[test]
    fn level_cycling_wraps_through_available_levels() {
        let levels = vec![0, 1, 2];
        assert_eq!(cycle_level(&levels, 0, 1), Some(1));
        assert_eq!(cycle_level(&levels, 2, 1), Some(0));
        assert_eq!(cycle_level(&levels, 0, -1), Some(2));
    }

    #[test]
    fn actor_label_prefers_display_name() {
        let mut actor = actor_debug_state_fixture();
        actor.actor_id = ActorId(7);
        actor.definition_id = Some(game_data::CharacterId("trader_lao_wang".into()));
        actor.display_name = "废土商人·老王".into();
        actor.kind = ActorKind::Enemy;
        actor.side = ActorSide::Hostile;
        actor.group_id = "hostile".into();
        actor.grid_position = GridCoord::new(2, 0, 3);

        assert_eq!(actor_label(&actor), "废土商人·老王");
    }

    #[test]
    fn actor_label_falls_back_to_plain_actor_id() {
        let mut actor = actor_debug_state_fixture();
        actor.actor_id = ActorId(7);
        actor.display_name = String::new();
        actor.kind = ActorKind::Enemy;
        actor.side = ActorSide::Hostile;
        actor.group_id = "hostile".into();
        actor.grid_position = GridCoord::new(2, 0, 3);

        assert_eq!(actor_label(&actor), "7");
    }

    #[test]
    fn movement_block_reasons_explain_multiple_sources() {
        let grid = GridCoord::new(2, 0, 1);
        let mut actor = actor_debug_state_fixture();
        actor.actor_id = ActorId(9);
        actor.display_name = "守卫".into();
        actor.side = ActorSide::Friendly;
        actor.group_id = "guard".into();
        actor.grid_position = grid;

        let snapshot = SimulationSnapshot {
            turn: TurnState::default(),
            actors: vec![actor],
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: Some(6),
                map_height: Some(6),
                default_level: Some(0),
                levels: vec![0],
                static_obstacles: vec![grid],
                map_blocked_cells: vec![grid],
                map_cells: vec![MapCellDebugState {
                    grid,
                    blocks_movement: true,
                    blocks_sight: false,
                    terrain: "wall".into(),
                }],
                map_objects: vec![MapObjectDebugState {
                    object_id: "crate".into(),
                    kind: MapObjectKind::Interactive,
                    anchor: grid,
                    footprint: MapObjectFootprint {
                        width: 1,
                        height: 1,
                    },
                    rotation: MapRotation::North,
                    blocks_movement: true,
                    blocks_sight: false,
                    occupied_cells: vec![grid],
                    payload_summary: BTreeMap::new(),
                }],
                runtime_blocked_cells: vec![grid],
                topology_version: 1,
                runtime_obstacle_version: 2,
            },
            vision: Default::default(),
            generated_buildings: Vec::new(),
            generated_doors: Vec::new(),
            combat: CombatDebugState {
                in_combat: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            interaction_context: InteractionContextSnapshot::default(),
            overworld: OverworldStateSnapshot::default(),
            path_preview: Vec::new(),
        };

        let reasons = movement_block_reasons(&snapshot, grid).join(" | ");
        assert!(reasons.contains("terrain:wall"));
        assert!(reasons.contains("map_blocked_set"));
        assert!(reasons.contains("static_obstacle"));
        assert!(reasons.contains("runtime_actor:守卫"));
        assert!(reasons.contains("object:crate"));
    }

    #[test]
    fn rendered_path_preview_is_empty_without_pending_movement() {
        let (runtime, _) = create_demo_runtime();
        let snapshot = runtime.snapshot();

        assert!(rendered_path_preview(&runtime, &snapshot, None).is_empty());
    }

    #[test]
    fn rendered_path_preview_starts_from_current_position() {
        let (mut runtime, handles) = create_demo_runtime();
        runtime
            .issue_actor_move(handles.player, GridCoord::new(0, 0, 2))
            .expect("path should be planned");

        let snapshot = runtime.snapshot();
        let preview = rendered_path_preview(&runtime, &snapshot, runtime.pending_movement());

        assert_eq!(preview.first().copied(), Some(GridCoord::new(0, 0, 1)));
        assert_eq!(preview.last().copied(), Some(GridCoord::new(0, 0, 2)));
    }

    #[test]
    fn hovered_grid_outline_marks_reachable_empty_cell() {
        let (runtime, handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        let viewer_state = ViewerState {
            selected_actor: Some(handles.player),
            current_level: 0,
            ..ViewerState::default()
        };

        let outline =
            hovered_grid_outline_kind(&runtime, &snapshot, &viewer_state, GridCoord::new(0, 0, 1));

        assert_eq!(outline, Some(HoveredGridOutlineKind::Reachable));
    }

    #[test]
    fn hovered_grid_outline_marks_hostile_cell_red() {
        let (runtime, handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        let viewer_state = ViewerState {
            selected_actor: Some(handles.player),
            current_level: 0,
            ..ViewerState::default()
        };

        let outline =
            hovered_grid_outline_kind(&runtime, &snapshot, &viewer_state, GridCoord::new(4, 0, 0));

        assert_eq!(outline, Some(HoveredGridOutlineKind::Hostile));
    }

    #[test]
    fn hovered_grid_outline_hides_unreachable_cell() {
        let (runtime, handles) = create_demo_runtime();
        let snapshot = runtime.snapshot();
        let viewer_state = ViewerState {
            selected_actor: Some(handles.player),
            current_level: 0,
            ..ViewerState::default()
        };

        let outline =
            hovered_grid_outline_kind(&runtime, &snapshot, &viewer_state, GridCoord::new(2, 0, 1));

        assert_eq!(outline, None);
    }

    #[test]
    fn camera_helpers_center_map_and_expand_distance_with_bounds() {
        let focus = camera_focus_point(
            GridBounds {
                min_x: 0,
                max_x: 11,
                min_z: 0,
                max_z: 7,
            },
            1,
            1.0,
            Vec2::new(2.0, -1.5),
        );

        assert_eq!(focus, Vec3::new(8.0, level_plane_height(1, 1.0), 2.5));

        let small = camera_world_distance(
            GridBounds {
                min_x: 0,
                max_x: 3,
                min_z: 0,
                max_z: 3,
            },
            1440.0,
            900.0,
            1.0,
            ViewerRenderConfig::default(),
        );
        let large = camera_world_distance(
            GridBounds {
                min_x: 0,
                max_x: 15,
                min_z: 0,
                max_z: 15,
            },
            1440.0,
            900.0,
            1.0,
            ViewerRenderConfig::default(),
        );

        assert!(large > small);
    }

    #[test]
    fn camera_distance_shrinks_when_zoom_factor_increases() {
        let mut zoomed_in = ViewerRenderConfig::default();
        zoomed_in.zoom_factor = 2.0;
        let base = camera_world_distance(
            GridBounds {
                min_x: 0,
                max_x: 11,
                min_z: 0,
                max_z: 11,
            },
            1440.0,
            900.0,
            1.0,
            ViewerRenderConfig::default(),
        );
        let zoomed = camera_world_distance(
            GridBounds {
                min_x: 0,
                max_x: 11,
                min_z: 0,
                max_z: 11,
            },
            1440.0,
            900.0,
            1.0,
            zoomed_in,
        );

        assert!(zoomed < base);
    }

    #[test]
    fn visible_world_footprint_expands_with_camera_distance() {
        let near = visible_world_footprint(1440.0, 900.0, 20.0, ViewerRenderConfig::default());
        let far = visible_world_footprint(1440.0, 900.0, 40.0, ViewerRenderConfig::default());

        assert!(far.x > near.x);
        assert!(far.y > near.y);
    }

    #[test]
    fn static_world_rebuild_helper_only_triggers_on_key_change() {
        let current = Some((Some("survivor_outpost_01_grid"), 0, 3_u64));
        let next_same = (Some("survivor_outpost_01_grid"), 0, 3_u64);
        let next_level = (Some("survivor_outpost_01_grid"), 1, 3_u64);

        assert!(!should_rebuild_static_world(&current, &next_same));
        assert!(should_rebuild_static_world(&current, &next_level));
    }

    #[test]
    fn clamp_camera_pan_offset_stops_at_map_edges() {
        let render_config = ViewerRenderConfig {
            hud_reserved_width_px: 0.0,
            viewport_padding_px: 0.0,
            camera_pitch_degrees: 90.0,
            zoom_factor: 2.0,
            ..ViewerRenderConfig::default()
        };

        let clamped = clamp_camera_pan_offset(
            GridBounds {
                min_x: 0,
                max_x: 9,
                min_z: 0,
                max_z: 9,
            },
            1.0,
            Vec2::new(99.0, -99.0),
            400.0,
            400.0,
            render_config,
        );

        assert!((clamped.x - 4.5).abs() < 0.001);
        assert!((clamped.y + 4.5).abs() < 0.001);
    }

    #[test]
    fn clamp_camera_pan_offset_allows_small_maps_to_pan_to_edge_cells() {
        let render_config = ViewerRenderConfig {
            hud_reserved_width_px: 0.0,
            viewport_padding_px: 0.0,
            camera_pitch_degrees: 90.0,
            ..ViewerRenderConfig::default()
        };

        let clamped = clamp_camera_pan_offset(
            GridBounds {
                min_x: 0,
                max_x: 1,
                min_z: 0,
                max_z: 1,
            },
            1.0,
            Vec2::new(5.0, 5.0),
            600.0,
            600.0,
            render_config,
        );

        assert_eq!(clamped, Vec2::splat(0.5));
    }

    #[test]
    fn occlusion_target_prefers_selected_player_on_current_level() {
        let mut selected_player = actor_debug_state_fixture();
        selected_player.actor_id = ActorId(3);
        selected_player.side = ActorSide::Player;
        selected_player.grid_position = GridCoord::new(2, 1, 4);
        selected_player.display_name = "selected".into();

        let mut fallback_player = actor_debug_state_fixture();
        fallback_player.actor_id = ActorId(4);
        fallback_player.side = ActorSide::Player;
        fallback_player.grid_position = GridCoord::new(0, 1, 0);
        fallback_player.display_name = "fallback".into();

        let snapshot = demo_snapshot_with_actors(vec![selected_player.clone(), fallback_player]);
        let viewer_state = ViewerState {
            selected_actor: Some(selected_player.actor_id),
            current_level: 1,
            ..ViewerState::default()
        };

        let target = resolve_occlusion_target(&snapshot, &viewer_state)
            .expect("selected player should be used");

        assert_eq!(target.actor_id, selected_player.actor_id);
    }

    #[test]
    fn occlusion_target_falls_back_when_selected_actor_is_not_player() {
        let mut hostile = actor_debug_state_fixture();
        hostile.actor_id = ActorId(7);
        hostile.side = ActorSide::Hostile;
        hostile.grid_position = GridCoord::new(1, 0, 1);

        let mut player = actor_debug_state_fixture();
        player.actor_id = ActorId(8);
        player.side = ActorSide::Player;
        player.grid_position = GridCoord::new(2, 0, 1);

        let snapshot = demo_snapshot_with_actors(vec![hostile.clone(), player.clone()]);
        let viewer_state = ViewerState {
            selected_actor: Some(hostile.actor_id),
            current_level: 0,
            ..ViewerState::default()
        };

        let target =
            resolve_occlusion_target(&snapshot, &viewer_state).expect("should fall back to player");

        assert_eq!(target.actor_id, player.actor_id);
    }

    #[test]
    fn occlusion_target_is_none_when_selected_player_is_on_another_level() {
        let mut player = actor_debug_state_fixture();
        player.actor_id = ActorId(12);
        player.side = ActorSide::Player;
        player.grid_position = GridCoord::new(0, 2, 0);

        let snapshot = demo_snapshot_with_actors(vec![player.clone()]);
        let viewer_state = ViewerState {
            selected_actor: Some(player.actor_id),
            current_level: 0,
            ..ViewerState::default()
        };

        assert!(resolve_occlusion_target(&snapshot, &viewer_state).is_none());
    }

    #[test]
    fn occlusion_focus_points_include_player_and_hovered_grid() {
        let mut player = actor_debug_state_fixture();
        player.actor_id = ActorId(21);
        player.side = ActorSide::Player;
        player.grid_position = GridCoord::new(2, 0, 2);

        let snapshot = demo_snapshot_with_actors(vec![player.clone()]);
        let viewer_state = ViewerState {
            selected_actor: Some(player.actor_id),
            hovered_grid: Some(GridCoord::new(4, 0, 3)),
            current_level: 0,
            ..ViewerState::default()
        };

        let focus_points = resolve_occlusion_focus_points(&snapshot, &viewer_state, true);

        assert_eq!(
            focus_points,
            vec![
                OcclusionFocusPoint::Actor(player.actor_id),
                OcclusionFocusPoint::Grid(GridCoord::new(4, 0, 3)),
            ]
        );
    }

    #[test]
    fn occlusion_focus_points_prefer_targeting_hover_when_valid() {
        let mut player = actor_debug_state_fixture();
        player.actor_id = ActorId(22);
        player.side = ActorSide::Player;
        player.grid_position = GridCoord::new(1, 0, 1);

        let snapshot = demo_snapshot_with_actors(vec![player.clone()]);
        let viewer_state = ViewerState {
            selected_actor: Some(player.actor_id),
            hovered_grid: Some(GridCoord::new(7, 0, 7)),
            targeting_state: Some(crate::state::ViewerTargetingState {
                actor_id: player.actor_id,
                action: crate::state::ViewerTargetingAction::Attack,
                source: crate::state::ViewerTargetingSource::AttackButton,
                shape: "single".into(),
                radius: 0,
                valid_grids: std::collections::BTreeSet::from([GridCoord::new(3, 0, 2)]),
                valid_actor_ids: Default::default(),
                hovered_grid: Some(GridCoord::new(3, 0, 2)),
                preview_target: None,
                preview_hit_grids: Vec::new(),
                preview_hit_actor_ids: Vec::new(),
                prompt_text: String::new(),
            }),
            current_level: 0,
            ..ViewerState::default()
        };

        let focus_points = resolve_occlusion_focus_points(&snapshot, &viewer_state, true);

        assert_eq!(
            focus_points,
            vec![
                OcclusionFocusPoint::Actor(player.actor_id),
                OcclusionFocusPoint::Grid(GridCoord::new(3, 0, 2)),
            ]
        );
    }

    #[test]
    fn occlusion_focus_points_drop_hover_when_hover_is_disabled() {
        let mut player = actor_debug_state_fixture();
        player.actor_id = ActorId(23);
        player.side = ActorSide::Player;
        player.grid_position = GridCoord::new(0, 0, 0);

        let snapshot = demo_snapshot_with_actors(vec![player.clone()]);
        let viewer_state = ViewerState {
            selected_actor: Some(player.actor_id),
            hovered_grid: Some(GridCoord::new(5, 0, 5)),
            current_level: 0,
            ..ViewerState::default()
        };

        let focus_points = resolve_occlusion_focus_points(&snapshot, &viewer_state, false);

        assert_eq!(
            focus_points,
            vec![OcclusionFocusPoint::Actor(player.actor_id)]
        );
    }

    #[test]
    fn grid_focus_world_position_targets_grid_center_above_floor() {
        let point = grid_focus_world_position(GridCoord::new(3, 2, 4), 1.5, 0.11);

        assert_eq!(point, Vec3::new(5.25, 3.11, 6.75));
    }

    #[test]
    fn segment_intersection_reports_hit_for_box_on_segment() {
        let hit = segment_aabb_intersection_fraction(
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(10.0, 0.0, 0.0),
            Vec3::new(4.0, 0.0, 0.0),
            Vec3::splat(0.5),
        );

        assert!(hit.is_some());
    }

    #[test]
    fn actor_ray_pick_hits_visible_actor_volume() {
        let mut actor = actor_debug_state_fixture();
        actor.actor_id = ActorId(99);
        actor.display_name = "Scout".into();
        actor.side = ActorSide::Friendly;
        actor.grid_position = GridCoord::new(1, 0, 0);

        let snapshot = demo_snapshot_with_actors(vec![actor]);
        let ray = Ray3d::new(
            Vec3::new(1.5, 0.6, -2.0),
            Dir3::new(Vec3::new(0.0, 0.0, 1.0)).expect("ray direction should be valid"),
        );

        let (hit_actor, _) = actor_hit_at_ray(&snapshot, 0, ray, ViewerRenderConfig::default())
            .expect("ray should hit actor body volume");

        assert_eq!(hit_actor.actor_id, ActorId(99));
    }

    #[test]
    fn map_object_ray_pick_hits_interactive_volume() {
        let snapshot = SimulationSnapshot {
            turn: TurnState::default(),
            actors: Vec::new(),
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: Some(6),
                map_height: Some(6),
                default_level: Some(0),
                levels: vec![0],
                static_obstacles: Vec::new(),
                map_blocked_cells: vec![GridCoord::new(2, 0, 1)],
                map_cells: Vec::new(),
                map_objects: vec![MapObjectDebugState {
                    object_id: "terminal".into(),
                    kind: MapObjectKind::Interactive,
                    anchor: GridCoord::new(2, 0, 1),
                    footprint: MapObjectFootprint::default(),
                    rotation: MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    occupied_cells: vec![GridCoord::new(2, 0, 1)],
                    payload_summary: BTreeMap::from([(
                        "interaction_kind".to_string(),
                        "terminal".to_string(),
                    )]),
                }],
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            vision: Default::default(),
            generated_buildings: Vec::new(),
            generated_doors: Vec::new(),
            combat: CombatDebugState {
                in_combat: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            interaction_context: InteractionContextSnapshot::default(),
            overworld: OverworldStateSnapshot::default(),
            path_preview: Vec::new(),
        };
        let ray = Ray3d::new(
            Vec3::new(2.5, 0.5, -2.0),
            Dir3::new(Vec3::new(0.0, 0.0, 1.0)).expect("ray direction should be valid"),
        );

        let (hit, _) = map_object_hit_at_ray(&snapshot, 0, ray, ViewerRenderConfig::default())
            .expect("ray should hit interactive object volume");

        assert_eq!(hit.object_id, "terminal");
    }

    #[test]
    fn generated_door_ray_pick_hits_visible_door_volume() {
        let snapshot = SimulationSnapshot {
            turn: TurnState::default(),
            actors: Vec::new(),
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: Some(6),
                map_height: Some(6),
                default_level: Some(0),
                levels: vec![0],
                static_obstacles: Vec::new(),
                map_blocked_cells: vec![GridCoord::new(1, 0, 0)],
                map_cells: Vec::new(),
                map_objects: vec![MapObjectDebugState {
                    object_id: "door".into(),
                    kind: MapObjectKind::Interactive,
                    anchor: GridCoord::new(1, 0, 0),
                    footprint: MapObjectFootprint::default(),
                    rotation: MapRotation::North,
                    blocks_movement: true,
                    blocks_sight: true,
                    occupied_cells: vec![GridCoord::new(1, 0, 0)],
                    payload_summary: BTreeMap::from([(
                        "generated_door".to_string(),
                        "true".to_string(),
                    )]),
                }],
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            vision: Default::default(),
            generated_buildings: Vec::new(),
            generated_doors: vec![GeneratedDoorDebugState {
                door_id: "door".into(),
                map_object_id: "door".into(),
                building_object_id: "building".into(),
                building_anchor: GridCoord::new(0, 0, 0),
                level: 0,
                opening_id: 0,
                anchor_grid: GridCoord::new(1, 0, 0),
                axis: GeometryAxis::Vertical,
                kind: DoorOpeningKind::Exterior,
                polygon: GeometryPolygon2 {
                    outer: vec![
                        GeometryPoint2::new(1.0, 0.0),
                        GeometryPoint2::new(2.0, 0.0),
                        GeometryPoint2::new(2.0, 0.12),
                        GeometryPoint2::new(1.0, 0.12),
                    ],
                    holes: Vec::new(),
                },
                wall_height: 2.35,
                is_open: false,
                is_locked: false,
            }],
            combat: CombatDebugState {
                in_combat: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            interaction_context: InteractionContextSnapshot::default(),
            overworld: OverworldStateSnapshot::default(),
            path_preview: Vec::new(),
        };
        let ray = Ray3d::new(
            Vec3::new(1.5, 1.0, -2.0),
            Dir3::new(Vec3::new(0.0, 0.0, 1.0)).expect("ray direction should be valid"),
        );

        let hit = generated_door_object_hit_at_ray(
            &snapshot,
            0,
            ray,
            ViewerRenderConfig::default().floor_thickness_world,
        )
        .expect("ray should hit generated door volume");

        assert_eq!(hit.0.object_id, "door");
    }

    #[test]
    fn occluder_blocking_rejects_box_behind_target() {
        let blocks = occluder_blocks_target(
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(4.0, 0.0, 0.0),
            Vec3::new(6.0, 0.0, 0.0),
            Vec3::splat(0.5),
        );

        assert!(!blocks);
    }

    #[test]
    fn occluder_blocking_accepts_box_between_camera_and_target() {
        let blocks = occluder_blocks_target(
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(6.0, 0.0, 0.0),
            Vec3::new(3.0, 0.0, 0.0),
            Vec3::splat(0.5),
        );

        assert!(blocks);
    }

    fn demo_snapshot_with_actors(actors: Vec<ActorDebugState>) -> SimulationSnapshot {
        SimulationSnapshot {
            turn: TurnState::default(),
            actors,
            grid: GridDebugState {
                grid_size: 1.0,
                map_id: None,
                map_width: Some(8),
                map_height: Some(8),
                default_level: Some(0),
                levels: vec![0, 1, 2],
                static_obstacles: Vec::new(),
                map_blocked_cells: Vec::new(),
                map_cells: Vec::new(),
                map_objects: Vec::new(),
                runtime_blocked_cells: Vec::new(),
                topology_version: 0,
                runtime_obstacle_version: 0,
            },
            vision: Default::default(),
            generated_buildings: Vec::new(),
            generated_doors: Vec::new(),
            combat: CombatDebugState {
                in_combat: false,
                current_actor_id: None,
                current_group_id: None,
                current_turn_index: 0,
            },
            interaction_context: InteractionContextSnapshot::default(),
            overworld: OverworldStateSnapshot::default(),
            path_preview: Vec::new(),
        }
    }
}
