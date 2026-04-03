//! 几何辅助模块：统一组织 viewer 的相机投影、拾取、遮挡与世界空间换算 helper。

use game_data::{ActorId, GridCoord};

mod camera;
mod occlusion;
mod picking;
mod world;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct GridWalkabilityDebugInfo {
    pub is_walkable: bool,
    pub reasons: Vec<String>,
}

pub(crate) const MISSING_GEO_BUILDING_PLACEHOLDER_HEIGHT_SCALE: f32 = 1.15;

#[allow(unused_imports)]
pub(crate) use camera::{
    camera_focus_point, camera_pan_delta_from_ground_drag, camera_world_distance,
    clamp_camera_pan_offset, grid_focus_world_position, level_base_height, level_plane_height,
    pick_grid_from_ray, ray_point_on_horizontal_plane, visible_world_footprint,
};
#[allow(unused_imports)]
pub(crate) use occlusion::{
    focused_target_summary, grid_walkability_debug_info, hovered_grid_outline_kind,
    movement_block_reasons, movement_block_reasons_for_actor, occluder_blocks_target,
    resolve_occlusion_focus_points, resolve_occlusion_target, sight_block_reasons,
    viewer_grid_is_walkable,
};
#[allow(unused_imports)]
pub(crate) use picking::{
    actor_at_grid, actor_hit_at_ray, generated_door_object_hit_at_ray,
    is_missing_generated_building, map_object_at_grid, map_object_debug_label,
    map_object_hit_at_ray, missing_geo_building_placeholder_box,
    segment_aabb_intersection_fraction,
};
#[allow(unused_imports)]
pub(crate) use world::{
    actor_body_translation, actor_label, actor_label_world_position, cycle_level, grid_bounds,
    rendered_path_preview, selected_actor, should_rebuild_static_world,
};

#[cfg(test)]
mod tests;
