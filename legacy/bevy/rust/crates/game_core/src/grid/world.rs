use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

use game_data::{
    building_layout_story_levels, expand_object_footprint, object_effectively_blocks_movement,
    ActorId, GridCoord, InteractionOptionDefinition, MapCellDefinition, MapDefinition, MapId,
    MapInteractiveProps, MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapObjectProps,
    MapRotation, MapSize, WorldCoord,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use tracing::warn;

use super::math::{grid_to_world, world_to_grid, DEFAULT_GRID_SIZE};
use crate::building::{
    generate_building_layout, GeneratedBuildingDebugState, GeneratedDoorDebugState,
};
use crate::simulation::interaction_behaviors::door::generated_door_interaction_options as build_generated_door_interaction_options;

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
    uses_explicit_cells_as_bounds: bool,
    default_level: Option<i32>,
    levels: BTreeSet<i32>,
    base_map_cells: HashMap<GridCoord, MapCellDefinition>,
    map_cells: HashMap<GridCoord, MapCellDefinition>,
    map_objects: BTreeMap<String, MapObjectDefinition>,
    map_object_cells: HashMap<GridCoord, Vec<String>>,
    map_blocked_cells: HashSet<GridCoord>,
    generated_buildings: Vec<GeneratedBuildingDebugState>,
    generated_doors: Vec<GeneratedDoorDebugState>,
    generated_door_object_ids: BTreeSet<String>,
    stair_adjacency: HashMap<GridCoord, Vec<GridCoord>>,
    topology_version: u64,
    runtime_obstacle_version: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct GridStaticObstacleSnapshot {
    pub grid: GridCoord,
    pub count: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct GridRuntimeActorCellSnapshot {
    pub actor_id: ActorId,
    pub grid: GridCoord,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct GridCellSnapshotEntry {
    pub grid: GridCoord,
    pub cell: MapCellDefinition,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub(crate) struct GridWorldSnapshot {
    pub grid_size: f32,
    pub manual_static_obstacles: Vec<GridStaticObstacleSnapshot>,
    pub runtime_actor_cells: Vec<GridRuntimeActorCellSnapshot>,
    pub map_id: Option<MapId>,
    pub map_size: Option<MapSize>,
    #[serde(default)]
    pub uses_explicit_cells_as_bounds: bool,
    pub default_level: Option<i32>,
    pub levels: Vec<i32>,
    pub base_map_cells: Vec<GridCellSnapshotEntry>,
    pub map_cells: Vec<GridCellSnapshotEntry>,
    pub map_objects: Vec<MapObjectDefinition>,
    pub generated_buildings: Vec<GeneratedBuildingDebugState>,
    #[serde(default)]
    pub generated_doors: Vec<GeneratedDoorDebugState>,
    pub topology_version: u64,
    pub runtime_obstacle_version: u64,
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
            uses_explicit_cells_as_bounds: false,
            default_level: None,
            levels: BTreeSet::new(),
            base_map_cells: HashMap::new(),
            map_cells: HashMap::new(),
            map_objects: BTreeMap::new(),
            map_object_cells: HashMap::new(),
            map_blocked_cells: HashSet::new(),
            generated_buildings: Vec::new(),
            generated_doors: Vec::new(),
            generated_door_object_ids: BTreeSet::new(),
            stair_adjacency: HashMap::new(),
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
        self.uses_explicit_cells_as_bounds = false;
        self.default_level = Some(definition.default_level);
        self.levels = definition.levels.iter().map(|level| level.y).collect();
        self.base_map_cells.clear();
        self.map_cells.clear();
        self.map_objects.clear();
        self.map_object_cells.clear();
        self.map_blocked_cells.clear();
        self.generated_buildings.clear();
        self.stair_adjacency.clear();

        for level in &definition.levels {
            for cell in &level.cells {
                let coord = GridCoord::new(cell.x as i32, level.y, cell.z as i32);
                self.base_map_cells.insert(coord, cell.clone());
            }
        }

        for object in &definition.objects {
            self.map_objects
                .insert(object.object_id.clone(), object.clone());
            self.levels.extend(building_layout_story_levels(object));
        }

        self.rebuild_static_topology();
        self.topology_version = self.topology_version.saturating_add(1);
    }

    pub fn load_explicit_topology(
        &mut self,
        default_level: Option<i32>,
        cells: impl IntoIterator<Item = (GridCoord, MapCellDefinition)>,
        objects: impl IntoIterator<Item = MapObjectDefinition>,
    ) {
        self.map_id = None;
        self.map_size = None;
        self.uses_explicit_cells_as_bounds = true;
        self.default_level = default_level;
        self.levels.clear();
        self.base_map_cells.clear();
        self.map_cells.clear();
        self.map_objects.clear();
        self.map_object_cells.clear();
        self.map_blocked_cells.clear();
        self.generated_buildings.clear();
        self.generated_doors.clear();
        self.generated_door_object_ids.clear();
        self.stair_adjacency.clear();

        if let Some(default_level) = default_level {
            self.levels.insert(default_level);
        }

        for (grid, cell) in cells {
            self.levels.insert(grid.y);
            self.base_map_cells.insert(grid, cell);
        }

        for object in objects {
            self.levels.extend(building_layout_story_levels(&object));
            self.map_objects.insert(object.object_id.clone(), object);
        }

        self.rebuild_static_topology();
        self.topology_version = self.topology_version.saturating_add(1);
    }

    pub fn clear_map(&mut self) {
        self.map_id = None;
        self.map_size = None;
        self.uses_explicit_cells_as_bounds = false;
        self.default_level = None;
        self.levels.clear();
        self.base_map_cells.clear();
        self.map_cells.clear();
        self.map_objects.clear();
        self.map_object_cells.clear();
        self.map_blocked_cells.clear();
        self.generated_buildings.clear();
        self.stair_adjacency.clear();
        self.topology_version = self.topology_version.saturating_add(1);
    }

    pub fn map_id(&self) -> Option<&MapId> {
        self.map_id.as_ref()
    }

    pub fn map_size(&self) -> Option<MapSize> {
        self.map_size
    }

    pub fn uses_explicit_cells_as_bounds(&self) -> bool {
        self.uses_explicit_cells_as_bounds
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
        if self.uses_explicit_cells_as_bounds && !self.map_cells.contains_key(&grid) {
            return false;
        }

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

    pub fn generated_buildings(&self) -> &[GeneratedBuildingDebugState] {
        &self.generated_buildings
    }

    pub fn stair_neighbors(&self, grid: GridCoord) -> &[GridCoord] {
        self.stair_adjacency
            .get(&grid)
            .map(Vec::as_slice)
            .unwrap_or(&[])
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

    pub fn generated_doors(&self) -> &[GeneratedDoorDebugState] {
        &self.generated_doors
    }

    pub fn generated_door_by_object_id(&self, object_id: &str) -> Option<&GeneratedDoorDebugState> {
        self.generated_doors
            .iter()
            .find(|door| door.map_object_id == object_id)
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
        let object_id = object.object_id.clone();
        self.map_objects.insert(object_id, object);
        self.levels.clear();
        if let Some(default_level) = self.default_level {
            self.levels.insert(default_level);
        }
        for grid in self.base_map_cells.keys() {
            self.levels.insert(grid.y);
        }
        for object in self.map_objects.values() {
            self.levels.extend(building_layout_story_levels(object));
        }
        self.rebuild_static_topology();
        self.topology_version = self.topology_version.saturating_add(1);
    }

    pub fn remove_map_object(&mut self, object_id: &str) -> Option<MapObjectDefinition> {
        let removed = self.map_objects.remove(object_id)?;
        self.levels.clear();
        if let Some(default_level) = self.default_level {
            self.levels.insert(default_level);
        }
        for grid in self.base_map_cells.keys() {
            self.levels.insert(grid.y);
        }
        for object in self.map_objects.values() {
            self.levels.extend(building_layout_story_levels(object));
        }
        self.rebuild_static_topology();
        self.topology_version = self.topology_version.saturating_add(1);
        Some(removed)
    }

    pub fn set_generated_door_state(
        &mut self,
        door_id: &str,
        is_open: bool,
        is_locked: bool,
    ) -> bool {
        let Some(door) = self
            .generated_doors
            .iter_mut()
            .find(|door| door.door_id == door_id)
        else {
            return false;
        };
        if door.is_open == is_open && door.is_locked == is_locked {
            return false;
        }
        door.is_open = is_open;
        door.is_locked = is_locked;
        self.rebuild_static_topology();
        self.topology_version = self.topology_version.saturating_add(1);
        true
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

    pub fn classify_pathfinding_walkability_for_actor(
        &self,
        grid: GridCoord,
        actor_id: Option<ActorId>,
    ) -> GridWalkability {
        let walkability = self.classify_walkability_for_actor(grid, actor_id);
        if walkability != GridWalkability::StaticBlocked {
            return walkability;
        }

        if self.is_auto_open_generated_door_cell(grid) {
            GridWalkability::Walkable
        } else {
            walkability
        }
    }

    pub fn auto_open_generated_door_at(
        &mut self,
        grid: GridCoord,
    ) -> Option<GeneratedDoorDebugState> {
        let door = self
            .generated_doors
            .iter()
            .find(|door| door.anchor_grid == grid && !door.is_open && !door.is_locked)
            .cloned()?;
        if !self.is_auto_open_generated_door_cell(grid) {
            return None;
        }
        if self.set_generated_door_state(&door.door_id, true, false) {
            Some(door)
        } else {
            None
        }
    }

    pub fn classify_walkability_for_actor(
        &self,
        grid: GridCoord,
        actor_id: Option<ActorId>,
    ) -> GridWalkability {
        if self.uses_explicit_cells_as_bounds && !self.map_cells.contains_key(&grid) {
            return GridWalkability::OutOfBounds;
        }

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

    pub(crate) fn save_snapshot(&self) -> GridWorldSnapshot {
        let mut manual_static_obstacles = self
            .manual_static_obstacle_ref_counts
            .iter()
            .map(|(grid, count)| GridStaticObstacleSnapshot {
                grid: *grid,
                count: *count,
            })
            .collect::<Vec<_>>();
        manual_static_obstacles.sort_by_key(|entry| (entry.grid.y, entry.grid.z, entry.grid.x));

        let mut runtime_actor_cells = self
            .runtime_actor_cells
            .iter()
            .map(|(actor_id, grid)| GridRuntimeActorCellSnapshot {
                actor_id: *actor_id,
                grid: *grid,
            })
            .collect::<Vec<_>>();
        runtime_actor_cells.sort_by_key(|entry| entry.actor_id);

        GridWorldSnapshot {
            grid_size: self.grid_size,
            manual_static_obstacles,
            runtime_actor_cells,
            map_id: self.map_id.clone(),
            map_size: self.map_size,
            uses_explicit_cells_as_bounds: self.uses_explicit_cells_as_bounds,
            default_level: self.default_level,
            levels: self.levels(),
            base_map_cells: self
                .base_map_cells
                .iter()
                .map(|(grid, cell)| GridCellSnapshotEntry {
                    grid: *grid,
                    cell: cell.clone(),
                })
                .collect(),
            map_cells: self
                .map_cell_entries()
                .into_iter()
                .map(|(grid, cell)| GridCellSnapshotEntry { grid, cell })
                .collect(),
            map_objects: self
                .map_object_entries()
                .into_iter()
                .filter(|object| !self.generated_door_object_ids.contains(&object.object_id))
                .collect(),
            generated_buildings: self.generated_buildings.clone(),
            generated_doors: self.generated_doors.clone(),
            topology_version: self.topology_version,
            runtime_obstacle_version: self.runtime_obstacle_version,
        }
    }

    pub(crate) fn load_snapshot(&mut self, snapshot: GridWorldSnapshot) {
        self.grid_size = snapshot.grid_size;
        self.manual_static_obstacle_ref_counts = snapshot
            .manual_static_obstacles
            .into_iter()
            .map(|entry| (entry.grid, entry.count))
            .collect();
        self.runtime_occupants_by_cell.clear();
        self.runtime_actor_cells = snapshot
            .runtime_actor_cells
            .into_iter()
            .map(|entry| {
                self.runtime_occupants_by_cell
                    .entry(entry.grid)
                    .or_default()
                    .insert(entry.actor_id);
                (entry.actor_id, entry.grid)
            })
            .collect();
        self.map_id = snapshot.map_id;
        self.map_size = snapshot.map_size;
        self.uses_explicit_cells_as_bounds = snapshot.uses_explicit_cells_as_bounds;
        self.default_level = snapshot.default_level;
        self.levels = snapshot.levels.into_iter().collect();
        self.base_map_cells = snapshot
            .base_map_cells
            .into_iter()
            .map(|entry| (entry.grid, entry.cell))
            .collect();
        self.map_cells = snapshot
            .map_cells
            .into_iter()
            .map(|entry| (entry.grid, entry.cell))
            .collect();
        self.map_objects = snapshot
            .map_objects
            .into_iter()
            .map(|object| (object.object_id.clone(), object))
            .collect();
        self.map_object_cells.clear();
        self.map_blocked_cells.clear();
        self.generated_buildings = snapshot.generated_buildings;
        self.generated_doors = snapshot.generated_doors;
        self.generated_door_object_ids = self
            .generated_doors
            .iter()
            .map(|door| door.map_object_id.clone())
            .collect();
        for door in &self.generated_doors {
            self.map_objects
                .insert(door.map_object_id.clone(), generated_door_map_object(door));
        }
        self.stair_adjacency.clear();

        for (grid, cell) in &self.map_cells {
            if cell.blocks_movement {
                self.map_blocked_cells.insert(*grid);
            }
        }

        for object in self.map_objects.values() {
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

        for building in self.generated_buildings.clone() {
            self.register_stair_edges(&building);
        }

        self.topology_version = snapshot.topology_version;
        self.runtime_obstacle_version = snapshot.runtime_obstacle_version;
    }

    fn rebuild_static_topology(&mut self) {
        let previous_door_states: BTreeMap<_, _> = self
            .generated_doors
            .iter()
            .map(|door| (door.door_id.clone(), door.clone()))
            .collect();

        self.map_cells = self.base_map_cells.clone();
        self.map_object_cells.clear();
        self.map_blocked_cells = self
            .map_cells
            .iter()
            .filter_map(|(grid, cell)| cell.blocks_movement.then_some(*grid))
            .collect();
        self.generated_buildings.clear();
        self.generated_doors.clear();
        for object_id in std::mem::take(&mut self.generated_door_object_ids) {
            self.map_objects.remove(&object_id);
        }
        self.stair_adjacency.clear();

        let objects = self.map_objects.values().cloned().collect::<Vec<_>>();
        for object in &objects {
            for cell in expand_object_footprint(object) {
                self.map_object_cells
                    .entry(cell)
                    .or_default()
                    .push(object.object_id.clone());
                if object_effectively_blocks_movement(object) {
                    self.map_blocked_cells.insert(cell);
                }
            }

            if let Some(building) = object
                .props
                .building
                .as_ref()
                .filter(|building| building.layout.is_some())
            {
                match generate_building_layout(
                    building.layout.as_ref().expect("layout presence checked"),
                    object.anchor,
                    object.rotation,
                    object.footprint,
                ) {
                    Ok(layout) => {
                        let debug_state = GeneratedBuildingDebugState {
                            object_id: object.object_id.clone(),
                            prefab_id: building.prefab_id.clone(),
                            wall_visual: building
                                .wall_visual
                                .clone()
                                .expect("validated building objects must define wall_visual"),
                            tile_set: building
                                .tile_set
                                .clone()
                                .expect("validated building objects must define tile_set"),
                            anchor: object.anchor,
                            rotation: object.rotation,
                            stories: layout.stories,
                            stairs: layout.stairs,
                            visual_outline: layout.visual_outline,
                        };
                        self.apply_generated_building(&debug_state);
                        self.generated_doors
                            .extend(collect_generated_doors(&debug_state, &previous_door_states));
                        self.generated_buildings.push(debug_state);
                    }
                    Err(error) => {
                        warn!(
                            object_id = %object.object_id,
                            ?error,
                            "failed to generate building layout; falling back to blocking footprint"
                        );
                        for cell in expand_object_footprint(object) {
                            self.map_blocked_cells.insert(cell);
                            let entry =
                                self.map_cells
                                    .entry(cell)
                                    .or_insert_with(|| MapCellDefinition {
                                        x: cell.x.max(0) as u32,
                                        z: cell.z.max(0) as u32,
                                        blocks_movement: false,
                                        blocks_sight: false,
                                        terrain: "generated_building_fallback".into(),
                                        visual: None,
                                        extra: Default::default(),
                                    });
                            entry.blocks_movement = true;
                            entry.blocks_sight = true;
                            entry.terrain = "generated_building_fallback".into();
                        }
                    }
                }
            }
        }

        for door in &self.generated_doors {
            let object = generated_door_map_object(door);
            self.generated_door_object_ids
                .insert(object.object_id.clone());
            self.map_objects
                .insert(object.object_id.clone(), object.clone());
            for cell in expand_object_footprint(&object) {
                self.map_object_cells
                    .entry(cell)
                    .or_default()
                    .push(object.object_id.clone());
                if object_effectively_blocks_movement(&object) {
                    self.map_blocked_cells.insert(cell);
                }
            }
        }

        for object_ids in self.map_object_cells.values_mut() {
            object_ids.sort();
            object_ids.dedup();
        }
        self.generated_buildings
            .sort_by(|a, b| a.object_id.cmp(&b.object_id));
        self.generated_doors
            .sort_by(|a, b| a.door_id.cmp(&b.door_id));
    }

    fn is_auto_open_generated_door_cell(&self, grid: GridCoord) -> bool {
        if self.manual_static_obstacle_ref_counts.contains_key(&grid) {
            return false;
        }

        if self
            .map_cells
            .get(&grid)
            .map(|cell| cell.blocks_movement)
            .unwrap_or(false)
        {
            return false;
        }

        let mut has_auto_open_door = false;
        for object in self.map_objects_at(grid) {
            if !object_effectively_blocks_movement(object) {
                continue;
            }

            let Some(door) = self.generated_door_by_object_id(&object.object_id) else {
                return false;
            };
            if door.is_open || door.is_locked {
                return false;
            }
            has_auto_open_door = true;
        }

        has_auto_open_door
    }

    fn apply_generated_building(&mut self, building: &GeneratedBuildingDebugState) {
        for story in &building.stories {
            for wall in &story.wall_cells {
                self.map_blocked_cells.insert(*wall);
                let entry = self
                    .map_cells
                    .entry(*wall)
                    .or_insert_with(|| MapCellDefinition {
                        x: wall.x.max(0) as u32,
                        z: wall.z.max(0) as u32,
                        blocks_movement: false,
                        blocks_sight: false,
                        terrain: "generated_wall".into(),
                        visual: None,
                        extra: Default::default(),
                    });
                entry.blocks_movement = true;
                entry.blocks_sight = true;
                if entry.terrain.is_empty() || entry.terrain == "generated_floor" {
                    entry.terrain = "generated_wall".into();
                }
            }

            for door in story
                .interior_door_cells
                .iter()
                .chain(story.exterior_door_cells.iter())
                .chain(story.walkable_cells.iter())
            {
                if let Some(cell) = self.map_cells.get_mut(door) {
                    if cell.terrain == "generated_wall" {
                        cell.blocks_movement = false;
                        cell.blocks_sight = false;
                        cell.terrain = "generated_floor".into();
                    }
                }
                self.map_blocked_cells.remove(door);
            }
        }

        self.register_stair_edges(building);
    }

    fn register_stair_edges(&mut self, building: &GeneratedBuildingDebugState) {
        for stair in &building.stairs {
            for (from, to) in stair.from_cells.iter().zip(stair.to_cells.iter()) {
                self.stair_adjacency.entry(*from).or_default().push(*to);
                self.stair_adjacency.entry(*to).or_default().push(*from);
            }
        }

        for neighbors in self.stair_adjacency.values_mut() {
            neighbors.sort();
            neighbors.dedup();
        }
    }
}

fn collect_generated_doors(
    building: &GeneratedBuildingDebugState,
    previous_door_states: &BTreeMap<String, GeneratedDoorDebugState>,
) -> Vec<GeneratedDoorDebugState> {
    let mut doors = Vec::new();
    for story in &building.stories {
        for opening in &story.door_openings {
            let door_id = generated_door_id(&building.object_id, story.level, opening.opening_id);
            let map_object_id = generated_door_map_object_id(&door_id);
            let previous = previous_door_states.get(&door_id);
            doors.push(GeneratedDoorDebugState {
                door_id,
                map_object_id,
                building_object_id: building.object_id.clone(),
                building_anchor: building.anchor,
                level: story.level,
                opening_id: opening.opening_id,
                anchor_grid: opening.anchor_grid,
                axis: opening.axis,
                kind: opening.kind,
                polygon: opening.polygon.clone(),
                wall_height: story.wall_height,
                is_open: previous.map(|door| door.is_open).unwrap_or(false),
                is_locked: previous.map(|door| door.is_locked).unwrap_or(false),
            });
        }
    }
    doors
}

fn generated_door_id(building_object_id: &str, level: i32, opening_id: usize) -> String {
    format!("{building_object_id}::door::{level}::{opening_id}")
}

fn generated_door_map_object_id(door_id: &str) -> String {
    door_id.to_string()
}

fn generated_door_map_object(door: &GeneratedDoorDebugState) -> MapObjectDefinition {
    let door_state = if door.is_open { "open" } else { "closed" };
    let mut extra = BTreeMap::new();
    extra.insert("generated_door".to_string(), Value::Bool(true));
    extra.insert("door_id".to_string(), Value::String(door.door_id.clone()));
    extra.insert(
        "building_object_id".to_string(),
        Value::String(door.building_object_id.clone()),
    );
    extra.insert(
        "door_state".to_string(),
        Value::String(door_state.to_string()),
    );
    extra.insert("door_locked".to_string(), Value::Bool(door.is_locked));

    MapObjectDefinition {
        object_id: door.map_object_id.clone(),
        kind: MapObjectKind::Interactive,
        anchor: door.anchor_grid,
        footprint: MapObjectFootprint {
            width: 1,
            height: 1,
        },
        rotation: match door.axis {
            crate::GeometryAxis::Horizontal => MapRotation::North,
            crate::GeometryAxis::Vertical => MapRotation::East,
        },
        blocks_movement: !door.is_open,
        blocks_sight: !door.is_open,
        props: MapObjectProps {
            interactive: Some(MapInteractiveProps {
                display_name: "Door".to_string(),
                interaction_distance: 1.4,
                interaction_kind: String::new(),
                target_id: None,
                options: generated_door_interaction_options(door),
                extra,
            }),
            ..MapObjectProps::default()
        },
    }
}

fn generated_door_interaction_options(
    door: &GeneratedDoorDebugState,
) -> Vec<InteractionOptionDefinition> {
    build_generated_door_interaction_options(door)
}
