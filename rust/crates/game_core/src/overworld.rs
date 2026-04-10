use std::cmp::Ordering;
use std::collections::{BTreeSet, BinaryHeap, HashMap, HashSet};

use game_data::overworld::{overworld_cardinal_neighbors, overworld_cell_is_traversable};
use game_data::{
    GridCoord, MapDefinition, OverworldCellDefinition, OverworldDefinition,
    OverworldLocationDefinition, OverworldLocationKind, WorldMode,
};
use serde::{Deserialize, Serialize};

pub type UnlockedLocationSet = BTreeSet<String>;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct LocationTransitionContext {
    pub location_id: String,
    pub map_id: String,
    pub entry_point_id: String,
    pub return_outdoor_location_id: Option<String>,
    pub return_entry_point_id: Option<String>,
    pub world_mode: WorldMode,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Default)]
pub struct OverworldStateSnapshot {
    pub overworld_id: Option<String>,
    pub active_location_id: Option<String>,
    pub active_outdoor_location_id: Option<String>,
    pub current_map_id: Option<String>,
    pub current_entry_point_id: Option<String>,
    pub current_overworld_cell: Option<GridCoord>,
    pub unlocked_locations: Vec<String>,
    pub world_mode: WorldMode,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct OpenNode {
    grid: GridCoord,
    priority: u32,
}

impl Ord for OpenNode {
    fn cmp(&self, other: &Self) -> Ordering {
        other
            .priority
            .cmp(&self.priority)
            .then_with(|| other.grid.z.cmp(&self.grid.z))
            .then_with(|| other.grid.x.cmp(&self.grid.x))
            .then_with(|| other.grid.y.cmp(&self.grid.y))
    }
}

impl PartialOrd for OpenNode {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

pub fn location_by_id<'a>(
    definition: &'a OverworldDefinition,
    location_id: &str,
) -> Option<&'a OverworldLocationDefinition> {
    definition
        .locations
        .iter()
        .find(|location| location.id.as_str() == location_id)
}

pub fn find_entry_point<'a>(
    map: &'a MapDefinition,
    entry_point_id: &str,
) -> Option<&'a game_data::MapEntryPointDefinition> {
    map.entry_points
        .iter()
        .find(|entry_point| entry_point.id == entry_point_id)
}

pub fn world_mode_for_location_kind(kind: OverworldLocationKind) -> WorldMode {
    match kind {
        OverworldLocationKind::Outdoor => WorldMode::Outdoor,
        OverworldLocationKind::Interior => WorldMode::Interior,
        OverworldLocationKind::Dungeon => WorldMode::Dungeon,
    }
}

pub fn compute_cell_path(
    definition: &OverworldDefinition,
    start: GridCoord,
    goal: GridCoord,
) -> Option<Vec<GridCoord>> {
    if start == goal {
        return Some(vec![start]);
    }
    if !is_overworld_walkable(definition, start, true)
        || !is_overworld_walkable(definition, goal, false)
    {
        return None;
    }

    let mut open = BinaryHeap::new();
    let mut previous = HashMap::<GridCoord, GridCoord>::new();
    let mut best_cost = HashMap::<GridCoord, u32>::from([(start, 0)]);

    open.push(OpenNode {
        grid: start,
        priority: heuristic_cost(start, goal),
    });

    while let Some(OpenNode { grid: current, .. }) = open.pop() {
        if current == goal {
            return Some(reconstruct_cell_path(&previous, start, goal));
        }

        let current_cost = *best_cost.get(&current)?;
        for neighbor in overworld_cardinal_neighbors(current) {
            if !is_overworld_walkable(definition, neighbor, false) {
                continue;
            }
            let Some(step_cost) = movement_cost(definition, neighbor) else {
                continue;
            };
            let next_cost = current_cost.saturating_add(step_cost);
            if next_cost >= *best_cost.get(&neighbor).unwrap_or(&u32::MAX) {
                continue;
            }
            best_cost.insert(neighbor, next_cost);
            previous.insert(neighbor, current);
            open.push(OpenNode {
                grid: neighbor,
                priority: next_cost.saturating_add(heuristic_cost(neighbor, goal)),
            });
        }
    }

    None
}

pub fn overworld_cell(
    definition: &OverworldDefinition,
    grid: GridCoord,
) -> Option<&OverworldCellDefinition> {
    definition.cells.iter().find(|cell| cell.grid == grid)
}

pub fn is_overworld_walkable(
    definition: &OverworldDefinition,
    grid: GridCoord,
    allow_outdoor_location_cell: bool,
) -> bool {
    let Some(cell) = overworld_cell(definition, grid) else {
        return false;
    };
    if !overworld_cell_is_traversable(cell) {
        return false;
    }
    allow_outdoor_location_cell || !is_outdoor_location_cell(definition, grid)
}

pub fn movement_cost(definition: &OverworldDefinition, grid: GridCoord) -> Option<u32> {
    overworld_cell(definition, grid)?.terrain.move_cost()
}

pub fn is_outdoor_location_cell(definition: &OverworldDefinition, grid: GridCoord) -> bool {
    definition.locations.iter().any(|location| {
        location.kind == OverworldLocationKind::Outdoor && location.overworld_cell == grid
    })
}

pub fn outdoor_interaction_ring(
    definition: &OverworldDefinition,
    location: &OverworldLocationDefinition,
) -> Vec<GridCoord> {
    let occupied = definition
        .locations
        .iter()
        .filter(|candidate| candidate.kind == OverworldLocationKind::Outdoor)
        .map(|candidate| candidate.overworld_cell)
        .collect::<HashSet<_>>();
    let mut ring = overworld_cardinal_neighbors(location.overworld_cell)
        .into_iter()
        .filter(|grid| !occupied.contains(grid))
        .filter(|grid| is_overworld_walkable(definition, *grid, false))
        .collect::<Vec<_>>();
    ring.sort_by_key(|grid| (grid.z, grid.x));
    ring
}

pub fn resolve_overworld_goal(
    definition: &OverworldDefinition,
    start: GridCoord,
    requested_goal: GridCoord,
) -> Option<GridCoord> {
    if is_outdoor_location_cell(definition, requested_goal) {
        let location = definition.locations.iter().find(|location| {
            location.kind == OverworldLocationKind::Outdoor
                && location.overworld_cell == requested_goal
        })?;
        return nearest_reachable_interaction_cell(definition, start, location);
    }
    is_overworld_walkable(definition, requested_goal, false).then_some(requested_goal)
}

pub fn nearest_reachable_interaction_cell(
    definition: &OverworldDefinition,
    start: GridCoord,
    location: &OverworldLocationDefinition,
) -> Option<GridCoord> {
    let mut best: Option<(u32, usize, GridCoord)> = None;
    for candidate in outdoor_interaction_ring(definition, location) {
        let Some(path) = compute_cell_path(definition, start, candidate) else {
            continue;
        };
        let cost = path_cost(definition, &path)?;
        let score = (cost, path.len(), candidate);
        if best.is_none_or(|current| score < current) {
            best = Some(score);
        }
    }
    best.map(|(_, _, grid)| grid)
}

pub fn default_outdoor_spawn_cell(
    definition: &OverworldDefinition,
    location: &OverworldLocationDefinition,
) -> Option<GridCoord> {
    outdoor_interaction_ring(definition, location)
        .into_iter()
        .min_by_key(|grid| {
            let cost = movement_cost(definition, *grid).unwrap_or(u32::MAX);
            (cost, grid.z, grid.x)
        })
}

fn reconstruct_cell_path(
    previous: &HashMap<GridCoord, GridCoord>,
    start: GridCoord,
    goal: GridCoord,
) -> Vec<GridCoord> {
    let mut path = vec![goal];
    let mut current = goal;
    while current != start {
        let Some(next) = previous.get(&current).copied() else {
            break;
        };
        current = next;
        path.push(current);
    }
    path.reverse();
    path
}

fn heuristic_cost(a: GridCoord, b: GridCoord) -> u32 {
    let dx = (a.x - b.x).unsigned_abs();
    let dz = (a.z - b.z).unsigned_abs();
    (dx + dz).saturating_mul(1)
}

fn path_cost(definition: &OverworldDefinition, path: &[GridCoord]) -> Option<u32> {
    path.iter().copied().skip(1).try_fold(0_u32, |sum, grid| {
        Some(sum.saturating_add(movement_cost(definition, grid)?))
    })
}

#[cfg(test)]
mod tests {
    use super::{
        compute_cell_path, default_outdoor_spawn_cell, find_entry_point, resolve_overworld_goal,
    };
    use game_data::{
        GridCoord, MapDefinition, MapEntryPointDefinition, MapId, MapLevelDefinition, MapSize,
        OverworldCellDefinition, OverworldDefinition, OverworldId, OverworldLocationDefinition,
        OverworldLocationId, OverworldLocationKind, OverworldTerrainKind, OverworldTravelRuleSet,
    };
    use std::collections::BTreeMap;

    #[test]
    fn cell_path_prefers_roads_over_forest_detour() {
        let definition = sample_overworld();
        let path = compute_cell_path(
            &definition,
            GridCoord::new(0, 0, 2),
            GridCoord::new(4, 0, 2),
        )
        .expect("cell path should resolve");
        assert_eq!(
            path,
            vec![
                GridCoord::new(0, 0, 2),
                GridCoord::new(0, 0, 1),
                GridCoord::new(1, 0, 1),
                GridCoord::new(2, 0, 1),
                GridCoord::new(3, 0, 1),
                GridCoord::new(4, 0, 1),
                GridCoord::new(4, 0, 2),
            ]
        );
    }

    #[test]
    fn cell_path_rejects_outdoor_location_goal() {
        let definition = sample_overworld();
        let path = compute_cell_path(
            &definition,
            GridCoord::new(0, 0, 2),
            GridCoord::new(2, 0, 2),
        );
        assert!(path.is_none());
    }

    #[test]
    fn clicking_outdoor_location_redirects_to_nearest_ring_cell() {
        let definition = sample_overworld();
        let goal = resolve_overworld_goal(
            &definition,
            GridCoord::new(0, 0, 2),
            GridCoord::new(2, 0, 2),
        )
        .expect("location click should redirect");
        assert_eq!(goal, GridCoord::new(1, 0, 2));
    }

    #[test]
    fn default_spawn_cell_uses_lowest_cost_ring_cell() {
        let definition = sample_overworld();
        let location = definition
            .locations
            .iter()
            .find(|location| location.id.as_str() == "outpost")
            .expect("outpost exists");
        assert_eq!(
            default_outdoor_spawn_cell(&definition, location),
            Some(GridCoord::new(2, 0, 1))
        );
    }

    #[test]
    fn entry_point_lookup_finds_named_entry() {
        let map = MapDefinition {
            id: MapId("sample".into()),
            name: "Sample".into(),
            size: MapSize {
                width: 4,
                height: 4,
            },
            default_level: 0,
            levels: vec![MapLevelDefinition {
                y: 0,
                cells: Vec::new(),
            }],
            entry_points: vec![MapEntryPointDefinition {
                id: "default_entry".into(),
                grid: GridCoord::new(1, 0, 1),
                facing: None,
                extra: BTreeMap::new(),
            }],
            objects: Vec::new(),
        };

        assert!(find_entry_point(&map, "default_entry").is_some());
    }

    fn sample_overworld() -> OverworldDefinition {
        OverworldDefinition {
            id: OverworldId("main".into()),
            size: MapSize {
                width: 5,
                height: 5,
            },
            locations: vec![sample_location("outpost", 2, 2)],
            cells: vec![
                sample_cell(0, 0, OverworldTerrainKind::Plain, false),
                sample_cell(1, 0, OverworldTerrainKind::Plain, false),
                sample_cell(2, 0, OverworldTerrainKind::Plain, false),
                sample_cell(3, 0, OverworldTerrainKind::Plain, false),
                sample_cell(4, 0, OverworldTerrainKind::Plain, false),
                sample_cell(0, 1, OverworldTerrainKind::Road, false),
                sample_cell(1, 1, OverworldTerrainKind::Road, false),
                sample_cell(2, 1, OverworldTerrainKind::Road, false),
                sample_cell(3, 1, OverworldTerrainKind::Road, false),
                sample_cell(4, 1, OverworldTerrainKind::Road, false),
                sample_cell(0, 2, OverworldTerrainKind::Plain, false),
                sample_cell(1, 2, OverworldTerrainKind::Forest, false),
                sample_cell(2, 2, OverworldTerrainKind::Urban, false),
                sample_cell(3, 2, OverworldTerrainKind::Forest, false),
                sample_cell(4, 2, OverworldTerrainKind::Plain, false),
                sample_cell(0, 3, OverworldTerrainKind::Plain, false),
                sample_cell(1, 3, OverworldTerrainKind::Plain, false),
                sample_cell(2, 3, OverworldTerrainKind::Mountain, false),
                sample_cell(3, 3, OverworldTerrainKind::Plain, false),
                sample_cell(4, 3, OverworldTerrainKind::Plain, false),
                sample_cell(0, 4, OverworldTerrainKind::Plain, false),
                sample_cell(1, 4, OverworldTerrainKind::Plain, false),
                sample_cell(2, 4, OverworldTerrainKind::Plain, false),
                sample_cell(3, 4, OverworldTerrainKind::Plain, false),
                sample_cell(4, 4, OverworldTerrainKind::Plain, false),
            ],
            travel_rules: OverworldTravelRuleSet::default(),
        }
    }

    fn sample_cell(
        x: i32,
        z: i32,
        terrain: OverworldTerrainKind,
        blocked: bool,
    ) -> OverworldCellDefinition {
        OverworldCellDefinition {
            grid: GridCoord::new(x, 0, z),
            terrain,
            blocked,
            visual: None,
            extra: BTreeMap::new(),
        }
    }

    fn sample_location(id: &str, x: i32, z: i32) -> OverworldLocationDefinition {
        OverworldLocationDefinition {
            id: OverworldLocationId(id.into()),
            name: id.into(),
            description: String::new(),
            kind: OverworldLocationKind::Outdoor,
            map_id: MapId(id.to_string()),
            entry_point_id: "default_entry".into(),
            parent_outdoor_location_id: None,
            return_entry_point_id: None,
            default_unlocked: true,
            visible: true,
            overworld_cell: GridCoord::new(x, 0, z),
            danger_level: 0,
            icon: String::new(),
            extra: BTreeMap::new(),
        }
    }
}
