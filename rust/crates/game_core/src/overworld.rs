use std::collections::{BTreeSet, HashMap, HashSet, VecDeque};

use game_data::{
    GridCoord, MapDefinition, OverworldDefinition, OverworldLocationDefinition,
    OverworldLocationKind, WorldMode,
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

    let walkable: HashSet<GridCoord> = definition
        .walkable_cells
        .iter()
        .map(|cell| cell.grid)
        .collect();
    if !walkable.contains(&start) || !walkable.contains(&goal) {
        return None;
    }

    let mut queue = VecDeque::from([start]);
    let mut previous = HashMap::<GridCoord, GridCoord>::new();
    let mut visited = HashSet::from([start]);
    while let Some(current) = queue.pop_front() {
        for neighbor in neighbors(current) {
            if !walkable.contains(&neighbor) || !visited.insert(neighbor) {
                continue;
            }
            previous.insert(neighbor, current);
            if neighbor == goal {
                return Some(reconstruct_cell_path(previous, start, goal));
            }
            queue.push_back(neighbor);
        }
    }

    None
}

fn reconstruct_cell_path(
    previous: HashMap<GridCoord, GridCoord>,
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

fn neighbors(current: GridCoord) -> [GridCoord; 4] {
    [
        GridCoord::new(current.x + 1, current.y, current.z),
        GridCoord::new(current.x - 1, current.y, current.z),
        GridCoord::new(current.x, current.y, current.z + 1),
        GridCoord::new(current.x, current.y, current.z - 1),
    ]
}

#[cfg(test)]
mod tests {
    use super::{compute_cell_path, find_entry_point};
    use game_data::{
        GridCoord, MapDefinition, MapEntryPointDefinition, MapId, MapLevelDefinition, MapSize,
        OverworldCellDefinition, OverworldDefinition, OverworldId, OverworldLocationDefinition,
        OverworldLocationId, OverworldLocationKind, OverworldTravelRuleSet,
    };
    use std::collections::BTreeMap;

    #[test]
    fn cell_path_uses_walkable_cells_only() {
        let definition = sample_overworld();
        let path = compute_cell_path(
            &definition,
            GridCoord::new(0, 0, 0),
            GridCoord::new(2, 0, 0),
        )
        .expect("cell path should resolve");
        assert_eq!(
            path,
            vec![
                GridCoord::new(0, 0, 0),
                GridCoord::new(1, 0, 0),
                GridCoord::new(2, 0, 0)
            ]
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
            locations: vec![
                sample_location("a", 0, 0),
                sample_location("b", 1, 0),
                sample_location("c", 2, 0),
            ],
            walkable_cells: vec![
                OverworldCellDefinition {
                    grid: GridCoord::new(0, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                },
                OverworldCellDefinition {
                    grid: GridCoord::new(1, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                },
                OverworldCellDefinition {
                    grid: GridCoord::new(2, 0, 0),
                    terrain: "road".into(),
                    extra: BTreeMap::new(),
                },
            ],
            travel_rules: OverworldTravelRuleSet::default(),
        }
    }

    fn sample_location(id: &str, x: i32, z: i32) -> OverworldLocationDefinition {
        OverworldLocationDefinition {
            id: OverworldLocationId(id.into()),
            name: id.into(),
            description: String::new(),
            kind: OverworldLocationKind::Outdoor,
            map_id: MapId(format!("{id}_grid")),
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
