//! 在线 NPC runtime 辅助模块。
//! 负责锚点与可达格解析，不负责生命周期同步或行动执行。

use game_data::GridCoord;

pub(crate) fn resolve_anchor_grid(
    settlement: &game_data::SettlementDefinition,
    anchor_id: &str,
) -> Option<GridCoord> {
    settlement
        .anchors
        .iter()
        .find(|anchor| anchor.id == anchor_id)
        .map(|anchor| anchor.grid)
}

pub(crate) fn resolve_reachable_runtime_grid(
    snapshot: &game_core::SimulationSnapshot,
    desired_grid: GridCoord,
    actor_id: Option<game_data::ActorId>,
) -> Option<GridCoord> {
    if is_runtime_grid_walkable(snapshot, desired_grid, actor_id) {
        return Some(desired_grid);
    }

    let max_radius = snapshot
        .grid
        .map_width
        .zip(snapshot.grid.map_height)
        .map(|(width, height)| width.max(height) as i32)
        .unwrap_or(8)
        .max(1);

    for radius in 1..=max_radius {
        for candidate in collect_ring_cells(desired_grid, radius) {
            if is_runtime_grid_walkable(snapshot, candidate, actor_id) {
                return Some(candidate);
            }
        }
    }

    None
}

fn is_runtime_grid_walkable(
    snapshot: &game_core::SimulationSnapshot,
    grid: GridCoord,
    actor_id: Option<game_data::ActorId>,
) -> bool {
    if grid.x < 0 || grid.z < 0 {
        return false;
    }

    if let Some(width) = snapshot.grid.map_width {
        if grid.x as u32 >= width {
            return false;
        }
    }
    if let Some(height) = snapshot.grid.map_height {
        if grid.z as u32 >= height {
            return false;
        }
    }
    if !snapshot.grid.levels.is_empty() && !snapshot.grid.levels.contains(&grid.y) {
        return false;
    }
    if snapshot.grid.map_blocked_cells.contains(&grid) {
        return false;
    }
    if snapshot.grid.runtime_blocked_cells.contains(&grid) {
        return actor_id
            .and_then(|actor_id| {
                snapshot
                    .actors
                    .iter()
                    .find(|actor| actor.actor_id == actor_id)
                    .map(|actor| actor.grid_position == grid)
            })
            .unwrap_or(false);
    }

    true
}

fn collect_ring_cells(center: GridCoord, radius: i32) -> Vec<GridCoord> {
    let mut cells = Vec::new();
    for dx in -radius..=radius {
        for dz in -radius..=radius {
            if dx.abs().max(dz.abs()) != radius {
                continue;
            }
            cells.push(GridCoord::new(center.x + dx, center.y, center.z + dz));
        }
    }
    cells
}
