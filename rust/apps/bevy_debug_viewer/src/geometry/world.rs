use bevy::prelude::*;
use game_core::{ActorDebugState, SimulationRuntime, SimulationSnapshot};
use game_data::{GridCoord, WorldCoord};

use crate::geometry::GridBounds;
use crate::state::{ViewerRenderConfig, ViewerState};

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

pub(crate) fn should_rebuild_static_world<Key>(current: &Option<Key>, next: &Key) -> bool
where
    Key: PartialEq,
{
    current.as_ref() != Some(next)
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
