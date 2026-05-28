use std::collections::{BTreeMap, BTreeSet, HashSet};

use game_data::{object_effectively_blocks_sight, ActorId, GridCoord, MapId};
use serde::{Deserialize, Serialize};

use crate::grid::GridWorld;

pub const DEFAULT_VISION_RADIUS: i32 = 10;

const fn default_vision_radius() -> i32 {
    DEFAULT_VISION_RADIUS
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct ActorVisionMapSnapshot {
    pub map_id: MapId,
    #[serde(default)]
    pub explored_cells: Vec<GridCoord>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct ActorVisionSnapshot {
    pub actor_id: ActorId,
    #[serde(default = "default_vision_radius")]
    pub radius: i32,
    #[serde(default)]
    pub active_map_id: Option<MapId>,
    #[serde(default)]
    pub visible_cells: Vec<GridCoord>,
    #[serde(default)]
    pub explored_maps: Vec<ActorVisionMapSnapshot>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct VisionRuntimeSnapshot {
    #[serde(default)]
    pub actors: Vec<ActorVisionSnapshot>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActorVisionUpdate {
    pub actor_id: ActorId,
    pub active_map_id: Option<MapId>,
    pub visible_cells: Vec<GridCoord>,
    pub explored_cells: Vec<GridCoord>,
}

#[derive(Debug, Clone, Default)]
pub(crate) struct VisionRuntimeState {
    actors: BTreeMap<ActorId, ActorVisionState>,
}

#[derive(Debug, Clone)]
struct ActorVisionState {
    radius: i32,
    active_map_id: Option<MapId>,
    visible_cells: Vec<GridCoord>,
    explored_by_map: BTreeMap<MapId, BTreeSet<GridCoord>>,
}

impl Default for ActorVisionState {
    fn default() -> Self {
        Self {
            radius: DEFAULT_VISION_RADIUS,
            active_map_id: None,
            visible_cells: Vec::new(),
            explored_by_map: BTreeMap::new(),
        }
    }
}

impl VisionRuntimeState {
    pub fn snapshot(&self) -> VisionRuntimeSnapshot {
        VisionRuntimeSnapshot {
            actors: self
                .actors
                .iter()
                .map(|(actor_id, state)| state.snapshot(*actor_id))
                .collect(),
        }
    }

    pub fn actor_snapshot(&self, actor_id: ActorId) -> Option<ActorVisionSnapshot> {
        self.actors
            .get(&actor_id)
            .map(|state| state.snapshot(actor_id))
    }

    pub fn load_snapshot(&mut self, snapshot: VisionRuntimeSnapshot) {
        self.actors.clear();
        for actor in snapshot.actors {
            self.actors
                .insert(actor.actor_id, ActorVisionState::from_snapshot(actor));
        }
    }

    pub fn clear_actor(&mut self, actor_id: ActorId) {
        self.actors.remove(&actor_id);
    }

    pub fn set_actor_radius(&mut self, actor_id: ActorId, radius: i32) {
        let state = self.actors.entry(actor_id).or_default();
        state.radius = radius.max(0);
    }

    pub fn recompute_actor(
        &mut self,
        actor_id: ActorId,
        active_map_id: Option<&MapId>,
        center: Option<GridCoord>,
        world: &GridWorld,
    ) -> Option<ActorVisionUpdate> {
        let state = self.actors.entry(actor_id).or_default();
        let next_map_id = active_map_id.cloned();

        let Some(center) = center else {
            let changed = state.active_map_id != next_map_id || !state.visible_cells.is_empty();
            state.active_map_id = next_map_id.clone();
            state.visible_cells.clear();
            return changed.then(|| ActorVisionUpdate {
                actor_id,
                active_map_id: next_map_id,
                visible_cells: Vec::new(),
                explored_cells: Vec::new(),
            });
        };

        let Some(map_id) = next_map_id.clone() else {
            let changed = state.active_map_id.is_some() || !state.visible_cells.is_empty();
            state.active_map_id = None;
            state.visible_cells.clear();
            return changed.then(|| ActorVisionUpdate {
                actor_id,
                active_map_id: None,
                visible_cells: Vec::new(),
                explored_cells: Vec::new(),
            });
        };

        let visible_cells = compute_visible_cells(world, center, state.radius);
        let explored_entry = state.explored_by_map.entry(map_id.clone()).or_default();
        let previous_visible = state.visible_cells.clone();
        let previous_explored = explored_entry.iter().copied().collect::<Vec<_>>();
        explored_entry.extend(visible_cells.iter().copied());
        let explored_cells = explored_entry.iter().copied().collect::<Vec<_>>();

        let changed = state.active_map_id.as_ref() != Some(&map_id)
            || previous_visible != visible_cells
            || previous_explored != explored_cells;
        state.active_map_id = Some(map_id.clone());
        state.visible_cells = visible_cells.clone();

        changed.then(|| ActorVisionUpdate {
            actor_id,
            active_map_id: Some(map_id),
            visible_cells,
            explored_cells,
        })
    }
}

impl ActorVisionState {
    fn snapshot(&self, actor_id: ActorId) -> ActorVisionSnapshot {
        ActorVisionSnapshot {
            actor_id,
            radius: self.radius,
            active_map_id: self.active_map_id.clone(),
            visible_cells: self.visible_cells.clone(),
            explored_maps: self
                .explored_by_map
                .iter()
                .map(|(map_id, cells)| ActorVisionMapSnapshot {
                    map_id: map_id.clone(),
                    explored_cells: cells.iter().copied().collect(),
                })
                .collect(),
        }
    }

    fn from_snapshot(snapshot: ActorVisionSnapshot) -> Self {
        Self {
            radius: snapshot.radius.max(0),
            active_map_id: snapshot.active_map_id,
            visible_cells: snapshot.visible_cells,
            explored_by_map: snapshot
                .explored_maps
                .into_iter()
                .map(|map| (map.map_id, map.explored_cells.into_iter().collect()))
                .collect(),
        }
    }
}

#[derive(Debug, Clone, Copy)]
struct VisionBounds {
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
}

fn compute_visible_cells(world: &GridWorld, center: GridCoord, radius: i32) -> Vec<GridCoord> {
    let radius = radius.max(0);
    let bounds = vision_bounds(world, center, radius);
    let min_x = bounds.map(|value| value.min_x).unwrap_or(center.x - radius);
    let max_x = bounds.map(|value| value.max_x).unwrap_or(center.x + radius);
    let min_z = bounds.map(|value| value.min_z).unwrap_or(center.z - radius);
    let max_z = bounds.map(|value| value.max_z).unwrap_or(center.z + radius);
    let blockers = blocker_cells(world, center.y, min_x, max_x, min_z, max_z);
    let radius_f = radius as f32;
    let mut visible = Vec::new();

    for x in min_x..=max_x {
        let dx = x - center.x;
        for z in min_z..=max_z {
            let dz = z - center.z;
            if !cell_intersects_vision_circle(dx, dz, radius_f) {
                continue;
            }
            let target = GridCoord::new(x, center.y, z);
            if has_line_of_sight(center, target, &blockers) {
                visible.push(target);
            }
        }
    }

    visible
}

pub(crate) fn has_grid_line_of_sight(world: &GridWorld, from: GridCoord, to: GridCoord) -> bool {
    if from.y != to.y {
        return false;
    }

    let min_x = from.x.min(to.x);
    let max_x = from.x.max(to.x);
    let min_z = from.z.min(to.z);
    let max_z = from.z.max(to.z);
    let blockers = blocker_cells(world, from.y, min_x, max_x, min_z, max_z);
    has_line_of_sight(from, to, &blockers)
}

fn vision_bounds(world: &GridWorld, center: GridCoord, radius: i32) -> Option<VisionBounds> {
    let size = world.map_size()?;
    Some(VisionBounds {
        min_x: (center.x - radius).max(0),
        max_x: (center.x + radius).min(size.width as i32 - 1),
        min_z: (center.z - radius).max(0),
        max_z: (center.z + radius).min(size.height as i32 - 1),
    })
}

fn blocker_cells(
    world: &GridWorld,
    level: i32,
    min_x: i32,
    max_x: i32,
    min_z: i32,
    max_z: i32,
) -> HashSet<GridCoord> {
    let mut blockers = HashSet::new();
    for x in min_x..=max_x {
        for z in min_z..=max_z {
            let grid = GridCoord::new(x, level, z);
            if grid_blocks_sight(world, grid) {
                blockers.insert(grid);
            }
        }
    }
    blockers
}

fn grid_blocks_sight(world: &GridWorld, grid: GridCoord) -> bool {
    world.map_cell(grid).is_some_and(|cell| cell.blocks_sight)
        || world
            .map_objects_at(grid)
            .into_iter()
            .any(object_effectively_blocks_sight)
}

fn has_line_of_sight(from: GridCoord, to: GridCoord, blockers: &HashSet<GridCoord>) -> bool {
    if from == to {
        return true;
    }

    let (mut x, mut z) = (from.x, from.z);
    let (x1, z1) = (to.x, to.z);
    let dx = (x1 - x).abs();
    let dz = (z1 - z).abs();
    let sx = if x < x1 { 1 } else { -1 };
    let sz = if z < z1 { 1 } else { -1 };
    let mut err = dx - dz;

    loop {
        if x == x1 && z == z1 {
            return true;
        }

        let e2 = err * 2;
        if e2 > -dz {
            err -= dz;
            x += sx;
        }
        if e2 < dx {
            err += dx;
            z += sz;
        }

        if x == x1 && z == z1 {
            return true;
        }

        if blockers.contains(&GridCoord::new(x, from.y, z)) {
            return false;
        }
    }
}

fn cell_intersects_vision_circle(dx: i32, dz: i32, radius: f32) -> bool {
    if radius <= 0.0 {
        return dx == 0 && dz == 0;
    }
    let qx = (dx.abs() as f32 - 0.5).max(0.0);
    let qz = (dz.abs() as f32 - 0.5).max(0.0);
    qx * qx + qz * qz <= radius * radius
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use game_data::{
        ActorId, GridCoord, MapCellDefinition, MapDefinition, MapId, MapLevelDefinition,
        MapObjectDefinition, MapObjectFootprint, MapObjectKind, MapRotation, MapSize,
    };

    use super::{cell_intersects_vision_circle, VisionRuntimeState};
    use crate::grid::GridWorld;

    fn sample_world() -> GridWorld {
        let map = MapDefinition {
            id: MapId("vision_test_map".into()),
            name: "Vision Test".into(),
            size: MapSize {
                width: 8,
                height: 8,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: vec![MapCellDefinition {
                    x: 3,
                    z: 2,
                    blocks_movement: true,
                    blocks_sight: true,
                    terrain: "wall".into(),
                    visual: None,
                    extra: BTreeMap::new(),
                }],
            }],
            entry_points: Vec::new(),
            objects: vec![MapObjectDefinition {
                object_id: "crate".into(),
                kind: MapObjectKind::Interactive,
                anchor: GridCoord::new(4, 0, 4),
                footprint: MapObjectFootprint {
                    width: 1,
                    height: 1,
                },
                rotation: MapRotation::North,
                blocks_movement: true,
                blocks_sight: true,
                props: Default::default(),
            }],
        };
        let mut world = GridWorld::default();
        world.load_map(&map);
        world
    }

    #[test]
    fn circle_intersection_matches_zero_radius_center_only() {
        assert!(cell_intersects_vision_circle(0, 0, 0.0));
        assert!(!cell_intersects_vision_circle(1, 0, 0.0));
    }

    #[test]
    fn runtime_state_blocks_cells_behind_occluders() {
        let mut state = VisionRuntimeState::default();
        let world = sample_world();
        let actor_id = ActorId(1);
        state.set_actor_radius(actor_id, 4);

        let update = state
            .recompute_actor(
                actor_id,
                Some(&MapId("vision_test_map".into())),
                Some(GridCoord::new(2, 0, 2)),
                &world,
            )
            .expect("vision should update");

        assert!(update.visible_cells.contains(&GridCoord::new(3, 0, 2)));
        assert!(!update.visible_cells.contains(&GridCoord::new(4, 0, 2)));
        assert!(update.visible_cells.contains(&GridCoord::new(4, 0, 4)));
    }

    #[test]
    fn explored_cells_persist_per_map_across_refreshes() {
        let mut state = VisionRuntimeState::default();
        let world = sample_world();
        let actor_id = ActorId(1);
        state.set_actor_radius(actor_id, 2);

        state.recompute_actor(
            actor_id,
            Some(&MapId("vision_test_map".into())),
            Some(GridCoord::new(1, 0, 1)),
            &world,
        );
        let update = state
            .recompute_actor(
                actor_id,
                Some(&MapId("vision_test_map".into())),
                Some(GridCoord::new(2, 0, 1)),
                &world,
            )
            .expect("second refresh should expand exploration");

        assert!(update.explored_cells.contains(&GridCoord::new(1, 0, 1)));
        assert!(update.explored_cells.contains(&GridCoord::new(2, 0, 1)));
    }
}
