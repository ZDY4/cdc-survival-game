//! 静态世界组装中的几何与网格辅助函数，保持为纯计算逻辑。

use std::collections::HashSet;

use bevy::prelude::*;
use game_core::{GeneratedStairConnection, SimulationSnapshot};
use game_data::{GridCoord, MapRotation};

use super::types::{BuildingWallNeighborMask, StaticWorldGridBounds};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct MergedGridRect {
    pub level: i32,
    pub min_x: i32,
    pub max_x: i32,
    pub min_z: i32,
    pub max_z: i32,
}

pub(crate) fn grid_cell_center(grid: GridCoord, grid_size: f32) -> Vec3 {
    Vec3::new(
        (grid.x as f32 + 0.5) * grid_size,
        (grid.y as f32 + 0.5) * grid_size,
        (grid.z as f32 + 0.5) * grid_size,
    )
}

pub(crate) fn simulation_bounds(
    snapshot: &SimulationSnapshot,
    level: i32,
) -> StaticWorldGridBounds {
    if let (Some(width), Some(height)) = (snapshot.grid.map_width, snapshot.grid.map_height) {
        return StaticWorldGridBounds {
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
    StaticWorldGridBounds {
        min_x,
        max_x,
        min_z,
        max_z,
    }
}

pub(crate) fn expand_bounds(bounds: &mut Option<StaticWorldGridBounds>, grid: GridCoord) {
    match bounds {
        Some(bounds) => {
            bounds.min_x = bounds.min_x.min(grid.x);
            bounds.max_x = bounds.max_x.max(grid.x);
            bounds.min_z = bounds.min_z.min(grid.z);
            bounds.max_z = bounds.max_z.max(grid.z);
        }
        None => {
            *bounds = Some(StaticWorldGridBounds {
                min_x: grid.x,
                max_x: grid.x,
                min_z: grid.z,
                max_z: grid.z,
            });
        }
    }
}

pub(crate) fn occupied_cells_box(cells: &[GridCoord], grid_size: f32) -> (f32, f32, f32, f32) {
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
    let center_x = (min_x + max_x + 1) as f32 * grid_size * 0.5;
    let center_z = (min_z + max_z + 1) as f32 * grid_size * 0.5;
    let width = (max_x - min_x + 1) as f32 * grid_size;
    let depth = (max_z - min_z + 1) as f32 * grid_size;
    (center_x, center_z, width, depth)
}

pub(crate) fn stair_run_direction(stair: &GeneratedStairConnection) -> Vec2 {
    let count = stair.from_cells.len().max(1) as f32;
    let delta_x = stair
        .from_cells
        .iter()
        .zip(stair.to_cells.iter())
        .map(|(from, to)| (to.x - from.x) as f32)
        .sum::<f32>()
        / count;
    let delta_z = stair
        .from_cells
        .iter()
        .zip(stair.to_cells.iter())
        .map(|(from, to)| (to.z - from.z) as f32)
        .sum::<f32>()
        / count;
    if delta_x.abs() > delta_z.abs() && delta_x.abs() > f32::EPSILON {
        Vec2::new(delta_x.signum(), 0.0)
    } else if delta_z.abs() > f32::EPSILON {
        Vec2::new(0.0, delta_z.signum())
    } else {
        Vec2::new(0.0, 1.0)
    }
}

pub(crate) fn merge_cells_into_rects(cells: &[GridCoord]) -> Vec<MergedGridRect> {
    let mut remaining = cells.iter().copied().collect::<HashSet<_>>();
    let mut rects = Vec::new();
    while let Some(start) = remaining
        .iter()
        .min_by_key(|cell| (cell.y, cell.z, cell.x))
        .copied()
    {
        let mut max_x = start.x;
        while remaining.contains(&GridCoord::new(max_x + 1, start.y, start.z)) {
            max_x += 1;
        }
        let mut max_z = start.z;
        'grow_depth: loop {
            let next_z = max_z + 1;
            for x in start.x..=max_x {
                if !remaining.contains(&GridCoord::new(x, start.y, next_z)) {
                    break 'grow_depth;
                }
            }
            max_z = next_z;
        }
        for z in start.z..=max_z {
            for x in start.x..=max_x {
                remaining.remove(&GridCoord::new(x, start.y, z));
            }
        }
        rects.push(MergedGridRect {
            level: start.y,
            min_x: start.x,
            max_x,
            min_z: start.z,
            max_z,
        });
    }
    rects.sort_by_key(|rect| (rect.level, rect.min_z, rect.min_x, rect.max_z, rect.max_x));
    rects
}

pub(crate) fn rect_center(rect: MergedGridRect, grid_size: f32) -> Vec3 {
    Vec3::new(
        (rect.min_x + rect.max_x + 1) as f32 * grid_size * 0.5,
        (rect.level as f32 + 0.5) * grid_size,
        (rect.min_z + rect.max_z + 1) as f32 * grid_size * 0.5,
    )
}

pub(crate) fn rect_size(rect: MergedGridRect, grid_size: f32, inset_size: f32) -> Vec3 {
    let width_cells = (rect.max_x - rect.min_x + 1) as f32;
    let depth_cells = (rect.max_z - rect.min_z + 1) as f32;
    let scale = (inset_size / grid_size).clamp(0.0, 1.2);
    Vec3::new(
        width_cells * grid_size * scale,
        0.0,
        depth_cells * grid_size * scale,
    )
}

pub(crate) fn wall_tile_neighbors(
    cells: &HashSet<GridCoord>,
    grid: GridCoord,
) -> BuildingWallNeighborMask {
    BuildingWallNeighborMask {
        north: cells.contains(&GridCoord::new(grid.x, grid.y, grid.z - 1)),
        east: cells.contains(&GridCoord::new(grid.x + 1, grid.y, grid.z)),
        south: cells.contains(&GridCoord::new(grid.x, grid.y, grid.z + 1)),
        west: cells.contains(&GridCoord::new(grid.x - 1, grid.y, grid.z)),
    }
}

pub(crate) fn level_base_height(level: i32, grid_size: f32) -> f32 {
    level as f32 * grid_size
}

pub(crate) fn is_scene_transition_trigger_kind(kind: &str) -> bool {
    matches!(
        kind.trim(),
        "enter_subscene" | "enter_overworld" | "exit_to_outdoor" | "enter_outdoor_location"
    )
}

pub(crate) fn trigger_decal_rotation(rotation: MapRotation) -> Quat {
    let yaw = match rotation {
        MapRotation::North => std::f32::consts::PI,
        MapRotation::East => -std::f32::consts::FRAC_PI_2,
        MapRotation::South => 0.0,
        MapRotation::West => std::f32::consts::FRAC_PI_2,
    };
    Quat::from_rotation_y(yaw)
}
