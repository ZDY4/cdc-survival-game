//! 几何模块测试：覆盖相机、拾取、遮挡与世界边界相关 helper 的回归场景。

use super::{
    actor_hit_at_ray, actor_label, camera_focus_point, camera_pan_delta_from_ground_drag,
    camera_world_distance, clamp_camera_pan_offset, cycle_level, generated_door_object_hit_at_ray,
    grid_bounds, grid_focus_world_position, grid_walkability_debug_info, hovered_grid_outline_kind,
    level_plane_height, map_object_hit_at_ray, movement_block_reasons,
    movement_block_reasons_for_actor, occluder_blocks_target, pick_grid_from_ray,
    rendered_path_preview, resolve_occlusion_focus_points, resolve_occlusion_target,
    segment_aabb_intersection_fraction, should_rebuild_static_world, viewer_grid_is_walkable,
    visible_world_footprint, GridBounds, HoveredGridOutlineKind, OcclusionFocusPoint,
};
use crate::state::{ViewerControlMode, ViewerRenderConfig, ViewerState};
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
            map_id: Some(MapId("survivor_outpost_01".into())),
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
fn movement_block_reasons_for_actor_ignores_selected_actor_occupancy() {
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
            static_obstacles: Vec::new(),
            map_blocked_cells: Vec::new(),
            map_cells: Vec::new(),
            map_objects: Vec::new(),
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

    let reasons = movement_block_reasons_for_actor(&snapshot, grid, Some(ActorId(9)));
    assert!(!reasons
        .iter()
        .any(|reason| reason.contains("runtime_actor")));
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
fn hovered_grid_outline_marks_hovered_empty_cell() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let viewer_state = ViewerState {
        selected_actor: Some(handles.player),
        current_level: 0,
        ..ViewerState::default()
    };

    let outline =
        hovered_grid_outline_kind(&runtime, &snapshot, &viewer_state, GridCoord::new(0, 0, 1));

    assert_eq!(outline, Some(HoveredGridOutlineKind::Neutral));
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
fn hovered_grid_outline_keeps_showing_for_blocked_in_bounds_cell() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let viewer_state = ViewerState {
        selected_actor: Some(handles.player),
        current_level: 0,
        ..ViewerState::default()
    };

    let outline =
        hovered_grid_outline_kind(&runtime, &snapshot, &viewer_state, GridCoord::new(2, 0, 1));

    assert_eq!(outline, Some(HoveredGridOutlineKind::Neutral));
}

#[test]
fn hovered_grid_outline_hides_out_of_bounds_cell() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let viewer_state = ViewerState {
        selected_actor: Some(handles.player),
        current_level: 0,
        ..ViewerState::default()
    };

    let outline =
        hovered_grid_outline_kind(&runtime, &snapshot, &viewer_state, GridCoord::new(0, 99, 0));

    assert_eq!(outline, None);
}

#[test]
fn viewer_grid_walkable_uses_actor_aware_semantics_for_selected_actor_cell() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let player_grid = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == handles.player)
        .expect("player should exist")
        .grid_position;
    let viewer_state = ViewerState {
        selected_actor: Some(handles.player),
        current_level: player_grid.y,
        ..ViewerState::default()
    };

    assert!(viewer_grid_is_walkable(
        &runtime,
        &snapshot,
        &viewer_state,
        player_grid
    ));
}

#[test]
fn viewer_grid_walkable_falls_back_to_runtime_semantics_without_command_actor() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let player_grid = snapshot
        .actors
        .iter()
        .find(|actor| actor.actor_id == handles.player)
        .expect("player should exist")
        .grid_position;
    let viewer_state = ViewerState {
        control_mode: ViewerControlMode::FreeObserve,
        current_level: player_grid.y,
        ..ViewerState::default()
    };

    assert!(!viewer_grid_is_walkable(
        &runtime,
        &snapshot,
        &viewer_state,
        player_grid
    ));
}

#[test]
fn grid_walkability_debug_info_reports_block_reasons_for_unwalkable_grid() {
    let (runtime, handles) = create_demo_runtime();
    let snapshot = runtime.snapshot();
    let viewer_state = ViewerState {
        selected_actor: Some(handles.player),
        current_level: 0,
        ..ViewerState::default()
    };

    let info =
        grid_walkability_debug_info(&runtime, &snapshot, &viewer_state, GridCoord::new(2, 0, 1));

    assert!(!info.is_walkable);
    assert!(!info.reasons.is_empty());
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
    let current = Some((Some("survivor_outpost_01"), 0, 3_u64));
    let next_same = (Some("survivor_outpost_01"), 0, 3_u64);
    let next_level = (Some("survivor_outpost_01"), 1, 3_u64);

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

    let target =
        resolve_occlusion_target(&snapshot, &viewer_state).expect("selected player should be used");

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
fn map_object_ray_pick_prefers_generated_door_over_parent_building() {
    let building_cells = (0..=2)
        .flat_map(|x| (0..=2).map(move |z| GridCoord::new(x, 0, z)))
        .collect::<Vec<_>>();
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
            map_blocked_cells: building_cells.clone(),
            map_cells: Vec::new(),
            map_objects: vec![
                MapObjectDebugState {
                    object_id: "building".into(),
                    kind: MapObjectKind::Building,
                    anchor: GridCoord::new(0, 0, 0),
                    footprint: MapObjectFootprint {
                        width: 3,
                        height: 3,
                    },
                    rotation: MapRotation::North,
                    blocks_movement: false,
                    blocks_sight: false,
                    occupied_cells: building_cells,
                    payload_summary: BTreeMap::new(),
                },
                MapObjectDebugState {
                    object_id: "door".into(),
                    kind: MapObjectKind::Interactive,
                    anchor: GridCoord::new(1, 0, 1),
                    footprint: MapObjectFootprint::default(),
                    rotation: MapRotation::East,
                    blocks_movement: true,
                    blocks_sight: true,
                    occupied_cells: vec![GridCoord::new(1, 0, 1)],
                    payload_summary: BTreeMap::from([
                        ("generated_door".to_string(), "true".to_string()),
                        ("building_object_id".to_string(), "building".to_string()),
                    ]),
                },
            ],
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
            anchor_grid: GridCoord::new(1, 0, 1),
            axis: GeometryAxis::Vertical,
            kind: DoorOpeningKind::Exterior,
            polygon: GeometryPolygon2 {
                outer: vec![
                    GeometryPoint2::new(1.2, 1.0),
                    GeometryPoint2::new(1.8, 1.0),
                    GeometryPoint2::new(1.8, 2.0),
                    GeometryPoint2::new(1.2, 2.0),
                ],
                holes: Vec::new(),
            },
            wall_height: 1.5,
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
        Vec3::new(1.5, 0.9, -2.0),
        Dir3::new(Vec3::new(0.0, 0.0, 1.0)).expect("ray direction should be valid"),
    );

    let (hit, _) = map_object_hit_at_ray(&snapshot, 0, ray, ViewerRenderConfig::default())
        .expect("ray should prefer the generated door hit");

    assert_eq!(hit.object_id, "door");
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
