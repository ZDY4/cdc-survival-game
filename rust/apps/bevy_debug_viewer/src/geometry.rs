use bevy::prelude::*;
use game_core::{ActorDebugState, SimulationRuntime, SimulationSnapshot};
use game_data::{GridCoord, InteractionTargetId, WorldCoord};

use crate::state::{ViewerHudPage, ViewerRenderConfig, ViewerState};

#[derive(Debug, Clone, Copy)]
pub(crate) struct GridBounds {
    pub min_x: i32,
    pub max_x: i32,
    pub min_z: i32,
    pub max_z: i32,
}

pub(crate) fn render_cell_extent(grid_size: f32, render_config: ViewerRenderConfig) -> f32 {
    grid_size * render_config.pixels_per_world_unit
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

pub(crate) fn fit_pixels_per_world_unit(
    viewport_width: f32,
    viewport_height: f32,
    grid_size: f32,
    bounds: GridBounds,
    render_config: ViewerRenderConfig,
) -> f32 {
    let grid_width_cells = (bounds.max_x - bounds.min_x + 1).max(1) as f32;
    let grid_height_cells = (bounds.max_z - bounds.min_z + 1).max(1) as f32;
    let usable_width = (viewport_width
        - render_config.hud_reserved_width_px
        - render_config.viewport_padding_px * 2.0)
        .max(160.0);
    let usable_height = (viewport_height - render_config.viewport_padding_px * 2.0).max(160.0);
    let fit_per_cell = (usable_width / grid_width_cells)
        .min(usable_height / (grid_height_cells * render_config.vertical_projection_factor()))
        .max(render_config.min_pixels_per_world_unit);

    (fit_per_cell * render_config.zoom_factor).clamp(
        render_config.min_pixels_per_world_unit,
        render_config.max_pixels_per_world_unit,
    ) / grid_size.max(f32::EPSILON)
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

pub(crate) fn pick_grid_from_ray(ray: Ray3d, level: i32, grid_size: f32) -> Option<GridCoord> {
    let plane_origin = Vec3::new(0.0, level_plane_height(level, grid_size), 0.0);
    let point = ray.plane_intersection_point(plane_origin, InfinitePlane3d::new(Vec3::Y))?;
    Some(GridCoord::new(
        (point.x / grid_size).floor() as i32,
        level,
        (point.z / grid_size).floor() as i32,
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
    grid_size: f32,
    render_config: ViewerRenderConfig,
) -> f32 {
    let world_width = (bounds.max_x - bounds.min_x + 1).max(1) as f32 * grid_size;
    let world_depth = (bounds.max_z - bounds.min_z + 1).max(1) as f32 * grid_size;
    (world_width.max(world_depth) * 1.35 + render_config.camera_distance_padding_world)
        .max(10.0 * grid_size)
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
    let map_width = (bounds.max_x - bounds.min_x + 1).max(1) as f32 * grid_size;
    let map_depth = (bounds.max_z - bounds.min_z + 1).max(1) as f32 * grid_size;
    let usable_width = (viewport_width
        - render_config.hud_reserved_width_px
        - render_config.viewport_padding_px * 2.0)
        .max(160.0)
        / render_config.pixels_per_world_unit.max(f32::EPSILON);
    let usable_depth = (viewport_height - render_config.viewport_padding_px * 2.0).max(160.0)
        / (render_config.pixels_per_world_unit * render_config.vertical_projection_factor())
            .max(f32::EPSILON);
    let half_visible_width = usable_width * 0.5;
    let half_visible_depth = usable_depth * 0.5;

    let clamped_focus_x = if map_width <= usable_width {
        center_x
    } else {
        (center_x + pan_offset.x).clamp(
            bounds.min_x as f32 * grid_size + half_visible_width,
            (bounds.max_x + 1) as f32 * grid_size - half_visible_width,
        )
    };
    let clamped_focus_z = if map_depth <= usable_depth {
        center_z
    } else {
        (center_z + pan_offset.y).clamp(
            bounds.min_z as f32 * grid_size + half_visible_depth,
            (bounds.max_z + 1) as f32 * grid_size - half_visible_depth,
        )
    };

    Vec2::new(clamped_focus_x - center_x, clamped_focus_z - center_z)
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
        actor_label, camera_focus_point, camera_world_distance, clamp_camera_pan_offset,
        cycle_level, fit_pixels_per_world_unit, grid_bounds, level_plane_height,
        movement_block_reasons, pick_grid_from_ray, rendered_path_preview,
        should_rebuild_static_world, GridBounds,
    };
    use crate::state::ViewerRenderConfig;
    use crate::test_support::actor_debug_state_fixture;
    use bevy::prelude::*;
    use game_core::{
        create_demo_runtime, CombatDebugState, GridDebugState, MapCellDebugState,
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

        let grid = pick_grid_from_ray(ray, 1, 1.0);

        assert_eq!(grid, Some(GridCoord::new(2, 1, 3)));
    }

    #[test]
    fn fit_scale_shrinks_when_bounds_grow() {
        let render_config = ViewerRenderConfig::default();
        let small = fit_pixels_per_world_unit(
            1440.0,
            900.0,
            1.0,
            GridBounds {
                min_x: 0,
                max_x: 5,
                min_z: 0,
                max_z: 5,
            },
            render_config,
        );
        let large = fit_pixels_per_world_unit(
            1440.0,
            900.0,
            1.0,
            GridBounds {
                min_x: 0,
                max_x: 19,
                min_z: 0,
                max_z: 19,
            },
            render_config,
        );

        assert!(large < small);
    }

    #[test]
    fn fit_scale_accounts_for_tilted_vertical_projection() {
        let mut shallow_pitch = ViewerRenderConfig::default();
        shallow_pitch.camera_pitch_degrees = 20.0;
        let mut steep_pitch = ViewerRenderConfig::default();
        steep_pitch.camera_pitch_degrees = 70.0;

        let shallow = fit_pixels_per_world_unit(
            1440.0,
            900.0,
            1.0,
            GridBounds {
                min_x: 0,
                max_x: 5,
                min_z: 0,
                max_z: 11,
            },
            shallow_pitch,
        );
        let steep = fit_pixels_per_world_unit(
            1440.0,
            900.0,
            1.0,
            GridBounds {
                min_x: 0,
                max_x: 5,
                min_z: 0,
                max_z: 11,
            },
            steep_pitch,
        );

        assert!(steep < shallow);
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
                map_id: Some(MapId("safehouse_grid".into())),
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
            1.0,
            ViewerRenderConfig::default(),
        );

        assert!(large > small);
    }

    #[test]
    fn static_world_rebuild_helper_only_triggers_on_key_change() {
        let current = Some((Some("safehouse_grid"), 0, 3_u64));
        let next_same = (Some("safehouse_grid"), 0, 3_u64);
        let next_level = (Some("safehouse_grid"), 1, 3_u64);

        assert!(!should_rebuild_static_world(&current, &next_same));
        assert!(should_rebuild_static_world(&current, &next_level));
    }

    #[test]
    fn clamp_camera_pan_offset_stops_at_map_edges() {
        let render_config = ViewerRenderConfig {
            pixels_per_world_unit: 100.0,
            hud_reserved_width_px: 0.0,
            viewport_padding_px: 0.0,
            camera_pitch_degrees: 90.0,
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

        assert_eq!(clamped, Vec2::new(3.0, -3.0));
    }

    #[test]
    fn clamp_camera_pan_offset_recenters_small_maps() {
        let render_config = ViewerRenderConfig {
            pixels_per_world_unit: 100.0,
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

        assert_eq!(clamped, Vec2::ZERO);
    }
}
