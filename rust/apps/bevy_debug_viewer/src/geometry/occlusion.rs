//! 遮挡几何 helper：负责焦点解析、遮挡检测和高亮/阻挡原因计算。

use bevy::prelude::*;
use game_core::{ActorDebugState, SimulationRuntime, SimulationSnapshot};
use game_data::{ActorId, ActorSide, GridCoord, InteractionTargetId};

use crate::geometry::{
    actor_at_grid, actor_label, map_object_debug_label, segment_aabb_intersection_fraction,
    selected_actor, GridWalkabilityDebugInfo, HoveredGridOutlineKind, OcclusionFocusPoint,
};
use crate::state::ViewerState;

pub(crate) fn hovered_grid_outline_kind(
    runtime: &SimulationRuntime,
    snapshot: &SimulationSnapshot,
    _viewer_state: &ViewerState,
    grid: GridCoord,
) -> Option<HoveredGridOutlineKind> {
    if actor_at_grid(snapshot, grid).is_some_and(|actor| actor.side == ActorSide::Hostile) {
        return Some(HoveredGridOutlineKind::Hostile);
    }

    if !runtime.is_grid_in_bounds(grid) {
        return None;
    }

    Some(HoveredGridOutlineKind::Neutral)
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

pub(crate) fn viewer_grid_is_walkable(
    runtime: &SimulationRuntime,
    snapshot: &SimulationSnapshot,
    viewer_state: &ViewerState,
    grid: GridCoord,
) -> bool {
    if !runtime.is_grid_in_bounds(grid) {
        return false;
    }

    viewer_state
        .command_actor_id(snapshot)
        .map(|actor_id| runtime.grid_walkable_for_actor(grid, Some(actor_id)))
        .unwrap_or_else(|| runtime.grid_walkable(grid))
}

pub(crate) fn grid_walkability_debug_info(
    runtime: &SimulationRuntime,
    snapshot: &SimulationSnapshot,
    viewer_state: &ViewerState,
    grid: GridCoord,
) -> GridWalkabilityDebugInfo {
    if !runtime.is_grid_in_bounds(grid) {
        return GridWalkabilityDebugInfo {
            is_walkable: false,
            reasons: vec!["out_of_bounds".to_string()],
        };
    }

    let actor_id = viewer_state.command_actor_id(snapshot);
    let is_walkable = actor_id
        .map(|actor_id| runtime.grid_walkable_for_actor(grid, Some(actor_id)))
        .unwrap_or_else(|| runtime.grid_walkable(grid));

    GridWalkabilityDebugInfo {
        is_walkable,
        reasons: if is_walkable {
            Vec::new()
        } else {
            movement_block_reasons_for_actor(snapshot, grid, actor_id)
        },
    }
}

pub(crate) fn movement_block_reasons(
    snapshot: &SimulationSnapshot,
    grid: GridCoord,
) -> Vec<String> {
    movement_block_reasons_for_actor(snapshot, grid, None)
}

pub(crate) fn movement_block_reasons_for_actor(
    snapshot: &SimulationSnapshot,
    grid: GridCoord,
    actor_id: Option<ActorId>,
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
        .filter(|actor| actor.grid_position == grid && Some(actor.actor_id) != actor_id)
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
