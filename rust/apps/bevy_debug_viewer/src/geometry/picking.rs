use bevy::prelude::*;
use game_core::{ActorDebugState, SimulationSnapshot};
use game_data::{GridCoord, MapObjectKind, WorldCoord};

use crate::geometry::{
    actor_body_translation, level_base_height, MISSING_GEO_BUILDING_PLACEHOLDER_HEIGHT_SCALE,
};
use crate::state::ViewerRenderConfig;

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
            if should_prefer_generated_door_hit(&door.0, &object.0) || door.1 <= object.1 {
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

fn is_generated_door_object(object: &game_core::MapObjectDebugState) -> bool {
    object
        .payload_summary
        .get("generated_door")
        .is_some_and(|value| value == "true")
}

fn should_prefer_generated_door_hit(
    door: &game_core::MapObjectDebugState,
    object: &game_core::MapObjectDebugState,
) -> bool {
    object.kind == MapObjectKind::Building
        && door
            .payload_summary
            .get("building_object_id")
            .is_some_and(|building_id| building_id == &object.object_id)
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
