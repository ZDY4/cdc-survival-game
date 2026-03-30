use bevy::prelude::*;
use game_core::{ActorDebugState, SimulationRuntime, SimulationSnapshot};
use game_data::{ActorSide, GridCoord, InteractionTargetId, WorldCoord};

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
        .find(|object| object.occupied_cells.contains(&grid))
        .cloned()
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

pub(crate) fn resolve_occlusion_target<'a>(
    snapshot: &'a SimulationSnapshot,
    viewer_state: &ViewerState,
) -> Option<&'a ActorDebugState> {
    if let Some(actor) = selected_actor(snapshot, viewer_state) {
        if actor.side == ActorSide::Player {
            return (actor.grid_position.y == viewer_state.current_level).then_some(actor);
        }
        return snapshot.actors.iter().find(|candidate| {
            candidate.side == ActorSide::Player
                && candidate.grid_position.y == viewer_state.current_level
        });
    }

    snapshot.actors.iter().find(|actor| {
        actor.side == ActorSide::Player && actor.grid_position.y == viewer_state.current_level
    })
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
                .map(|object| format!("{} ({:?})", object.object_id, object.kind))
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
        actor_label, camera_focus_point, camera_pan_delta_from_ground_drag, camera_world_distance,
        clamp_camera_pan_offset, cycle_level, grid_bounds, hovered_grid_outline_kind,
        level_plane_height, movement_block_reasons, occluder_blocks_target, pick_grid_from_ray,
        rendered_path_preview, resolve_occlusion_target, segment_aabb_intersection_fraction,
        should_rebuild_static_world, visible_world_footprint, GridBounds, HoveredGridOutlineKind,
    };
    use crate::state::{ViewerRenderConfig, ViewerState};
    use crate::test_support::actor_debug_state_fixture;
    use bevy::prelude::*;
    use game_core::{
        create_demo_runtime, ActorDebugState, CombatDebugState, GridDebugState, MapCellDebugState,
        MapObjectDebugState, OverworldStateSnapshot, SimulationSnapshot,
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
            generated_buildings: Vec::new(),
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
            generated_buildings: Vec::new(),
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
            generated_buildings: Vec::new(),
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
            generated_buildings: Vec::new(),
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
