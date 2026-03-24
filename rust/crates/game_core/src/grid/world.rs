use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use game_data::{
    expand_object_footprint, object_effectively_blocks_movement, ActorId, GridCoord,
    MapCellDefinition, MapDefinition, MapId, MapObjectDefinition, MapSize, WorldCoord,
};

use super::math::{grid_to_world, world_to_grid, DEFAULT_GRID_SIZE};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GridWalkability {
    Walkable,
    OutOfBounds,
    InvalidLevel,
    StaticBlocked,
    Occupied,
}

#[derive(Debug, Clone)]
pub struct GridWorld {
    grid_size: f32,
    manual_static_obstacle_ref_counts: HashMap<GridCoord, u32>,
    runtime_occupants_by_cell: HashMap<GridCoord, HashSet<ActorId>>,
    runtime_actor_cells: HashMap<ActorId, GridCoord>,
    map_id: Option<MapId>,
    map_size: Option<MapSize>,
    default_level: Option<i32>,
    levels: BTreeSet<i32>,
    map_cells: HashMap<GridCoord, MapCellDefinition>,
    map_objects: BTreeMap<String, MapObjectDefinition>,
    map_object_cells: HashMap<GridCoord, Vec<String>>,
    map_blocked_cells: HashSet<GridCoord>,
    topology_version: u64,
    runtime_obstacle_version: u64,
}

impl Default for GridWorld {
    fn default() -> Self {
        Self {
            grid_size: DEFAULT_GRID_SIZE,
            manual_static_obstacle_ref_counts: HashMap::new(),
            runtime_occupants_by_cell: HashMap::new(),
            runtime_actor_cells: HashMap::new(),
            map_id: None,
            map_size: None,
            default_level: None,
            levels: BTreeSet::new(),
            map_cells: HashMap::new(),
            map_objects: BTreeMap::new(),
            map_object_cells: HashMap::new(),
            map_blocked_cells: HashSet::new(),
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

    pub fn load_map(&mut self, definition: &MapDefinition) {
        self.map_id = Some(definition.id.clone());
        self.map_size = Some(definition.size);
        self.default_level = Some(definition.default_level);
        self.levels = definition.levels.iter().map(|level| level.y).collect();
        self.map_cells.clear();
        self.map_objects.clear();
        self.map_object_cells.clear();
        self.map_blocked_cells.clear();

        for level in &definition.levels {
            for cell in &level.cells {
                let coord = GridCoord::new(cell.x as i32, level.y, cell.z as i32);
                if cell.blocks_movement {
                    self.map_blocked_cells.insert(coord);
                }
                self.map_cells.insert(coord, cell.clone());
            }
        }

        for object in &definition.objects {
            self.map_objects
                .insert(object.object_id.clone(), object.clone());

            for cell in expand_object_footprint(object) {
                self.map_object_cells
                    .entry(cell)
                    .or_default()
                    .push(object.object_id.clone());
                if object_effectively_blocks_movement(object) {
                    self.map_blocked_cells.insert(cell);
                }
            }
        }

        for object_ids in self.map_object_cells.values_mut() {
            object_ids.sort();
            object_ids.dedup();
        }

        self.topology_version = self.topology_version.saturating_add(1);
    }

    pub fn clear_map(&mut self) {
        self.map_id = None;
        self.map_size = None;
        self.default_level = None;
        self.levels.clear();
        self.map_cells.clear();
        self.map_objects.clear();
        self.map_object_cells.clear();
        self.map_blocked_cells.clear();
        self.topology_version = self.topology_version.saturating_add(1);
    }

    pub fn map_id(&self) -> Option<&MapId> {
        self.map_id.as_ref()
    }

    pub fn map_size(&self) -> Option<MapSize> {
        self.map_size
    }

    pub fn default_level(&self) -> Option<i32> {
        self.default_level
    }

    pub fn levels(&self) -> Vec<i32> {
        self.levels.iter().copied().collect()
    }

    pub fn has_level(&self, y: i32) -> bool {
        self.levels.contains(&y)
    }

    pub fn is_in_bounds(&self, grid: GridCoord) -> bool {
        if let Some(size) = self.map_size {
            if grid.x < 0 || grid.z < 0 {
                return false;
            }
            if (grid.x as u32) >= size.width || (grid.z as u32) >= size.height {
                return false;
            }
        }

        if !self.levels.is_empty() && !self.levels.contains(&grid.y) {
            return false;
        }

        true
    }

    pub fn map_cell(&self, grid: GridCoord) -> Option<&MapCellDefinition> {
        self.map_cells.get(&grid)
    }

    pub fn map_object(&self, object_id: &str) -> Option<&MapObjectDefinition> {
        self.map_objects.get(object_id)
    }

    pub fn map_objects_at(&self, grid: GridCoord) -> Vec<&MapObjectDefinition> {
        self.map_object_cells
            .get(&grid)
            .into_iter()
            .flat_map(|object_ids| object_ids.iter())
            .filter_map(|object_id| self.map_objects.get(object_id))
            .collect()
    }

    pub fn map_object_footprint_cells(&self, object_id: &str) -> Vec<GridCoord> {
        self.map_objects
            .get(object_id)
            .map(expand_object_footprint)
            .unwrap_or_default()
    }

    pub fn map_cell_entries(&self) -> Vec<(GridCoord, MapCellDefinition)> {
        let mut entries: Vec<(GridCoord, MapCellDefinition)> = self
            .map_cells
            .iter()
            .map(|(grid, cell)| (*grid, cell.clone()))
            .collect();
        entries.sort_by_key(|(grid, _)| (grid.y, grid.z, grid.x));
        entries
    }

    pub fn map_object_entries(&self) -> Vec<MapObjectDefinition> {
        self.map_objects.values().cloned().collect()
    }

    pub fn upsert_map_object(&mut self, object: MapObjectDefinition) {
        if self.map_objects.contains_key(&object.object_id) {
            let _ = self.remove_map_object(&object.object_id);
        }

        let object_id = object.object_id.clone();
        for cell in expand_object_footprint(&object) {
            self.map_object_cells
                .entry(cell)
                .or_default()
                .push(object_id.clone());
            if object_effectively_blocks_movement(&object) {
                self.map_blocked_cells.insert(cell);
            }
        }

        for object_ids in self.map_object_cells.values_mut() {
            object_ids.sort();
            object_ids.dedup();
        }

        self.map_objects.insert(object_id, object);
        self.topology_version = self.topology_version.saturating_add(1);
    }

    pub fn remove_map_object(&mut self, object_id: &str) -> Option<MapObjectDefinition> {
        let removed = self.map_objects.remove(object_id)?;

        for cell in expand_object_footprint(&removed) {
            if let Some(object_ids) = self.map_object_cells.get_mut(&cell) {
                object_ids.retain(|entry| entry != object_id);
                if object_ids.is_empty() {
                    self.map_object_cells.remove(&cell);
                }
            }

            if object_effectively_blocks_movement(&removed) {
                let still_blocked = self
                    .map_object_cells
                    .get(&cell)
                    .into_iter()
                    .flat_map(|ids| ids.iter())
                    .filter_map(|id| self.map_objects.get(id))
                    .any(object_effectively_blocks_movement);
                if !still_blocked
                    && !self
                        .map_cells
                        .get(&cell)
                        .is_some_and(|cell| cell.blocks_movement)
                {
                    self.map_blocked_cells.remove(&cell);
                }
            }
        }

        self.topology_version = self.topology_version.saturating_add(1);
        Some(removed)
    }

    pub fn map_blocked_cells(&self, level: Option<i32>) -> Vec<GridCoord> {
        let mut cells: Vec<GridCoord> = self
            .map_blocked_cells
            .iter()
            .copied()
            .filter(|grid| level.is_none_or(|target_y| target_y == grid.y))
            .collect();
        cells.sort_by_key(|cell| (cell.y, cell.z, cell.x));
        cells
    }

    pub fn register_static_obstacle(&mut self, grid: GridCoord) {
        let next_count = self
            .manual_static_obstacle_ref_counts
            .get(&grid)
            .copied()
            .unwrap_or(0)
            + 1;
        self.manual_static_obstacle_ref_counts
            .insert(grid, next_count);
        self.topology_version = self.topology_version.saturating_add(1);
    }

    pub fn unregister_static_obstacle(&mut self, grid: GridCoord) {
        let Some(current_count) = self.manual_static_obstacle_ref_counts.get(&grid).copied() else {
            return;
        };

        if current_count <= 1 {
            self.manual_static_obstacle_ref_counts.remove(&grid);
        } else {
            self.manual_static_obstacle_ref_counts
                .insert(grid, current_count - 1);
        }
        self.topology_version = self.topology_version.saturating_add(1);
    }

    pub fn is_walkable(&self, grid: GridCoord) -> bool {
        self.is_walkable_static(grid) && self.is_walkable_dynamic(grid)
    }

    pub fn is_walkable_static(&self, grid: GridCoord) -> bool {
        matches!(
            self.classify_walkability_for_actor(grid, None),
            GridWalkability::Walkable | GridWalkability::Occupied
        )
    }

    pub fn is_walkable_dynamic(&self, grid: GridCoord) -> bool {
        !self.runtime_occupants_by_cell.contains_key(&grid)
    }

    pub fn is_walkable_for_actor(&self, grid: GridCoord, actor_id: Option<ActorId>) -> bool {
        self.classify_walkability_for_actor(grid, actor_id) == GridWalkability::Walkable
    }

    pub fn classify_walkability_for_actor(
        &self,
        grid: GridCoord,
        actor_id: Option<ActorId>,
    ) -> GridWalkability {
        if let Some(size) = self.map_size {
            if grid.x < 0 || grid.z < 0 {
                return GridWalkability::OutOfBounds;
            }
            if (grid.x as u32) >= size.width || (grid.z as u32) >= size.height {
                return GridWalkability::OutOfBounds;
            }
        }

        if !self.levels.is_empty() && !self.levels.contains(&grid.y) {
            return GridWalkability::InvalidLevel;
        }

        if self.manual_static_obstacle_ref_counts.contains_key(&grid)
            || self.map_blocked_cells.contains(&grid)
        {
            return GridWalkability::StaticBlocked;
        }

        let Some(occupants) = self.runtime_occupants_by_cell.get(&grid) else {
            return GridWalkability::Walkable;
        };

        match actor_id {
            None if occupants.is_empty() => GridWalkability::Walkable,
            Some(actor_id) if occupants.len() == 1 && occupants.contains(&actor_id) => {
                GridWalkability::Walkable
            }
            _ => GridWalkability::Occupied,
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
        self.runtime_obstacle_version = self.runtime_obstacle_version.saturating_add(1);
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
        self.runtime_obstacle_version = self.runtime_obstacle_version.saturating_add(1);
    }

    pub fn runtime_blocked_cells(&self) -> Vec<GridCoord> {
        let mut blocked: HashSet<GridCoord> = self.static_obstacle_cells().into_iter().collect();
        blocked.extend(self.runtime_occupants_by_cell.keys().copied());

        let mut cells: Vec<GridCoord> = blocked.into_iter().collect();
        cells.sort_by_key(|cell| (cell.y, cell.z, cell.x));
        cells
    }

    pub fn static_obstacle_cells(&self) -> Vec<GridCoord> {
        let mut cells: HashSet<GridCoord> = self
            .manual_static_obstacle_ref_counts
            .keys()
            .copied()
            .collect();
        cells.extend(self.map_blocked_cells.iter().copied());

        let mut sorted: Vec<GridCoord> = cells.into_iter().collect();
        sorted.sort_by_key(|cell| (cell.y, cell.z, cell.x));
        sorted
    }

    pub fn topology_version(&self) -> u64 {
        self.topology_version
    }

    pub fn runtime_obstacle_version(&self) -> u64 {
        self.runtime_obstacle_version
    }
}
