use std::collections::{HashMap, HashSet};

use game_data::{ActorId, GridCoord, WorldCoord};

use super::math::{grid_to_world, world_to_grid, DEFAULT_GRID_SIZE};

#[derive(Debug, Clone)]
pub struct GridWorld {
    grid_size: f32,
    static_obstacle_ref_counts: HashMap<GridCoord, u32>,
    runtime_occupants_by_cell: HashMap<GridCoord, HashSet<ActorId>>,
    runtime_actor_cells: HashMap<ActorId, GridCoord>,
    topology_version: u64,
    runtime_obstacle_version: u64,
}

impl Default for GridWorld {
    fn default() -> Self {
        Self {
            grid_size: DEFAULT_GRID_SIZE,
            static_obstacle_ref_counts: HashMap::new(),
            runtime_occupants_by_cell: HashMap::new(),
            runtime_actor_cells: HashMap::new(),
            topology_version: 0,
            runtime_obstacle_version: 0,
        }
    }
}

impl GridWorld {
    pub fn grid_size(&self) -> f32 {
        self.grid_size
    }

    pub fn world_to_grid(&self, world: WorldCoord) -> GridCoord {
        world_to_grid(world, self.grid_size)
    }

    pub fn grid_to_world(&self, grid: GridCoord) -> WorldCoord {
        grid_to_world(grid, self.grid_size)
    }

    pub fn snap_to_grid(&self, world: WorldCoord) -> WorldCoord {
        self.grid_to_world(self.world_to_grid(world))
    }

    pub fn register_static_obstacle(&mut self, grid: GridCoord) {
        let next_count = self
            .static_obstacle_ref_counts
            .get(&grid)
            .copied()
            .unwrap_or(0)
            + 1;
        self.static_obstacle_ref_counts.insert(grid, next_count);
        self.topology_version += 1;
    }

    pub fn unregister_static_obstacle(&mut self, grid: GridCoord) {
        let Some(current_count) = self.static_obstacle_ref_counts.get(&grid).copied() else {
            return;
        };

        if current_count <= 1 {
            self.static_obstacle_ref_counts.remove(&grid);
        } else {
            self.static_obstacle_ref_counts
                .insert(grid, current_count - 1);
        }
        self.topology_version += 1;
    }

    pub fn is_walkable(&self, grid: GridCoord) -> bool {
        self.is_walkable_static(grid) && self.is_walkable_dynamic(grid)
    }

    pub fn is_walkable_static(&self, grid: GridCoord) -> bool {
        !self.static_obstacle_ref_counts.contains_key(&grid)
    }

    pub fn is_walkable_dynamic(&self, grid: GridCoord) -> bool {
        !self.runtime_occupants_by_cell.contains_key(&grid)
    }

    pub fn is_walkable_for_actor(&self, grid: GridCoord, actor_id: Option<ActorId>) -> bool {
        if !self.is_walkable_static(grid) {
            return false;
        }

        let Some(occupants) = self.runtime_occupants_by_cell.get(&grid) else {
            return true;
        };

        match actor_id {
            None => occupants.is_empty(),
            Some(actor_id) => occupants.len() == 1 && occupants.contains(&actor_id),
        }
    }

    pub fn set_runtime_actor_grid(&mut self, actor_id: ActorId, next_grid: GridCoord) {
        if self.runtime_actor_cells.get(&actor_id).copied() == Some(next_grid) {
            return;
        }

        if let Some(previous_grid) = self.runtime_actor_cells.insert(actor_id, next_grid) {
            if let Some(occupants) = self.runtime_occupants_by_cell.get_mut(&previous_grid) {
                occupants.remove(&actor_id);
                if occupants.is_empty() {
                    self.runtime_occupants_by_cell.remove(&previous_grid);
                }
            }
        }

        self.runtime_occupants_by_cell
            .entry(next_grid)
            .or_default()
            .insert(actor_id);
        self.runtime_obstacle_version += 1;
    }

    pub fn unregister_runtime_actor(&mut self, actor_id: ActorId) {
        let Some(previous_grid) = self.runtime_actor_cells.remove(&actor_id) else {
            return;
        };

        if let Some(occupants) = self.runtime_occupants_by_cell.get_mut(&previous_grid) {
            occupants.remove(&actor_id);
            if occupants.is_empty() {
                self.runtime_occupants_by_cell.remove(&previous_grid);
            }
        }
        self.runtime_obstacle_version += 1;
    }

    pub fn runtime_blocked_cells(&self) -> Vec<GridCoord> {
        let mut blocked: HashSet<GridCoord> = self
            .static_obstacle_ref_counts
            .keys()
            .copied()
            .collect();
        blocked.extend(self.runtime_occupants_by_cell.keys().copied());

        let mut cells: Vec<GridCoord> = blocked.into_iter().collect();
        cells.sort_by_key(|cell| (cell.y, cell.z, cell.x));
        cells
    }

    pub fn static_obstacle_cells(&self) -> Vec<GridCoord> {
        let mut cells: Vec<GridCoord> = self.static_obstacle_ref_counts.keys().copied().collect();
        cells.sort_by_key(|cell| (cell.y, cell.z, cell.x));
        cells
    }

    pub fn topology_version(&self) -> u64 {
        self.topology_version
    }

    pub fn runtime_obstacle_version(&self) -> u64 {
        self.runtime_obstacle_version
    }
}
